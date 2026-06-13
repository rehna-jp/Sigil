'use client';

import { useReadContracts, useAccount } from 'wagmi';
import { CONTRACTS } from '../lib/constants';
import { WatcherRegistryABI, MockPriceFeedABI } from '../lib/contracts';
import { useSigilStore, ActiveWatcher } from '../stores/sigil';
import { useEffect } from 'react';

const ETH_USD_FEED = '0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165'; // Chainlink Arb Sepolia ETH/USD

const WATCHER_TYPE_MAP = ['PRICE', 'TIME', 'RISK', 'GOVERNANCE'] as const;
const WATCHER_STATUS_MAP = ['ACTIVE', 'TRIGGERED', 'EXPIRED', 'CANCELLED'] as const;

export function useWatchers(watcherIds: readonly `0x${string}`[]) {
  const { isConnected, chain } = useAccount();
  const registryAddr = CONTRACTS.arbitrumSepolia.WatcherRegistry;

  const watcherCalls = watcherIds.map((id) => ({
    address: registryAddr,
    abi: WatcherRegistryABI,
    functionName: 'getWatcher' as const,
    args: [id] as const,
  }));

  const { data: watcherData, isLoading } = useReadContracts({
    contracts: watcherCalls,
    query: {
      enabled: isConnected && watcherIds.length > 0 && chain?.id === 421614,
      refetchInterval: 15_000,
    },
  });

  // Fetch current ETH/USD price for price watchers
  const { data: priceData } = useReadContracts({
    contracts: [
      {
        address: ETH_USD_FEED as `0x${string}`,
        abi: MockPriceFeedABI,
        functionName: 'latestRoundData',
      },
    ],
    query: {
      enabled: isConnected && chain?.id === 421614,
      refetchInterval: 15_000,
    },
  });

  // Parse current price (Chainlink returns 8 decimals)
  const currentEthPrice = priceData?.[0]?.status === 'success'
    ? Number((priceData[0].result as readonly [bigint, bigint, bigint, bigint, bigint])[1]) / 1e8
    : null;

  // Enrich and return watcher objects
  const enrichedWatchers: ActiveWatcher[] = (watcherData ?? [])
    .map((result, i): ActiveWatcher | null => {
      if (result.status !== 'success') return null;
      const w = result.result as {
        watcherId: `0x${string}`;
        parentIntentId: `0x${string}`;
        owner: `0x${string}`;
        watcherType: number;
        status: number;
        parameters: `0x${string}`;
        triggerAction: `0x${string}`;
        createdAt: bigint;
        expiresAt: bigint;
        lastChecked: bigint;
        checkCount: bigint;
      };

      const watcherType = WATCHER_TYPE_MAP[w.watcherType] ?? 'PRICE';
      const status = WATCHER_STATUS_MAP[w.status] ?? 'ACTIVE';

      return {
        id: watcherIds[i],
        watcherType,
        status,
        condition: watcherType === 'PRICE' ? 'ETH/USD price threshold' : 'Condition monitoring',
        currentPrice: watcherType === 'PRICE' ? (currentEthPrice ?? undefined) : undefined,
        action: 'Execute on trigger',
        createdAt: Number(w.createdAt) * 1000,
        expiresAt: Number(w.expiresAt) * 1000,
        intentSummary: `Watcher ${String(watcherIds[i]).slice(0, 8)}…`,
      } satisfies ActiveWatcher;
    })
    .filter((w): w is ActiveWatcher => w !== null);

  return { watchers: enrichedWatchers, currentEthPrice, isLoading };
}
