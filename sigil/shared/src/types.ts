export enum SegmentType {
  SWAP = 'SWAP',
  DEPOSIT = 'DEPOSIT',
  WITHDRAW = 'WITHDRAW',
  HEDGE = 'HEDGE'
}

export enum WatcherType {
  PRICE = 'PRICE',
  GOVERNANCE = 'GOVERNANCE',
  RISK = 'RISK',
  TIME = 'TIME'
}

export enum WatcherStatus {
  ACTIVE = 'ACTIVE',
  TRIGGERED = 'TRIGGERED',
  EXPIRED = 'EXPIRED',
  CANCELLED = 'CANCELLED'
}

export type Segment = {
  type: SegmentType;
  data: Record<string, any>;
};

export type Watcher = {
  type: WatcherType;
  params: Record<string, any>;
  status?: WatcherStatus;
};

export type IntentSchema = {
  id?: string;
  owner?: string;
  text: string;
  segments: Segment[];
  watchers?: Watcher[];
};

export const CONTRACT_ADDRESSES: Record<string, Record<string, string>> = {
  arbitrum_sepolia: {
    SigilEngine: ''
  }
};
