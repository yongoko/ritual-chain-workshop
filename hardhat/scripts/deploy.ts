/**
 * Deploy CommitRevealAIJudge to Ritual Chain (or any EVM chain) with viem.
 *
 * Usage (from the hardhat/ directory):
 *   npx hardhat compile
 *   node scripts/deploy.ts          # reads hardhat/.env automatically
 *
 * Required env (hardhat/.env, gitignored — see .env.example):
 *   DEPLOYER_PRIVATE_KEY=0x...      # funded deployer key
 * Optional:
 *   RITUAL_RPC_URL, RITUAL_CHAIN_ID
 *
 * This script prints ONLY the derived public address, the contract address and
 * the deploy transaction hash. It never logs the private key.
 */
import { readFileSync, existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import {
  createWalletClient,
  createPublicClient,
  http,
  defineChain,
  formatEther,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";

const HARDHAT_DIR = join(dirname(fileURLToPath(import.meta.url)), "..");

/** Minimal .env loader so no extra dependency is required. */
function loadEnv(): void {
  const envPath = join(HARDHAT_DIR, ".env");
  if (!existsSync(envPath)) return;
  for (const line of readFileSync(envPath, "utf8").split("\n")) {
    const trimmed = line.trim();
    if (trimmed === "" || trimmed.startsWith("#")) continue;
    const eq = trimmed.indexOf("=");
    if (eq === -1) continue;
    const key = trimmed.slice(0, eq).trim();
    let val = trimmed.slice(eq + 1).trim();
    if (
      (val.startsWith('"') && val.endsWith('"')) ||
      (val.startsWith("'") && val.endsWith("'"))
    ) {
      val = val.slice(1, -1);
    }
    if (process.env[key] === undefined) process.env[key] = val;
  }
}

loadEnv();

const RPC_URL = process.env.RITUAL_RPC_URL ?? "https://rpc.ritualfoundation.org";
const CHAIN_ID = Number(process.env.RITUAL_CHAIN_ID ?? "1979");

const ritual = defineChain({
  id: CHAIN_ID,
  name: "Ritual Chain",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: { default: { http: [RPC_URL] } },
});

function loadArtifact(): { abi: unknown[]; bytecode: `0x${string}` } {
  const p = join(
    HARDHAT_DIR,
    "artifacts/contracts/CommitRevealAIJudge.sol/CommitRevealAIJudge.json",
  );
  if (!existsSync(p)) {
    throw new Error("Artifact missing — run `npx hardhat compile` first.");
  }
  const json = JSON.parse(readFileSync(p, "utf8"));
  return { abi: json.abi, bytecode: json.bytecode };
}

async function main(): Promise<void> {
  const rawKey = process.env.DEPLOYER_PRIVATE_KEY?.trim();
  if (!rawKey) {
    throw new Error(
      "DEPLOYER_PRIVATE_KEY is not set. Add it to hardhat/.env (see .env.example).",
    );
  }
  const pk = (rawKey.startsWith("0x") ? rawKey : `0x${rawKey}`) as `0x${string}`;
  const account = privateKeyToAccount(pk);

  const publicClient = createPublicClient({
    chain: ritual,
    transport: http(RPC_URL),
  });
  const walletClient = createWalletClient({
    account,
    chain: ritual,
    transport: http(RPC_URL),
  });

  const chainId = await publicClient.getChainId();
  const balance = await publicClient.getBalance({ address: account.address });

  console.log("Network   :", ritual.name, `(chainId ${chainId})`);
  console.log("RPC       :", RPC_URL);
  console.log("Deployer  :", account.address);
  console.log("Balance   :", formatEther(balance), "ETH");

  if (balance === 0n) {
    throw new Error(
      "Deployer balance is 0 — fund the account on Ritual Chain before deploying.",
    );
  }

  const { abi, bytecode } = loadArtifact();
  console.log("\nDeploying CommitRevealAIJudge ...");

  const hash = await walletClient.deployContract({ abi, bytecode, args: [] });
  console.log("Deploy tx :", hash);

  const receipt = await publicClient.waitForTransactionReceipt({ hash });
  console.log("\n✅ Deployed");
  console.log("Contract  :", receipt.contractAddress);
  console.log("Block     :", receipt.blockNumber.toString());
  console.log("Gas used  :", receipt.gasUsed.toString());
  console.log("Status    :", receipt.status);
}

main().catch((err: unknown) => {
  console.error(
    "\n❌ Deployment failed:",
    err instanceof Error ? err.message : err,
  );
  process.exit(1);
});
