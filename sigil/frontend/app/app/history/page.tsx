'use client';

import { useCallback, useState, useEffect } from 'react';
import Link from 'next/link';
import { Clock } from 'lucide-react';
import { Timeline } from '../../../components/history/Timeline';
import { useSigilStore } from '../../../stores/sigil';
import { useWebSocket } from '../../../hooks/useWebSocket';
import { WSEvent } from '../../../components/providers/WebSocketProvider';

export default function HistoryPage() {
  const { triggerFeed, handleWSEvent } = useSigilStore();
  const [filter, setFilter] = useState<'ALL' | 'TRIGGER' | 'LOOP' | 'WATCHER'>('ALL');

  // Set browser page title
  useEffect(() => {
    document.title = 'Trigger History | Sigil';
  }, []);

  // Keep listening for new events to add to history
  const handler = useCallback((event: WSEvent) => {
    handleWSEvent(event);
  }, [handleWSEvent]);

  useWebSocket(['trigger:fired', 'loop:completed', 'watcher:created', 'intent:executed'], handler);

  const filteredEvents = triggerFeed.filter((event) => {
    if (filter === 'ALL') return true;
    if (filter === 'TRIGGER') return event.eventType === 'trigger:fired';
    if (filter === 'LOOP') return event.eventType === 'loop:completed';
    if (filter === 'WATCHER') return event.eventType === 'watcher:created';
    return true;
  });

  const filterOptions = [
    { value: 'ALL', label: 'All Events' },
    { value: 'TRIGGER', label: 'Triggers' },
    { value: 'LOOP', label: 'Loops' },
    { value: 'WATCHER', label: 'Watchers' },
  ] as const;

  if (triggerFeed.length === 0) {
    return (
      <div className="max-w-2xl mx-auto">
        <div className="mb-8">
          <h1 className="font-display text-2xl text-text-primary">Trigger History</h1>
          <p className="text-text-tertiary text-sm mt-1">
            Chronological audit trail of all watcher triggers and intent executions
          </p>
        </div>
        <div className="rounded-xl border border-white/[0.07] bg-sigil-secondary p-8 flex flex-col items-center justify-center text-center py-16">
          <div className="w-12 h-12 rounded-full border border-white/[0.07] flex items-center justify-center mb-4 text-text-tertiary">
            <Clock size={20} />
          </div>
          <h3 className="text-sm font-semibold text-text-primary mb-1">No history yet</h3>
          <p className="text-xs text-text-tertiary mb-6 max-w-sm">
            Trigger events and executed actions will appear here once your active price or time watchers are triggered.
          </p>
          <Link
            href="/app/cast"
            className="px-4 py-2 rounded-lg text-xs font-semibold text-white bg-gradient-to-r from-amethyst-700 to-amethyst-500 hover:from-amethyst-600 hover:to-amethyst-400 transition-all shadow-glow-amethyst"
          >
            Cast a Sigil
          </Link>
        </div>
      </div>
    );
  }

  return (
    <div className="max-w-2xl mx-auto">
      <div className="mb-8">
        <h1 className="font-display text-2xl text-text-primary">Trigger History</h1>
        <p className="text-text-tertiary text-sm mt-1">
          Chronological audit trail of all watcher triggers and intent executions
        </p>
      </div>

      {/* Filter controls */}
      <div className="flex flex-wrap items-center justify-between gap-3 mb-6">
        <div className="flex gap-2">
          {filterOptions.map((opt) => (
            <button
              key={opt.value}
              onClick={() => setFilter(opt.value)}
              className={`px-3 py-1.5 rounded-lg text-xs font-medium border transition-all duration-200 ${
                filter === opt.value
                  ? 'border-amethyst-500 bg-amethyst-900/20 text-amethyst-300'
                  : 'border-white/[0.07] bg-sigil-secondary text-text-tertiary hover:text-text-secondary hover:border-white/20'
              }`}
            >
              {opt.label}
            </button>
          ))}
        </div>
        <p className="text-xs text-text-tertiary">
          {filteredEvents.length} event{filteredEvents.length !== 1 ? 's' : ''} shown
        </p>
      </div>

      <div className="rounded-xl border border-white/[0.07] bg-sigil-secondary p-6">
        {filteredEvents.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-12 text-center">
            <Clock size={20} className="text-text-tertiary mb-2 opacity-40" />
            <p className="text-text-secondary text-xs">No matching events found</p>
          </div>
        ) : (
          <Timeline events={filteredEvents} />
        )}
      </div>
    </div>
  );
}
