import { Metadata } from 'next';
import { notFound } from 'next/navigation';
import { IdentityCard } from '@/components/identity/IdentityCard';
import { getIdentityWithFallback, MOCK_IDENTITY } from '@/lib/api';
import { GnsIdentity } from '@/lib/types';
import Link from 'next/link';

interface ProfilePageProps {
  params: { handle: string };
}

// Generate metadata for SEO
export async function generateMetadata({ params }: ProfilePageProps): Promise<Metadata> {
  const identity = await getIdentityWithFallback(params.handle);
  
  if (!identity) {
    return {
      title: 'Identity Not Found',
    };
  }

  const title = identity.displayName 
    ? `${identity.displayName} (@${identity.handle})`
    : `@${identity.handle}`;

  return {
    title,
    description: identity.bio || `View ${title}'s GNS identity and trust score.`,
    openGraph: {
      title: `${title} | GNS World Browser`,
      description: identity.bio || `${identity.trustScore}% trust score • ${identity.breadcrumbCount} breadcrumbs`,
      type: 'profile',
      images: identity.avatarUrl ? [identity.avatarUrl] : undefined,
    },
    twitter: {
      card: 'summary',
      title,
      description: identity.bio || `${identity.trustScore}% trust score`,
    },
  };
}

export default async function ProfilePage({ params }: ProfilePageProps) {
  const { handle } = params;
  
  // Fetch identity data
  const identity = await getIdentityWithFallback(handle);

  if (!identity) {
    notFound();
  }

  return (
    <div className="min-h-screen py-8 sm:py-12">
      <div className="max-w-2xl mx-auto px-4 sm:px-6 lg:px-8">
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
            <li className="text-[var(--text-primary)]">
              @{identity.handle}
            </li>
          </ol>
        </nav>

        {/* Main Identity Card */}
        <IdentityCard identity={identity} size="lg" />

        {/* Activity Section */}
        <div className="mt-8 gns-card">
          <h2 className="text-lg font-semibold text-[var(--text-primary)] mb-4">
            Recent Activity
          </h2>
          
          {/* Activity Timeline */}
          <div className="space-y-4">
            <ActivityItem
              emoji="🍞"
              title="Dropped breadcrumb"
              subtitle={identity.lastLocationRegion || 'Unknown location'}
              time="Recently"
            />
            <ActivityItem
              emoji="✨"
              title="Trust score updated"
              subtitle={`Now at ${identity.trustScore}%`}
              time="Today"
            />
            {identity.handle && (
              <ActivityItem
                emoji="🏷️"
                title="Claimed handle"
                subtitle={`@${identity.handle}`}
                time={`${identity.daysSinceCreation} days ago`}
              />
            )}
            <ActivityItem
              emoji="🌱"
              title="Identity created"
              subtitle="Genesis breadcrumb dropped"
              time={`${identity.daysSinceCreation} days ago`}
            />
          </div>
        </div>

        {/* Breadcrumb Map Preview (Placeholder) */}
        <div className="mt-8 gns-card">
          <h2 className="text-lg font-semibold text-[var(--text-primary)] mb-4">
            Presence Map
          </h2>
          <div className="aspect-video bg-[var(--surface)] rounded-xl flex items-center justify-center border border-[var(--border)]">
            <div className="text-center">
              <span className="text-4xl mb-2 block">🗺️</span>
              <p className="text-[var(--text-muted)] text-sm">
                Map visualization coming soon
              </p>
              <p className="text-[var(--text-muted)] text-xs mt-1">
                {identity.breadcrumbCount} breadcrumbs across multiple regions
              </p>
            </div>
          </div>
        </div>

        {/* Connection CTA */}
        <div className="mt-8 p-6 bg-gradient-to-br from-gns-primary/10 to-gns-secondary/10 rounded-2xl text-center">
          <h3 className="text-lg font-semibold text-[var(--text-primary)] mb-2">
            Want to connect with @{identity.handle}?
          </h3>
          <p className="text-[var(--text-secondary)] text-sm mb-4">
            Download Globe Crumbs to message, send payments, or add as a contact.
          </p>
          <a
            href={`globecrumbs://profile/${identity.publicKey}`}
            className="gns-button-primary inline-flex items-center gap-2"
          >
            <span>📱</span>
            <span>Open in Globe Crumbs</span>
          </a>
        </div>
      </div>
    </div>
  );
}

// Activity Item Component
function ActivityItem({ 
  emoji, 
  title, 
  subtitle, 
  time 
}: { 
  emoji: string; 
  title: string; 
  subtitle: string; 
  time: string;
}) {
  return (
    <div className="flex items-start gap-3">
      <div className="w-10 h-10 rounded-full bg-[var(--surface)] flex items-center justify-center flex-shrink-0">
        <span>{emoji}</span>
      </div>
      <div className="flex-1 min-w-0">
        <p className="text-sm font-medium text-[var(--text-primary)]">{title}</p>
        <p className="text-sm text-[var(--text-muted)] truncate">{subtitle}</p>
      </div>
      <span className="text-xs text-[var(--text-muted)] flex-shrink-0">{time}</span>
    </div>
  );
}
