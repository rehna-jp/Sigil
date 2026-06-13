'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { LayoutDashboard, Feather, Clock, Zap } from 'lucide-react';
import { SigilLogo } from './SigilLogo';
import { useEthPrice } from '../../hooks/useEthPrice';

const NAV_ITEMS = [
  {
    href: '/app',
    label: 'Dashboard',
    icon: LayoutDashboard,
    description: 'Active sigils & watchers',
    highlight: false,
  },
  {
    href: '/app/cast',
    label: 'Cast a Sigil',
    icon: Feather,
    description: 'Inscribe a new intent',
    highlight: true,
  },
  {
    href: '/app/history',
    label: 'History',
    icon: Clock,
    description: 'Trigger audit trail',
    highlight: false,
  },
] as const;

export function Sidebar() {
  const pathname = usePathname();
  const ethPrice = useEthPrice();

  return (
    <aside className="w-56 hidden md:flex flex-col h-full bg-sigil-primary border-r border-white/[0.06]">
      {/* Brand */}
      <div className="flex items-center gap-2.5 px-5 py-5 border-b border-white/[0.06]">
        <SigilLogo size={32} />
        <div>
          <p className="font-display text-base text-text-primary leading-none">Sigil</p>
          <p className="text-[10px] text-text-tertiary mt-0.5">Persistent Intent Engine</p>
        </div>
      </div>

      {/* Nav items */}
      <nav className="flex-1 px-3 py-4 space-y-1" aria-label="Main navigation">
        {NAV_ITEMS.map(({ href, label, icon: Icon, description, highlight }) => {
          const isActive = href === '/app'
            ? pathname === '/app'
            : pathname.startsWith(href);

          return (
            <Link
              key={href}
              href={href}
              id={`nav-${label.toLowerCase().replace(/\s+/g, '-')}`}
              className={`
                flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm transition-all duration-150 group
                ${isActive
                  ? 'bg-amethyst-900/50 text-amethyst-300 border border-amethyst-500/20'
                  : 'text-text-secondary hover:text-text-primary hover:bg-sigil-hover'
                }
                ${highlight && !isActive
                  ? 'border border-amethyst-500/10'
                  : ''
                }
              `}
            >
              <Icon
                size={16}
                className={`flex-shrink-0 transition-colors ${
                  isActive ? 'text-amethyst-400' : 'text-text-tertiary group-hover:text-text-secondary'
                }`}
              />
              <div className="min-w-0">
                <p className="font-medium truncate">{label}</p>
                <p className="text-[10px] text-text-tertiary truncate">{description}</p>
              </div>
            </Link>
          );
        })}
      </nav>

      {/* Footer */}
      <div className="px-5 py-4 border-t border-white/[0.06] space-y-2">
        {ethPrice !== null && (
          <div className="flex items-center justify-between text-xs text-text-secondary">
            <span>ETH/USD</span>
            <span className="font-mono font-medium text-emerald-400">
              ${ethPrice.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}
            </span>
          </div>
        )}
        <div className="flex items-center gap-2 text-xs text-text-tertiary">
          <Zap size={12} className="text-amethyst-500" />
          <span>Arbitrum Sepolia</span>
        </div>
      </div>
    </aside>
  );
}
