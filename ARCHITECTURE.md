# Architecture Note — Commit-Reveal vs Ritual-Native Hidden Submissions

This note compares the two ways to keep bounty answers hidden until judging:
the **commit-reveal** scheme implemented here, and a **Ritual-native TEE** design
for the advanced track. It ends with the test plan for the reveal cases.

---

## 1. Approach A — Commit-Reveal (implemented)

Participants publish only `keccak256(abi.encodePacked(answer, salt, msg.sender,
bountyId))` during submission. The plaintext is revealed later and verified
against the commitment.

```
 Submission phase                Reveal phase                 Judging
 ────────────────                ────────────                 ───────
 answer (kept locally) ──hash──▶ on-chain commitment
                                 │
                                 └─ reveal(answer,salt) ─▶ verify hash ─▶ eligible
                                                                          │
                                                  all revealed answers ───┴─▶ 1 batch LLM call
```

- **Where plaintext exists:** only off-chain (in the participant's wallet/UI)
  during submission. It becomes **public on-chain** the moment they reveal.
- **On-chain:** the reward escrow, one commitment hash per participant, the
  revealed plaintext answers (after reveal), and the raw AI review bytes.
- **Trust:** none beyond the EVM itself — works on any EVM chain.
- **Limitation:** answers are public *after reveal but before/around judging*.
  A participant who reveals early is exposed to late revealers within the reveal
  window. Commit-reveal hides answers **during submission**, not necessarily
  **until judging completes**. That gap is exactly what the advanced track closes.

## 2. Approach B — Ritual-Native Hidden Submissions (design)

Encrypt each answer **to a Ritual TEE executor** so plaintext never appears on
chain. The TEE decrypts privately at judging time, runs one batched inference,
and publishes only the winner plus a verifiable hash of the revealed bundle.

```
 Participant                      Chain (public)               Ritual TEE executor (private)
 ───────────                      ──────────────               ─────────────────────────────
 answer
   │ encrypt to executor pubkey
   ▼
 ciphertext ──store off-chain──▶ submissionRef + ciphertextHash
 (IPFS / storage-ref)            (only refs + hashes on-chain)
                                         │
                       judgeAll() ───────┘
                                         │  (after reveal deadline)
                                         ▼
                                  TEE pulls all ciphertexts ─▶ decrypts inside enclave
                                         │                      (plaintext only in TEE)
                                         ▼
                                  single batched LLM inference over all answers
                                         │
                                         ▼
                                  result: { winnerIndex, ranking, summary,
                                            revealedAnswersRef, revealedAnswersHash }
                                         │
                       on-chain ◀────────┘  store winner + revealedAnswersHash
                                            (bundle published off-chain; hash commits to it)
```

### Advanced-track design answers

- **Where do plaintext answers exist, and who can read them?** Only inside the
  TEE executor during judging, and in the author's own client before submission.
  No other participant — and not the public chain — ever sees plaintext before the
  final reveal. After judging, the full answer bundle is published off-chain and
  anyone can read it.
- **On-chain vs off-chain.** On-chain: reward escrow, per-submission
  `submissionRef` + `ciphertextHash`, the chosen `winnerIndex`, and
  `revealedAnswersHash`. Off-chain: the encrypted answer blobs (IPFS / storage-ref)
  and, after judging, the published plaintext bundle. Large plaintext is never
  stored on-chain — only a 32-byte hash commits to it.
- **How the LLM receives all submissions together.** `judgeAll` triggers one
  TEE workflow that fetches every ciphertext, decrypts them inside the enclave,
  concatenates them into a single structured prompt, and makes **one** inference
  call — batch judging, not one call per answer.
- **How the final reveal happens.** The TEE outputs `revealedAnswersRef`
  (where the plaintext bundle is published) and `revealedAnswersHash`
  (`keccak256` of the canonical bundle). All answers become public at once,
  after the decision — so no one gains an early-information advantage.
- **How the contract commits to the revealed bundle.** It stores
  `revealedAnswersHash`. Anyone can fetch the bundle at `revealedAnswersRef`,
  recompute the hash, and confirm it equals the on-chain value — proving the
  published answers are exactly what the AI judged.

### Example final output shape

```json
{
  "winnerIndex": 2,
  "ranking": [{ "index": 2, "score": 94, "reason": "Best satisfies the rubric." }],
  "revealedAnswersRef": "ipfs://… or storage-ref://…",
  "revealedAnswersHash": "0x…",
  "summary": "Submission 2 is the strongest answer."
}
```

## 3. Side-by-side

| | Commit-Reveal (A, built) | Ritual-Native TEE (B, design) |
| --- | --- | --- |
| Answers hidden during submission | ✅ | ✅ |
| Answers hidden **until judging done** | ⚠️ public once revealed | ✅ until final reveal |
| Plaintext on-chain | yes, after reveal | never (only refs + hashes) |
| Extra trust assumption | none (any EVM) | Ritual TEE executor + key flow |
| Participant UX | must return to reveal | encrypt once, no reveal step |
| Batch judging | ✅ one call | ✅ one call |
| Human finalization | ✅ | ✅ |

Commit-reveal is simple, portable, and trustless; the Ritual-native design removes
the reveal-window leak by keeping plaintext inside a TEE until the decision is made,
at the cost of depending on Ritual's private-execution stack.

## 4. Test plan — reveal cases (37 passing)

Run: `cd hardhat && npx hardhat test solidity`.

| Case | Test |
| --- | --- |
| Valid reveal stores answer, bumps `revealedCount` | `test_Reveal_Valid_StoresAnswerAndCounts` |
| Commitment formula parity (helper == on-chain) | `test_ComputeCommitment_MatchesContractFormula` |
| Wrong salt rejected | `test_Reveal_RevertsWrongSalt` |
| Wrong answer rejected | `test_Reveal_RevertsWrongAnswer` |
| Copying another's commitment fails (sender binding) | `test_Reveal_RevertsImpersonation` |
| Double reveal rejected | `test_Reveal_RevertsDoubleReveal` |
| Reveal with no commitment rejected | `test_Reveal_RevertsNoCommitment` |
| Oversized answer rejected | `test_Reveal_RevertsAnswerTooLong` |
| Reveal before window opens rejected | `test_Reveal_RevertsBeforeSubmissionDeadline` |
| Reveal at reveal deadline rejected | `test_Reveal_RevertsAtExactRevealDeadline` |
| Reveal at edge of window accepted | `test_Reveal_WorksJustBeforeRevealDeadline` |
| Submission after deadline rejected | `test_SubmitCommitment_RevertsAfterDeadline` |
| One commitment per participant | `test_SubmitCommitment_RevertsAlreadyCommitted` |
| Zero / capacity / unknown-bounty guards | `test_SubmitCommitment_Reverts{ZeroCommitment,WhenFull,UnknownBounty}` |
| Judge only owner / only after reveal / needs reveals | `test_JudgeAll_Reverts{NonOwner,BeforeRevealDeadline,WhenNothingRevealed}` |
| Single batched LLM call | `test_JudgeAll_StoresReviewInSingleBatchedCall` |
| Inference error propagates | `test_JudgeAll_PropagatesInferenceError` |
| Pay exactly one winner | `test_FinalizeWinner_PaysExactlyOneWinner` |
| Unrevealed winner ineligible | `test_FinalizeWinner_RevertsUnrevealedWinner` |
| Not-judged / non-owner / bad index / double finalize | `test_FinalizeWinner_Reverts{NotJudged,NonOwner,InvalidIndex,DoubleFinalize}` |
| Reentrancy blocked on payout | `test_FinalizeWinner_ReentrancyIsBlocked` |
| Bounty creation + deadline validation | `test_CreateBounty_*` |
