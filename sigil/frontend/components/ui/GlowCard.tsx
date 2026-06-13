'use client';

import { ReactNode } from 'react';
import { clsx } from 'clsx';

type GlowVariant = 'emerald' | 'amethyst' | 'ruby' | 'sapphire' | 'none';

interface GlowCardProps {
  children: ReactNode;
  variant?: GlowVariant;
  className?: string;
  onClick?: () => void;
  id?: string;
}

const variantClasses: Record<GlowVariant, string> = {
  emerald:  'border-emerald-500/20 hover:glow-emerald hover:border-emerald-500/30',
  amethyst: 'border-amethyst-500/20 hover:glow-amethyst hover:border-amethyst-500/30',
  ruby:     'border-ruby-500/20 hover:glow-ruby hover:border-ruby-500/30',
  sapphire: 'border-sapphire-500/20 hover:glow-sapphire hover:border-sapphire-500/30',
  none:     'border-white/[0.08]',
};

export function GlowCard({ children, variant = 'none', className, onClick, id }: GlowCardProps) {
  return (
    <div
      id={id}
      onClick={onClick}
      className={clsx(
        'rounded-xl border bg-sigil-secondary transition-all duration-300',
        variantClasses[variant],
        onClick && 'cursor-pointer',
        className,
      )}
    >
      {children}
    </div>
  );
}
