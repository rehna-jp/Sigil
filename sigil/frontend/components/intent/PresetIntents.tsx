'use client';

import { PRESET_INTENTS } from '../../lib/constants';

interface PresetIntentsProps {
  onSelect: (text: string) => void;
}

export function PresetIntents({ onSelect }: PresetIntentsProps) {
  return (
    <div className="space-y-2">
      <p className="text-xs text-text-tertiary uppercase tracking-wider font-medium">Popular Sigils</p>
      <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
        {PRESET_INTENTS.map((preset) => (
          <button
            key={preset.id}
            id={`preset-${preset.id}`}
            onClick={() => onSelect(preset.text)}
            className="group text-left px-4 py-3 rounded-lg border border-white/[0.08] bg-sigil-tertiary/50 
              hover:border-amethyst-500/30 hover:bg-amethyst-900/20 
              transition-all duration-150"
          >
            <div className="flex items-center gap-2 mb-1">
              <span className="text-base">{preset.icon}</span>
              <span className="text-xs font-medium text-text-primary group-hover:text-amethyst-300 transition-colors">
                {preset.label}
              </span>
            </div>
            <p className="text-[11px] text-text-tertiary leading-relaxed line-clamp-2">
              {preset.text}
            </p>
          </button>
        ))}
      </div>
    </div>
  );
}
