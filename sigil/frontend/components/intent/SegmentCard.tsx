'use client';

import { ArrowRight, RefreshCw } from 'lucide-react';
import { Segment } from '../../stores/sigil';

const TYPE_COLORS: Record<string, { bg: string; border: string; text: string; icon: string }> = {
  SWAP:     { bg: 'bg-sapphire-500/10', border: 'border-sapphire-400/20', text: 'text-sapphire-400', icon: '⇄' },
  DEPOSIT:  { bg: 'bg-emerald-900/20',  border: 'border-emerald-500/20',  text: 'text-emerald-400',  icon: '↓' },
  WITHDRAW: { bg: 'bg-amber-500/10',    border: 'border-amber-500/20',    text: 'text-amber-400',    icon: '↑' },
  HEDGE:    { bg: 'bg-amethyst-900/20', border: 'border-amethyst-500/20', text: 'text-amethyst-400', icon: '△' },
  CUSTOM:   { bg: 'bg-sigil-tertiary',  border: 'border-white/10',        text: 'text-text-secondary', icon: '◆' },
};

interface SegmentCardProps {
  segment: Segment;
  index: number;
}

export function SegmentCard({ segment, index }: SegmentCardProps) {
  const c = TYPE_COLORS[segment.type] ?? TYPE_COLORS.CUSTOM;

  return (
    <div className={`relative rounded-xl border p-4 ${c.bg} ${c.border} transition-all`}>
      {/* Step number */}
      <div className="flex items-center gap-3 mb-3">
        <div className={`w-7 h-7 rounded-full border ${c.border} flex items-center justify-center text-xs font-bold ${c.text}`}>
          {index + 1}
        </div>
        <div className="flex items-center gap-2">
          <span className={`text-xs font-semibold uppercase tracking-wider px-2 py-0.5 rounded-full border ${c.border} ${c.text} ${c.bg}`}>
            {c.icon} {segment.type}
          </span>
          {segment.protocol && (
            <span className="text-xs text-text-tertiary">via {segment.protocol}</span>
          )}
        </div>
      </div>

      {/* Description */}
      <p className="text-sm text-text-primary">{segment.description}</p>

      {/* Token flow */}
      {(segment.from || segment.to) && (
        <div className="flex items-center gap-2 mt-3">
          {segment.from && (
            <span className="text-xs px-2.5 py-1 rounded-lg bg-sigil-tertiary border border-white/10 text-text-secondary font-mono">
              {segment.from}
            </span>
          )}
          {segment.from && segment.to && <ArrowRight size={12} className="text-text-tertiary" />}
          {segment.to && (
            <span className={`text-xs px-2.5 py-1 rounded-lg border font-mono ${c.bg} ${c.border} ${c.text}`}>
              {segment.to}
            </span>
          )}
          {segment.amount && (
            <span className="ml-auto text-xs text-text-tertiary font-mono">{segment.amount}</span>
          )}
        </div>
      )}

      {/* Status */}
      {segment.status === 'executing' && (
        <div className="flex items-center gap-1.5 mt-3 text-xs text-amethyst-400">
          <RefreshCw size={10} className="animate-spin" />
          Executing…
        </div>
      )}
    </div>
  );
}
