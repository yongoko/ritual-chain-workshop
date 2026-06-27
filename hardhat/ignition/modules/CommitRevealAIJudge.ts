import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

/**
 * Ignition module for the commit-reveal bounty judge.
 *
 * Deploy locally:
 *   npx hardhat ignition deploy ignition/modules/CommitRevealAIJudge.ts
 *
 * Deploy to Ritual Chain (needs DEPLOYER_PRIVATE_KEY in the environment, see
 * hardhat.config.ts → networks.ritual):
 *   npx hardhat ignition deploy --network ritual ignition/modules/CommitRevealAIJudge.ts
 */
export default buildModule("CommitRevealAIJudgeModule", (m) => {
  const commitRevealAIJudge = m.contract("CommitRevealAIJudge");

  return { commitRevealAIJudge };
});
