'use client';

import { Eye, Clock, TrendingDown, AlertTriangle } from 'lucide-react';
import { WatcherConfig } from '../../stores/sigil';

const TYPE_META: Record<string, { icon: React.ElementType; color: string; border: string; bg: string; label: string }> = {
  PRICE:      { icon: TrendingDown, color: 'text-ruby-400',    border: 'border-ruby-500/20',    bg: 'bg-ruby-900/20',    label: 'Price Alert' },
  TIME:       { icon: Clock,        color: 'text-sapphire-400', border: 'border-sapphire-400/20', bg: 'bg-sapphire-500/10', label: 'Time Trigger' },
  RISK:       { icon: AlertTriangle, color: 'text-amber-400',   border: 'border-amber-500/20',   bg: 'bg-amber-500/10',   label: 'Risk Monitor' },
  GOVERNANCE: { icon: Eye,          color: 'text-amethyst-400', border: 'border-amethyst-500/20', bg: 'bg-amethyst-900/20', label: 'Governance Watch' },
};

interface WatcherConfigCardProps {
  watcher: WatcherConfig;
  index: number;
}

export function WatcherConfigCard({ watcher, index }: WatcherConfigCardProps) {
  const meta = TYPE_META[watcher.watcherType] ?? TYPE_META.PRICE;
  const Icon = meta.icon;

  return (
    <div className={`rounded-xl border p-4 ${meta.bg} ${meta.border} transition-all`}>
      {/* Header */}
      <div className="flex items-center gap-3 mb-3">
        <div className={`w-8 h-8 rounded-lg ${meta.bg} border ${meta.border} flex items-center justify-center flex-shrink-0`}>
          <Icon size={14} className={meta.color} />
        </div>
        <div>
          <p className="text-sm font-medium text-text-primary">{meta.label}</p>
          <p className="text-[11px] text-text-tertiary">Watcher #{index + 1}</p>
        </div>
      </div>

      {/* Condition */}
      <div className="space-y-2">
        <div className="flex items-center justify-between">
          <span className="text-[11px] text-text-tertiary uppercase tracking-wide">Condition</span>
          <span className={`text-xs font-mono font-medium ${meta.color}`}>{watcher.condition}</span>
        </div>
        {watcher.threshold && (
          <div className="flex items-center justify-between">
            <span className="text-[11px] text-text-tertiary uppercase tracking-wide">Threshold</span>
            <span className="text-xs font-mono text-text-primary">${watcher.threshold.toLocaleString()}</span>
          </div>
        )}
        <div className="flex items-start justify-between gap-2 pt-1 border-t border-white/[0.05]">
          <span className="text-[11px] text-text-tertiary uppercase tracking-wide">Action</span>
          <span className="text-xs text-text-primary text-right max-w-[65%]">{watcher.action}</span>
        </div>
      </div>

      {/* Infinite loop indicator */}
      <div className={`flex items-center gap-1.5 mt-3 text-[10px] ${meta.color} opacity-70`}>
        <span>⟳</span>
        <span>Persists until triggered or expired</span>
      </div>
    </div>
  );
}
