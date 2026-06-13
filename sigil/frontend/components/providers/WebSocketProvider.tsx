'use client';

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useRef,
  useState,
  ReactNode,
} from 'react';

// ============================================================
// Types
// ============================================================
export type WSEventType =
  | 'intent:created'
  | 'intent:executed'
  | 'watcher:created'
  | 'watcher:status'
  | 'trigger:fired'
  | 'loop:completed';

export interface WSEvent {
  type: WSEventType;
  timestamp: number;
  data: Record<string, unknown>;
}

interface WSContextValue {
  isConnected: boolean;
  isSimulating: boolean;
  lastEvent: WSEvent | null;
  events: WSEvent[];
  subscribe: (type: WSEventType, handler: (event: WSEvent) => void) => () => void;
}

// ============================================================
// Simulation — fires mock events when WS is unavailable
// ============================================================
const ETH_START_PRICE = 3750;
const THRESHOLD = 3500;

function generateSimulatedEvents(dispatch: (e: WSEvent) => void) {
  let currentPrice = ETH_START_PRICE;
  let phase: 'stable' | 'declining' | 'triggered' = 'stable';
  let tickCount = 0;

  const tick = () => {
    tickCount++;

    if (phase === 'stable' && tickCount > 6) phase = 'declining';

    if (phase === 'declining') {
      currentPrice -= Math.random() * 35 + 15;
    } else {
      currentPrice += (Math.random() - 0.48) * 20;
    }

    dispatch({
      type: 'watcher:status',
      timestamp: Date.now(),
      data: {
        watcherId: 'sim-watcher-1',
        watcherType: 'PRICE',
        currentPrice: Math.round(currentPrice),
        threshold: THRESHOLD,
        status: 'ACTIVE',
        lastChecked: Date.now(),
      },
    });

    if (phase === 'declining' && currentPrice < THRESHOLD) {
      phase = 'triggered';
      setTimeout(() => {
        dispatch({
          type: 'trigger:fired',
          timestamp: Date.now(),
          data: {
            watcherId: 'sim-watcher-1',
            watcherType: 'PRICE',
            triggerPrice: Math.round(currentPrice),
            threshold: THRESHOLD,
            condition: `ETH dropped below $${THRESHOLD}`,
            newIntent: 'Exit 0.5 ETH → USDC',
            txHash: '0xsim' + Math.random().toString(16).slice(2, 10),
          },
        });
        dispatch({
          type: 'loop:completed',
          timestamp: Date.now(),
          data: { watcherId: 'sim-watcher-1' },
        });
      }, 1500);
    }
  };

  // Watcher created event on load
  setTimeout(() => {
    dispatch({
      type: 'watcher:created',
      timestamp: Date.now(),
      data: {
        watcherId: 'sim-watcher-1',
        watcherType: 'PRICE',
        condition: `ETH < $${THRESHOLD}`,
        intentSummary: 'Put 0.5 ETH into Aave. Exit to USDC if ETH < $3,500.',
      },
    });
  }, 1000);

  const interval = setInterval(tick, 2500);
  return () => clearInterval(interval);
}

// ============================================================
// Context
// ============================================================
const WSContext = createContext<WSContextValue>({
  isConnected: false,
  isSimulating: false,
  lastEvent: null,
  events: [],
  subscribe: () => () => {},
});

const MAX_EVENTS = 50;

export function WebSocketProvider({ children }: { children: ReactNode }) {
  const [isConnected, setIsConnected] = useState(false);
  const [isSimulating, setIsSimulating] = useState(false);
  const [lastEvent, setLastEvent] = useState<WSEvent | null>(null);
  const [events, setEvents] = useState<WSEvent[]>([]);
  const listenersRef = useRef<Map<WSEventType, Set<(e: WSEvent) => void>>>(new Map());
  const wsRef = useRef<WebSocket | null>(null);
  const retryRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const retryCount = useRef(0);

  const dispatch = useCallback((event: WSEvent) => {
    setLastEvent(event);
    setEvents(prev => [event, ...prev].slice(0, MAX_EVENTS));
    listenersRef.current.get(event.type)?.forEach(handler => handler(event));
  }, []);

  const startSimulation = useCallback(() => {
    setIsSimulating(true);
    return generateSimulatedEvents(dispatch);
  }, [dispatch]);

  const connect = useCallback(() => {
    const wsUrl = process.env.NEXT_PUBLIC_WS_URL ?? 'ws://localhost:3002';
    try {
      const ws = new WebSocket(wsUrl);
      wsRef.current = ws;

      ws.onopen = () => {
        setIsConnected(true);
        setIsSimulating(false);
        retryCount.current = 0;
      };

      ws.onmessage = (msg) => {
        try {
          const event: WSEvent = JSON.parse(msg.data);
          dispatch(event);
        } catch { /* ignore malformed */ }
      };

      ws.onclose = () => {
        setIsConnected(false);
        wsRef.current = null;

        // Exponential backoff reconnect
        const delay = Math.min(1000 * 2 ** retryCount.current, 30000);
        retryCount.current++;
        retryRef.current = setTimeout(connect, delay);
      };

      ws.onerror = () => {
        ws.close();
      };
    } catch {
      // WS unavailable — fall through to simulation
      startSimulation();
    }
  }, [dispatch, startSimulation]);

  useEffect(() => {
    // Try live connection first, fallback to simulation after 3s
    const fallbackTimer = setTimeout(() => {
      if (!isConnected) {
        startSimulation();
      }
    }, 3000);

    connect();

    return () => {
      clearTimeout(fallbackTimer);
      if (retryRef.current) clearTimeout(retryRef.current);
      wsRef.current?.close();
    };
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const subscribe = useCallback(
    (type: WSEventType, handler: (event: WSEvent) => void) => {
      if (!listenersRef.current.has(type)) {
        listenersRef.current.set(type, new Set());
      }
      listenersRef.current.get(type)!.add(handler);
      return () => listenersRef.current.get(type)?.delete(handler);
    },
    [],
  );

  return (
    <WSContext.Provider value={{ isConnected, isSimulating, lastEvent, events, subscribe }}>
      {children}
    </WSContext.Provider>
  );
}

export const useWSContext = () => useContext(WSContext);
