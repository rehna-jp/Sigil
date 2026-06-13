'use client';

import { useEffect } from 'react';
import { useWSContext, WSEventType, WSEvent } from '../components/providers/WebSocketProvider';

/**
 * Subscribe to one or more WebSocket event types.
 * Returns the full event list and connection state.
 */
export function useWebSocket(
  type?: WSEventType | WSEventType[],
  handler?: (event: WSEvent) => void,
) {
  const { isConnected, isSimulating, lastEvent, events, subscribe } = useWSContext();

  useEffect(() => {
    if (!type || !handler) return;
    const types = Array.isArray(type) ? type : [type];
    const unsubs = types.map((t) => subscribe(t, handler));
    return () => unsubs.forEach((u) => u());
  }, [type, handler, subscribe]);

  return { isConnected, isSimulating, lastEvent, events };
}
