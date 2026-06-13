'use client';

import { clsx } from 'clsx';

interface LoadingSkeletonProps {
  className?: string;
  lines?: number;
}

export function LoadingSkeleton({ className, lines = 1 }: LoadingSkeletonProps) {
  return (
    <div className={clsx('space-y-2', className)}>
      {Array.from({ length: lines }).map((_, i) => (
        <div
          key={i}
          className={clsx(
            'h-4 rounded skeleton',
            i === lines - 1 && lines > 1 ? 'w-2/3' : 'w-full',
          )}
        />
      ))}
    </div>
  );
}

export function CardSkeleton({ className }: { className?: string }) {
  return (
    <div className={clsx('rounded-xl border border-white/[0.06] bg-sigil-secondary p-4 space-y-3', className)}>
      <div className="flex items-center gap-3">
        <div className="w-8 h-8 rounded-full skeleton" />
        <div className="flex-1 space-y-1.5">
          <div className="h-3 w-1/3 rounded skeleton" />
          <div className="h-2 w-1/4 rounded skeleton" />
        </div>
      </div>
      <LoadingSkeleton lines={3} />
    </div>
  );
}
