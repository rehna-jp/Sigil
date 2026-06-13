'use client';

import { ConnectButton } from '@rainbow-me/rainbowkit';
import { useChainId } from 'wagmi';
import { arbitrumSepolia } from 'wagmi/chains';
import { SigilLogo } from './SigilLogo';
import { useWSContext } from '../providers/WebSocketProvider';
import Link from 'next/link';

export function Navbar() {
  const chainId = useChainId();
  const { isConnected, isSimulating } = useWSContext();
  const isWrongNetwork = chainId !== arbitrumSepolia.id;

  return (
    <nav className="h-14 flex items-center justify-between px-6 border-b border-white/[0.06] bg-sigil-primary/80 backdrop-blur-xl sticky top-0 z-50">
      {/* Logo */}
      <Link href="/" className="flex items-center gap-2.5 group">
        <SigilLogo size={28} />
        <span className="font-display text-lg text-text-primary tracking-wide group-hover:text-amethyst-300 transition-colors">
          Sigil
        </span>
      </Link>

      {/* Right side */}
      <div className="flex items-center gap-3">
        {/* WS status */}
        <div className="hidden sm:flex items-center gap-1.5 text-xs text-text-tertiary">
          <span
            className={`w-1.5 h-1.5 rounded-full ${
              isConnected
                ? 'bg-emerald-500 animate-pulse-dot'
                : isSimulating
                ? 'bg-amber-400 animate-pulse-dot'
                : 'bg-text-tertiary'
            }`}
          />
          <span>
            {isConnected ? 'Live' : isSimulating ? 'Simulating' : 'Offline'}
          </span>
        </div>

        {/* Wrong network warning */}
        {isWrongNetwork && (
          <div className="hidden sm:flex items-center gap-1.5 px-2.5 py-1 rounded-full bg-ruby-900/40 border border-ruby-500/30 text-ruby-400 text-xs font-medium">
            <span>⚠</span>
            <span>Switch to Arbitrum Sepolia</span>
          </div>
        )}

        {/* Connect button */}
        <ConnectButton
          accountStatus="avatar"
          chainStatus="icon"
          showBalance={false}
        />
      </div>
    </nav>
  );
}
