'use client';

import { useEffect, useMemo } from 'react';
import { useReadContract, useReadContracts, useAccount } from 'wagmi';
import { decodeAbiParameters, parseAbiParameters } from 'viem';
import { CONTRACTS } from '../lib/constants';
import { IntentDecomposerABI, WatcherRegistryABI } from '../lib/contracts';
import { useSigilStore, ActiveWatcher, ActiveIntent, Segment } from '../stores/sigil';

const STATUS_MAP = [
  'PENDING', 'EXECUTING', 'ACTIVE', 'TRIGGERED', 'COMPLETED', 'CANCELLED', 'EXPIRED',
] as const;
type OnChainStatus = typeof STATUS_MAP[number];

const WETH_ADDR = CONTRACTS.arbitrumSepolia.WETH;
const USDC_ADDR = CONTRACTS.arbitrumSepolia.USDC;
const UNISWAP_ADAPTER = CONTRACTS.arbitrumSepolia.UniswapV3Adapter;
const AAVE_ADAPTER = CONTRACTS.arbitrumSepolia.AaveV3Adapter;

function getProtocolName(targetProtocol: string) {
  const p = targetProtocol.toLowerCase();
  if (p === UNISWAP_ADAPTER.toLowerCase()) return 'Uniswap V3';
  if (p === AAVE_ADAPTER.toLowerCase()) return 'Aave V3';
  return 'Unknown Protocol';
}

function formatToken(addr: string) {
  if (addr.toLowerCase() === USDC_ADDR.toLowerCase()) return 'USDC';
  if (addr.toLowerCase() === WETH_ADDR.toLowerCase()) return 'WETH';
  return addr.slice(0, 6) + '...' + addr.slice(-4);
}

function decodeSegment(s: { segmentType: number; targetProtocol: string; callData: `0x${string}`; value: bigint; minGasLimit: bigint }): Segment {
  const typeMap = ['SWAP', 'DEPOSIT', 'WITHDRAW', 'HEDGE', 'CUSTOM'] as const;
  const type = typeMap[s.segmentType] ?? 'CUSTOM';
  let description = `${type} on ${getProtocolName(s.targetProtocol)}`;
  let from = '';
  let to = '';
  let amount = '';

  try {
    if (s.targetProtocol.toLowerCase() === UNISWAP_ADAPTER.toLowerCase() && s.callData !== '0x') {
      const [tokenIn, tokenOut, fee, amountIn, minAmountOut] = decodeAbiParameters(
        parseAbiParameters('address tokenIn, address tokenOut, uint24 fee, uint256 amountIn, uint256 minAmountOut'),
        s.callData
      );
      from = formatToken(tokenIn);
      to = formatToken(tokenOut);
      const dec = tokenIn.toLowerCase() === USDC_ADDR.toLowerCase() ? 6 : 18;
      amount = (Number(amountIn) / 10 ** dec).toString();
      description = `Swap ${amount} ${from} to ${to}`;
    } else if (s.targetProtocol.toLowerCase() === AAVE_ADAPTER.toLowerCase() && s.callData !== '0x') {
      const [operation, asset, amountVal] = decodeAbiParameters(
        parseAbiParameters('uint8 operation, address asset, uint256 amount'),
        s.callData
      );
      const isDeposit = operation === 0;
      from = formatToken(asset);
      const dec = asset.toLowerCase() === USDC_ADDR.toLowerCase() ? 6 : 18;
      amount = (Number(amountVal) / 10 ** dec).toString();
      description = `${isDeposit ? 'Deposit' : 'Withdraw'} ${amount} ${from} ${isDeposit ? 'into' : 'from'} Aave`;
    }
  } catch (err) {
    console.error('Failed to decode segment callData', err);
  }

  return {
    type,
    protocol: getProtocolName(s.targetProtocol),
    description,
    from,
    to,
    amount,
    status: 'done'
  };
}

function decodeWatcher(w: {
  watcherId: `0x${string}`;
  watcherType: number;
  status: number;
  parameters: `0x${string}`;
  triggerAction: `0x${string}`;
  createdAt: bigint;
  expiresAt: bigint;
  parentIntentId: `0x${string}`;
}): Omit<ActiveWatcher, 'intentSummary'> & { parentIntentId: `0x${string}` } {
  const typeMap = ['PRICE', 'TIME', 'RISK', 'GOVERNANCE'] as const;
  const statusMap = ['ACTIVE', 'TRIGGERED', 'EXPIRED', 'CANCELLED'] as const;

  const watcherType = typeMap[w.watcherType] ?? 'PRICE';
  const status = statusMap[w.status] ?? 'ACTIVE';

  let condition = 'Monitoring...';
  let threshold: number | undefined;
  let action = 'Trigger on condition';

  try {
    if (watcherType === 'PRICE' && w.parameters !== '0x') {
      const [priceFeed, thresholdVal, comparison, decimals] = decodeAbiParameters(
        parseAbiParameters('address priceFeed, int256 threshold, uint8 comparison, uint8 decimals'),
        w.parameters
      );
      const opMap = ['>', '<', '>=', '<=', '=', '!='];
      const op = opMap[comparison] ?? '<';
      const formattedPrice = (Number(thresholdVal) / 10 ** decimals).toLocaleString();
      condition = `ETH/USD ${op} $${formattedPrice}`;
      threshold = Number(thresholdVal) / 10 ** decimals;
    } else if (watcherType === 'TIME' && w.parameters !== '0x') {
      const [interval, nextTrigger, maxTriggers, triggerCount] = decodeAbiParameters(
        parseAbiParameters('uint256 interval, uint256 nextTrigger, uint256 maxTriggers, uint256 triggerCount'),
        w.parameters
      );
      const hours = Number(interval) / 3600;
      condition = hours >= 24 ? `Every ${hours / 24} days` : `Every ${hours} hours`;
    }

    if (w.triggerAction !== '0x') {
      const [exitSegments] = decodeAbiParameters(
        parseAbiParameters('(uint8, address, bytes, uint256, uint256)[]'),
        w.triggerAction
      ) as [any[]];
      if (exitSegments && exitSegments.length > 0) {
        const decodedExitSegments = exitSegments.map(s => decodeSegment({
          segmentType: s[0],
          targetProtocol: s[1],
          callData: s[2],
          value: s[3],
          minGasLimit: s[4]
        }));
        action = decodedExitSegments.map(s => s.description).join(' then ');
      }
    }
  } catch (err) {
    console.error('Failed to decode watcher data', err);
  }

  return {
    id: w.watcherId,
    parentIntentId: w.parentIntentId,
    watcherType,
    status,
    condition,
    threshold,
    action,
    createdAt: Number(w.createdAt) * 1000,
    expiresAt: Number(w.expiresAt) * 1000,
  };
}

export function useIntents() {
  const { address, isConnected, chain } = useAccount();
  const { addIntent } = useSigilStore();

  const decomposerAddr = CONTRACTS.arbitrumSepolia.IntentDecomposer;
  const watcherRegistryAddr = CONTRACTS.arbitrumSepolia.WatcherRegistry;

  const isChainValid = isConnected && !!address && chain?.id === 421614;

  // Step 1: Fetch intent IDs for the user
  const { data: intentIds, isLoading: loadingIds, refetch } = useReadContract({
    address: decomposerAddr,
    abi: IntentDecomposerABI,
    functionName: 'getUserIntents',
    args: address ? [address] : undefined,
    query: {
      enabled: isChainValid,
      refetchInterval: 30_000,
    },
  });

  // Step 2: Fetch intent details and segments for each ID
  const intentCalls = useMemo(() => {
    return (intentIds ?? []).flatMap((id) => [
      {
        address: decomposerAddr,
        abi: IntentDecomposerABI,
        functionName: 'getIntent' as const,
        args: [id] as const,
      },
      {
        address: decomposerAddr,
        abi: IntentDecomposerABI,
        functionName: 'getIntentSegments' as const,
        args: [id] as const,
      }
    ]);
  }, [intentIds, decomposerAddr]);

  const { data: intentResults, isLoading: loadingIntents } = useReadContracts({
    contracts: intentCalls,
    query: { enabled: isChainValid && intentCalls.length > 0 },
  });

  // Step 3: Fetch watcher details for all active watcher IDs
  const allWatcherIds = useMemo(() => {
    if (!intentResults) return [] as `0x${string}`[];
    return intentResults
      .filter((result, idx) => idx % 2 === 0 && result.status === 'success')
      .flatMap((result) => {
        const d = result.result as any;
        return (d.watcherIds ?? []) as `0x${string}`[];
      });
  }, [intentResults]);

  const watcherCalls = useMemo(() => {
    return allWatcherIds.map((wid) => ({
      address: watcherRegistryAddr,
      abi: WatcherRegistryABI,
      functionName: 'getWatcher' as const,
      args: [wid] as const,
    }));
  }, [allWatcherIds, watcherRegistryAddr]);

  const { data: watcherResults, isLoading: loadingWatchers } = useReadContracts({
    contracts: watcherCalls,
    query: { enabled: isChainValid && watcherCalls.length > 0 },
  });

  // Sync on-chain intents and watchers into Zustand store
  useEffect(() => {
    if (!intentResults || !intentIds) return;

    // Build map of decoded watchers
    const watcherMap: Record<string, ReturnType<typeof decodeWatcher>> = {};
    if (watcherResults) {
      watcherResults.forEach((wResult) => {
        if (wResult.status !== 'success') return;
        const rawW = wResult.result as {
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
        const decoded = decodeWatcher(rawW);
        watcherMap[decoded.id] = decoded;
      });
    }

    // Process intent results
    const loadedCount = intentIds.length;
    for (let i = 0; i < loadedCount; i++) {
      const intentResult = intentResults[2 * i];
      const segmentsResult = intentResults[2 * i + 1];

      if (!intentResult || intentResult.status !== 'success') continue;

      const rawIntent = intentResult.result as {
        intentId: `0x${string}`;
        user: `0x${string}`;
        submitter: `0x${string}`;
        watcherIds: readonly `0x${string}`[];
        segmentCount: bigint;
        timestamp: bigint;
        expiresAt: bigint;
        status: number;
      };

      const intentId = rawIntent.intentId;

      const status = STATUS_MAP[rawIntent.status] as OnChainStatus ?? 'PENDING';

      // Decode segments
      let segments: Segment[] = [];
      if (segmentsResult && segmentsResult.status === 'success') {
        const rawSegments = segmentsResult.result as any[];
        segments = rawSegments.map((s) => decodeSegment({
          segmentType: s.segmentType,
          targetProtocol: s.targetProtocol,
          callData: s.callData,
          value: s.value,
          minGasLimit: s.minGasLimit,
        }));
      } else {
        // Fallback placeholder segments
        segments = Array.from({ length: Number(rawIntent.segmentCount) }, (_, j) => ({
          type: 'CUSTOM' as const,
          description: `Segment ${j + 1}`,
          status: status === 'COMPLETED' ? 'done' as const : 'pending' as const,
        }));
      }

      // Populate watchers
      const watchers: ActiveWatcher[] = (rawIntent.watcherIds ?? [])
        .map((wid) => watcherMap[wid])
        .filter(Boolean)
        .map((w) => ({
          id: w.id,
          watcherType: w.watcherType,
          status: w.status,
          condition: w.condition,
          threshold: w.threshold,
          action: w.action,
          createdAt: w.createdAt,
          expiresAt: w.expiresAt,
          intentSummary: `Intent ${intentId.slice(0, 8)}...`,
        }));

      // Generate a dynamic summary for the on-chain intent
      const summary = segments.length > 0 
        ? segments.map(s => s.description).join(' then ') 
        : `On-chain Intent #${i + 1}`;

      addIntent({
        id: intentId,
        summary,
        status,
        segments,
        watchers,
        createdAt: Number(rawIntent.timestamp) * 1000,
      });
    }
  }, [intentResults, watcherResults, intentIds, addIntent]);

  return {
    intentIds: intentIds ?? [],
    isLoading: loadingIds || loadingIntents || loadingWatchers,
    refetch,
  };
}
