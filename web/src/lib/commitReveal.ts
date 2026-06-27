import { encodePacked, keccak256, type Address, type Hex } from "viem";

/**
 * ============================================================================
 *  Commit-reveal helpers (client side)
 * ============================================================================
 *
 * These reproduce the exact on-chain commitment formula used by
 * `CommitRevealAIJudge`:
 *
 *     commitment = keccak256(abi.encodePacked(answer, salt, submitter, bountyId))
 *
 * Binding `submitter` and `bountyId` into the hash is what stops a copycat from
 * re-using someone else's commitment. A reveal built from the same inputs will
 * pass the contract's verification in `revealAnswer`.
 *
 * The parity between this function and the contract is asserted on-chain by the
 * Solidity test `test_ComputeCommitment_MatchesContractFormula`.
 */
export function computeCommitment(params: {
  answer: string;
  salt: Hex; // 32-byte hex
  submitter: Address;
  bountyId: bigint;
}): Hex {
  const { answer, salt, submitter, bountyId } = params;
  return keccak256(
    encodePacked(
      ["string", "bytes32", "address", "uint256"],
      [answer, salt, submitter, bountyId],
    ),
  );
}

/** Generate a cryptographically-random 32-byte salt (works in browser + Node). */
export function randomSalt(): Hex {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  const hex = Array.from(bytes)
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
  return `0x${hex}` as Hex;
}

/**
 * The secret material a participant must keep locally to reveal later. Only
 * `commitment` is published on-chain during the submission phase; `answer` and
 * `salt` stay private until the reveal phase.
 */
export type StoredCommitment = {
  bountyId: string;
  answer: string;
  salt: Hex;
  commitment: Hex;
};

/**
 * Build a commitment for a bounty answer. If no salt is supplied a random one is
 * generated. Persist the returned object (e.g. localStorage) so the participant
 * can reveal during the reveal phase.
 */
export function buildCommitment(params: {
  answer: string;
  submitter: Address;
  bountyId: bigint;
  salt?: Hex;
}): StoredCommitment {
  const salt = params.salt ?? randomSalt();
  const commitment = computeCommitment({
    answer: params.answer,
    salt,
    submitter: params.submitter,
    bountyId: params.bountyId,
  });
  return {
    bountyId: params.bountyId.toString(),
    answer: params.answer,
    salt,
    commitment,
  };
}
