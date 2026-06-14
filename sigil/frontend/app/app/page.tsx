'use client';

import { useEffect, useCallback } from 'react';
import { useAccount } from 'wagmi';
import { ConnectButton } from '@rainbow-me/rainbowkit';
import { StatsBar } from '../../components/dashboard/StatsBar';
import { ActiveSigils } from '../../components/dashboard/ActiveSigils';
import { TriggerFeed } from '../../components/dashboard/TriggerFeed';
import { useSigilStore } from '../../stores/sigil';
import { useIntents } from '../../hooks/useIntents';
import { useWebSocket } from '../../hooks/useWebSocket';
import { WSEvent } from '../../components/providers/WebSocketProvider';
import { PulsingDot } from '../../components/ui/PulsingDot';
import { useEthPrice } from '../../hooks/useEthPrice';
import { useWatchers } from '../../hooks/useWatchers';

export default function DashboardPage() {
  const { isConnected, chain } = useAccount();
  const isOnChain = isConnected && chain?.id === 421614;
  const { activeIntents, triggerFeed, handleWSEvent, loadDemoState, clearDemoState } = useSigilStore();
  const { isLoading } = useIntents();
  const { isConnected: wsConnected, isSimulating } = useWebSocket();

  // Set browser page title
  useEffect(() => {
    document.title = 'Dashboard | Sigil';
  }, []);

  // Clear demo data immediately when wallet connects to the right chain
  useEffect(() => {
    if (isOnChain) {
      clearDemoState();
    }
  }, [isOnChain, clearDemoState]);

  // Pre-load demo state on first render if no wallet connected
  useEffect(() => {
    if (!isConnected && activeIntents.length === 0) {
      loadDemoState();
    }
  }, [isConnected, activeIntents.length, loadDemoState]);

  // Subscribe to all WS events and push to store
  const handler = useCallback((event: WSEvent) => {
    handleWSEvent(event);
  }, [handleWSEvent]);

  useWebSocket(
    ['watcher:status', 'trigger:fired', 'watcher:created', 'loop:completed'],
    handler,
  );

  // Get active watcher IDs to trigger the query and store price updates
  const activeWatcherIds = activeIntents
    .flatMap((i) => i.watchers)
    .filter((w) => w.status === 'ACTIVE' && w.id.startsWith('0x'))
    .map((w) => w.id as `0x${string}`);

  useWatchers(activeWatcherIds);
  const ethPrice = useEthPrice();

  // Compute stats
  const totalWatchers = activeIntents.reduce((sum, i) => sum + i.watchers.filter((w) => w.status === 'ACTIVE').length, 0);
  const triggersFired = triggerFeed.length;
  const activeCount = activeIntents.filter((i) => ['ACTIVE', 'EXECUTING', 'PENDING'].includes(i.status)).length;

  // Calculate TVL
  const tvl = activeIntents
    .filter((i) => ['ACTIVE', 'EXECUTING', 'PENDING'].includes(i.status))
    .reduce((sum, intent) => {
      let intentVal = 0;
      intent.segments.forEach((seg) => {
        if (seg.type === 'DEPOSIT' || seg.type === 'SWAP') {
          const amt = parseFloat(seg.amount || '0');
          if (!isNaN(amt)) {
            const isUSDC = seg.from?.toUpperCase() === 'USDC' || seg.to?.toUpperCase() === 'USDC';
            const val = isUSDC ? amt : amt * ethPrice;
            if (val > intentVal) {
              intentVal = val;
            }
          }
        }
      });
      return sum + intentVal;
    }, 0);

  const formattedTVL = new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD',
  }).format(tvl);

  return (
    <div className="max-w-5xl mx-auto">
      {/* Page header */}
      <div className="flex items-start justify-between mb-8">
        <div>
          <h1 className="font-display text-2xl text-text-primary">Dashboard</h1>
          <div className="flex items-center gap-2 mt-1">
            <PulsingDot
              color={isOnChain ? 'emerald' : wsConnected ? 'emerald' : isSimulating ? 'amethyst' : 'amber'}
              size="sm"
            />
            <p className="text-xs text-text-tertiary">
              {isOnChain
                ? wsConnected
                  ? 'On-chain · Live feed connected'
                  : 'On-chain mode · Arbitrum Sepolia'
                : wsConnected
                ? 'Live feed connected'
                : isSimulating
                ? 'Demo mode — connect wallet to go live'
                : 'Connecting…'}
            </p>
          </div>
        </div>
        {!isConnected && (
          <div className="flex-shrink-0">
            <ConnectButton />
          </div>
        )}
      </div>

      {/* Stats */}
      <StatsBar
        activeSigils={activeCount}
        liveWatchers={totalWatchers}
        triggersFired={triggersFired}
        protectedTVL={formattedTVL}
      />

      {/* Main grid */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Active sigils — 2/3 width */}
        <div className="lg:col-span-2 space-y-4">
          <h2 className="text-sm font-semibold text-text-secondary uppercase tracking-wider">Active Sigils</h2>
          <ActiveSigils intents={activeIntents} isLoading={isLoading && isConnected} />
        </div>

        {/* Trigger feed — 1/3 width */}
        <div className="space-y-4">
          <h2 className="text-sm font-semibold text-text-secondary uppercase tracking-wider flex items-center gap-2">
            Trigger Feed
            {triggerFeed.length > 0 && (
              <span className="text-[10px] px-1.5 py-0.5 rounded-full bg-ruby-900/30 text-ruby-400 border border-ruby-500/20">
                {triggerFeed.length}
              </span>
            )}
          </h2>
          <div className="rounded-xl border border-white/[0.07] bg-sigil-secondary p-4">
            <TriggerFeed events={triggerFeed} />
          </div>
        </div>
      </div>
    </div>
  );
}
