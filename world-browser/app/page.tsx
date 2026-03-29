'use client';

import { useState, useEffect } from 'react';
import { SearchBar } from '@/components/ui/SearchBar';
import Link from 'next/link';

const HIVE_STATUS_URL = 'https://gns-browser-production.up.railway.app/hive/status';

interface HiveStatus {
  active_nodes: number;
  total_tflops: number;
  total_tokens_distributed: number;
  pipeline_cells: number;
}

export default function HomePage() {
  const [hive, setHive] = useState<HiveStatus | null>(null);

  useEffect(() => {
    const fetchHive = () =>
      fetch(HIVE_STATUS_URL)
        .then(r => r.json())
        .then(d => d.success && setHive(d.data))
        .catch(() => {});

    fetchHive();
    const timer = setInterval(fetchHive, 30_000);
    return () => clearInterval(timer);
  }, []);

  return (
    <div className="min-h-screen">

      {/* ── Hero ─────────────────────────────────────────── */}
      <section className="relative overflow-hidden">
        <div className="absolute inset-0 bg-gradient-to-br from-gns-primary/10 via-transparent to-gns-secondary/10" />

        <div className="relative max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-20 sm:py-32">
          <div className="text-center max-w-3xl mx-auto">

            {/* Badge */}
            <div className="inline-flex items-center gap-2 px-4 py-2 rounded-full bg-gns-primary/10 text-gns-primary text-sm font-medium mb-6">
              <span>⬡</span>
              <span>Identity · AI · Presence</span>
            </div>

            {/* Headline */}
            <h1 className="text-4xl sm:text-5xl lg:text-6xl font-bold text-[var(--text-primary)] mb-6">
              Browse <span className="text-gradient">Identities</span>,
              <br />Not Websites
            </h1>

            {/* Subheadline */}
            <p className="text-lg sm:text-xl text-[var(--text-secondary)] mb-8 max-w-2xl mx-auto">
              Discover verified people, organisations, and AI agents by their @handle.
              Every identity is cryptographically proven through physical presence.
            </p>

            {/* Search Bar */}
            <div className="max-w-xl mx-auto">
              <SearchBar size="lg" placeholder="Search @handle or ask anything..." autoFocus />
            </div>

            {/* Quick Links */}
            <div className="mt-6 flex flex-wrap justify-center gap-3 text-sm">
              <span className="text-[var(--text-muted)]">Try:</span>
              <Link href="/camiloayerbe" className="text-gns-primary hover:underline">@camiloayerbe</Link>
              <span className="text-[var(--text-muted)]">·</span>
              <Link href="/hai" className="text-gns-primary hover:underline">@hai</Link>
              <span className="text-[var(--text-muted)]">·</span>
              <Link href="/search?q=rome" className="text-gns-primary hover:underline">Rome</Link>
            </div>
          </div>
        </div>
      </section>

      {/* ── Hive Status ──────────────────────────────────── */}
      {hive && (
        <section className="py-8 border-y border-[var(--border)] bg-[var(--surface)]">
          <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
            <div className="flex flex-col sm:flex-row items-center justify-between gap-4">
              <div className="flex items-center gap-3">
                <span className="w-2.5 h-2.5 rounded-full bg-green-500 animate-pulse" />
                <span className="text-sm font-semibold text-[var(--text-primary)]">
                  GEIANT Hive — Network Live
                </span>
              </div>
              <div className="flex flex-wrap items-center gap-6 text-sm font-mono">
                <span className="text-[var(--text-secondary)]">
                  <span className="text-gns-primary font-bold">{hive.active_nodes}</span> nodes online
                </span>
                <span className="text-[var(--text-muted)]">·</span>
                <span className="text-[var(--text-secondary)]">
                  <span className="text-gns-primary font-bold">{hive.total_tflops.toFixed(1)}</span> TFLOPS
                </span>
                <span className="text-[var(--text-muted)]">·</span>
                <span className="text-[var(--text-secondary)]">
                  <span className="text-green-500 font-bold">{hive.total_tokens_distributed.toFixed(4)}</span> GNS earned
                </span>
                {hive.pipeline_cells > 0 && (
                  <>
                    <span className="text-[var(--text-muted)]">·</span>
                    <span className="text-green-500 font-semibold">
                      {hive.pipeline_cells} pipeline cell{hive.pipeline_cells !== 1 ? 's' : ''}
                    </span>
                  </>
                )}
                <a
                  href="https://hive.geiant.com/console"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-gns-primary hover:underline"
                >
                  View console →
                </a>
              </div>
            </div>
          </div>
        </section>
      )}

      {/* ── How It Works ─────────────────────────────────── */}
      <section className="py-20 bg-[var(--surface)]">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <h2 className="text-3xl font-bold text-center text-[var(--text-primary)] mb-12">
            How GNS Works
          </h2>
          <div className="grid md:grid-cols-3 gap-8">
            <div className="text-center">
              <div className="w-16 h-16 mx-auto mb-4 rounded-2xl bg-gns-primary/10 flex items-center justify-center">
                <span className="text-3xl">🔑</span>
              </div>
              <h3 className="text-xl font-semibold mb-2 text-[var(--text-primary)]">
                Identity = Public Key
              </h3>
              <p className="text-[var(--text-secondary)]">
                Your identity is a cryptographic keypair. No passwords, no emails, no phone numbers.
              </p>
            </div>
            <div className="text-center">
              <div className="w-16 h-16 mx-auto mb-4 rounded-2xl bg-gns-secondary/10 flex items-center justify-center">
                <span className="text-3xl">🍞</span>
              </div>
              <h3 className="text-xl font-semibold mb-2 text-[var(--text-primary)]">
                Prove Through Presence
              </h3>
              <p className="text-[var(--text-secondary)]">
                Drop cryptographic breadcrumbs as you move. 100 breadcrumbs earn you a permanent @handle.
              </p>
            </div>
            <div className="text-center">
              <div className="w-16 h-16 mx-auto mb-4 rounded-2xl bg-gns-accent/10 flex items-center justify-center">
                <span className="text-3xl">⬡</span>
              </div>
              <h3 className="text-xl font-semibold mb-2 text-[var(--text-primary)]">
                Contribute Compute
              </h3>
              <p className="text-[var(--text-secondary)]">
                Your devices join the GEIANT Hive. Every AI request you relay earns GNS tokens. Your phone is a bee.
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* ── CTA ──────────────────────────────────────────── */}
      <section className="py-20 bg-gradient-to-br from-gns-primary to-gns-secondary">
        <div className="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 text-center">
          <h2 className="text-3xl sm:text-4xl font-bold text-white mb-6">
            Ready to Claim Your Identity?
          </h2>
          <p className="text-lg text-white/80 mb-8 max-w-2xl mx-auto">
            Download Globe Crumbs, create your cryptographic identity, and start collecting
            breadcrumbs to earn your @handle — and join the Hive.
          </p>
          <div className="flex flex-col sm:flex-row gap-4 justify-center">
            <a
              href="https://apps.apple.com/app/globe-crumbs"
              target="_blank"
              rel="noopener noreferrer"
              className="px-8 py-4 bg-white text-gns-primary font-semibold rounded-xl hover:bg-white/90 transition-colors flex items-center justify-center gap-2"
            >
              <svg className="w-6 h-6" viewBox="0 0 24 24" fill="currentColor">
                <path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.81-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z"/>
              </svg>
              <span>Download for iOS</span>
            </a>
            <a
              href="https://hive.geiant.com/console"
              target="_blank"
              rel="noopener noreferrer"
              className="px-8 py-4 bg-white/10 text-white font-semibold rounded-xl hover:bg-white/20 transition-colors border border-white/30 flex items-center justify-center gap-2"
            >
              <span>⬡</span>
              <span>Join the Hive</span>
            </a>
          </div>
        </div>
      </section>

      {/* ── Stats ────────────────────────────────────────── */}
      <section className="py-16 border-t border-[var(--border)]">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="grid grid-cols-2 md:grid-cols-4 gap-8 text-center">
            <div>
              <p className="text-3xl font-bold text-gns-primary">
                {hive ? hive.active_nodes : '—'}
              </p>
              <p className="text-[var(--text-muted)] text-sm mt-1">Hive Nodes Online</p>
            </div>
            <div>
              <p className="text-3xl font-bold text-gns-secondary">
                {hive ? `${hive.total_tflops.toFixed(1)}` : '—'}
              </p>
              <p className="text-[var(--text-muted)] text-sm mt-1">TFLOPS Available</p>
            </div>
            <div>
              <p className="text-3xl font-bold text-gns-accent">
                {hive ? hive.total_tokens_distributed.toFixed(2) : '—'}
              </p>
              <p className="text-[var(--text-muted)] text-sm mt-1">GNS Distributed</p>
            </div>
            <div>
              <p className="text-3xl font-bold text-[var(--text-primary)]">∞</p>
              <p className="text-[var(--text-muted)] text-sm mt-1">Possibilities</p>
            </div>
          </div>
        </div>
      </section>

    </div>
  );
}
