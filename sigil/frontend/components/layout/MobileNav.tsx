'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { LayoutDashboard, Feather, Clock } from 'lucide-react';

const NAV_ITEMS = [
  {
    href: '/app',
    label: 'Dashboard',
    icon: LayoutDashboard,
  },
  {
    href: '/app/cast',
    label: 'Cast',
    icon: Feather,
  },
  {
    href: '/app/history',
    label: 'History',
    icon: Clock,
  },
] as const;

export function MobileNav() {
  const pathname = usePathname();

  return (
    <nav className="md:hidden fixed bottom-0 left-0 right-0 h-16 bg-sigil-primary/95 border-t border-white/[0.06] backdrop-blur-xl flex items-center justify-around px-4 z-40">
      {NAV_ITEMS.map(({ href, label, icon: Icon }) => {
        const isActive = href === '/app'
          ? pathname === '/app'
          : pathname.startsWith(href);

        return (
          <Link
            key={href}
            href={href}
            className={`flex flex-col items-center justify-center gap-1 w-16 py-1 transition-all duration-150 rounded-lg ${
              isActive
                ? 'text-amethyst-400 font-semibold'
                : 'text-text-secondary hover:text-text-primary'
            }`}
          >
            <Icon
              size={18}
              className={`transition-colors ${
                isActive ? 'text-amethyst-400' : 'text-text-tertiary'
              }`}
            />
            <span className="text-[10px] tracking-wide">{label}</span>
          </Link>
        );
      })}
    </nav>
  );
}
