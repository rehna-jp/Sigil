'use client';

import { useCallback } from 'react';
import { Timeline } from '../../../components/history/Timeline';
import { useSigilStore } from '../../../stores/sigil';
import { useWebSocket } from '../../../hooks/useWebSocket';
import { WSEvent } from '../../../components/providers/WebSocketProvider';

export default function HistoryPage() {
  const { triggerFeed, handleWSEvent } = useSigilStore();

  // Keep listening for new events to add to history
  const handler = useCallback((event: WSEvent) => {
    handleWSEvent(event);
  }, [handleWSEvent]);

  useWebSocket(['trigger:fired', 'loop:completed'], handler);

  return (
    <div className="max-w-2xl mx-auto">
      <div className="mb-8">
        <h1 className="font-display text-2xl text-text-primary">Trigger History</h1>
        <p className="text-text-tertiary text-sm mt-1">
          Chronological audit trail of all watcher triggers and intent executions
        </p>
      </div>

      {/* Filter hint */}
      {triggerFeed.length > 0 && (
        <div className="flex items-center justify-between mb-4">
          <p className="text-xs text-text-tertiary">{triggerFeed.length} event{triggerFeed.length !== 1 ? 's' : ''}</p>
        </div>
      )}

      <div className="rounded-xl border border-white/[0.07] bg-sigil-secondary p-6">
        <Timeline events={triggerFeed} />
      </div>
    </div>
  );
}
