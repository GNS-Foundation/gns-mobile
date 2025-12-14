import { SearchBar } from '@/components/ui/SearchBar';
import { IdentityCard } from '@/components/identity/IdentityCard';
import { MOCK_IDENTITY } from '@/lib/api';
import Link from 'next/link';

export default function HomePage() {
  // Featured identities (would come from API in production)
  const featuredIdentities = [
    { ...MOCK_IDENTITY, handle: 'caterve', displayName: 'Camilo Ayerbe' },
  ];

  return (
    <div className="min-h-screen">
      {/* Hero Section */}
      <section className="relative overflow-hidden">
        {/* Background gradient */}
        <div className="absolute inset-0 bg-gradient-to-br from-gns-primary/10 via-transparent to-gns-secondary/10" />
        
        <div className="relative max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-20 sm:py-32">
          <div className="text-center max-w-3xl mx-auto">
            {/* Badge */}
            <div className="inline-flex items-center gap-2 px-4 py-2 rounded-full bg-gns-primary/10 text-gns-primary text-sm font-medium mb-6">
              <span>🌐</span>
              <span>The Identity Graph for Humans</span>
            </div>

            {/* Headline */}
            <h1 className="text-4xl sm:text-5xl lg:text-6xl font-bold text-[var(--text-primary)] mb-6">
              Browse <span className="text-gradient">Identities</span>,
              <br />Not Websites
            </h1>

            {/* Subheadline */}
            <p className="text-lg sm:text-xl text-[var(--text-secondary)] mb-10 max-w-2xl mx-auto">
              Discover verified people, places, and businesses by their @handle. 
              Every identity is cryptographically proven through presence.
            </p>

            {/* Search Bar */}
            <div className="max-w-xl mx-auto">
              <SearchBar size="lg" placeholder="Search @handle or place..." autoFocus />
            </div>

            {/* Quick Links */}
            <div className="mt-6 flex flex-wrap justify-center gap-3 text-sm">
              <span className="text-[var(--text-muted)]">Try:</span>
              <Link href="/caterve" className="text-gns-primary hover:underline">@caterve</Link>
              <span className="text-[var(--text-muted)]">•</span>
              <Link href="/entity/colosseum" className="text-gns-primary hover:underline">Colosseum</Link>
              <span className="text-[var(--text-muted)]">•</span>
              <Link href="/search?q=rome" className="text-gns-primary hover:underline">Rome</Link>
            </div>
          </div>
        </div>
      </section>

      {/* How It Works Section */}
      <section className="py-20 bg-[var(--surface)]">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <h2 className="text-3xl font-bold text-center text-[var(--text-primary)] mb-12">
            How GNS Works
          </h2>

          <div className="grid md:grid-cols-3 gap-8">
            {/* Step 1 */}
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

            {/* Step 2 */}
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

            {/* Step 3 */}
            <div className="text-center">
              <div className="w-16 h-16 mx-auto mb-4 rounded-2xl bg-gns-accent/10 flex items-center justify-center">
                <span className="text-3xl">🌐</span>
              </div>
              <h3 className="text-xl font-semibold mb-2 text-[var(--text-primary)]">
                Connect Globally
              </h3>
              <p className="text-[var(--text-secondary)]">
                Message anyone by @handle. Send payments. Verify businesses. All decentralized.
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* Featured Identities */}
      <section className="py-20">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex items-center justify-between mb-8">
            <h2 className="text-2xl font-bold text-[var(--text-primary)]">
              Featured Identities
            </h2>
            <Link href="/search" className="text-gns-primary hover:underline text-sm">
              View all →
            </Link>
          </div>

          <div className="grid md:grid-cols-2 lg:grid-cols-3 gap-6">
            {featuredIdentities.map((identity) => (
              <Link key={identity.publicKey} href={`/${identity.handle}`}>
                <IdentityCard 
                  identity={identity} 
                  size="sm" 
                  showQR={false}
                  showLinks={false}
                />
              </Link>
            ))}
            
            {/* Placeholder cards */}
            <div className="gns-card p-6 flex flex-col items-center justify-center min-h-[200px] border-dashed">
              <span className="text-4xl mb-3">🌱</span>
              <p className="text-[var(--text-muted)] text-center">
                More identities coming soon
              </p>
            </div>
            <div className="gns-card p-6 flex flex-col items-center justify-center min-h-[200px] border-dashed">
              <span className="text-4xl mb-3">🏪</span>
              <p className="text-[var(--text-muted)] text-center">
                Businesses & places
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* CTA Section */}
      <section className="py-20 bg-gradient-to-br from-gns-primary to-gns-secondary">
        <div className="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 text-center">
          <h2 className="text-3xl sm:text-4xl font-bold text-white mb-6">
            Ready to Claim Your Identity?
          </h2>
          <p className="text-lg text-white/80 mb-8 max-w-2xl mx-auto">
            Download Globe Crumbs, create your cryptographic identity, and start collecting breadcrumbs to earn your @handle.
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
              href="https://play.google.com/store/apps/details?id=xyz.gns.globecrumbs"
              target="_blank"
              rel="noopener noreferrer"
              className="px-8 py-4 bg-white/10 text-white font-semibold rounded-xl hover:bg-white/20 transition-colors border border-white/30 flex items-center justify-center gap-2"
            >
              <svg className="w-6 h-6" viewBox="0 0 24 24" fill="currentColor">
                <path d="M3,20.5V3.5C3,2.91 3.34,2.39 3.84,2.15L13.69,12L3.84,21.85C3.34,21.6 3,21.09 3,20.5M16.81,15.12L6.05,21.34L14.54,12.85L16.81,15.12M20.16,10.81C20.5,11.08 20.75,11.5 20.75,12C20.75,12.5 20.53,12.9 20.18,13.18L17.89,14.5L15.39,12L17.89,9.5L20.16,10.81M6.05,2.66L16.81,8.88L14.54,11.15L6.05,2.66Z"/>
              </svg>
              <span>Coming to Android</span>
            </a>
          </div>
        </div>
      </section>

      {/* Stats Section */}
      <section className="py-16 border-t border-[var(--border)]">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="grid grid-cols-2 md:grid-cols-4 gap-8 text-center">
            <div>
              <p className="text-3xl font-bold text-gns-primary">1</p>
              <p className="text-[var(--text-muted)] text-sm mt-1">Identity Created</p>
            </div>
            <div>
              <p className="text-3xl font-bold text-gns-secondary">106</p>
              <p className="text-[var(--text-muted)] text-sm mt-1">Breadcrumbs Dropped</p>
            </div>
            <div>
              <p className="text-3xl font-bold text-gns-accent">1</p>
              <p className="text-[var(--text-muted)] text-sm mt-1">Handle Claimed</p>
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
