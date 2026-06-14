export default {
  reactStrictMode: true,
  typescript: {
    ignoreBuildErrors: true,
  },
  turbopack: {
    resolveAlias: {
      '@react-native-async-storage/async-storage': { browser: './src/lib/empty.js' },
      'pino-pretty': { browser: './src/lib/empty.js' },
      'fsevents': { browser: './src/lib/empty.js' },
    },
  },
  async rewrites() {
    return [
      {
        source: '/api/:path*',
        destination: `${process.env.BACKEND_URL || 'http://localhost:3001'}/:path*`,
      },
    ];
  },
};
