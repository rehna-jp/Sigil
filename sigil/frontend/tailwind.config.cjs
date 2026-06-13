module.exports = {
  content: [
    "./app/**/*.{ts,tsx}",
    "./components/**/*.{ts,tsx}",
  ],
  darkMode: 'class',
  theme: {
    extend: {
      colors: {
        sigil: {
          abyss:     '#08080F',
          primary:   '#0D0D1A',
          secondary: '#141428',
          tertiary:  '#1C1C36',
          hover:     '#242445',
        },
        emerald: {
          900: '#064E3B',
          700: '#047857',
          500: '#10B981',
          400: '#34D399',
          300: '#6EE7B7',
        },
        amethyst: {
          900: '#3B1F6E',
          700: '#5B3A9E',
          500: '#7C5CBF',
          400: '#9F7AEA',
          300: '#C4B5FD',
        },
        sapphire: {
          500: '#3B82F6',
          400: '#60A5FA',
          300: '#93C5FD',
        },
        ruby: {
          900: '#5F1E1E',
          500: '#EF4444',
          400: '#F87171',
          300: '#FCA5A5',
        },
        amber: {
          500: '#F59E0B',
          400: '#FBBF24',
          300: '#FDE68A',
        },
        text: {
          primary:   '#E8E6F0',
          secondary: '#9896A8',
          tertiary:  '#5C5A6E',
        },
      },
      fontFamily: {
        display: ['Instrument Serif', 'serif'],
        sans:    ['DM Sans', 'sans-serif'],
        mono:    ['JetBrains Mono', 'monospace'],
      },
      keyframes: {
        pulse: {
          '0%, 100%': { opacity: '1', transform: 'scale(1)' },
          '50%':       { opacity: '0.6', transform: 'scale(1.15)' },
        },
        fadeUp: {
          from: { opacity: '0', transform: 'translateY(12px)' },
          to:   { opacity: '1', transform: 'translateY(0)' },
        },
        glowBorder: {
          '0%, 100%': { borderColor: 'rgba(124, 92, 191, 0.2)' },
          '50%':       { borderColor: 'rgba(124, 92, 191, 0.5)' },
        },
        spin: {
          from: { transform: 'rotate(0deg)' },
          to:   { transform: 'rotate(360deg)' },
        },
        rubyFlash: {
          '0%, 100%': { boxShadow: '0 0 24px rgba(239, 68, 68, 0.2)', borderColor: 'rgba(239, 68, 68, 0.3)' },
          '50%':       { boxShadow: '0 0 48px rgba(239, 68, 68, 0.6)', borderColor: 'rgba(239, 68, 68, 0.8)' },
        },
        shimmer: {
          '0%': { backgroundPosition: '-200% 0' },
          '100%': { backgroundPosition: '200% 0' },
        },
      },
      animation: {
        'pulse-dot':   'pulse 2s ease-in-out infinite',
        'fade-up':     'fadeUp 0.3s ease-out forwards',
        'glow-border': 'glowBorder 2s ease-in-out infinite',
        'spin-slow':   'spin 10s linear infinite',
        'ruby-flash':  'rubyFlash 0.6s ease-in-out infinite',
        'shimmer':     'shimmer 2s linear infinite',
      },
      boxShadow: {
        'glow-emerald': '0 0 24px rgba(16, 185, 129, 0.2), inset 0 1px 0 rgba(16, 185, 129, 0.15)',
        'glow-amethyst': '0 0 24px rgba(124, 92, 191, 0.2), inset 0 1px 0 rgba(124, 92, 191, 0.15)',
        'glow-ruby': '0 0 24px rgba(239, 68, 68, 0.2), inset 0 1px 0 rgba(239, 68, 68, 0.15)',
        'glow-sapphire': '0 0 24px rgba(59, 130, 246, 0.2), inset 0 1px 0 rgba(59, 130, 246, 0.15)',
      },
    },
  },
  plugins: [],
};
