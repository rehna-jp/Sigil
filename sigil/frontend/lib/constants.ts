// Contract addresses for Arbitrum Sepolia
// Fill in after deployment: forge script script/DeploySigil.s.sol --rpc-url arbitrum_sepolia --broadcast

export const ARBITRUM_SEPOLIA_CHAIN_ID = 421614;

export const ARBISCAN_BASE = 'https://sepolia.arbiscan.io';

export const CONTRACTS = {
  arbitrumSepolia: {
    chainId: ARBITRUM_SEPOLIA_CHAIN_ID,
    IntentDecomposer:  (process.env.NEXT_PUBLIC_INTENT_DECOMPOSER  ?? '0xDaf6B30C15a0Ce8501A685f0606154F517b8d62a') as `0x${string}`,
    WatcherRegistry:   (process.env.NEXT_PUBLIC_WATCHER_REGISTRY   ?? '0xB3073A12EBD1ffE05B9Bd530A50625779AB8E93d') as `0x${string}`,
    TriggerExecutor:   (process.env.NEXT_PUBLIC_TRIGGER_EXECUTOR   ?? '0xE80dd053081b941FBfF60eB8b105bBF4f971327a') as `0x${string}`,
    IntentRouter:      (process.env.NEXT_PUBLIC_INTENT_ROUTER      ?? '0x2D514AB7E8C2F05FA82Bb4885de00Da933501022') as `0x${string}`,
    MockPriceFeed:     (process.env.NEXT_PUBLIC_MOCK_PRICE_FEED    ?? '0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165') as `0x${string}`,
    UniswapV3Adapter:  '0x315bbDFE5Ea6F2083c554612D2F339a47afC0605' as `0x${string}`,
    AaveV3Adapter:     '0x64D41E4D849b83aA1870f30B148a94A2F01a300A' as `0x${string}`,
    WETH:              '0x980B62Da83eFf3D4576C647993b0c1D7faf17c73' as `0x${string}`,
    USDC:              '0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d' as `0x${string}`,
  },
} as const;

export function getArbiscanTx(txHash: string) {
  return `${ARBISCAN_BASE}/tx/${txHash}`;
}

export function getArbiscanAddress(address: string) {
  return `${ARBISCAN_BASE}/address/${address}`;
}

export const BACKEND_URL  = process.env.NEXT_PUBLIC_BACKEND_URL ?? 'http://localhost:3001';
export const WS_URL       = process.env.NEXT_PUBLIC_WS_URL      ?? 'ws://localhost:3002';
export const RPC_URL      = process.env.NEXT_PUBLIC_ARBITRUM_SEPOLIA_RPC ?? 'https://sepolia-rollup.arbitrum.io/rpc';

// Preset intent templates
export const PRESET_INTENTS = [
  {
    id: 'yield-protection',
    label: 'Yield with price protection',
    icon: '🌿',
    text: 'Put 0.5 ETH into Aave for yield on Arbitrum. Exit to USDC if ETH price drops below $3,500.',
  },
  {
    id: 'monthly-rebalance',
    label: 'Monthly rebalancer',
    icon: '⚖️',
    text: 'Every 30 days, rebalance my portfolio to 60% ETH and 40% USDC.',
  },
  {
    id: 'governance-guardian',
    label: 'Governance guardian',
    icon: '🏛️',
    text: 'Watch Arbitrum DAO governance proposals. If a proposal to change fee structure passes, swap 1 ETH to ARB.',
  },
  {
    id: 'quick-swap',
    label: 'Quick swap',
    icon: '⚡',
    text: 'Swap 100 USDC to ETH when ETH price drops below $3,200.',
  },
] as const;
