# Privacy-Preserving AI Bounty Judge — Commit-Reveal

> Ritual Academy · Proof of Building · **Required Track: Commit-Reveal Bounty**
> Fork of [`cozfuttu/ritual-chain-workshop`](https://github.com/cozfuttu/ritual-chain-workshop).

The original workshop contract (`hardhat/contracts/AIJudge.sol`) made every answer
**public the instant it was submitted**. In a bounty where only one person can win,
that is unfair: a late participant can read earlier answers, copy the good ideas,
and submit a slightly better version.

This submission fixes that with a **commit-reveal** flow in a new contract,
[`hardhat/contracts/CommitRevealAIJudge.sol`](hardhat/contracts/CommitRevealAIJudge.sol).
Answers stay hidden during submission and only become public when their owner
opens them during the reveal phase — after which Ritual's LLM judges all revealed
answers in a single batch.

- **Lifecycle & API** — this file.
- **Architecture note (commit-reveal vs Ritual-native TEE)** — [`ARCHITECTURE.md`](ARCHITECTURE.md).
- **Reflection answer** — [`REFLECTION.md`](REFLECTION.md).
- **Deployed address + deploy tx** — [`DEPLOYMENT.md`](DEPLOYMENT.md).

---

## 1. The new bounty lifecycle

```
   ┌── Submission phase ──┐   ┌──── Reveal phase ────┐   ┌── Judge ──┐   ┌─ Finalize ─┐
   │  t < submissionDl    │   │ submissionDl ≤ t <   │   │  t ≥      │   │  owner     │
   │                      │   │ revealDl             │   │  revealDl │   │  picks 1   │
   ▼                      ▼   ▼                      ▼   ▼           ▼   ▼            ▼
createBounty        submitCommitment           revealAnswer       judgeAll      finalizeWinner
 (escrow reward)    (hash only, hidden)        (open + verify)    (1 batch LLM) (pay winner)
```

1. **`createBounty(title, rubric, submissionDeadline, revealDeadline)`** *(payable)* —
   the owner escrows the reward and sets two deadlines.
2. **`submitCommitment(bountyId, commitment)`** — during the submission phase a
   participant publishes **only** a hash:
   `commitment = keccak256(abi.encodePacked(answer, salt, msg.sender, bountyId))`.
   The plaintext answer never touches the chain yet. One commitment per address.
3. **`revealAnswer(bountyId, answer, salt)`** — after the submission deadline and
   before the reveal deadline, the participant reveals. The contract recomputes the
   hash with `msg.sender` + `bountyId` bound in and accepts it **only if it matches**
   the stored commitment. Only revealed answers become eligible for judging.
4. **`judgeAll(bountyId, llmInput)`** — after the reveal deadline, the owner sends
   **all** revealed answers to Ritual's LLM inference precompile in a **single batch
   request** (never one call per answer). The raw completion is stored on-chain.
5. **`finalizeWinner(bountyId, winnerIndex)`** — the owner reviews the AI's
   recommendation and finalizes exactly one winner, who is paid the reward.
   AI recommends; a human decides (human-in-the-loop).

## 2. Contract rules enforced

| Rule | Where |
| --- | --- |
| Commitments only **before** the submission deadline | `submitCommitment` → `SubmissionPhaseOver` |
| One commitment per participant per bounty | `submitCommitment` → `AlreadyCommitted` |
| Reveal only **after** submission deadline and **before** reveal deadline | `revealAnswer` → `RevealPhaseNotStarted` / `RevealPhaseOver` |
| A reveal is valid only if the hash matches | `revealAnswer` → `CommitmentMismatch` |
| `msg.sender` + `bountyId` bound into the hash (anti-copy) | commitment formula |
| Unrevealed submissions are never judged or paid | `judgeAll` (`revealedCount`), `finalizeWinner` → `WinnerNotRevealed` |
| Owner can judge only **after** the reveal deadline | `judgeAll` → `RevealPhaseNotOver` |
| Owner can finalize only **after** judging | `finalizeWinner` → `NotJudged` |
| Exactly one winner is paid, once | `finalizeWinner` → `AlreadyFinalized` |
| Access control on judge/finalize | `onlyOwner` → `NotBountyOwner` |
| Safe payout (checks-effects-interactions + guard) | `finalizeWinner` + `nonReentrant` |

## 3. Why bind `msg.sender` and `bountyId`?

If the commitment were just `keccak256(answer, salt)`, a copycat could watch the
mempool, copy your commitment hash, submit it as their own, and then reveal "your"
answer as theirs. Binding the submitter's address and the bounty id means a copied
hash can only ever be opened by the original author, for the original bounty.
This is proven on-chain by `test_Reveal_RevertsImpersonation`.

## 4. Ritual integration & batch judging

`judgeAll` forwards an off-chain-built `llmInput` to the **LLM inference precompile
at `0x0802`** (see `hardhat/contracts/utils/PrecompileConsumer.sol`). The Ritual
block builder runs the model inside a TEE executor and replays the transaction with
the signed result, which the contract decodes and stores. The prompt packs **all**
revealed answers into one request (see `web/src/lib/ritualLlm.ts`), satisfying the
"batch judging, not one call per answer" requirement. Inference is paid via the
Ritual Wallet (`0x532F…3948`); the owner deposits before judging.

The AI output is **not** auto-paid: `judgeAll` only stores the raw review bytes,
and a human owner parses the recommendation off-chain and calls `finalizeWinner`.

## 5. Build, test, deploy

```bash
cd hardhat
pnpm install
npx hardhat compile          # solc 0.8.24
npx hardhat test solidity    # 37 passing — see hardhat/test/CommitRevealAIJudge.t.sol
```

Deploy to Ritual Chain (chainId 1979):

```bash
cp .env.example .env
nano .env                    # set DEPLOYER_PRIVATE_KEY=0x...  (never committed)
node scripts/deploy.ts       # prints contract address + deploy tx hash
# or, via Ignition:
npx hardhat ignition deploy --network ritual ignition/modules/CommitRevealAIJudge.ts
```

`.env` is gitignored; the deploy script logs only the deployer's public address,
the contract address and the transaction hash — never the private key.

## 6. Tests (reveal cases covered)

The Solidity suite (`hardhat/test/CommitRevealAIJudge.t.sol`, forge-std) covers the
full lifecycle with **37 passing tests**, including the required valid/invalid
reveal cases: correct reveal, wrong salt, wrong answer, impersonation (sender
binding), double reveal, reveal with no commitment, oversized answer, reveal before
the window opens, and reveal at/after the reveal deadline — plus judging access
control, single-batch judging, payout, winner eligibility and a reentrancy attack.
See [`ARCHITECTURE.md`](ARCHITECTURE.md) §"Test plan" for the full matrix.

> The judging step calls a Ritual-only precompile that does not exist in a local
> EVM, so tests override the *external* `_judge` call via a `virtual` seam while
> running every other line (access control, deadlines, eligibility, payout) for
> real. This is a test seam, not mocked bounty data.

## 7. Repository layout

```
hardhat/
  contracts/
    CommitRevealAIJudge.sol     ← the commit-reveal contract (this submission)
    AIJudge.sol                 ← original public-answer workshop contract (kept for reference)
    utils/PrecompileConsumer.sol
  test/CommitRevealAIJudge.t.sol  ← 37 forge-std tests
  ignition/modules/CommitRevealAIJudge.ts
  scripts/deploy.ts             ← viem deploy script (.env based)
web/
  src/abi/CommitRevealAIJudge.ts  ← generated ABI
  src/lib/commitReveal.ts         ← client-side commitment helper
ARCHITECTURE.md · REFLECTION.md · DEPLOYMENT.md
```
