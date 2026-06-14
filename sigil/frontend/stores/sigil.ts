import { create } from 'zustand';
import { WSEvent } from '../components/providers/WebSocketProvider';

// ============================================================
// Types
// ============================================================
export type IntentStep =
  | 'idle'
  | 'loading'
  | 'decomposed'
  | 'confirming'
  | 'executing'
  | 'done'
  | 'error';

export interface Segment {
  type: 'SWAP' | 'DEPOSIT' | 'WITHDRAW' | 'HEDGE' | 'CUSTOM';
  protocol?: string;
  description: string;
  from?: string;
  to?: string;
  amount?: string;
  txHash?: string;
  status?: 'pending' | 'executing' | 'done' | 'error';
}

export interface WatcherConfig {
  watcherType: 'PRICE' | 'TIME' | 'RISK' | 'GOVERNANCE';
  condition: string;
  threshold?: number;
  action: string;
  expiresAt?: number;
}

export interface DecomposedIntent {
  summary: string;
  immediateSegments: Segment[];
  watchers: WatcherConfig[];
  intentId?: string;
}

export interface ActiveWatcher {
  id: string;
  watcherType: 'PRICE' | 'TIME' | 'RISK' | 'GOVERNANCE';
  status: 'ACTIVE' | 'TRIGGERED' | 'EXPIRED' | 'CANCELLED';
  condition: string;
  threshold?: number;
  currentPrice?: number;
  action: string;
  createdAt: number;
  expiresAt?: number;
  intentSummary: string;
}

export interface ActiveIntent {
  id: string;
  summary: string;
  status: 'PENDING' | 'EXECUTING' | 'ACTIVE' | 'TRIGGERED' | 'COMPLETED' | 'CANCELLED' | 'EXPIRED';
  segments: Segment[];
  watchers: ActiveWatcher[];
  createdAt: number;
  txHash?: string;
}

export interface TriggerEvent {
  id: string;
  watcherId: string;
  watcherType: string;
  eventType: string;        // ← added to drive Timeline icons
  condition: string;
  triggerPrice?: number;
  threshold?: number;
  newIntent?: string;
  txHash?: string;
  timestamp: number;
  status: 'pending' | 'confirmed';
}

interface SigilState {
  // Intent creation flow
  intentText: string;
  intentStep: IntentStep;
  decomposed: DecomposedIntent | null;
  intentError: string | null;

  // Dashboard data
  activeIntents: ActiveIntent[];
  triggerFeed: TriggerEvent[];

  // Actions
  setIntentText: (text: string) => void;
  setIntentStep: (step: IntentStep) => void;
  setDecomposed: (d: DecomposedIntent | null) => void;
  setIntentError: (err: string | null) => void;
  resetIntent: () => void;

  addIntent: (intent: ActiveIntent) => void;
  updateIntentStatus: (intentId: string, status: ActiveIntent['status']) => void;
  updateWatcherPrice: (watcherId: string, price: number) => void;
  triggerWatcher: (watcherId: string) => void;
  addTriggerEvent: (event: TriggerEvent) => void;
  confirmTriggerEvent: (eventId: string) => void;
  handleWSEvent: (event: WSEvent) => void;

  // Simulation — pre-load demo state for judges
  loadDemoState: () => void;
  clearDemoState: () => void;
}

// ============================================================
// Demo state for judge presentation
// ============================================================
const DEMO_INTENT: ActiveIntent = {
  id: 'demo-intent-1',
  summary: 'Put 0.5 ETH into Aave for yield. Exit to USDC if ETH drops below $3,500.',
  status: 'ACTIVE',
  segments: [
    { type: 'DEPOSIT', description: 'Deposit 0.5 ETH into Aave v3', status: 'done', protocol: 'Aave', txHash: '0xdemo1', amount: '0.5', from: 'ETH' },
  ],
  watchers: [
    {
      id: 'sim-watcher-1',
      watcherType: 'PRICE',
      status: 'ACTIVE',
      condition: 'ETH < $3,500',
      threshold: 3500,
      currentPrice: 3750,
      action: 'Exit 0.5 ETH → USDC',
      createdAt: Date.now() - 120_000,
      intentSummary: 'Put 0.5 ETH into Aave for yield. Exit to USDC if ETH drops below $3,500.',
    },
  ],
  createdAt: Date.now() - 120_000,
  txHash: '0xdemo1',
};

// ============================================================
// Store
// ============================================================
export const useSigilStore = create<SigilState>((set, get) => ({
  intentText: '',
  intentStep: 'idle',
  decomposed: null,
  intentError: null,
  activeIntents: [],
  triggerFeed: [],

  setIntentText: (text) => set({ intentText: text }),
  setIntentStep: (step) => set({ intentStep: step }),
  setDecomposed: (d) => set({ decomposed: d }),
  setIntentError: (err) => set({ intentError: err }),

  resetIntent: () => set({
    intentText: '',
    intentStep: 'idle',
    decomposed: null,
    intentError: null,
  }),

  addIntent: (intent) => set((state) => {
    const exists = state.activeIntents.some((a) => a.id === intent.id);
    if (exists) {
      return {
        activeIntents: state.activeIntents.map((i) =>
          i.id === intent.id ? { ...i, status: intent.status, segments: intent.segments, watchers: intent.watchers } : i
        ),
      };
    }
    return { activeIntents: [intent, ...state.activeIntents] };
  }),

  updateIntentStatus: (intentId, status) => set((state) => ({
    activeIntents: state.activeIntents.map((i) =>
      i.id === intentId ? { ...i, status } : i
    ),
  })),

  updateWatcherPrice: (watcherId, price) => set((state) => {
    let changed = false;
    const nextIntents = state.activeIntents.map((intent) => {
      let watcherChanged = false;
      const nextWatchers = intent.watchers.map((w) => {
        if (w.id === watcherId && w.currentPrice !== price) {
          watcherChanged = true;
          changed = true;
          return { ...w, currentPrice: price };
        }
        return w;
      });
      return watcherChanged ? { ...intent, watchers: nextWatchers } : intent;
    });
    return changed ? { activeIntents: nextIntents } : state;
  }),

  triggerWatcher: (watcherId) => set((state) => ({
    activeIntents: state.activeIntents.map((intent) => ({
      ...intent,
      watchers: intent.watchers.map((w) =>
        w.id === watcherId ? { ...w, status: 'TRIGGERED' as const } : w
      ),
    })),
  })),

  addTriggerEvent: (event) => set((state) => ({
    triggerFeed: [event, ...state.triggerFeed].slice(0, 50),
  })),

  confirmTriggerEvent: (eventId) => set((state) => ({
    triggerFeed: state.triggerFeed.map((e) =>
      e.id === eventId ? { ...e, status: 'confirmed' as const } : e
    ),
  })),

  handleWSEvent: (event) => {
    const { updateWatcherPrice, triggerWatcher, addTriggerEvent, confirmTriggerEvent } = get();

    const makeEvent = (overrides: Partial<TriggerEvent>): TriggerEvent => ({
      id: `evt-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`,
      watcherId: '',
      watcherType: 'PRICE',
      eventType: event.type,
      condition: '',
      timestamp: event.timestamp,
      status: 'pending',
      ...overrides,
    });

    switch (event.type) {
      case 'watcher:status': {
        const d = event.data as { watcherId: string; currentPrice: number };
        if (d.watcherId && d.currentPrice) {
          updateWatcherPrice(d.watcherId, d.currentPrice);
        }
        break;
      }

      case 'trigger:fired': {
        const d = event.data as {
          watcherId: string;
          watcherType: string;
          triggerPrice?: number;
          threshold?: number;
          condition?: string;
          newIntent?: string;
          txHash?: string;
        };
        triggerWatcher(d.watcherId);
        const ev = makeEvent({
          watcherId: d.watcherId,
          watcherType: d.watcherType ?? 'PRICE',
          condition: d.condition ?? 'Threshold met',
          triggerPrice: d.triggerPrice,
          threshold: d.threshold,
          newIntent: d.newIntent,
          txHash: d.txHash,
        });
        addTriggerEvent(ev);
        // Mark confirmed after 8 s (simulate on-chain confirmation)
        setTimeout(() => confirmTriggerEvent(ev.id), 8_000);
        break;
      }

      case 'watcher:created': {
        const d = event.data as { watcherId?: string; watcherType?: string; condition?: string };
        const ev = makeEvent({
          watcherId: d.watcherId ?? '',
          watcherType: d.watcherType ?? 'PRICE',
          condition: d.condition ?? 'Watcher registered on-chain',
        });
        addTriggerEvent(ev);
        setTimeout(() => confirmTriggerEvent(ev.id), 5_000);
        break;
      }

      case 'loop:completed': {
        const d = event.data as { intentId?: string; newIntentId?: string; summary?: string };
        const ev = makeEvent({
          watcherType: 'SYSTEM',
          condition: d.summary ?? 'Intent loop completed — new intent created',
          newIntent: d.newIntentId ? `Intent ${String(d.newIntentId).slice(0, 10)}…` : undefined,
        });
        addTriggerEvent(ev);
        setTimeout(() => confirmTriggerEvent(ev.id), 5_000);
        break;
      }

      default:
        break;
    }
  },

  loadDemoState: () => set({
    activeIntents: [DEMO_INTENT],
    triggerFeed: [],
  }),

  clearDemoState: () => set((state) => ({
    // Remove only the demo intent — keep any real on-chain intents already loaded
    activeIntents: state.activeIntents.filter((i) => !i.id.startsWith('demo-')),
    // Clear simulated trigger events (they have no txHash and were generated locally)
    triggerFeed: state.triggerFeed.filter((e) => !!e.txHash),
  })),
}));
