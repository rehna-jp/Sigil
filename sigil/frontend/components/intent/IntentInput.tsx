'use client';

import { useRef, KeyboardEvent } from 'react';
import { Send, Loader2 } from 'lucide-react';

interface IntentInputProps {
  value: string;
  onChange: (v: string) => void;
  onSubmit: () => void;
  isLoading?: boolean;
  placeholder?: string;
}

export function IntentInput({ value, onChange, onSubmit, isLoading, placeholder }: IntentInputProps) {
  const ref = useRef<HTMLTextAreaElement>(null);

  const handleKey = (e: KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) {
      e.preventDefault();
      onSubmit();
    }
  };

  return (
    <div
      className={`
        relative rounded-2xl border transition-all duration-300 overflow-hidden
        ${isLoading
          ? 'border-amethyst-500/60 shadow-glow-amethyst animate-glow-border'
          : 'border-white/10 hover:border-amethyst-500/30 focus-within:border-amethyst-500/50 focus-within:shadow-glow-amethyst'
        }
        bg-sigil-secondary
      `}
    >
      <textarea
        ref={ref}
        id="intent-input"
        value={value}
        onChange={(e) => onChange(e.target.value)}
        onKeyDown={handleKey}
        placeholder={placeholder ?? 'Describe your intent in plain English…\n\nExample: "Put 0.5 ETH into Aave for yield. Exit to USDC if ETH drops below $3,500."'}
        disabled={isLoading}
        rows={5}
        className="
          w-full px-5 py-4 bg-transparent text-text-primary text-sm leading-relaxed
          placeholder:text-text-tertiary resize-none outline-none
          disabled:opacity-60 scrollbar-thin
        "
      />
      <div className="flex items-center justify-between px-4 py-3 border-t border-white/[0.05]">
        <p className="text-[11px] text-text-tertiary">
          <kbd className="font-mono bg-sigil-tertiary px-1.5 py-0.5 rounded text-[10px] border border-white/10">⌘ Enter</kbd>
          {' '} to cast
        </p>
        <button
          id="cast-intent-btn"
          onClick={onSubmit}
          disabled={!value.trim() || isLoading}
          className="
            flex items-center gap-2 px-4 py-2 rounded-xl text-sm font-medium text-white
            bg-gradient-to-r from-amethyst-700 to-amethyst-500
            hover:from-amethyst-600 hover:to-amethyst-400
            disabled:opacity-40 disabled:cursor-not-allowed
            transition-all duration-200 shadow-glow-amethyst
          "
        >
          {isLoading ? (
            <><Loader2 size={14} className="animate-spin" /> Analyzing…</>
          ) : (
            <><Send size={14} /> Cast Sigil</>
          )}
        </button>
      </div>
    </div>
  );
}
