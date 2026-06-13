'use client';

import { useCallback, useState } from 'react';
import { useAccount } from 'wagmi';
import { apiDecompose } from '../lib/api';
import { useSigilStore } from '../stores/sigil';

export function useDecompose() {
  const { address } = useAccount();
  const { setIntentStep, setDecomposed, setIntentError } = useSigilStore();
  const [isLoading, setIsLoading] = useState(false);

  const decompose = useCallback(async (text: string) => {
    if (!text.trim()) return;
    setIsLoading(true);
    setIntentStep('loading');
    setIntentError(null);

    try {
      const result = await apiDecompose({
        userInput: text,
        userAddress: address ?? '0x0000000000000000000000000000000000000000',
      });

      if (!result.ok) throw new Error(result.error ?? 'Decomposition failed');

      setDecomposed({
        summary: result.summary,
        immediateSegments: result.immediateSegments.map((s) => ({
          type: s.type as 'SWAP' | 'DEPOSIT' | 'WITHDRAW' | 'HEDGE' | 'CUSTOM',
          protocol: s.protocol,
          description: s.description,
          from: s.from,
          to: s.to,
          amount: s.amount,
          status: 'pending',
        })),
        watchers: result.watchers.map((w) => ({
          watcherType: w.watcherType as 'PRICE' | 'TIME' | 'RISK' | 'GOVERNANCE',
          condition: w.condition,
          threshold: w.threshold,
          action: w.action,
        })),
        intentId: result.intentId,
      });
      setIntentStep('decomposed');
    } catch (err) {
      setIntentError(err instanceof Error ? err.message : 'Unknown error');
      setIntentStep('error');
    } finally {
      setIsLoading(false);
    }
  }, [address, setIntentStep, setDecomposed, setIntentError]);

  return { decompose, isLoading };
}
