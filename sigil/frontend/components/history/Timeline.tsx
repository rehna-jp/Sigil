'use client';

import { Clock, Zap, Eye, AlertCircle, CheckCircle2, XCircle } from 'lucide-react';
import { TriggerEvent } from '../../stores/sigil';

const EVENT_META: Record<string, { icon: React.ElementType; color: string; border: string; bg: string; label: string }> = {
  'trigger:fired':    { icon: Zap,          color: 'text-ruby-400',    border: 'border-ruby-500/20',    bg: 'bg-ruby-900/20',    label: 'Trigger Fired' },
  'watcher:created':  { icon: Eye,          color: 'text-emerald-400', border: 'border-emerald-500/20', bg: 'bg-emerald-900/20', label: 'Watcher Created' },
  'intent:executed':  { icon: CheckCircle2, color: 'text-amethyst-400',border: 'border-amethyst-500/20', bg: 'bg-amethyst-900/20', label: 'Intent Executed' },
  'loop:completed':   { icon: CheckCircle2, color: 'text-sapphire-400',border: 'border-sapphire-400/20', bg: 'bg-sapphire-500/10', label: 'Loop Completed' },
  'intent:created':   { icon: Zap,          color: 'text-amethyst-400',border: 'border-amethyst-500/20', bg: 'bg-amethyst-900/20', label: 'Intent Created' },
  'watcher:status':   { icon: Eye,          color: 'text-text-tertiary', border: 'border-white/[0.07]', bg: 'bg-sigil-secondary', label: 'Watcher Status' },
};

function timeStr(ts: number) {
  return new Date(ts).toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit', second: '2-digit' });
}

interface TimelineProps {
  events: TriggerEvent[];
}

export function Timeline({ events }: TimelineProps) {
  if (events.length === 0) {
    return (
      <div className="flex flex-col items-center justify-center py-20 text-center">
        <Clock size={28} className="text-text-tertiary mb-3 opacity-40" />
        <p className="text-text-secondary">No history yet</p>
        <p className="text-xs text-text-tertiary mt-1">Trigger events will be logged here</p>
      </div>
    );
  }

  return (
    <div className="relative">
      {/* Vertical line */}
      <div className="absolute left-[15px] top-0 bottom-0 w-px bg-white/[0.06]" />

      <div className="space-y-1">
        {events.map((event) => {
          const meta = EVENT_META[event.eventType] ?? EVENT_META['trigger:fired'];
          const IconComponent = meta.icon;
          return (
            <div key={event.id} className="relative flex items-start gap-4 pl-10 py-4">
              {/* Dot */}
              <div className={`absolute left-0 w-[30px] h-[30px] rounded-full border flex items-center justify-center flex-shrink-0 ${meta.bg} ${meta.border}`}>
                <IconComponent size={12} className={meta.color} />
              </div>

              {/* Content */}
              <div className="flex-1 min-w-0">
                <div className="flex items-start justify-between gap-2">
                  <div>
                    <p className="text-sm font-medium text-text-primary">
                      {meta.label}
                    </p>
                    <p className="text-xs text-text-tertiary mt-0.5">{event.condition}</p>
                    {event.triggerPrice && event.threshold && (
                      <p className="text-xs mt-1">
                        <span className="text-ruby-400">${event.triggerPrice.toLocaleString()}</span>
                        <span className="text-text-tertiary"> below threshold </span>
                        <span className="text-text-secondary">${event.threshold.toLocaleString()}</span>
                      </p>
                    )}
                    {event.newIntent && (
                      <p className="text-xs text-amethyst-400 mt-1">→ {event.newIntent}</p>
                    )}
                  </div>
                  <div className="flex-shrink-0 text-right">
                    <p className="text-[10px] text-text-tertiary font-mono">{timeStr(event.timestamp)}</p>
                    <span className={`inline-block mt-1 text-[10px] px-1.5 py-0.5 rounded-full border ${
                      event.status === 'confirmed'
                        ? 'border-emerald-500/20 text-emerald-400 bg-emerald-900/20'
                        : 'border-amber-500/20 text-amber-400 bg-amber-500/10'
                    }`}>
                      {event.status}
                    </span>
                  </div>
                </div>
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}
