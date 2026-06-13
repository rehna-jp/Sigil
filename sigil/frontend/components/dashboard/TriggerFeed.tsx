'use client';

import { ExternalLink, Bell, Zap } from 'lucide-react';
import { TriggerEvent } from '../../stores/sigil';
import { getArbiscanTx } from '../../lib/constants';

interface TriggerFeedProps {
  events: TriggerEvent[];
}

function timeAgo(ts: number) {
  const s = Math.floor((Date.now() - ts) / 1000);
  if (s < 60) return `${s}s ago`;
  if (s < 3600) return `${Math.floor(s / 60)}m ago`;
  return `${Math.floor(s / 3600)}h ago`;
}

export function TriggerFeed({ events }: TriggerFeedProps) {
  if (events.length === 0) {
    return (
      <div className="flex flex-col items-center justify-center py-10 text-center">
        <Bell size={24} className="text-text-tertiary mb-3 opacity-40" />
        <p className="text-text-tertiary text-sm">Waiting for trigger events…</p>
        <p className="text-text-tertiary text-xs mt-1 opacity-70">Events will appear here in real-time</p>
      </div>
    );
  }

  return (
    <div className="space-y-2">
      {events.map((event) => (
        <div
          key={event.id}
          className={`relative flex items-start gap-3 px-4 py-3 rounded-xl border transition-all
            ${event.status === 'confirmed'
              ? 'border-emerald-500/15 bg-emerald-900/10'
              : 'border-ruby-500/15 bg-ruby-900/10 animate-pulse'
            }`}
        >
          {/* Icon */}
          <div className={`flex-shrink-0 w-7 h-7 rounded-full border flex items-center justify-center mt-0.5
            ${event.status === 'confirmed'
              ? 'border-emerald-500/30 bg-emerald-900/30'
              : 'border-ruby-500/30 bg-ruby-900/30'
            }`}
          >
            <Zap size={12} className={event.status === 'confirmed' ? 'text-emerald-400' : 'text-ruby-400'} />
          </div>

          {/* Content */}
          <div className="flex-1 min-w-0">
            <div className="flex items-start justify-between gap-2">
              <div>
                <p className="text-xs font-medium text-text-primary">
                  {event.watcherType} Trigger Fired
                </p>
                <p className="text-[11px] text-text-tertiary mt-0.5">
                  {event.condition}
                  {event.triggerPrice && (
                    <span className="text-ruby-400 ml-1">@ ${event.triggerPrice.toLocaleString()}</span>
                  )}
                </p>
                {event.newIntent && (
                  <p className="text-[11px] text-amethyst-400 mt-1">→ {event.newIntent}</p>
                )}
              </div>
              <div className="flex-shrink-0 text-right">
                <p className="text-[10px] text-text-tertiary">{timeAgo(event.timestamp)}</p>
                {event.txHash && (
                  <a
                    href={getArbiscanTx(event.txHash)}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="flex items-center gap-0.5 text-[10px] text-amethyst-400 hover:text-amethyst-300 mt-0.5"
                  >
                    <ExternalLink size={9} />
                    Tx
                  </a>
                )}
              </div>
            </div>
          </div>
        </div>
      ))}
    </div>
  );
}
