'use client';

import { ChevronDown, ChevronUp, ExternalLink } from 'lucide-react';
import { useState } from 'react';
import { StatusBadge } from '../ui/StatusBadge';
import { WatcherCard } from './WatcherCard';
import { ActiveIntent } from '../../stores/sigil';
import { getArbiscanTx } from '../../lib/constants';

interface SigilCardProps {
  intent: ActiveIntent;
  onCancelWatcher?: (watcherId: string) => void;
}

const TYPE_ICONS: Record<string, string> = {
  SWAP:     '⇄',
  DEPOSIT:  '↓',
  WITHDRAW: '↑',
  HEDGE:    '△',
  CUSTOM:   '◆',
};

export function SigilCard({ intent, onCancelWatcher }: SigilCardProps) {
  const [expanded, setExpanded] = useState(false);
  const activeWatchers = intent.watchers.filter((w) => w.status === 'ACTIVE');

  return (
    <div className="rounded-xl border border-white/[0.07] bg-sigil-secondary overflow-hidden transition-all duration-200 hover:border-amethyst-500/20">
      {/* Card header */}
      <div className="px-4 py-4">
        <div className="flex items-start justify-between gap-3">
          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-2 mb-1">
              <StatusBadge status={intent.status} />
              {intent.txHash && (
                <a
                  href={getArbiscanTx(intent.txHash)}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-[10px] text-amethyst-400 hover:text-amethyst-300 transition-colors flex items-center gap-1"
                >
                  <ExternalLink size={9} />
                  Tx
                </a>
              )}
            </div>
            <p className="text-sm text-text-primary leading-snug line-clamp-2">{intent.summary}</p>
            <p className="text-xs text-text-tertiary mt-1.5">
              {new Date(intent.createdAt).toLocaleDateString(undefined, {
                month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit',
              })}
              {' · '}
              {intent.segments.length} segment{intent.segments.length !== 1 ? 's' : ''}
              {' · '}
              {activeWatchers.length} active watcher{activeWatchers.length !== 1 ? 's' : ''}
            </p>
          </div>
          <button
            onClick={() => setExpanded((v) => !v)}
            className="flex-shrink-0 p-1.5 rounded-lg text-text-tertiary hover:text-text-secondary hover:bg-sigil-hover transition-all"
            aria-label={expanded ? 'Collapse' : 'Expand'}
          >
            {expanded ? <ChevronUp size={14} /> : <ChevronDown size={14} />}
          </button>
        </div>

        {/* Segment pills */}
        <div className="flex flex-wrap gap-1.5 mt-3">
          {intent.segments.map((seg, i) => (
            <span
              key={i}
              className={`text-[10px] px-2 py-0.5 rounded-full border font-medium
                ${seg.status === 'done'
                  ? 'border-emerald-500/20 text-emerald-400 bg-emerald-900/20'
                  : seg.status === 'error'
                  ? 'border-ruby-500/20 text-ruby-400 bg-ruby-900/20'
                  : 'border-white/10 text-text-tertiary bg-sigil-tertiary'
                }`}
            >
              {TYPE_ICONS[seg.type] ?? '◆'} {seg.type}
              {seg.protocol ? ` · ${seg.protocol}` : ''}
            </span>
          ))}
        </div>
      </div>

      {/* Expanded watchers */}
      {expanded && intent.watchers.length > 0 && (
        <div className="border-t border-white/[0.05] px-4 py-4 space-y-3">
          <p className="text-xs font-medium text-text-tertiary uppercase tracking-wider">Watchers</p>
          {intent.watchers.map((w) => (
            <WatcherCard key={w.id} watcher={w} onCancel={onCancelWatcher} />
          ))}
        </div>
      )}
    </div>
  );
}
