'use client';

import { Zap, Eye, ChevronRight } from 'lucide-react';
import { DecomposedIntent } from '../../stores/sigil';
import { SegmentCard } from './SegmentCard';
import { WatcherConfigCard } from './WatcherConfigCard';

interface DecompositionViewProps {
  decomposed: DecomposedIntent;
  onConfirm: () => void;
  onReset: () => void;
  isConfirming?: boolean;
}

export function DecompositionView({ decomposed, onConfirm, onReset, isConfirming }: DecompositionViewProps) {
  return (
    <div className="space-y-6 animate-fade-up">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-base font-semibold text-text-primary">Intent Decomposed</h2>
          <p className="text-xs text-text-tertiary mt-0.5">Review the execution plan before casting</p>
        </div>
        <button
          onClick={onReset}
          className="text-xs text-text-tertiary hover:text-text-secondary transition-colors px-3 py-1.5 rounded-lg border border-white/[0.07] hover:border-white/20"
        >
          ← Edit
        </button>
      </div>

      {/* Summary */}
      <div className="p-4 rounded-xl border border-amethyst-500/15 bg-amethyst-900/10">
        <p className="text-sm text-text-secondary leading-relaxed">{decomposed.summary}</p>
      </div>

      {/* Immediate segments */}
      {decomposed.immediateSegments.length > 0 && (
        <section>
          <div className="flex items-center gap-2 mb-3">
            <Zap size={14} className="text-amethyst-400" />
            <h3 className="text-xs font-semibold text-text-secondary uppercase tracking-wider">
              Immediate Actions ({decomposed.immediateSegments.length})
            </h3>
          </div>
          <div className="space-y-3">
            {decomposed.immediateSegments.map((seg, i) => (
              <SegmentCard key={i} segment={seg} index={i} />
            ))}
          </div>
        </section>
      )}

      {/* Watchers */}
      {decomposed.watchers.length > 0 && (
        <section>
          <div className="flex items-center gap-2 mb-3">
            <Eye size={14} className="text-emerald-400" />
            <h3 className="text-xs font-semibold text-text-secondary uppercase tracking-wider">
              Persistent Watchers ({decomposed.watchers.length})
            </h3>
          </div>
          <div className="space-y-3">
            {decomposed.watchers.map((w, i) => (
              <WatcherConfigCard key={i} watcher={w} index={i} />
            ))}
          </div>
        </section>
      )}

      {/* Confirm CTA */}
      <div className="pt-2">
        <button
          id="confirm-cast-btn"
          onClick={onConfirm}
          disabled={isConfirming}
          className="
            w-full flex items-center justify-center gap-2.5 py-3.5 rounded-xl text-sm font-semibold text-white
            bg-gradient-to-r from-amethyst-700 to-amethyst-500
            hover:from-amethyst-600 hover:to-amethyst-400
            disabled:opacity-50 disabled:cursor-not-allowed
            transition-all duration-200 shadow-glow-amethyst
          "
        >
          {isConfirming ? (
            <>Processing…</>
          ) : (
            <>
              Confirm & Cast Sigil
              <ChevronRight size={16} />
            </>
          )}
        </button>
        <p className="text-center text-[11px] text-text-tertiary mt-2">
          This will submit a transaction on Arbitrum Sepolia
        </p>
      </div>
    </div>
  );
}
