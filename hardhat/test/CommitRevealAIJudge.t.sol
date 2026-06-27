// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {CommitRevealAIJudge} from "../contracts/CommitRevealAIJudge.sol";

/**
 * @dev Test harness.
 *
 *      `judgeAll` calls Ritual's LLM inference precompile (address 0x0802),
 *      which only exists on Ritual Chain — there is no such precompile in a
 *      local EVM. The production `_judge` is `virtual` precisely so a test can
 *      substitute the *external* judging step with a deterministic result, while
 *      every other line of `judgeAll` (access control, deadlines, eligibility,
 *      state transitions, events) runs exactly as in production.
 *
 *      This is a test seam around an unavailable precompile, NOT mocked bounty
 *      data: commitments, reveals and payouts all execute against the real
 *      contract logic.
 */
contract Harness is CommitRevealAIJudge {
    /// Number of times the LLM step was invoked — must be exactly 1 per bounty
    /// (proves batch judging, never one call per answer).
    uint256 public judgeCalls;
    /// The exact `llmInput` forwarded to the (overridden) judging step.
    bytes public lastLlmInput;
    /// Deterministic review bytes the harness returns instead of the precompile.
    bytes public review = bytes("BATCH_REVIEW_RESULT");
    /// When true, simulate a failed inference (hasError == true on Ritual).
    bool public shouldFail;

    function setReview(bytes calldata r) external {
        review = r;
    }

    function setShouldFail(bool v) external {
        shouldFail = v;
    }

    function _judge(
        bytes calldata llmInput
    ) internal override returns (bytes memory) {
        judgeCalls += 1;
        lastLlmInput = llmInput;
        if (shouldFail) revert JudgingFailed("forced failure");
        return review;
    }
}

contract CommitRevealAIJudgeTest is Test {
    Harness internal judge;

    address internal owner;
    address internal alice;
    address internal bob;
    address internal carol;

    uint256 internal constant REWARD = 1 ether;

    function setUp() public {
        // A sane, non-zero base timestamp so deadline math never underflows.
        vm.warp(1_000_000);

        judge = new Harness();

        owner = makeAddr("owner");
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        carol = makeAddr("carol");

        vm.deal(owner, 100 ether);
    }

    // ── helpers ──────────────────────────────────────────────────────────────

    function _createBounty()
        internal
        returns (uint256 id, uint64 subDl, uint64 revDl)
    {
        subDl = uint64(block.timestamp + 1 days);
        revDl = uint64(block.timestamp + 2 days);
        vm.prank(owner);
        id = judge.createBounty{value: REWARD}(
            "Best one-liner",
            "Clearest, correct and concise wins",
            subDl,
            revDl
        );
    }

    // ── createBounty / getBounty ───────────────────────────────────────────────

    function test_CreateBounty_StoresFields() public {
        (uint256 id, uint64 subDl, uint64 revDl) = _createBounty();

        CommitRevealAIJudge.BountyView memory b = judge.getBounty(id);
        assertEq(id, 1, "first id is 1");
        assertEq(b.owner, owner, "owner");
        assertEq(b.reward, REWARD, "reward escrowed");
        assertEq(b.submissionDeadline, subDl, "submission deadline");
        assertEq(b.revealDeadline, revDl, "reveal deadline");
        assertFalse(b.judged, "not judged");
        assertFalse(b.finalized, "not finalized");
        assertEq(b.submissionCount, 0, "no submissions yet");
        assertEq(b.revealedCount, 0, "no reveals yet");
        assertEq(b.winnerIndex, type(uint256).max, "winner unset");
        assertEq(address(judge).balance, REWARD, "reward held in escrow");
    }

    function test_CreateBounty_AssignsSequentialIds() public {
        (uint256 id1, , ) = _createBounty();
        (uint256 id2, , ) = _createBounty();
        assertEq(id1, 1);
        assertEq(id2, 2);
        assertEq(judge.nextBountyId(), 3);
    }

    function test_CreateBounty_RevertsWithoutReward() public {
        uint64 subDl = uint64(block.timestamp + 1 days);
        uint64 revDl = uint64(block.timestamp + 2 days);
        vm.prank(owner);
        vm.expectRevert(CommitRevealAIJudge.RewardRequired.selector);
        judge.createBounty("t", "r", subDl, revDl);
    }

    function test_CreateBounty_RevertsSubmissionDeadlineNotFuture() public {
        uint64 subDl = uint64(block.timestamp); // not strictly in the future
        uint64 revDl = uint64(block.timestamp + 1 days);
        vm.prank(owner);
        vm.expectRevert(CommitRevealAIJudge.InvalidDeadlines.selector);
        judge.createBounty{value: REWARD}("t", "r", subDl, revDl);
    }

    function test_CreateBounty_RevertsRevealBeforeSubmission() public {
        uint64 subDl = uint64(block.timestamp + 2 days);
        uint64 revDl = uint64(block.timestamp + 1 days); // reveal <= submission
        vm.prank(owner);
        vm.expectRevert(CommitRevealAIJudge.InvalidDeadlines.selector);
        judge.createBounty{value: REWARD}("t", "r", subDl, revDl);
    }

    function test_GetBounty_RevertsForUnknownBounty() public {
        vm.expectRevert(CommitRevealAIJudge.BountyNotFound.selector);
        judge.getBounty(999);
    }

    // ── helper: commit ─────────────────────────────────────────────────────────

    function _commit(
        address who,
        uint256 id,
        string memory answer,
        bytes32 salt
    ) internal returns (bytes32 commitment) {
        commitment = keccak256(abi.encodePacked(answer, salt, who, id));
        vm.prank(who);
        judge.submitCommitment(id, commitment);
    }

    // ── submitCommitment ───────────────────────────────────────────────────────

    function test_SubmitCommitment_StoresHiddenAndCounts() public {
        (uint256 id, , ) = _createBounty();
        bytes32 c = _commit(alice, id, "answer-a", bytes32(uint256(0xA11CE)));

        (
            address submitter,
            bytes32 commitment,
            bool revealed,
            string memory answer
        ) = judge.getSubmission(id, 0);

        assertEq(submitter, alice, "submitter recorded");
        assertEq(commitment, c, "commitment stored");
        assertFalse(revealed, "not revealed yet");
        assertEq(bytes(answer).length, 0, "answer stays hidden before reveal");
        assertEq(judge.submissionCount(id), 1, "one submission");
    }

    function test_SubmitCommitment_RevertsAfterDeadline() public {
        (uint256 id, uint64 subDl, ) = _createBounty();
        vm.warp(subDl); // exactly at the deadline => closed (>=)
        bytes32 c = keccak256(abi.encodePacked("x", bytes32(uint256(1)), alice, id));
        vm.prank(alice);
        vm.expectRevert(CommitRevealAIJudge.SubmissionPhaseOver.selector);
        judge.submitCommitment(id, c);
    }

    function test_SubmitCommitment_RevertsZeroCommitment() public {
        (uint256 id, , ) = _createBounty();
        vm.prank(alice);
        vm.expectRevert(CommitRevealAIJudge.ZeroCommitment.selector);
        judge.submitCommitment(id, bytes32(0));
    }

    function test_SubmitCommitment_RevertsAlreadyCommitted() public {
        (uint256 id, , ) = _createBounty();
        _commit(alice, id, "a", bytes32(uint256(1)));
        bytes32 c2 = keccak256(abi.encodePacked("b", bytes32(uint256(2)), alice, id));
        vm.prank(alice);
        vm.expectRevert(CommitRevealAIJudge.AlreadyCommitted.selector);
        judge.submitCommitment(id, c2);
    }

    function test_SubmitCommitment_RevertsUnknownBounty() public {
        vm.prank(alice);
        vm.expectRevert(CommitRevealAIJudge.BountyNotFound.selector);
        judge.submitCommitment(42, keccak256("x"));
    }

    function test_SubmitCommitment_RevertsWhenFull() public {
        (uint256 id, , ) = _createBounty();
        uint256 max = judge.MAX_SUBMISSIONS();
        for (uint256 i = 0; i < max; i++) {
            address p = address(uint160(1000 + i));
            bytes32 c = keccak256(abi.encodePacked("ans", i, p, id));
            vm.prank(p);
            judge.submitCommitment(id, c);
        }
        assertEq(judge.submissionCount(id), max, "filled to capacity");

        address extra = address(uint160(99_999));
        bytes32 ce = keccak256(abi.encodePacked("x", extra, id));
        vm.prank(extra);
        vm.expectRevert(CommitRevealAIJudge.TooManySubmissions.selector);
        judge.submitCommitment(id, ce);
    }

    function test_GetCommitment_TracksParticipant() public {
        (uint256 id, , ) = _createBounty();

        (bool committed0, , , ) = judge.getCommitment(id, alice);
        assertFalse(committed0, "no commitment initially");

        bytes32 c = _commit(alice, id, "a", bytes32(uint256(7)));

        (
            bool committed,
            uint256 index,
            bytes32 commitment,
            bool revealed
        ) = judge.getCommitment(id, alice);
        assertTrue(committed, "now committed");
        assertEq(index, 0, "index 0");
        assertEq(commitment, c, "commitment matches");
        assertFalse(revealed, "not revealed");
    }

    // ── helper: reveal ─────────────────────────────────────────────────────────

    function _reveal(
        address who,
        uint256 id,
        string memory answer,
        bytes32 salt
    ) internal {
        vm.prank(who);
        judge.revealAnswer(id, answer, salt);
    }

    // ── computeCommitment parity + valid reveal ────────────────────────────────

    function test_ComputeCommitment_MatchesContractFormula() public {
        (uint256 id, , ) = _createBounty();
        string memory answer = "the answer";
        bytes32 salt = keccak256("a-secret-salt");

        bytes32 onchain = judge.computeCommitment(answer, salt, alice, id);
        bytes32 local = keccak256(abi.encodePacked(answer, salt, alice, id));
        assertEq(onchain, local, "helper reproduces verification formula");
    }

    function test_Reveal_Valid_StoresAnswerAndCounts() public {
        (uint256 id, uint64 subDl, ) = _createBounty();
        string memory answer = "alice's winning answer";
        bytes32 salt = bytes32(uint256(0xABCD));

        _commit(alice, id, answer, salt);
        vm.warp(subDl); // reveal window opens at the submission deadline
        _reveal(alice, id, answer, salt);

        (, , bool revealed, string memory got) = judge.getSubmission(id, 0);
        assertTrue(revealed, "marked revealed");
        assertEq(got, answer, "plaintext now readable");

        CommitRevealAIJudge.BountyView memory b = judge.getBounty(id);
        assertEq(b.revealedCount, 1, "revealedCount incremented");

        (, , , bool revealedFlag) = judge.getCommitment(id, alice);
        assertTrue(revealedFlag, "commitment marked revealed");
    }

    // ── invalid reveals ─────────────────────────────────────────────────────────

    function _stringOfLength(uint256 n) internal pure returns (string memory) {
        bytes memory b = new bytes(n);
        for (uint256 i = 0; i < n; i++) {
            b[i] = "a";
        }
        return string(b);
    }

    function test_Reveal_RevertsWrongSalt() public {
        (uint256 id, uint64 subDl, ) = _createBounty();
        _commit(alice, id, "answer", bytes32(uint256(1)));
        vm.warp(subDl);
        vm.prank(alice);
        vm.expectRevert(CommitRevealAIJudge.CommitmentMismatch.selector);
        judge.revealAnswer(id, "answer", bytes32(uint256(2)));
    }

    function test_Reveal_RevertsWrongAnswer() public {
        (uint256 id, uint64 subDl, ) = _createBounty();
        bytes32 salt = bytes32(uint256(3));
        _commit(alice, id, "answer", salt);
        vm.warp(subDl);
        vm.prank(alice);
        vm.expectRevert(CommitRevealAIJudge.CommitmentMismatch.selector);
        judge.revealAnswer(id, "tampered-answer", salt);
    }

    /// A copycat who re-uses someone else's commitment hash cannot reveal it,
    /// because msg.sender is bound into the hash.
    function test_Reveal_RevertsImpersonation() public {
        (uint256 id, uint64 subDl, ) = _createBounty();
        string memory answer = "stolen idea";
        bytes32 salt = bytes32(uint256(5));

        // Bob copies Alice's commitment (bound to ALICE) and submits it himself.
        bytes32 aliceBound = keccak256(
            abi.encodePacked(answer, salt, alice, id)
        );
        vm.prank(bob);
        judge.submitCommitment(id, aliceBound);

        vm.warp(subDl);
        // When Bob reveals, the contract recomputes with msg.sender = bob.
        vm.prank(bob);
        vm.expectRevert(CommitRevealAIJudge.CommitmentMismatch.selector);
        judge.revealAnswer(id, answer, salt);
    }

    function test_Reveal_RevertsDoubleReveal() public {
        (uint256 id, uint64 subDl, ) = _createBounty();
        bytes32 salt = bytes32(uint256(6));
        _commit(alice, id, "answer", salt);
        vm.warp(subDl);
        _reveal(alice, id, "answer", salt);
        vm.prank(alice);
        vm.expectRevert(CommitRevealAIJudge.AlreadyRevealed.selector);
        judge.revealAnswer(id, "answer", salt);
    }

    function test_Reveal_RevertsNoCommitment() public {
        (uint256 id, uint64 subDl, ) = _createBounty();
        vm.warp(subDl);
        vm.prank(alice);
        vm.expectRevert(CommitRevealAIJudge.NoCommitment.selector);
        judge.revealAnswer(id, "answer", bytes32(uint256(1)));
    }

    function test_Reveal_RevertsAnswerTooLong() public {
        (uint256 id, uint64 subDl, ) = _createBounty();
        uint256 maxLen = judge.MAX_ANSWER_LENGTH();
        string memory longAnswer = _stringOfLength(maxLen + 1);
        bytes32 salt = bytes32(uint256(9));

        bytes32 c = keccak256(abi.encodePacked(longAnswer, salt, alice, id));
        vm.prank(alice);
        judge.submitCommitment(id, c);

        vm.warp(subDl);
        vm.prank(alice);
        vm.expectRevert(CommitRevealAIJudge.AnswerTooLong.selector);
        judge.revealAnswer(id, longAnswer, salt);
    }

    // ── reveal window boundaries ────────────────────────────────────────────────

    function test_Reveal_RevertsBeforeSubmissionDeadline() public {
        (uint256 id, , ) = _createBounty();
        bytes32 salt = bytes32(uint256(1));
        _commit(alice, id, "a", salt);
        // Still inside the submission phase: revealing is not allowed yet.
        vm.prank(alice);
        vm.expectRevert(CommitRevealAIJudge.RevealPhaseNotStarted.selector);
        judge.revealAnswer(id, "a", salt);
    }

    function test_Reveal_RevertsAtExactRevealDeadline() public {
        (uint256 id, , uint64 revDl) = _createBounty();
        bytes32 salt = bytes32(uint256(2));
        _commit(alice, id, "a", salt);
        vm.warp(revDl); // exactly at the reveal deadline => closed (>=)
        vm.prank(alice);
        vm.expectRevert(CommitRevealAIJudge.RevealPhaseOver.selector);
        judge.revealAnswer(id, "a", salt);
    }

    function test_Reveal_WorksJustBeforeRevealDeadline() public {
        (uint256 id, , uint64 revDl) = _createBounty();
        bytes32 salt = bytes32(uint256(3));
        _commit(alice, id, "a", salt);
        vm.warp(uint256(revDl) - 1); // last valid second
        _reveal(alice, id, "a", salt);
        (, , bool revealed, ) = judge.getSubmission(id, 0);
        assertTrue(revealed, "reveal accepted at edge of window");
    }

    // ── judging ─────────────────────────────────────────────────────────────────

    /// Commit + reveal Alice and Bob, then warp past the reveal deadline.
    function _twoRevealedReadyToJudge() internal returns (uint256 id) {
        uint64 subDl;
        uint64 revDl;
        (id, subDl, revDl) = _createBounty();
        bytes32 sa = bytes32(uint256(0x1));
        bytes32 sb = bytes32(uint256(0x2));
        _commit(alice, id, "alice answer", sa);
        _commit(bob, id, "bob answer", sb);
        vm.warp(subDl);
        _reveal(alice, id, "alice answer", sa);
        _reveal(bob, id, "bob answer", sb);
        vm.warp(revDl);
    }

    function test_JudgeAll_RevertsNonOwner() public {
        uint256 id = _twoRevealedReadyToJudge();
        vm.prank(alice);
        vm.expectRevert(CommitRevealAIJudge.NotBountyOwner.selector);
        judge.judgeAll(id, hex"1234");
    }

    function test_JudgeAll_RevertsBeforeRevealDeadline() public {
        (uint256 id, uint64 subDl, ) = _createBounty();
        bytes32 s = bytes32(uint256(1));
        _commit(alice, id, "a", s);
        vm.warp(subDl);
        _reveal(alice, id, "a", s); // revealed, but reveal window still open
        vm.prank(owner);
        vm.expectRevert(CommitRevealAIJudge.RevealPhaseNotOver.selector);
        judge.judgeAll(id, hex"01");
    }

    function test_JudgeAll_RevertsWhenNothingRevealed() public {
        (uint256 id, , uint64 revDl) = _createBounty();
        _commit(alice, id, "a", bytes32(uint256(1))); // committed, never revealed
        vm.warp(revDl);
        vm.prank(owner);
        vm.expectRevert(CommitRevealAIJudge.NoRevealedSubmissions.selector);
        judge.judgeAll(id, hex"01");
    }

    function test_JudgeAll_StoresReviewInSingleBatchedCall() public {
        uint256 id = _twoRevealedReadyToJudge();
        bytes memory input = hex"deadbeefcafe";
        vm.prank(owner);
        judge.judgeAll(id, input);

        CommitRevealAIJudge.BountyView memory b = judge.getBounty(id);
        assertTrue(b.judged, "marked judged");
        assertEq(b.aiReview, judge.review(), "stores the review bytes");
        assertEq(b.revealedCount, 2, "two revealed answers judged");
        assertEq(judge.judgeCalls(), 1, "exactly one LLM call (batched)");
        assertEq(judge.lastLlmInput(), input, "forwards the batch input as-is");
    }

    function test_JudgeAll_RevertsDoubleJudge() public {
        uint256 id = _twoRevealedReadyToJudge();
        vm.prank(owner);
        judge.judgeAll(id, hex"01");
        vm.prank(owner);
        vm.expectRevert(CommitRevealAIJudge.AlreadyJudged.selector);
        judge.judgeAll(id, hex"02");
    }

    function test_JudgeAll_PropagatesInferenceError() public {
        uint256 id = _twoRevealedReadyToJudge();
        judge.setShouldFail(true);
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                CommitRevealAIJudge.JudgingFailed.selector,
                "forced failure"
            )
        );
        judge.judgeAll(id, hex"01");
    }

    // ── finalization ────────────────────────────────────────────────────────────

    function test_FinalizeWinner_PaysExactlyOneWinner() public {
        uint256 id = _twoRevealedReadyToJudge();
        vm.prank(owner);
        judge.judgeAll(id, hex"01");

        uint256 balBefore = alice.balance;
        vm.prank(owner);
        judge.finalizeWinner(id, 0); // alice is index 0

        assertEq(alice.balance, balBefore + REWARD, "winner paid the reward");
        CommitRevealAIJudge.BountyView memory b = judge.getBounty(id);
        assertTrue(b.finalized, "finalized");
        assertEq(b.winnerIndex, 0, "winner index recorded");
        assertEq(b.reward, 0, "escrow drained");
        assertEq(address(judge).balance, 0, "no funds left in contract");
    }

    function test_FinalizeWinner_RevertsNotJudged() public {
        uint256 id = _twoRevealedReadyToJudge();
        vm.prank(owner);
        vm.expectRevert(CommitRevealAIJudge.NotJudged.selector);
        judge.finalizeWinner(id, 0);
    }

    function test_FinalizeWinner_RevertsNonOwner() public {
        uint256 id = _twoRevealedReadyToJudge();
        vm.prank(owner);
        judge.judgeAll(id, hex"01");
        vm.prank(alice);
        vm.expectRevert(CommitRevealAIJudge.NotBountyOwner.selector);
        judge.finalizeWinner(id, 0);
    }

    function test_FinalizeWinner_RevertsInvalidIndex() public {
        uint256 id = _twoRevealedReadyToJudge();
        vm.prank(owner);
        judge.judgeAll(id, hex"01");
        vm.prank(owner);
        vm.expectRevert(CommitRevealAIJudge.InvalidWinnerIndex.selector);
        judge.finalizeWinner(id, 99);
    }

    function test_FinalizeWinner_RevertsUnrevealedWinner() public {
        (uint256 id, uint64 subDl, uint64 revDl) = _createBounty();
        bytes32 sa = bytes32(uint256(1));
        _commit(alice, id, "a", sa);
        _commit(bob, id, "b", bytes32(uint256(2))); // bob never reveals
        vm.warp(subDl);
        _reveal(alice, id, "a", sa);
        vm.warp(revDl);
        vm.prank(owner);
        judge.judgeAll(id, hex"01");

        vm.prank(owner);
        vm.expectRevert(CommitRevealAIJudge.WinnerNotRevealed.selector);
        judge.finalizeWinner(id, 1); // bob (unrevealed) is ineligible
    }

    function test_FinalizeWinner_RevertsDoubleFinalize() public {
        uint256 id = _twoRevealedReadyToJudge();
        vm.prank(owner);
        judge.judgeAll(id, hex"01");
        vm.prank(owner);
        judge.finalizeWinner(id, 0);
        vm.prank(owner);
        vm.expectRevert(CommitRevealAIJudge.AlreadyFinalized.selector);
        judge.finalizeWinner(id, 1);
    }

    function test_FinalizeWinner_ReentrancyIsBlocked() public {
        ReentrantWinner attacker = new ReentrantWinner(judge);
        (uint256 id, uint64 subDl, uint64 revDl) = _createBounty();

        bytes32 s = bytes32(uint256(0xBEEF));
        bytes32 c = keccak256(abi.encodePacked("a", s, address(attacker), id));
        vm.prank(address(attacker));
        judge.submitCommitment(id, c);
        vm.warp(subDl);
        vm.prank(address(attacker));
        judge.revealAnswer(id, "a", s);
        vm.warp(revDl);
        vm.prank(owner);
        judge.judgeAll(id, hex"01");

        attacker.arm(id, 0);
        // The reentrant call inside receive() trips the guard, the payout fails,
        // and the whole finalize reverts — no double spend.
        vm.prank(owner);
        vm.expectRevert(CommitRevealAIJudge.PaymentFailed.selector);
        judge.finalizeWinner(id, 0);

        assertEq(address(judge).balance, REWARD, "escrow untouched");
    }
}


/// @dev Malicious winner that tries to re-enter finalizeWinner during payout.
contract ReentrantWinner {
    CommitRevealAIJudge public immutable target;
    uint256 public bountyId;
    uint256 public winnerIndex;
    bool public attacked;

    constructor(CommitRevealAIJudge t) {
        target = t;
    }

    function arm(uint256 b, uint256 w) external {
        bountyId = b;
        winnerIndex = w;
    }

    receive() external payable {
        if (!attacked) {
            attacked = true;
            target.finalizeWinner(bountyId, winnerIndex);
        }
    }
}
