'use client';

import { useCallback, useState, useEffect } from 'react';
import { useAccount, useWriteContract, useWaitForTransactionReceipt } from 'wagmi';
import { encodeAbiParameters, parseAbiParameters, parseEther, parseUnits } from 'viem';
import { CheckCircle2, Loader2, AlertCircle, ExternalLink } from 'lucide-react';
import { CONTRACTS, getArbiscanTx, RPC_URL } from '../../lib/constants';
import { IntentDecomposerABI } from '../../lib/contracts';
import { DecomposedIntent, ActiveIntent, useSigilStore } from '../../stores/sigil';

interface ConfirmIntentProps {
  decomposed: DecomposedIntent;
  onSuccess: () => void;
  onCancel: () => void;
}

type Step = 'idle' | 'submitting' | 'confirming' | 'done' | 'error';

// Map segment type string → uint8 enum value
const SEG_TYPE: Record<string, number> = { SWAP: 0, DEPOSIT: 1, WITHDRAW: 2, HEDGE: 3, CUSTOM: 4 };
// Map watcher type string → uint8 enum value
const WATCHER_TYPE: Record<string, number> = { PRICE: 0, TIME: 1, RISK: 2, GOVERNANCE: 3 };

const WETH_ADDR = CONTRACTS.arbitrumSepolia.WETH;
const USDC_ADDR = CONTRACTS.arbitrumSepolia.USDC;
const UNISWAP_ADAPTER = CONTRACTS.arbitrumSepolia.UniswapV3Adapter;
const AAVE_ADAPTER = CONTRACTS.arbitrumSepolia.AaveV3Adapter;
const ETH_USD_FEED = CONTRACTS.arbitrumSepolia.MockPriceFeed;

function parseToken(symbol?: string) {
  if (!symbol) return WETH_ADDR;
  const norm = symbol.toUpperCase();
  if (norm === 'USDC') return USDC_ADDR;
  return WETH_ADDR;
}

function parseAmount(amtStr?: string, symbol?: string) {
  if (!amtStr) return 0n;
  const cleanAmt = amtStr.replace(/[^0-9.]/g, '');
  if (!cleanAmt) return 0n;
  const norm = symbol?.toUpperCase();
  if (norm === 'USDC') {
    return parseUnits(cleanAmt, 6);
  }
  return parseEther(cleanAmt);
}

function encodeSegment(s: { type: string; from?: string; to?: string; amount?: string }) {
  const segmentType = SEG_TYPE[s.type] ?? 4;
  let targetProtocol = '0x0000000000000000000000000000000000000000' as `0x${string}`;
  let callData = '0x' as `0x${string}`;
  let value = 0n;
  let minGasLimit = 300000n;

  if (s.type === 'SWAP') {
    targetProtocol = UNISWAP_ADAPTER;
    const tokenIn = parseToken(s.from);
    const tokenOut = parseToken(s.to);
    const amountIn = parseAmount(s.amount, s.from);
    callData = encodeAbiParameters(
      parseAbiParameters('address tokenIn, address tokenOut, uint24 fee, uint256 amountIn, uint256 minAmountOut'),
      [tokenIn, tokenOut, 3000, amountIn, 0n]
    );
  } else if (s.type === 'DEPOSIT' || s.type === 'WITHDRAW') {
    targetProtocol = AAVE_ADAPTER;
    const operation = s.type === 'DEPOSIT' ? 0 : 1; // 0=SUPPLY, 1=WITHDRAW
    const token = parseToken(s.from || s.to);
    const amount = parseAmount(s.amount, s.from || s.to);
    callData = encodeAbiParameters(
      parseAbiParameters('uint8 operation, address asset, uint256 amount'),
      [operation, token, amount]
    );
  }

  return {
    segmentType,
    targetProtocol,
    callData,
    value,
    minGasLimit,
  };
}

export function ConfirmIntent({ decomposed, onSuccess, onCancel }: ConfirmIntentProps) {
  const { address, isConnected, chain } = useAccount();
  const { addIntent, setIntentStep } = useSigilStore();
  const [step, setStep] = useState<Step>('idle');
  const [errorMsg, setErrorMsg] = useState<string | null>(null);
  const [simMode, setSimMode] = useState(false);

  const { writeContractAsync } = useWriteContract();
  const [txHash, setTxHash] = useState<`0x${string}` | undefined>();

  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
    hash: txHash,
  });

  const finalize = useCallback((hash?: `0x${string}`) => {
    const now = Date.now();
    const newIntent: ActiveIntent = {
      id: hash ?? `local-${now}`,
      summary: decomposed.summary,
      status: 'ACTIVE',
      segments: decomposed.immediateSegments.map((s) => ({
        ...s,
        status: 'done' as const,
        txHash: hash,
      })),
      watchers: decomposed.watchers.map((w, i) => ({
        id: hash ? `${hash}-w${i}` : `local-${now}-w${i}`,
        watcherType: w.watcherType,
        status: 'ACTIVE' as const,
        condition: w.condition,
        threshold: w.threshold,
        action: w.action,
        createdAt: now,
        expiresAt: w.expiresAt,
        intentSummary: decomposed.summary,
      })),
      createdAt: now,
      txHash: hash,
    };
    addIntent(newIntent);
    setIntentStep('done');
    setTimeout(onSuccess, 1500);
  }, [decomposed, addIntent, setIntentStep, onSuccess]);

  useEffect(() => {
    if (isSuccess && txHash) {
      setStep('done');
      finalize(txHash);
    }
  }, [isSuccess, txHash, finalize]);

  const handleSubmit = useCallback(async () => {
    setErrorMsg(null);

    // If wallet not connected or wrong chain — use simulation mode
    if (!isConnected || !address || chain?.id !== 421614) {
      setSimMode(true);
      setStep('confirming');
      await new Promise((r) => setTimeout(r, 2000));
      setStep('done');
      finalize();
      return;
    }

    try {
      setStep('submitting');

      const expiresAt = BigInt(Math.floor(Date.now() / 1000) + 30 * 24 * 60 * 60); // 30 days

      // Encode segments
      const segments = decomposed.immediateSegments.map(encodeSegment);

      // Encode watchers
      const watchers = decomposed.watchers.map((w) => {
        let parameters = '0x' as `0x${string}`;
        if (w.watcherType === 'PRICE') {
          const thresholdVal = BigInt(w.threshold ?? 3500) * 10n ** 8n;
          const comparison = w.condition.includes('>') || w.condition.includes('above') ? 0 : 1;
          parameters = encodeAbiParameters(
            parseAbiParameters('address priceFeed, int256 threshold, uint8 comparison, uint8 decimals'),
            [ETH_USD_FEED, thresholdVal, comparison, 8]
          );
        } else if (w.watcherType === 'TIME') {
          let interval = 24n * 3600n;
          const lowerCond = w.condition.toLowerCase();
          if (lowerCond.includes('30 days')) {
            interval = 30n * 24n * 3600n;
          } else if (lowerCond.includes('day')) {
            const match = lowerCond.match(/(\d+)\s*day/);
            if (match) interval = BigInt(match[1]) * 24n * 3600n;
          } else if (lowerCond.includes('hour')) {
            const match = lowerCond.match(/(\d+)\s*hour/);
            if (match) {
              interval = BigInt(match[1]) * 3600n;
            } else {
              interval = 3600n;
            }
          }
          const nextTrigger = BigInt(Math.floor(Date.now() / 1000)) + interval;
          parameters = encodeAbiParameters(
            parseAbiParameters('uint256 interval, uint256 nextTrigger, uint256 maxTriggers, uint256 triggerCount'),
            [interval, nextTrigger, 0n, 0n]
          );
        }

        // Build triggerAction (rebalance/exit segments)
        const exitSegments: any[] = [];
        const actionText = w.action.toLowerCase();
        const isAaveExit = actionText.includes('withdraw') || decomposed.immediateSegments.some(s => s.type === 'DEPOSIT');

        if (isAaveExit) {
          const depSeg = decomposed.immediateSegments.find(s => s.type === 'DEPOSIT');
          const tokenSymbol = depSeg?.from || 'ETH';
          const amount = depSeg?.amount || '0.5';
          exitSegments.push({
            type: 'WITHDRAW',
            from: tokenSymbol,
            to: tokenSymbol,
            amount: amount,
          });
          exitSegments.push({
            type: 'SWAP',
            from: tokenSymbol,
            to: 'USDC',
            amount: amount,
          });
        } else {
          const swapSeg = decomposed.immediateSegments.find(s => s.type === 'SWAP');
          const tokenSymbol = swapSeg?.from || 'ETH';
          const amount = swapSeg?.amount || '0.5';
          exitSegments.push({
            type: 'SWAP',
            from: tokenSymbol,
            to: 'USDC',
            amount: amount,
          });
        }

        const encodedExitSegments = exitSegments.map(encodeSegment);
        const triggerAction = encodeAbiParameters(
          parseAbiParameters('(uint8, address, bytes, uint256, uint256)[]'),
          [
            encodedExitSegments.map(s => [
              s.segmentType,
              s.targetProtocol,
              s.callData,
              s.value,
              s.minGasLimit
            ] as [number, `0x${string}`, `0x${string}`, bigint, bigint])
          ]
        );

        return {
          watcherType: WATCHER_TYPE[w.watcherType] ?? 0,
          parameters,
          triggerAction,
          expiresAt,
        };
      });

      const hash = await writeContractAsync({
        address: CONTRACTS.arbitrumSepolia.IntentDecomposer,
        abi: IntentDecomposerABI,
        functionName: 'submitDecomposition',
        args: [address, segments, watchers, expiresAt],
      });

      setTxHash(hash);
      setStep('confirming');
    } catch (err) {
      console.error(err);
      let msg = err instanceof Error ? err.message : 'Transaction failed';
      if (msg.includes('not authorized') || msg.includes('0x82b42900')) {
        msg = `Not authorized submitter. Sigil's IntentDecomposer restricts intent submission to authorized AI agents. To authorize your connected wallet, run the following CLI command using Foundry:
        
        cast send ${CONTRACTS.arbitrumSepolia.IntentDecomposer} "addAuthorizedSubmitter(address)" ${address} --rpc-url ${RPC_URL} --private-key <DEPLOYER_PRIVATE_KEY>`;
      }
      setErrorMsg(msg);
      setStep('error');
    }
  }, [address, isConnected, chain, decomposed, writeContractAsync, finalize]);

  if (step === 'done') {
    return (
      <div className="flex flex-col items-center justify-center py-12 animate-fade-up text-center">
        <div className="w-16 h-16 rounded-full border border-emerald-500/30 bg-emerald-900/20 flex items-center justify-center mb-4">
          <CheckCircle2 size={28} className="text-emerald-400" />
        </div>
        <h3 className="text-lg font-semibold text-text-primary mb-2">Sigil Cast!</h3>
        <p className="text-sm text-text-secondary mb-4 max-w-xs">
          Your intent is now live on Arbitrum Sepolia.
          {simMode && ' (Simulation mode — wallet not connected)'}
        </p>
        {txHash && (
          <a
            href={getArbiscanTx(txHash)}
            target="_blank"
            rel="noopener noreferrer"
            className="flex items-center gap-1.5 text-xs text-amethyst-400 hover:text-amethyst-300 transition-colors"
          >
            <ExternalLink size={12} />
            View on Arbiscan
          </a>
        )}
      </div>
    );
  }

  return (
    <div className="space-y-6 animate-fade-up">
      <div>
        <h3 className="text-base font-semibold text-text-primary">Confirm Broadcast</h3>
        <p className="text-xs text-text-tertiary mt-1">
          {isConnected && chain?.id === 421614
            ? 'Submit the intent to the IntentDecomposer contract on Arbitrum Sepolia'
            : 'Wallet not connected — will simulate submission locally'
          }
        </p>
      </div>

      {/* Summary */}
      <div className="p-4 rounded-xl border border-white/[0.07] bg-sigil-secondary space-y-2.5">
        <div className="flex justify-between text-xs">
          <span className="text-text-tertiary">Segments</span>
          <span className="text-text-primary">{decomposed.immediateSegments.length}</span>
        </div>
        <div className="flex justify-between text-xs">
          <span className="text-text-tertiary">Watchers</span>
          <span className="text-text-primary">{decomposed.watchers.length}</span>
        </div>
        <div className="flex justify-between text-xs">
          <span className="text-text-tertiary">Network</span>
          <span className="text-amethyst-400">Arbitrum Sepolia</span>
        </div>
        <div className="flex justify-between text-xs">
          <span className="text-text-tertiary">Expiry</span>
          <span className="text-text-primary">30 days</span>
        </div>
      </div>

      {/* Error */}
      {step === 'error' && errorMsg && (
        <div className="flex items-start gap-2 p-3 rounded-xl border border-ruby-500/20 bg-ruby-900/20">
          <AlertCircle size={14} className="text-ruby-400 flex-shrink-0 mt-0.5" />
          <p className="text-xs text-ruby-400">{errorMsg}</p>
        </div>
      )}

      {/* Actions */}
      <div className="flex gap-3">
        <button
          onClick={onCancel}
          disabled={step === 'submitting' || step === 'confirming'}
          className="flex-1 py-3 rounded-xl text-sm font-medium border border-white/10 text-text-secondary hover:border-white/20 hover:text-text-primary transition-all disabled:opacity-40"
        >
          Cancel
        </button>
        <button
          id="confirm-broadcast-btn"
          onClick={handleSubmit}
          disabled={step === 'submitting' || step === 'confirming'}
          className="flex-1 flex items-center justify-center gap-2 py-3 rounded-xl text-sm font-semibold text-white
            bg-gradient-to-r from-amethyst-700 to-amethyst-500
            hover:from-amethyst-600 hover:to-amethyst-400
            disabled:opacity-50 disabled:cursor-not-allowed
            transition-all duration-200 shadow-glow-amethyst"
        >
          {step === 'submitting' || step === 'confirming' ? (
            <><Loader2 size={14} className="animate-spin" />
              {step === 'submitting' ? 'Submitting…' : 'Confirming…'}
            </>
          ) : (
            'Broadcast'
          )}
        </button>
      </div>
    </div>
  );
}
