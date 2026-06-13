'use client';

import { Zap, Eye, Bell, ShieldCheck } from 'lucide-react';

interface Stat {
  icon: React.ElementType;
  label: string;
  value: string | number;
  sub?: string;
  color: 'emerald' | 'amethyst' | 'amber' | 'sapphire';
}

const COLOR_MAP: Record<Stat['color'], { icon: string; bg: string; border: string; glow: string }> = {
  emerald:  { icon: 'text-emerald-400',  bg: 'bg-emerald-900/20',  border: 'border-emerald-500/20',  glow: 'shadow-glow-emerald' },
  amethyst: { icon: 'text-amethyst-400', bg: 'bg-amethyst-900/20', border: 'border-amethyst-500/20', glow: 'shadow-glow-amethyst' },
  amber:    { icon: 'text-amber-400',    bg: 'bg-amber-500/10',    border: 'border-amber-500/20',    glow: '' },
  sapphire: { icon: 'text-sapphire-400', bg: 'bg-sapphire-500/10', border: 'border-sapphire-400/20', glow: 'shadow-glow-sapphire' },
};

interface StatsBarProps {
  activeSigils: number;
  liveWatchers: number;
  triggersFired: number;
  protectedTVL?: string;
}

export function StatsBar({ activeSigils, liveWatchers, triggersFired, protectedTVL = '$0.00' }: StatsBarProps) {
  const stats: Stat[] = [
    { icon: Zap,         label: 'Active Sigils',   value: activeSigils,  color: 'amethyst' },
    { icon: Eye,         label: 'Live Watchers',   value: liveWatchers,  color: 'emerald'  },
    { icon: Bell,        label: 'Triggers Fired',  value: triggersFired, color: 'amber'    },
    { icon: ShieldCheck, label: 'Protected TVL',   value: protectedTVL,  color: 'sapphire' },
  ];

  return (
    <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-8">
      {stats.map(({ icon: Icon, label, value, color }) => {
        const c = COLOR_MAP[color];
        return (
          <div
            key={label}
            className={`flex items-center gap-4 px-5 py-4 rounded-xl border ${c.border} ${c.bg} transition-all duration-200 hover:border-opacity-50`}
          >
            <div className={`flex-shrink-0 w-10 h-10 rounded-lg ${c.bg} border ${c.border} flex items-center justify-center`}>
              <Icon size={18} className={c.icon} />
            </div>
            <div>
              <p className="text-2xl font-semibold text-text-primary leading-none">{value}</p>
              <p className="text-xs text-text-tertiary mt-1">{label}</p>
            </div>
          </div>
        );
      })}
    </div>
  );
}
