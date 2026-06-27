// Auto-generated from hardhat/artifacts/.../CommitRevealAIJudge.json
// (the compiled ABI of contracts/CommitRevealAIJudge.sol). Do not edit by hand.

const abi = [
  {
    "inputs": [],
    "name": "AlreadyCommitted",
    "type": "error"
  },
  {
    "inputs": [],
    "name": "AlreadyFinalized",
    "type": "error"
  },
  {
    "inputs": [],
    "name": "AlreadyJudged",
    "type": "error"
  },
  {
    "inputs": [],
    "name": "AlreadyRevealed",
    "type": "error"
  },
  {
    "inputs": [],
    "name": "AnswerTooLong",
    "type": "error"
  },
  {
    "inputs": [],
    "name": "BountyNotFound",
    "type": "error"
  },
  {
    "inputs": [],
    "name": "CommitmentMismatch",
    "type": "error"
  },
  {
    "inputs": [],
    "name": "InvalidDeadlines",
    "type": "error"
  },
  {
    "inputs": [],
    "name": "InvalidIndex",
    "type": "error"
  },
  {
    "inputs": [],
    "name": "InvalidWinnerIndex",
    "type": "error"
  },
  {
    "inputs": [
      {
        "internalType": "string",
        "name": "reason",
        "type": "string"
      }
    ],
    "name": "JudgingFailed",
    "type": "error"
  },
  {
    "inputs": [],
    "name": "NoCommitment",
    "type": "error"
  },
  {
    "inputs": [],
    "name": "NoRevealedSubmissions",
    "type": "error"
  },
  {
    "inputs": [],
    "name": "NotBountyOwner",
    "type": "error"
  },
  {
    "inputs": [],
    "name": "NotJudged",
    "type": "error"
  },
  {
    "inputs": [],
    "name": "PaymentFailed",
    "type": "error"
  },
  {
    "inputs": [],
    "name": "ReentrantCall",
    "type": "error"
  },
  {
    "inputs": [],
    "name": "RevealPhaseNotOver",
    "type": "error"
  },
  {
    "inputs": [],
    "name": "RevealPhaseNotStarted",
    "type": "error"
  },
  {
    "inputs": [],
    "name": "RevealPhaseOver",
    "type": "error"
  },
  {
    "inputs": [],
    "name": "RewardRequired",
    "type": "error"
  },
  {
    "inputs": [],
    "name": "SubmissionPhaseOver",
    "type": "error"
  },
  {
    "inputs": [],
    "name": "TooManySubmissions",
    "type": "error"
  },
  {
    "inputs": [],
    "name": "WinnerNotRevealed",
    "type": "error"
  },
  {
    "inputs": [],
    "name": "ZeroCommitment",
    "type": "error"
  },
  {
    "anonymous": false,
    "inputs": [
      {
        "indexed": true,
        "internalType": "uint256",
        "name": "bountyId",
        "type": "uint256"
      },
      {
        "indexed": false,
        "internalType": "uint256",
        "name": "revealedCount",
        "type": "uint256"
      },
      {
        "indexed": false,
        "internalType": "bytes",
        "name": "aiReview",
        "type": "bytes"
      }
    ],
    "name": "AllAnswersJudged",
    "type": "event"
  },
  {
    "anonymous": false,
    "inputs": [
      {
        "indexed": true,
        "internalType": "uint256",
        "name": "bountyId",
        "type": "uint256"
      },
      {
        "indexed": true,
        "internalType": "uint256",
        "name": "submissionIndex",
        "type": "uint256"
      },
      {
        "indexed": true,
        "internalType": "address",
        "name": "submitter",
        "type": "address"
      }
    ],
    "name": "AnswerRevealed",
    "type": "event"
  },
  {
    "anonymous": false,
    "inputs": [
      {
        "indexed": true,
        "internalType": "uint256",
        "name": "bountyId",
        "type": "uint256"
      },
      {
        "indexed": true,
        "internalType": "address",
        "name": "owner",
        "type": "address"
      },
      {
        "indexed": false,
        "internalType": "string",
        "name": "title",
        "type": "string"
      },
      {
        "indexed": false,
        "internalType": "uint256",
        "name": "reward",
        "type": "uint256"
      },
      {
        "indexed": false,
        "internalType": "uint64",
        "name": "submissionDeadline",
        "type": "uint64"
      },
      {
        "indexed": false,
        "internalType": "uint64",
        "name": "revealDeadline",
        "type": "uint64"
      }
    ],
    "name": "BountyCreated",
    "type": "event"
  },
  {
    "anonymous": false,
    "inputs": [
      {
        "indexed": true,
        "internalType": "uint256",
        "name": "bountyId",
        "type": "uint256"
      },
      {
        "indexed": true,
        "internalType": "uint256",
        "name": "submissionIndex",
        "type": "uint256"
      },
      {
        "indexed": true,
        "internalType": "address",
        "name": "submitter",
        "type": "address"
      },
      {
        "indexed": false,
        "internalType": "bytes32",
        "name": "commitment",
        "type": "bytes32"
      }
    ],
    "name": "CommitmentSubmitted",
    "type": "event"
  },
  {
    "anonymous": false,
    "inputs": [
      {
        "indexed": true,
        "internalType": "uint256",
        "name": "bountyId",
        "type": "uint256"
      },
      {
        "indexed": true,
        "internalType": "uint256",
        "name": "winnerIndex",
        "type": "uint256"
      },
      {
        "indexed": true,
        "internalType": "address",
        "name": "winner",
        "type": "address"
      },
      {
        "indexed": false,
        "internalType": "uint256",
        "name": "reward",
        "type": "uint256"
      }
    ],
    "name": "WinnerFinalized",
    "type": "event"
  },
  {
    "inputs": [],
    "name": "MAX_ANSWER_LENGTH",
    "outputs": [
      {
        "internalType": "uint256",
        "name": "",
        "type": "uint256"
      }
    ],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "MAX_SUBMISSIONS",
    "outputs": [
      {
        "internalType": "uint256",
        "name": "",
        "type": "uint256"
      }
    ],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "RITUAL_WALLET",
    "outputs": [
      {
        "internalType": "contract IRitualWallet",
        "name": "",
        "type": "address"
      }
    ],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [
      {
        "internalType": "string",
        "name": "answer",
        "type": "string"
      },
      {
        "internalType": "bytes32",
        "name": "salt",
        "type": "bytes32"
      },
      {
        "internalType": "address",
        "name": "submitter",
        "type": "address"
      },
      {
        "internalType": "uint256",
        "name": "bountyId",
        "type": "uint256"
      }
    ],
    "name": "computeCommitment",
    "outputs": [
      {
        "internalType": "bytes32",
        "name": "",
        "type": "bytes32"
      }
    ],
    "stateMutability": "pure",
    "type": "function"
  },
  {
    "inputs": [
      {
        "internalType": "string",
        "name": "title",
        "type": "string"
      },
      {
        "internalType": "string",
        "name": "rubric",
        "type": "string"
      },
      {
        "internalType": "uint64",
        "name": "submissionDeadline",
        "type": "uint64"
      },
      {
        "internalType": "uint64",
        "name": "revealDeadline",
        "type": "uint64"
      }
    ],
    "name": "createBounty",
    "outputs": [
      {
        "internalType": "uint256",
        "name": "bountyId",
        "type": "uint256"
      }
    ],
    "stateMutability": "payable",
    "type": "function"
  },
  {
    "inputs": [
      {
        "internalType": "uint256",
        "name": "bountyId",
        "type": "uint256"
      },
      {
        "internalType": "uint256",
        "name": "winnerIndex",
        "type": "uint256"
      }
    ],
    "name": "finalizeWinner",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [
      {
        "internalType": "uint256",
        "name": "bountyId",
        "type": "uint256"
      }
    ],
    "name": "getBounty",
    "outputs": [
      {
        "components": [
          {
            "internalType": "address",
            "name": "owner",
            "type": "address"
          },
          {
            "internalType": "string",
            "name": "title",
            "type": "string"
          },
          {
            "internalType": "string",
            "name": "rubric",
            "type": "string"
          },
          {
            "internalType": "uint256",
            "name": "reward",
            "type": "uint256"
          },
          {
            "internalType": "uint64",
            "name": "submissionDeadline",
            "type": "uint64"
          },
          {
            "internalType": "uint64",
            "name": "revealDeadline",
            "type": "uint64"
          },
          {
            "internalType": "bool",
            "name": "judged",
            "type": "bool"
          },
          {
            "internalType": "bool",
            "name": "finalized",
            "type": "bool"
          },
          {
            "internalType": "uint256",
            "name": "submissionCount",
            "type": "uint256"
          },
          {
            "internalType": "uint256",
            "name": "revealedCount",
            "type": "uint256"
          },
          {
            "internalType": "uint256",
            "name": "winnerIndex",
            "type": "uint256"
          },
          {
            "internalType": "bytes",
            "name": "aiReview",
            "type": "bytes"
          }
        ],
        "internalType": "struct CommitRevealAIJudge.BountyView",
        "name": "",
        "type": "tuple"
      }
    ],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [
      {
        "internalType": "uint256",
        "name": "bountyId",
        "type": "uint256"
      },
      {
        "internalType": "address",
        "name": "participant",
        "type": "address"
      }
    ],
    "name": "getCommitment",
    "outputs": [
      {
        "internalType": "bool",
        "name": "committed",
        "type": "bool"
      },
      {
        "internalType": "uint256",
        "name": "index",
        "type": "uint256"
      },
      {
        "internalType": "bytes32",
        "name": "commitment",
        "type": "bytes32"
      },
      {
        "internalType": "bool",
        "name": "revealed",
        "type": "bool"
      }
    ],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [
      {
        "internalType": "uint256",
        "name": "bountyId",
        "type": "uint256"
      },
      {
        "internalType": "uint256",
        "name": "index",
        "type": "uint256"
      }
    ],
    "name": "getSubmission",
    "outputs": [
      {
        "internalType": "address",
        "name": "submitter",
        "type": "address"
      },
      {
        "internalType": "bytes32",
        "name": "commitment",
        "type": "bytes32"
      },
      {
        "internalType": "bool",
        "name": "revealed",
        "type": "bool"
      },
      {
        "internalType": "string",
        "name": "answer",
        "type": "string"
      }
    ],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [
      {
        "internalType": "uint256",
        "name": "bountyId",
        "type": "uint256"
      },
      {
        "internalType": "bytes",
        "name": "llmInput",
        "type": "bytes"
      }
    ],
    "name": "judgeAll",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "nextBountyId",
    "outputs": [
      {
        "internalType": "uint256",
        "name": "",
        "type": "uint256"
      }
    ],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [
      {
        "internalType": "uint256",
        "name": "bountyId",
        "type": "uint256"
      },
      {
        "internalType": "string",
        "name": "answer",
        "type": "string"
      },
      {
        "internalType": "bytes32",
        "name": "salt",
        "type": "bytes32"
      }
    ],
    "name": "revealAnswer",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [
      {
        "internalType": "uint256",
        "name": "bountyId",
        "type": "uint256"
      }
    ],
    "name": "submissionCount",
    "outputs": [
      {
        "internalType": "uint256",
        "name": "",
        "type": "uint256"
      }
    ],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [
      {
        "internalType": "uint256",
        "name": "bountyId",
        "type": "uint256"
      },
      {
        "internalType": "bytes32",
        "name": "commitment",
        "type": "bytes32"
      }
    ],
    "name": "submitCommitment",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  }
] as const;

export default abi;
