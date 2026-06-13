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

export default function DashboardPage() {
  const { isConnected } = useAccount();
  const { activeIntents, triggerFeed, handleWSEvent, loadDemoState } = useSigilStore();
  const { isLoading } = useIntents();
  const { isConnected: wsConnected, isSimulating } = useWebSocket();

  // Pre-load demo state on first render if no on-chain intents
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

  // Compute stats
  const totalWatchers = activeIntents.reduce((sum, i) => sum + i.watchers.filter((w) => w.status === 'ACTIVE').length, 0);
  const triggersFired = triggerFeed.length;
  const activeCount = activeIntents.filter((i) => ['ACTIVE', 'EXECUTING', 'PENDING'].includes(i.status)).length;

  return (
    <div className="max-w-5xl mx-auto">
      {/* Page header */}
      <div className="flex items-start justify-between mb-8">
        <div>
          <h1 className="font-display text-2xl text-text-primary">Dashboard</h1>
          <div className="flex items-center gap-2 mt-1">
            <PulsingDot color={wsConnected || isSimulating ? 'emerald' : 'amber'} size="sm" />
            <p className="text-xs text-text-tertiary">
              {wsConnected ? 'Live feed connected' : isSimulating ? 'Simulation mode — live feed' : 'Connecting…'}
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
        protectedTVL="$0.00"
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
