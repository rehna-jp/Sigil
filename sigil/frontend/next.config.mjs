const BACKEND_URL = process.env.NEXT_PUBLIC_BACKEND_URL || 'https://sigil-backend-724136559213.us-central1.run.app';

/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  async rewrites() {
    return [
      {
        source: '/api/:path*',
        destination: `${BACKEND_URL}/:path*`,
      },
    ];
  },
};

export default nextConfig;
