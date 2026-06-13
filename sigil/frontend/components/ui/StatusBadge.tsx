'use client';

import { clsx } from 'clsx';

type BadgeStatus = 'active' | 'triggered' | 'pending' | 'executing' | 'completed' | 'cancelled' | 'expired';

interface StatusBadgeProps {
  status: BadgeStatus | Uppercase<BadgeStatus> | string;
  className?: string;
}

const STATUS_CONFIG: Record<BadgeStatus, { label: string; className: string }> = {
  active:    { label: 'Active',     className: 'bg-emerald-900/40 text-emerald-400 border-emerald-500/25' },
  triggered: { label: 'Triggered',  className: 'bg-ruby-900/40 text-ruby-400 border-ruby-500/25' },
  pending:   { label: 'Pending',    className: 'bg-amber-500/10 text-amber-400 border-amber-500/25' },
  executing: { label: 'Executing',  className: 'bg-sapphire-500/10 text-sapphire-400 border-sapphire-500/25' },
  completed: { label: 'Completed',  className: 'bg-emerald-900/30 text-emerald-300 border-emerald-500/20' },
  cancelled: { label: 'Cancelled',  className: 'bg-sigil-tertiary text-text-tertiary border-white/10' },
  expired:   { label: 'Expired',    className: 'bg-sigil-tertiary text-text-tertiary border-white/10' },
};

export function StatusBadge({ status, className }: StatusBadgeProps) {
  const normalizedStatus = status.toLowerCase() as BadgeStatus;
  const config = STATUS_CONFIG[normalizedStatus] || STATUS_CONFIG.active;
  return (
    <span
      className={clsx(
        'inline-flex items-center px-2 py-0.5 rounded-full text-[11px] font-medium border',
        config.className,
        className,
      )}
    >
      {config.label}
    </span>
  );
}
