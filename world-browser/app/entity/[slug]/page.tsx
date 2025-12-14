import { Metadata } from 'next';
import { notFound } from 'next/navigation';
import { getEntityWithFallback, MOCK_ENTITY } from '@/lib/api';
import Link from 'next/link';

interface EntityPageProps {
  params: { slug: string };
}

// Generate metadata for SEO
export async function generateMetadata({ params }: EntityPageProps): Promise<Metadata> {
  const entity = await getEntityWithFallback(params.slug);
  
  if (!entity) {
    return {
      title: 'Entity Not Found',
    };
  }

  return {
    title: entity.primaryName,
    description: entity.description || `${entity.primaryName} on GNS - ${entity.visitorCount} verified visitors`,
    openGraph: {
      title: `${entity.primaryName} | GNS World Browser`,
      description: entity.description || `Verified ${entity.entityType} with ${entity.visitorCount} visitors`,
      type: 'website',
      images: entity.imageUrl ? [entity.imageUrl] : undefined,
    },
  };
}

export default async function EntityPage({ params }: EntityPageProps) {
  const { slug } = params;
  const entity = await getEntityWithFallback(slug);

  if (!entity) {
    notFound();
  }

  const entityTypeEmoji = {
    place: '📍',
    business: '🏪',
    artwork: '🎨',
    device: '📱',
    media: '🎬',
    person: '👤',
    website: '🌐',
  }[entity.entityType] || '📍';

  return (
    <div className="min-h-screen py-8 sm:py-12">
      <div className="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8">
        {/* Breadcrumb Navigation */}
        <nav className="mb-6 text-sm">
          <ol className="flex items-center gap-2 text-[var(--text-muted)]">
            <li>
              <Link href="/" className="hover:text-gns-primary transition-colors">
                Home
              </Link>
            </li>
            <li>
              <span className="mx-2">/</span>
            </li>
            <li>
              <Link href={`/search?type=${entity.entityType}`} className="hover:text-gns-primary transition-colors capitalize">
                {entity.entityType}s
              </Link>
            </li>
            <li>
              <span className="mx-2">/</span>
            </li>
            <li className="text-[var(--text-primary)]">
              {entity.primaryName}
            </li>
          </ol>
        </nav>

        {/* Hero Image */}
        {entity.imageUrl && (
          <div className="aspect-video mb-8 rounded-2xl overflow-hidden">
            <img 
              src={entity.imageUrl} 
              alt={entity.primaryName}
              className="w-full h-full object-cover"
            />
          </div>
        )}

        {/* Main Content */}
        <div className="grid lg:grid-cols-3 gap-8">
          {/* Left Column - Main Info */}
          <div className="lg:col-span-2">
            <div className="gns-card">
              {/* Header */}
              <div className="flex items-start gap-4 mb-6">
                <div className="w-16 h-16 rounded-xl bg-gns-primary/10 flex items-center justify-center flex-shrink-0">
                  <span className="text-3xl">{entityTypeEmoji}</span>
                </div>
                <div>
                  <div className="flex items-center gap-2">
                    <h1 className="text-2xl font-bold text-[var(--text-primary)]">
                      {entity.primaryName}
                    </h1>
                    {entity.isVerified && (
                      <span className="bg-gns-secondary text-white text-xs px-2 py-1 rounded-full">
                        ✓ Verified
                      </span>
                    )}
                  </div>
                  <p className="text-[var(--text-secondary)] capitalize">
                    {entity.entityType} • {entity.city}, {entity.country}
                  </p>
                </div>
              </div>

              {/* Description */}
              {entity.description && (
                <p className="text-[var(--text-secondary)] mb-6">
                  {entity.description}
                </p>
              )}

              {/* Tags */}
              {entity.tags && entity.tags.length > 0 && (
                <div className="flex flex-wrap gap-2 mb-6">
                  {entity.tags.map((tag) => (
                    <Link
                      key={tag}
                      href={`/search?q=${tag}`}
                      className="px-3 py-1 rounded-full bg-[var(--surface)] border border-[var(--border)] text-sm text-[var(--text-secondary)] hover:border-gns-primary transition-colors"
                    >
                      #{tag}
                    </Link>
                  ))}
                </div>
              )}

              {/* Stats */}
              <div className="grid grid-cols-3 gap-4 pt-6 border-t border-[var(--border)]">
                <div className="text-center">
                  <p className="text-2xl font-bold text-gns-primary">
                    {entity.visitorCount.toLocaleString()}
                  </p>
                  <p className="text-xs text-[var(--text-muted)]">Verified Visitors</p>
                </div>
                <div className="text-center">
                  <p className="text-2xl font-bold text-gns-secondary">
                    {entity.trustScore}%
                  </p>
                  <p className="text-xs text-[var(--text-muted)]">Trust Score</p>
                </div>
                <div className="text-center">
                  <p className="text-2xl font-bold text-gns-accent">
                    {entity.isClaimed ? '✓' : '○'}
                  </p>
                  <p className="text-xs text-[var(--text-muted)]">
                    {entity.isClaimed ? 'Claimed' : 'Unclaimed'}
                  </p>
                </div>
              </div>
            </div>

            {/* Recent Visitors */}
            <div className="mt-8 gns-card">
              <h2 className="text-lg font-semibold text-[var(--text-primary)] mb-4">
                Recent Verified Visitors
              </h2>
              
              {entity.recentVisitors && entity.recentVisitors.length > 0 ? (
                <div className="space-y-3">
                  {entity.recentVisitors.map((visitor) => (
                    <Link
                      key={visitor.publicKey}
                      href={`/${visitor.handle}`}
                      className="flex items-center gap-3 p-3 rounded-xl hover:bg-[var(--surface)] transition-colors"
                    >
                      <div className="w-10 h-10 rounded-full bg-gradient-to-br from-gns-primary to-gns-secondary flex items-center justify-center text-white font-medium">
                        {(visitor.displayName || visitor.handle || '?')[0].toUpperCase()}
                      </div>
                      <div className="flex-1">
                        <p className="font-medium text-[var(--text-primary)]">
                          {visitor.displayName || `@${visitor.handle}`}
                        </p>
                        <p className="text-sm text-[var(--text-muted)]">
                          {visitor.trustScore}% trust
                        </p>
                      </div>
                      <span className="text-xs text-[var(--text-muted)]">
                        {visitor.lastSeen ? 'Recently' : 'Visited'}
                      </span>
                    </Link>
                  ))}
                </div>
              ) : (
                <div className="text-center py-8">
                  <span className="text-4xl mb-2 block">👀</span>
                  <p className="text-[var(--text-muted)]">
                    No verified visitors yet
                  </p>
                  <p className="text-sm text-[var(--text-muted)] mt-1">
                    Be the first to drop a breadcrumb here!
                  </p>
                </div>
              )}
            </div>
          </div>

          {/* Right Column - Sidebar */}
          <div className="lg:col-span-1">
            {/* Claim CTA */}
            {!entity.isClaimed && (
              <div className="gns-card mb-6 border-2 border-dashed border-gns-primary/30">
                <div className="text-center">
                  <span className="text-3xl mb-2 block">🏪</span>
                  <h3 className="font-semibold text-[var(--text-primary)] mb-2">
                    Own this {entity.entityType}?
                  </h3>
                  <p className="text-sm text-[var(--text-secondary)] mb-4">
                    Claim it to manage your GNS presence and connect with verified visitors.
                  </p>
                  <a
                    href={`globecrumbs://claim/${entity.slug}`}
                    className="gns-button-primary w-full text-center block"
                  >
                    Claim in App
                  </a>
                </div>
              </div>
            )}

            {/* Check In CTA */}
            <div className="gns-card mb-6">
              <h3 className="font-semibold text-[var(--text-primary)] mb-3">
                Visit {entity.primaryName}?
              </h3>
              <p className="text-sm text-[var(--text-secondary)] mb-4">
                Drop a breadcrumb to prove your presence and earn GNS rewards.
              </p>
              <a
                href={`globecrumbs://checkin/${entity.slug}`}
                className="gns-button-secondary w-full text-center block"
              >
                📍 Check In via App
              </a>
            </div>

            {/* Location Info */}
            <div className="gns-card">
              <h3 className="font-semibold text-[var(--text-primary)] mb-3">
                Location
              </h3>
              <p className="text-[var(--text-secondary)]">
                {entity.city}, {entity.country}
              </p>
              
              {/* Map Placeholder */}
              <div className="mt-4 aspect-square bg-[var(--surface)] rounded-xl flex items-center justify-center border border-[var(--border)]">
                <div className="text-center">
                  <span className="text-2xl">🗺️</span>
                  <p className="text-xs text-[var(--text-muted)] mt-1">
                    Map coming soon
                  </p>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
