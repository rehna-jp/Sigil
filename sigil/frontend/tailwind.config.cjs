module.exports = {
  content: ["./app/**/*.{ts,tsx}", "./components/**/*.{ts,tsx}"],
  darkMode: 'class',
  theme: {
    extend: {
      colors: {
        sigil: {
          abyss: '#08080F',
          primary: '#0D0D1A',
          secondary: '#141428',
          tertiary: '#1C1C36',
          hover: '#242445'
        },
        emerald: { 500: '#10B981', 400: '#34D399', 300: '#6EE7B7', 900: '#064E3B' },
        amethyst: { 500: '#7C5CBF', 400: '#9F7AEA', 300: '#C4B5FD', 900: '#3B1F6E', 700: '#5B3A9E' },
        sapphire: { 500: '#3B82F6', 400: '#60A5FA', 300: '#93C5FD' },
        ruby: { 500: '#EF4444', 400: '#F87171', 300: '#FCA5A5', 900: '#5F1E1E' },
        amber: { 500: '#F59E0B', 400: '#FBBF24', 300: '#FDE68A' }
      }
    }
  }
};
