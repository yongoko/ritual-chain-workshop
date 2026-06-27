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
}
