import '../styles/globals.css';
import { ReactNode } from 'react';
import { WagmiProvider } from '../components/providers/WagmiProvider';
import { WebSocketProvider } from '../components/providers/WebSocketProvider';

export const metadata = {
  title: 'Sigil — Persistent Intent Engine',
  description: 'Inscribe your financial intent once. It watches, reacts, and protects — autonomously. Built on Arbitrum.',
  keywords: ['DeFi', 'Arbitrum', 'intent', 'AI', 'yield', 'automation', 'wagmi'],
  openGraph: {
    title: 'Sigil — Persistent Intent Engine',
    description: 'Inscribe your financial intent once. It watches, reacts, and protects — autonomously.',
    type: 'website',
  },
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en" className="dark">
      <body className="bg-sigil-abyss text-text-primary font-sans antialiased">
        <WagmiProvider>
          <WebSocketProvider>
            {children}
          </WebSocketProvider>
        </WagmiProvider>
      </body>
    </html>
  );
}
