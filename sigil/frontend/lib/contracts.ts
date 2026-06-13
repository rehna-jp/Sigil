// Minimal ABI fragments for Sigil contracts — full ABIs populated after forge build

export const IntentDecomposerABI = [
  {
    name: 'submitDecomposition',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'user',      type: 'address' },
      {
        name: 'segments',
        type: 'tuple[]',
        components: [
          { name: 'segmentType',    type: 'uint8'   },
          { name: 'targetProtocol', type: 'address' },
          { name: 'callData',       type: 'bytes'   },
          { name: 'value',          type: 'uint256' },
          { name: 'minGasLimit',    type: 'uint256' },
        ],
      },
      {
        name: 'watchers',
        type: 'tuple[]',
        components: [
          { name: 'watcherType',   type: 'uint8'   },
          { name: 'parameters',    type: 'bytes'   },
          { name: 'triggerAction', type: 'bytes'   },
          { name: 'expiresAt',     type: 'uint256' },
        ],
      },
      { name: 'expiresAt', type: 'uint256' },
    ],
    outputs: [{ name: 'intentId', type: 'bytes32' }],
  },
  {
    name: 'getUserIntents',
    type: 'function',
    stateMutability: 'view',
    inputs:  [{ name: 'user', type: 'address' }],
    outputs: [{ name: 'intentIds', type: 'bytes32[]' }],
  },
  {
    name: 'getIntent',
    type: 'function',
    stateMutability: 'view',
    inputs:  [{ name: 'intentId', type: 'bytes32' }],
    outputs: [
      {
        name: 'intent',
        type: 'tuple',
        components: [
          { name: 'intentId',     type: 'bytes32'  },
          { name: 'user',         type: 'address'  },
          { name: 'submitter',    type: 'address'  },
          { name: 'watcherIds',   type: 'bytes32[]' },
          { name: 'segmentCount', type: 'uint256'  },
          { name: 'timestamp',    type: 'uint256'  },
          { name: 'expiresAt',    type: 'uint256'  },
          { name: 'status',       type: 'uint8'    },
        ],
      },
    ],
  },
  {
    name: 'getIntentSegments',
    type: 'function',
    stateMutability: 'view',
    inputs:  [{ name: 'intentId', type: 'bytes32' }],
    outputs: [
      {
        name: 'segments',
        type: 'tuple[]',
        components: [
          { name: 'segmentType',    type: 'uint8'   },
          { name: 'targetProtocol', type: 'address' },
          { name: 'callData',       type: 'bytes'   },
          { name: 'value',          type: 'uint256' },
          { name: 'minGasLimit',    type: 'uint256' },
        ],
      },
    ],
  },
  {
    name: 'cancelIntent',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs:  [{ name: 'intentId', type: 'bytes32' }],
    outputs: [],
  },
  {
    name: 'IntentDecomposed',
    type: 'event',
    inputs: [
      { name: 'intentId',      type: 'bytes32', indexed: true },
      { name: 'user',          type: 'address', indexed: true },
      { name: 'submitter',     type: 'address', indexed: false },
      { name: 'segmentCount',  type: 'uint256', indexed: false },
      { name: 'watcherCount',  type: 'uint256', indexed: false },
      { name: 'expiresAt',     type: 'uint256', indexed: false },
    ],
  },
] as const;

export const WatcherRegistryABI = [
  {
    name: 'getUserActiveWatchers',
    type: 'function',
    stateMutability: 'view',
    inputs:  [{ name: 'user', type: 'address' }],
    outputs: [{ name: 'watcherIds', type: 'bytes32[]' }],
  },
  {
    name: 'getWatcher',
    type: 'function',
    stateMutability: 'view',
    inputs:  [{ name: 'watcherId', type: 'bytes32' }],
    outputs: [
      {
        name: 'watcher',
        type: 'tuple',
        components: [
          { name: 'watcherId',      type: 'bytes32' },
          { name: 'parentIntentId', type: 'bytes32' },
          { name: 'owner',          type: 'address' },
          { name: 'watcherType',    type: 'uint8'   },
          { name: 'status',         type: 'uint8'   },
          { name: 'parameters',     type: 'bytes'   },
          { name: 'triggerAction',  type: 'bytes'   },
          { name: 'createdAt',      type: 'uint256' },
          { name: 'expiresAt',      type: 'uint256' },
          { name: 'lastChecked',    type: 'uint256' },
          { name: 'checkCount',     type: 'uint256' },
        ],
      },
    ],
  },
  {
    name: 'cancelWatcher',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs:  [{ name: 'watcherId', type: 'bytes32' }],
    outputs: [],
  },
  {
    name: 'WatcherCreated',
    type: 'event',
    inputs: [
      { name: 'watcherId',      type: 'bytes32', indexed: true },
      { name: 'parentIntentId', type: 'bytes32', indexed: true },
      { name: 'owner',          type: 'address', indexed: true },
      { name: 'watcherType',    type: 'uint8',   indexed: false },
      { name: 'expiresAt',      type: 'uint256', indexed: false },
    ],
  },
  {
    name: 'WatcherTriggered',
    type: 'event',
    inputs: [
      { name: 'watcherId',     type: 'bytes32', indexed: true },
      { name: 'intentId',      type: 'bytes32', indexed: true },
      { name: 'triggerAction', type: 'bytes',   indexed: false },
      { name: 'blockNumber',   type: 'uint256', indexed: false },
    ],
  },
] as const;

export const MockPriceFeedABI = [
  {
    name: 'latestRoundData',
    type: 'function',
    stateMutability: 'view',
    inputs: [],
    outputs: [
      { name: 'roundId',         type: 'uint80'  },
      { name: 'answer',          type: 'int256'  },
      { name: 'startedAt',       type: 'uint256' },
      { name: 'updatedAt',       type: 'uint256' },
      { name: 'answeredInRound', type: 'uint80'  },
    ],
  },
  {
    name: 'setPrice',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [{ name: 'price', type: 'int256' }],
    outputs: [],
  },
] as const;
