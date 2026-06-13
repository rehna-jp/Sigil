'use client';

import { clsx } from 'clsx';

type DotColor = 'emerald' | 'amethyst' | 'ruby' | 'amber' | 'sapphire';

interface PulsingDotProps {
  color?: DotColor;
  size?: 'sm' | 'md' | 'lg';
  className?: string;
}

const colorClasses: Record<DotColor, string> = {
  emerald:  'bg-emerald-500',
  amethyst: 'bg-amethyst-500',
  ruby:     'bg-ruby-500',
  amber:    'bg-amber-400',
  sapphire: 'bg-sapphire-500',
};

const sizeClasses = {
  sm: 'w-1.5 h-1.5',
  md: 'w-2 h-2',
  lg: 'w-2.5 h-2.5',
};

export function PulsingDot({ color = 'emerald', size = 'md', className }: PulsingDotProps) {
  return (
    <span
      className={clsx(
        'rounded-full flex-shrink-0 animate-pulse-dot',
        colorClasses[color],
        sizeClasses[size],
        className,
      )}
      aria-hidden="true"
    />
  );
}
