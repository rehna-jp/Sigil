/**
 * TypeScript types matching Solidity contract structs
 * Based on Types.sol from smart contracts
 */

export enum SegmentType {
  SWAP = 0,
  DEPOSIT = 1,
  WITHDRAW = 2,
  HEDGE = 3,
  CUSTOM = 4
}

export enum WatcherType {
  PRICE = 0,
  GOVERNANCE = 1,
  RISK = 2,
  TIME = 3
}

export enum WatcherStatus {
  ACTIVE = 0,
  TRIGGERED = 1,
  EXPIRED = 2,
  CANCELLED = 3
}

export enum IntentStatus {
  PENDING = 0,
  EXECUTING = 1,
  ACTIVE = 2,
  TRIGGERED = 3,
  COMPLETED = 4,
  FAILED = 5,
  CANCELLED = 6
}

export enum ComparisonOp {
  GT = 0,
  LT = 1,
  GTE = 2,
  LTE = 3
}

export enum ProtocolCategory {
  DEX = 0,
  LENDING = 1,
  DERIVATIVES = 2,
  YIELD = 3,
  BRIDGE = 4,
  CUSTOM = 5
}

// Solidity struct mappings
export interface Segment {
  segmentType: SegmentType;
  targetProtocol: string; // address
  callData: string; // bytes
  value: bigint;
}

export interface WatcherConfig {
  watcherType: WatcherType;
  parameters: string; // bytes (ABI-encoded params)
  triggerAction: string; // bytes (ABI-encoded action)
  expiry: bigint;
}

export interface DecomposedIntent {
  intentId: string; // bytes32
  user: string; // address
  immediateSegments: Segment[];
  watchers: WatcherConfig[];
  timestamp: bigint;
  status: IntentStatus;
}

export interface Watcher {
  watcherId: string; // bytes32
  parentIntentId: string; // bytes32
  owner: string; // address
  watcherType: WatcherType;
  status: WatcherStatus;
  parameters: string; // bytes
  triggerAction: string; // bytes
  createdAt: bigint;
  expiresAt: bigint;
  lastChecked: bigint;
}

// Price watcher parameters
export interface PriceParams {
  priceFeed: string; // address
  threshold: bigint; // int256
  comparison: ComparisonOp;
}

// Time watcher parameters
export interface TimeParams {
  interval: bigint; // uint256
  nextTrigger: bigint; // uint256
  maxTriggers: bigint; // uint256
  triggerCount: bigint; // uint256
}

// Risk watcher parameters
export interface RiskParams {
  protocol: string; // address
  tvlDropThreshold: bigint; // uint256 (basis points)
  baselineTVL: bigint; // uint256
  watchUpgrades: boolean;
}

// Governance watcher parameters
export interface GovernanceParams {
  governanceContract: string; // address
  proposalSelector: string; // bytes4
  watchedParamKeys: string[]; // bytes32[]
}

// For Claude AI decomposition
export interface AIDecompositionRequest {
  userInput: string;
  userAddress: string;
  context?: {
    balances?: Record<string, string>;
    positions?: any[];
  };
}

export interface AIDecomposedIntent {
  segments: {
    type: SegmentType;
    protocol: string;
    description: string;
    data: any;
  }[];
  watchers: {
    type: WatcherType;
    description: string;
    params: any;
  }[];
  reasoning: string;
}
