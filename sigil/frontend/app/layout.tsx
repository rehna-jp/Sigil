import './globals.css'
import { ReactNode } from 'react'

export const metadata = {
  title: 'Sigil Dashboard',
  description: 'Persistent Intent Engine'
}

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en" className="dark">
      <body className="bg-sigil-primary text-white font-sans">{children}</body>
    </html>
  )
}
