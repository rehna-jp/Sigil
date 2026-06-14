'use client';

import { useEffect, useRef, useState } from 'react';
import { Clock, TrendingDown, ExternalLink } from 'lucide-react';
import { PulsingDot } from '../ui/PulsingDot';
import { ActiveWatcher } from '../../stores/sigil';
import { getArbiscanAddress, CONTRACTS } from '../../lib/constants';

interface WatcherCardProps {
  watcher: ActiveWatcher;
  onCancel?: (id: string) => void;
}

function PriceGauge({ current, threshold }: { current: number; threshold: number }) {
  // gauge range: ±15% around threshold
  const range = threshold * 0.15;
  const min = threshold - range;
  const max = threshold + range;
  const pct = Math.min(100, Math.max(0, ((current - min) / (max - min)) * 100));

  // Color based on proximity
  const proximityPct = ((current - threshold) / threshold) * 100; // negative = below threshold
  const color = proximityPct > 5
    ? 'bg-emerald-500'
    : proximityPct > 0
    ? 'bg-amber-400'
    : 'bg-ruby-500';

  return (
    <div className="space-y-2 my-3">
      <div className="flex justify-between text-xs text-text-tertiary">
        <span>${threshold.toLocaleString()} threshold</span>
        <span className={`font-mono font-medium ${proximityPct < 0 ? 'text-ruby-400' : proximityPct < 5 ? 'text-amber-400' : 'text-emerald-400'}`}>
          ${current.toLocaleString(undefined, { minimumFractionDigits: 0, maximumFractionDigits: 0 })}
        </span>
      </div>
      {/* Track */}
      <div className="relative h-1.5 rounded-full bg-sigil-tertiary overflow-hidden">
        {/* Threshold marker */}
        <div
          className="absolute top-0 w-0.5 h-full bg-white/30 z-10"
          style={{ left: '50%' }}
        />
        {/* Current price indicator */}
        <div
          className={`absolute top-0 h-full w-1.5 rounded-full ${color} transition-all duration-700 -translate-x-1/2`}
          style={{ left: `${pct}%` }}
        />
      </div>
      <div className="flex justify-between text-[10px] text-text-tertiary">
        <span>${(threshold - range).toLocaleString(undefined, { maximumFractionDigits: 0 })}</span>
        <span>${(threshold + range).toLocaleString(undefined, { maximumFractionDigits: 0 })}</span>
      </div>
    </div>
  );
}

export function WatcherCard({ watcher, onCancel }: WatcherCardProps) {
  const [isTriggered, setIsTriggered] = useState(watcher.status === 'TRIGGERED');
  const prevStatus = useRef(watcher.status);

  // Flash animation when status changes to TRIGGERED
  useEffect(() => {
    if (prevStatus.current !== 'TRIGGERED' && watcher.status === 'TRIGGERED') {
      setIsTriggered(true);
    }
    prevStatus.current = watcher.status;
  }, [watcher.status]);

  const expiresIn = watcher.expiresAt
    ? Math.max(0, Math.floor((watcher.expiresAt - Date.now()) / (1000 * 60 * 60 * 24)))
    : null;

  const dotColor = watcher.status === 'TRIGGERED'
    ? 'ruby'
    : watcher.status === 'EXPIRED' || watcher.status === 'CANCELLED'
    ? 'amber'
    : watcher.currentPrice && watcher.threshold && watcher.currentPrice < (watcher.threshold * 1.05)
    ? 'amber'
    : 'emerald';

  return (
    <div
      className={`
        relative rounded-xl border p-4 transition-all duration-300
        ${isTriggered
          ? 'animate-ruby-flash border-ruby-500/60 bg-ruby-900/20'
          : dotColor === 'amber'
          ? 'border-amber-500/25 bg-sigil-secondary hover:border-amber-500/40'
          : 'border-white/[0.07] bg-sigil-secondary hover:border-amethyst-500/30'
        }
      `}
    >
      {/* Header */}
      <div className="flex items-start justify-between gap-2">
        <div className="flex items-center gap-2">
          <PulsingDot color={dotColor} />
          <div>
            <p className="text-sm font-medium text-text-primary">{watcher.condition}</p>
            <p className="text-xs text-text-tertiary mt-0.5">{watcher.watcherType} Watcher</p>
          </div>
        </div>
        <span
          className={`text-[10px] font-medium px-2 py-0.5 rounded-full border ${
            watcher.status === 'ACTIVE'     ? 'text-emerald-400 border-emerald-500/20 bg-emerald-900/20' :
            watcher.status === 'TRIGGERED'  ? 'text-ruby-400 border-ruby-500/20 bg-ruby-900/20' :
            'text-text-tertiary border-white/10 bg-sigil-tertiary'
          }`}
        >
          {watcher.status}
        </span>
      </div>

      {/* Price gauge for PRICE watchers */}
      {watcher.watcherType === 'PRICE' && watcher.currentPrice && watcher.threshold && (
        <PriceGauge current={watcher.currentPrice} threshold={watcher.threshold} />
      )}

      {/* Trigger info */}
      {isTriggered && (
        <div className="mt-3 p-2.5 rounded-lg bg-ruby-900/30 border border-ruby-500/20">
          <div className="flex items-center gap-2 text-xs text-ruby-400">
            <TrendingDown size={12} />
            <span>Condition met — {watcher.action}</span>
          </div>
        </div>
      )}

      {/* Footer */}
      <div className="flex items-center justify-between mt-3 pt-3 border-t border-white/[0.05]">
        <div className="flex items-center gap-1.5 text-[11px] text-text-tertiary">
          <Clock size={10} />
          {expiresIn !== null ? (
            <span>Expires in {expiresIn}d</span>
          ) : (
            <span>No expiry</span>
          )}
        </div>
        <div className="flex items-center gap-2">
          <a
            href={`${getArbiscanAddress(CONTRACTS.arbitrumSepolia.WatcherRegistry)}#readContract`}
            target="_blank"
            rel="noopener noreferrer"
            className="text-[11px] text-text-tertiary hover:text-amethyst-400 transition-colors flex items-center gap-1"
            title={`Watcher ID: ${watcher.id}`}
          >
            <ExternalLink size={10} />
            View
          </a>
          {watcher.status === 'ACTIVE' && onCancel && (
            <button
              onClick={() => onCancel(watcher.id)}
              className="text-[11px] text-text-tertiary hover:text-ruby-400 transition-colors"
            >
              Cancel
            </button>
          )}
        </div>
      </div>
    </div>
  );
}
