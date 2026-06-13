'use client';

import { useReadContracts, useAccount } from 'wagmi';
import { CONTRACTS } from '../lib/constants';
import { WatcherRegistryABI } from '../lib/contracts';
import { useSigilStore, ActiveWatcher } from '../stores/sigil';
import { useEffect } from 'react';
import { useEthPrice } from './useEthPrice';

const WATCHER_TYPE_MAP = ['PRICE', 'TIME', 'RISK', 'GOVERNANCE'] as const;
const WATCHER_STATUS_MAP = ['ACTIVE', 'TRIGGERED', 'EXPIRED', 'CANCELLED'] as const;

export function useWatchers(watcherIds: readonly `0x${string}`[]) {
  const { isConnected, chain } = useAccount();
  const { updateWatcherPrice } = useSigilStore();
  const currentEthPrice = useEthPrice();
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
      enabled: watcherIds.length > 0 && (!isConnected || chain?.id === 421614),
      refetchInterval: 15_000,
    },
  });

  const watcherIdsKey = watcherIds.join(',');
  useEffect(() => {
    if (currentEthPrice !== null && currentEthPrice !== undefined) {
      watcherIds.forEach((id) => {
        updateWatcherPrice(id, currentEthPrice);
      });
    }
  }, [currentEthPrice, watcherIdsKey, updateWatcherPrice]);

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
