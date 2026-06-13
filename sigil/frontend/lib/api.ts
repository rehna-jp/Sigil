import { BACKEND_URL } from './constants';

// ============================================================
// API Client — wraps fetch to backend REST endpoints
// ============================================================

interface DecomposeRequest {
  userInput: string;
  userAddress: string;
}

interface DecomposeResponse {
  ok: boolean;
  summary: string;
  immediateSegments: Array<{
    type: string;
    protocol?: string;
    description: string;
    from?: string;
    to?: string;
    amount?: string;
  }>;
  watchers: Array<{
    watcherType: string;
    condition: string;
    threshold?: number;
    action: string;
  }>;
  intentId?: string;
  error?: string;
}

// Mock decomposition for when backend is unavailable
function mockDecompose(userInput: string): DecomposeResponse {
  const lower = userInput.toLowerCase();
  const hasYield  = lower.includes('yield') || lower.includes('aave');
  const hasSwap   = lower.includes('swap') || lower.includes('usdc');
  const hasDrop   = lower.includes('drop') || lower.includes('below') || lower.includes('<');
  const hasRebal  = lower.includes('rebalance');

  // Parse threshold
  const threshMatch = userInput.match(/\$([0-9,]+)/);
  const threshold = threshMatch ? parseInt(threshMatch[1].replace(',', '')) : 3500;

  const segments = [];
  const watchers = [];

  if (hasYield) {
    segments.push({
      type: 'DEPOSIT',
      protocol: 'Aave v3',
      description: 'Deposit ETH into Aave v3 for yield',
      from: 'ETH',
      to: 'aETH',
    });
  }
  if (hasSwap && !hasYield) {
    segments.push({
      type: 'SWAP',
      protocol: 'Uniswap v3',
      description: 'Swap tokens on Uniswap v3',
      from: 'ETH',
      to: 'USDC',
    });
  }
  if (hasRebal) {
    segments.push({
      type: 'SWAP',
      protocol: 'Uniswap v3',
      description: 'Rebalance portfolio to 60% ETH / 40% USDC',
      from: 'USDC',
      to: 'ETH',
    });
  }
  if (segments.length === 0) {
    segments.push({
      type: 'SWAP',
      protocol: 'Uniswap v3',
      description: 'Execute swap on Uniswap v3',
      from: 'ETH',
      to: 'USDC',
    });
  }

  if (hasDrop) {
    watchers.push({
      watcherType: 'PRICE',
      condition: `ETH/USD < $${threshold.toLocaleString()}`,
      threshold,
      action: 'Exit position to USDC',
    });
  }
  if (hasRebal) {
    watchers.push({
      watcherType: 'TIME',
      condition: 'Every 30 days',
      action: 'Rebalance portfolio to 60/40',
    });
  }
  if (watchers.length === 0 && hasYield) {
    watchers.push({
      watcherType: 'PRICE',
      condition: `ETH/USD < $${threshold.toLocaleString()}`,
      threshold,
      action: 'Withdraw from Aave and exit to USDC',
    });
  }

  return {
    ok: true,
    summary: userInput,
    immediateSegments: segments,
    watchers,
  };
}

export async function apiDecompose(req: DecomposeRequest): Promise<DecomposeResponse> {
  try {
    const res = await fetch(`${BACKEND_URL}/api/decompose`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(req),
      signal: AbortSignal.timeout(10_000),
    });

    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    return res.json();
  } catch {
    // Backend unavailable — use mock decomposer
    await new Promise(r => setTimeout(r, 1800)); // realistic delay
    return mockDecompose(req.userInput);
  }
}

export async function apiGetIntents(address: string) {
  try {
    const res = await fetch(`${BACKEND_URL}/api/intents/${address}`, {
      signal: AbortSignal.timeout(5_000),
    });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    return res.json();
  } catch {
    return { intents: [] };
  }
}

export async function apiGetWatchers(address: string) {
  try {
    const res = await fetch(`${BACKEND_URL}/api/watchers/${address}`, {
      signal: AbortSignal.timeout(5_000),
    });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    return res.json();
  } catch {
    return { watchers: [] };
  }
}

export async function apiHealth(): Promise<boolean> {
  try {
    const res = await fetch(`${BACKEND_URL}/api/health`, {
      signal: AbortSignal.timeout(3_000),
    });
    return res.ok;
  } catch {
    return false;
  }
}
