/**
 * Deployed contract addresses on Arbitrum Sepolia
 * Auto-loaded from deployment artifact
 */

export const ARBITRUM_SEPOLIA_ADDRESSES = {
  registry: "0x239F7823CeA86DF8BF1cC5680a3f78c12592ab76",
  decomposer: "0xDaf6B30C15a0Ce8501A685f0606154F517b8d62a",
  watcherRegistry: "0xB3073A12EBD1ffE05B9Bd530A50625779AB8E93d",
  router: "0x2D514AB7E8C2F05FA82Bb4885de00Da933501022",
  executor: "0xE80dd053081b941FBfF60eB8b105bBF4f971327a",
  uniswapAdapter: "0x315bbDFE5Ea6F2083c554612D2F339a47afC0605",
  aaveAdapter: "0x64D41E4D849b83aA1870f30B148a94A2F01a300A"
} as const;

export type ContractName = keyof typeof ARBITRUM_SEPOLIA_ADDRESSES;

// Protocol addresses on Arbitrum Sepolia
export const PROTOCOL_ADDRESSES = {
  uniswapV3Router: "0x101F443B4d1b059569D643917553c771E1b9663E",
  aaveV3Pool: "0x6cAd12b3618A6e8638E19049E7Ff94802904C1ed",
  ethUsdFeed: "0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165",
  usdcUsdFeed: "0x0153002d20B96532C639313c2d54c3dA09109309"
} as const;
