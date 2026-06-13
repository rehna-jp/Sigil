'use client';

import Link from 'next/link';
import { ArrowRight, Layers } from 'lucide-react';
import { SigilLogo } from '../components/layout/SigilLogo';

export default function LandingPage() {
  return (
    <main className="relative min-h-screen bg-sigil-abyss flex flex-col items-center justify-center overflow-hidden">

      {/* Background radial glows */}
      <div className="pointer-events-none absolute inset-0">
        <div
          className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-[600px] h-[600px] rounded-full"
          style={{ background: 'radial-gradient(ellipse at center, rgba(124,92,191,0.12) 0%, transparent 70%)' }}
        />
        <div
          className="absolute top-1/3 left-1/2 -translate-x-1/2 w-[400px] h-[400px] rounded-full"
          style={{ background: 'radial-gradient(ellipse at center, rgba(16,185,129,0.07) 0%, transparent 70%)' }}
        />
      </div>

      {/* Grid overlay */}
      <div
        className="pointer-events-none absolute inset-0 opacity-[0.03]"
        style={{
          backgroundImage: 'linear-gradient(rgba(255,255,255,0.5) 1px, transparent 1px), linear-gradient(90deg, rgba(255,255,255,0.5) 1px, transparent 1px)',
          backgroundSize: '48px 48px',
        }}
      />

      {/* Hero content */}
      <div className="relative z-10 flex flex-col items-center text-center px-6 animate-fade-up">

        {/* Rotating logo */}
        <div className="mb-8">
          <SigilLogo size={80} animate />
        </div>

        {/* Headline */}
        <h1 className="font-display text-7xl md:text-8xl mb-4 leading-none">
          <span className="gradient-amethyst-emerald">Sigil</span>
        </h1>

        {/* Subheadline */}
        <p className="text-text-secondary text-lg md:text-xl max-w-xl mb-10 leading-relaxed font-sans">
          Inscribe your financial intent once.{' '}
          <span className="text-text-primary">It watches, reacts, and protects</span>{' '}
          — autonomously.
        </p>

        {/* CTA buttons */}
        <div className="flex flex-col sm:flex-row items-center gap-4">
          <Link
            href="/app"
            id="launch-app-btn"
            className="group flex items-center gap-2.5 px-7 py-3.5 rounded-xl text-white font-medium text-sm
              bg-gradient-to-r from-amethyst-700 to-amethyst-500 
              hover:from-amethyst-600 hover:to-amethyst-400
              shadow-glow-amethyst hover:shadow-[0_0_36px_rgba(124,92,191,0.45)]
              transition-all duration-200"
          >
            Launch App
            <ArrowRight size={16} className="group-hover:translate-x-0.5 transition-transform" />
          </Link>
          <a
            href="https://github.com/rehna-jp/Sigil"
            target="_blank"
            rel="noopener noreferrer"
            className="flex items-center gap-2 px-6 py-3 rounded-xl text-text-secondary text-sm border border-white/10 hover:border-white/20 hover:text-text-primary transition-all duration-200"
          >
            View Source
          </a>
        </div>

        {/* Feature pills */}
        <div className="flex flex-wrap justify-center gap-2 mt-12">
          {[
            { icon: '🧠', label: 'AI Decomposition' },
            { icon: '👁️', label: 'Persistent Watchers' },
            { icon: '⚡', label: 'Auto-Execution' },
            { icon: '🔁', label: 'Intent Loops' },
          ].map(({ icon, label }) => (
            <div
              key={label}
              className="flex items-center gap-1.5 px-3 py-1.5 rounded-full border border-white/[0.08] bg-sigil-secondary/50 text-text-secondary text-xs"
            >
              <span>{icon}</span>
              <span>{label}</span>
            </div>
          ))}
        </div>
      </div>

      {/* Arbitrum badge */}
      <div className="absolute bottom-8 flex items-center gap-2 text-text-tertiary text-xs">
        <Layers size={12} className="text-sapphire-400" />
        <span>Built on Arbitrum Sepolia</span>
      </div>
    </main>
  );
}
