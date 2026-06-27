// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PrecompileConsumer} from "./utils/PrecompileConsumer.sol";

/// @notice Minimal interface to the Ritual Wallet that funds LLM inference on
///         Ritual Chain. The bounty owner deposits here so the contract's calls
///         to the LLM precompile during `judgeAll` can be paid for.
interface IRitualWallet {
    function deposit(uint256 lockDuration) external payable;

    function depositFor(address user, uint256 lockDuration) external payable;

    function withdraw(uint256 amount) external;

    function balanceOf(address) external view returns (uint256);

    function lockUntil(address) external view returns (uint256);
}

/**
 * @title  CommitRevealAIJudge
 * @author yongoko
 * @notice A privacy-preserving AI bounty judge.
 *
 *         In the original workshop contract, answers were public the moment they
 *         were submitted, so later participants could read earlier answers, copy
 *         the good ideas, and submit an improved version. That is unfair when
 *         only one submission can win.
 *
 *         This version fixes that with a **commit-reveal** scheme:
 *
 *           1. Submission phase — participants publish only a commitment hash:
 *                commitment = keccak256(abi.encodePacked(answer, salt, msg.sender, bountyId))
 *              The plaintext answer never touches the chain during this phase.
 *           2. Reveal phase — after the submission deadline, participants reveal
 *              their `answer` + `salt`; the contract recomputes the hash and only
 *              accepts it if it matches the original commitment.
 *           3. Judging — after the reveal deadline, the owner calls `judgeAll`,
 *              which forwards all revealed answers to Ritual's LLM precompile in a
 *              single batch request (never one call per answer).
 *           4. Finalization — the owner finalizes exactly one winner, who is paid
 *              the reward. AI recommends; a human finalizes (human-in-the-loop).
 *
 *         Binding `msg.sender` and `bountyId` into the commitment stops a copycat
 *         from re-using someone else's commitment hash and revealing it as theirs.
 */
contract CommitRevealAIJudge is PrecompileConsumer {
    // ─────────────────────────────────────────────────────────────────────────
    //  Constants
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Max number of commitments accepted per bounty (anti-spam bound).
    uint256 public constant MAX_SUBMISSIONS = 50;

    /// @notice Max byte length of a revealed answer (caps gas / storage cost).
    uint256 public constant MAX_ANSWER_LENGTH = 4_000;

    /// @notice Canonical Ritual Wallet that funds LLM inference on Ritual Chain.
    ///         The owner deposits here before judging; see README "Funding".
    IRitualWallet public constant RITUAL_WALLET =
        IRitualWallet(0x532F0dF0896F353d8C3DD8cc134e8129DA2a3948);

    // ─────────────────────────────────────────────────────────────────────────
    //  Storage
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Auto-incrementing id for the next bounty (ids start at 1).
    uint256 public nextBountyId = 1;

    struct Submission {
        address submitter; // who committed
        bytes32 commitment; // keccak256(answer, salt, submitter, bountyId)
        string answer; // empty until a valid reveal
        bool revealed; // true once the commitment has been opened
    }

    /// @dev Mirrors the tuple the Ritual LLM precompile appends to its output.
    struct ConvoHistory {
        string storageType;
        string path;
        string secretsName;
    }

    /// @dev Flat, memory-returnable view of a bounty (no mapping / no array of
    ///      structs) so `getBounty` can return a single decoded object.
    struct BountyView {
        address owner;
        string title;
        string rubric;
        uint256 reward;
        uint64 submissionDeadline;
        uint64 revealDeadline;
        bool judged;
        bool finalized;
        uint256 submissionCount;
        uint256 revealedCount;
        uint256 winnerIndex;
        bytes aiReview;
    }

    struct Bounty {
        address owner;
        string title;
        string rubric;
        uint256 reward;
        uint64 submissionDeadline; // commitments accepted strictly before this
        uint64 revealDeadline; // reveals accepted in [submission, reveal)
        bool judged;
        bool finalized;
        uint256 winnerIndex; // type(uint256).max until finalized
        uint256 revealedCount; // number of valid reveals so far
        bytes aiReview; // raw bytes returned by the LLM precompile
        Submission[] submissions;
        // participant => (submission index + 1); 0 means "no commitment yet"
        mapping(address => uint256) committerIndexPlusOne;
    }

    /// @dev Private so the compiler does not try to auto-generate a getter for a
    ///      struct that contains a mapping; explicit view functions are exposed.
    mapping(uint256 => Bounty) private bounties;

    /// @dev Reentrancy guard state: 1 = unlocked, 2 = locked.
    uint256 private _locked = 1;

    // ─────────────────────────────────────────────────────────────────────────
    //  Events
    // ─────────────────────────────────────────────────────────────────────────

    event BountyCreated(
        uint256 indexed bountyId,
        address indexed owner,
        string title,
        uint256 reward,
        uint64 submissionDeadline,
        uint64 revealDeadline
    );

    event CommitmentSubmitted(
        uint256 indexed bountyId,
        uint256 indexed submissionIndex,
        address indexed submitter,
        bytes32 commitment
    );

    event AnswerRevealed(
        uint256 indexed bountyId,
        uint256 indexed submissionIndex,
        address indexed submitter
    );

    event AllAnswersJudged(
        uint256 indexed bountyId,
        uint256 revealedCount,
        bytes aiReview
    );

    event WinnerFinalized(
        uint256 indexed bountyId,
        uint256 indexed winnerIndex,
        address indexed winner,
        uint256 reward
    );

    // ─────────────────────────────────────────────────────────────────────────
    //  Errors
    // ─────────────────────────────────────────────────────────────────────────

    error RewardRequired();
    error InvalidDeadlines();
    error BountyNotFound();
    error SubmissionPhaseOver();
    error ZeroCommitment();
    error AlreadyCommitted();
    error TooManySubmissions();
    error RevealPhaseNotStarted();
    error RevealPhaseOver();
    error NoCommitment();
    error AlreadyRevealed();
    error AnswerTooLong();
    error CommitmentMismatch();
    error NotBountyOwner();
    error RevealPhaseNotOver();
    error AlreadyJudged();
    error AlreadyFinalized();
    error NoRevealedSubmissions();
    error JudgingFailed(string reason);
    error NotJudged();
    error InvalidWinnerIndex();
    error WinnerNotRevealed();
    error PaymentFailed();
    error ReentrantCall();
    error InvalidIndex();

    // ─────────────────────────────────────────────────────────────────────────
    //  Modifiers
    // ─────────────────────────────────────────────────────────────────────────

    modifier bountyExists(uint256 bountyId) {
        if (bounties[bountyId].owner == address(0)) revert BountyNotFound();
        _;
    }

    modifier onlyOwner(uint256 bountyId) {
        if (msg.sender != bounties[bountyId].owner) revert NotBountyOwner();
        _;
    }

    modifier nonReentrant() {
        if (_locked != 1) revert ReentrantCall();
        _locked = 2;
        _;
        _locked = 1;
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Bounty lifecycle — creation
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Create a bounty with a reward, a submission deadline, and a reveal
     *         deadline. The attached `msg.value` becomes the reward escrow.
     * @param  title              Human-readable bounty title.
     * @param  rubric             Judging rubric the AI must score answers against.
     * @param  submissionDeadline Unix time; commitments accepted strictly before.
     * @param  revealDeadline     Unix time; reveals accepted in [submission, reveal).
     * @return bountyId           The id assigned to the new bounty.
     */
    function createBounty(
        string calldata title,
        string calldata rubric,
        uint64 submissionDeadline,
        uint64 revealDeadline
    ) external payable returns (uint256 bountyId) {
        if (msg.value == 0) revert RewardRequired();
        if (
            submissionDeadline <= block.timestamp ||
            revealDeadline <= submissionDeadline
        ) revert InvalidDeadlines();

        bountyId = nextBountyId++;

        Bounty storage bounty = bounties[bountyId];
        bounty.owner = msg.sender;
        bounty.title = title;
        bounty.rubric = rubric;
        bounty.reward = msg.value;
        bounty.submissionDeadline = submissionDeadline;
        bounty.revealDeadline = revealDeadline;
        bounty.winnerIndex = type(uint256).max;

        emit BountyCreated(
            bountyId,
            msg.sender,
            title,
            msg.value,
            submissionDeadline,
            revealDeadline
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Submission phase — commitments only (answers stay hidden)
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Submit a commitment hash during the submission phase. The plaintext
     *         answer is NOT revealed here — only its hash is stored on-chain.
     * @dev    The expected commitment is
     *           keccak256(abi.encodePacked(answer, salt, msg.sender, bountyId)).
     *         A participant may commit only once per bounty.
     * @param  bountyId   Target bounty.
     * @param  commitment The keccak256 commitment to the (answer, salt) pair.
     */
    function submitCommitment(
        uint256 bountyId,
        bytes32 commitment
    ) external bountyExists(bountyId) {
        Bounty storage bounty = bounties[bountyId];

        if (block.timestamp >= bounty.submissionDeadline) {
            revert SubmissionPhaseOver();
        }
        if (commitment == bytes32(0)) revert ZeroCommitment();
        if (bounty.committerIndexPlusOne[msg.sender] != 0) {
            revert AlreadyCommitted();
        }
        if (bounty.submissions.length >= MAX_SUBMISSIONS) {
            revert TooManySubmissions();
        }

        bounty.submissions.push(
            Submission({
                submitter: msg.sender,
                commitment: commitment,
                answer: "",
                revealed: false
            })
        );
        // Store index + 1 so that the default value (0) reliably means "none".
        bounty.committerIndexPlusOne[msg.sender] = bounty.submissions.length;

        emit CommitmentSubmitted(
            bountyId,
            bounty.submissions.length - 1,
            msg.sender,
            commitment
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Reveal phase — open commitments after the submission deadline
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Reveal a previously committed answer. Valid only after the
     *         submission deadline and before the reveal deadline.
     * @dev    Recomputes keccak256(abi.encodePacked(answer, salt, msg.sender,
     *         bountyId)) and requires it to equal the stored commitment. Only
     *         successfully revealed submissions become eligible for judging.
     * @param  bountyId Target bounty.
     * @param  answer   The plaintext answer being revealed.
     * @param  salt     The secret salt used when building the commitment.
     */
    function revealAnswer(
        uint256 bountyId,
        string calldata answer,
        bytes32 salt
    ) external bountyExists(bountyId) {
        Bounty storage bounty = bounties[bountyId];

        if (block.timestamp < bounty.submissionDeadline) {
            revert RevealPhaseNotStarted();
        }
        if (block.timestamp >= bounty.revealDeadline) revert RevealPhaseOver();

        uint256 indexPlusOne = bounty.committerIndexPlusOne[msg.sender];
        if (indexPlusOne == 0) revert NoCommitment();
        if (bytes(answer).length > MAX_ANSWER_LENGTH) revert AnswerTooLong();

        Submission storage submission = bounty.submissions[indexPlusOne - 1];
        if (submission.revealed) revert AlreadyRevealed();

        bytes32 expected = keccak256(
            abi.encodePacked(answer, salt, msg.sender, bountyId)
        );
        if (expected != submission.commitment) revert CommitmentMismatch();

        submission.answer = answer;
        submission.revealed = true;
        unchecked {
            bounty.revealedCount += 1;
        }

        emit AnswerRevealed(bountyId, indexPlusOne - 1, msg.sender);
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Judging — single batched LLM call over all revealed answers
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Judge every revealed answer in one batched Ritual LLM request.
     * @dev    Only the bounty owner, only after the reveal deadline, and only if
     *         at least one answer was revealed. The `llmInput` is built off-chain
     *         (see web/src/lib/ritualLlm.ts) and contains ALL revealed answers in
     *         a single prompt — never one LLM call per answer. The raw completion
     *         bytes are stored verbatim; parsing/validation happens off-chain and
     *         a human owner makes the final call via `finalizeWinner`.
     * @param  bountyId Target bounty.
     * @param  llmInput ABI-encoded batch request forwarded to the LLM precompile.
     */
    function judgeAll(
        uint256 bountyId,
        bytes calldata llmInput
    ) external bountyExists(bountyId) onlyOwner(bountyId) {
        Bounty storage bounty = bounties[bountyId];

        if (block.timestamp < bounty.revealDeadline) {
            revert RevealPhaseNotOver();
        }
        if (bounty.judged) revert AlreadyJudged();
        if (bounty.finalized) revert AlreadyFinalized();
        if (bounty.revealedCount == 0) revert NoRevealedSubmissions();

        bytes memory review = _judge(llmInput);

        bounty.judged = true;
        bounty.aiReview = review;

        emit AllAnswersJudged(bountyId, bounty.revealedCount, review);
    }

    /**
     * @dev Forward the batch request to Ritual's LLM inference precompile and
     *      return the completion bytes. Isolated and marked `virtual` so tests can
     *      override it with a deterministic result — the precompile is only
     *      available on Ritual Chain, not in a local EVM.
     */
    function _judge(
        bytes calldata llmInput
    ) internal virtual returns (bytes memory) {
        bytes memory output = _executePrecompile(
            LLM_INFERENCE_PRECOMPILE,
            llmInput
        );

        (
            bool hasError,
            bytes memory completionData,
            ,
            string memory errorMessage,

        ) = abi.decode(output, (bool, bytes, bytes, string, ConvoHistory));

        if (hasError) revert JudgingFailed(errorMessage);

        return completionData;
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Finalization — human-in-the-loop payout to exactly one winner
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Finalize a bounty by paying the reward to exactly one winner.
     * @dev    Only the owner, only after judging, only once. The winner must be a
     *         revealed submission (unrevealed entries are never eligible). Uses
     *         checks-effects-interactions plus a reentrancy guard around the
     *         external value transfer.
     * @param  bountyId    Target bounty.
     * @param  winnerIndex Index into the bounty's submissions array.
     */
    function finalizeWinner(
        uint256 bountyId,
        uint256 winnerIndex
    ) external bountyExists(bountyId) onlyOwner(bountyId) nonReentrant {
        Bounty storage bounty = bounties[bountyId];

        if (!bounty.judged) revert NotJudged();
        if (bounty.finalized) revert AlreadyFinalized();
        if (winnerIndex >= bounty.submissions.length) {
            revert InvalidWinnerIndex();
        }

        Submission storage winnerSub = bounty.submissions[winnerIndex];
        if (!winnerSub.revealed) revert WinnerNotRevealed();

        // Effects before interaction.
        bounty.finalized = true;
        bounty.winnerIndex = winnerIndex;
        uint256 reward = bounty.reward;
        bounty.reward = 0;
        address winner = winnerSub.submitter;

        (bool ok, ) = payable(winner).call{value: reward}("");
        if (!ok) revert PaymentFailed();

        emit WinnerFinalized(bountyId, winnerIndex, winner, reward);
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Views & helpers
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Read the public, non-secret fields of a bounty.
    function getBounty(
        uint256 bountyId
    ) external view bountyExists(bountyId) returns (BountyView memory) {
        Bounty storage bounty = bounties[bountyId];
        return
            BountyView({
                owner: bounty.owner,
                title: bounty.title,
                rubric: bounty.rubric,
                reward: bounty.reward,
                submissionDeadline: bounty.submissionDeadline,
                revealDeadline: bounty.revealDeadline,
                judged: bounty.judged,
                finalized: bounty.finalized,
                submissionCount: bounty.submissions.length,
                revealedCount: bounty.revealedCount,
                winnerIndex: bounty.winnerIndex,
                aiReview: bounty.aiReview
            });
    }

    /**
     * @notice Read a single submission. Before a valid reveal, `answer` is empty
     *         and `revealed` is false — the plaintext is never exposed early.
     */
    function getSubmission(
        uint256 bountyId,
        uint256 index
    )
        external
        view
        bountyExists(bountyId)
        returns (
            address submitter,
            bytes32 commitment,
            bool revealed,
            string memory answer
        )
    {
        Bounty storage bounty = bounties[bountyId];
        if (index >= bounty.submissions.length) revert InvalidIndex();
        Submission storage submission = bounty.submissions[index];
        return (
            submission.submitter,
            submission.commitment,
            submission.revealed,
            submission.answer
        );
    }

    /// @notice Look up a participant's commitment status for a bounty.
    function getCommitment(
        uint256 bountyId,
        address participant
    )
        external
        view
        bountyExists(bountyId)
        returns (bool committed, uint256 index, bytes32 commitment, bool revealed)
    {
        Bounty storage bounty = bounties[bountyId];
        uint256 indexPlusOne = bounty.committerIndexPlusOne[participant];
        if (indexPlusOne == 0) {
            return (false, 0, bytes32(0), false);
        }
        Submission storage submission = bounty.submissions[indexPlusOne - 1];
        return (
            true,
            indexPlusOne - 1,
            submission.commitment,
            submission.revealed
        );
    }

    /// @notice Number of commitments submitted to a bounty.
    function submissionCount(
        uint256 bountyId
    ) external view bountyExists(bountyId) returns (uint256) {
        return bounties[bountyId].submissions.length;
    }

    /**
     * @notice Pure helper that reproduces the on-chain commitment formula, so
     *         front-ends and tests build commitments identically to verification.
     * @return The keccak256 commitment for the given inputs.
     */
    function computeCommitment(
        string calldata answer,
        bytes32 salt,
        address submitter,
        uint256 bountyId
    ) external pure returns (bytes32) {
        return keccak256(abi.encodePacked(answer, salt, submitter, bountyId));
    }
}
