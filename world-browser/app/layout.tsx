import type { Metadata } from 'next';
import './globals.css';
import { Header } from '@/components/layout/Header';
import { Footer } from '@/components/layout/Footer';

export const metadata: Metadata = {
  title: {
    default: 'GNS World Browser | Browse Identities, Not Websites',
    template: '%s | GNS World Browser',
  },
  description: 'Discover and connect with verified identities on the Global Navigation & Settlement network. Browse people, places, and businesses by @handle.',
  keywords: ['GNS', 'identity', 'blockchain', 'decentralized', 'presence', 'breadcrumbs'],
  authors: [{ name: 'GNS Protocol' }],
  creator: 'GNS Protocol',
  openGraph: {
    type: 'website',
    locale: 'en_US',
    url: 'https://browser.gns.xyz',
    siteName: 'GNS World Browser',
    title: 'GNS World Browser | Browse Identities, Not Websites',
    description: 'Discover and connect with verified identities on GNS.',
    images: [
      {
        url: '/og-image.png',
        width: 1200,
        height: 630,
        alt: 'GNS World Browser',
      },
    ],
  },
  twitter: {
    card: 'summary_large_image',
    title: 'GNS World Browser',
    description: 'Browse identities, not websites.',
    images: ['/og-image.png'],
  },
  robots: {
    index: true,
    follow: true,
  },
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en" suppressHydrationWarning>
      <body className="min-h-screen flex flex-col bg-[var(--background)]">
        <Header />
        <main className="flex-1">
          {children}
        </main>
        <Footer />
      </body>
    </html>
  );
}
