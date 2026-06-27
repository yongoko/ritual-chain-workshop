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
}
