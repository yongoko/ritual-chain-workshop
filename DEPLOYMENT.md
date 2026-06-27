# Deployment

`CommitRevealAIJudge` is deployed and verified on **Ritual Chain**.

| Field | Value |
| --- | --- |
| Contract | `CommitRevealAIJudge` |
| Network | Ritual Chain |
| Chain ID | `1979` |
| RPC | `https://rpc.ritualfoundation.org` |
| **Contract address** | `0xf7da1aa7e3a97d73abb7c93b8696e7e6c4a66e9a` |
| **Deploy transaction** | `0x82ef5301addf28e6f990cd0a7364e322ea7b16879dd257ad0e38f72f41abd610` |
| Block | `38425648` |
| Deployer | `0x0eBab54518c4d1Bf127fb44E77bB4fFa73820A74` |
| Tx status | `success` (`0x1`) |
| Gas used | `2,941,549` |
| Solc | `0.8.24` |

## How it was deployed

```bash
cd hardhat
# DEPLOYER_PRIVATE_KEY set in hardhat/.env (gitignored — never committed)
node scripts/deploy.ts
```

## On-chain verification

The deployment was independently confirmed against the public RPC:

```bash
# 1) Non-empty bytecode at the address (13,211 bytes deployed)
curl -s -X POST https://rpc.ritualfoundation.org -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","method":"eth_getCode","params":["0xf7da1aa7e3a97d73abb7c93b8696e7e6c4a66e9a","latest"],"id":1}'

# 2) Successful deploy receipt (status 0x1, matching contractAddress)
curl -s -X POST https://rpc.ritualfoundation.org -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","method":"eth_getTransactionReceipt","params":["0x82ef5301addf28e6f990cd0a7364e322ea7b16879dd257ad0e38f72f41abd610"],"id":1}'
```

Read-back of public state on the live contract:

| Getter | Value |
| --- | --- |
| `nextBountyId()` | `1` |
| `MAX_SUBMISSIONS()` | `50` |
| `MAX_ANSWER_LENGTH()` | `4000` |
| `RITUAL_WALLET()` | `0x532F0dF0896F353d8C3DD8cc134e8129DA2a3948` |
