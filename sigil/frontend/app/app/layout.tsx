import { ReactNode } from 'react';
import { Navbar } from '../../components/layout/Navbar';
import { Sidebar } from '../../components/layout/Sidebar';

export const metadata = {
  title: 'Sigil App',
};

export default function AppLayout({ children }: { children: ReactNode }) {
  return (
    <div className="flex flex-col h-screen bg-sigil-primary">
      <Navbar />
      <div className="flex flex-1 overflow-hidden">
        <Sidebar />
        <main className="flex-1 overflow-y-auto scrollbar-thin p-6">
          {children}
        </main>
      </div>
    </div>
  );
}
