'use client';

import Link from 'next/link';
import { Plus } from 'lucide-react';
import { SigilCard } from './SigilCard';
import { LoadingSkeleton } from '../ui/LoadingSkeleton';
import { ActiveIntent } from '../../stores/sigil';

interface ActiveSigilsProps {
  intents: ActiveIntent[];
  isLoading?: boolean;
  onCancelWatcher?: (id: string) => void;
}

export function ActiveSigils({ intents, isLoading, onCancelWatcher }: ActiveSigilsProps) {
  if (isLoading) {
    return (
      <div className="space-y-4">
        {[1, 2].map((i) => <LoadingSkeleton key={i} className="h-32 rounded-xl" />)}
      </div>
    );
  }

  if (intents.length === 0) {
    return (
      <div className="flex flex-col items-center justify-center py-20 text-center">
        <div className="w-16 h-16 rounded-2xl border border-white/[0.07] bg-sigil-secondary flex items-center justify-center mb-4">
          <span className="text-2xl">⬡</span>
        </div>
        <p className="text-text-secondary font-medium mb-1">No active sigils</p>
        <p className="text-text-tertiary text-sm mb-6">Cast your first intent to get started</p>
        <Link
          href="/app/cast"
          id="cast-first-sigil-btn"
          className="flex items-center gap-2 px-5 py-2.5 rounded-xl text-sm font-medium text-white
            bg-gradient-to-r from-amethyst-700 to-amethyst-500 hover:from-amethyst-600 hover:to-amethyst-400
            transition-all duration-200 shadow-glow-amethyst"
        >
          <Plus size={14} />
          Cast a Sigil
        </Link>
      </div>
    );
  }

  return (
    <div className="space-y-4">
      {intents.map((intent) => (
        <SigilCard
          key={intent.id}
          intent={intent}
          onCancelWatcher={onCancelWatcher}
        />
      ))}
    </div>
  );
}
