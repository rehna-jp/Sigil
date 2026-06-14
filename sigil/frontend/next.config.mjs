const BACKEND_URL = process.env.NEXT_PUBLIC_BACKEND_URL || 'https://sigil-backend-724136559213.us-central1.run.app';

export default {
  reactStrictMode: true,
  typescript: {
    ignoreBuildErrors: true,
  },
  eslint: {
    ignoreDuringBuilds: true,
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
        destination: `${BACKEND_URL}/:path*`,
      },
    ];
  },
};
