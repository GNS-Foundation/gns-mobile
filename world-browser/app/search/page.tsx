'use client';

import { useState, useEffect } from 'react';
import { useSearchParams } from 'next/navigation';
import Link from 'next/link';
import { SearchBar } from '@/components/ui/SearchBar';
import { search, MOCK_IDENTITY, MOCK_ENTITY } from '@/lib/api';
import { GnsIdentity, GnsEntity, SearchResult, getTrustEmoji } from '@/lib/types';

export default function SearchPage() {
  const searchParams = useSearchParams();
  const query = searchParams.get('q') || '';
  const typeFilter = searchParams.get('type') || 'all';
  
  const [results, setResults] = useState<SearchResult[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [activeTab, setActiveTab] = useState<'all' | 'identity' | 'entity'>(
    typeFilter as 'all' | 'identity' | 'entity'
  );

  useEffect(() => {
    async function performSearch() {
      if (!query.trim()) {
        setResults([]);
        return;
      }

      setIsLoading(true);
      
      try {
        const response = await search(query, { type: activeTab });
        
        if (response.success && response.data) {
          setResults(response.data.results);
        } else {
          // Use mock data in development
          console.log('Using mock search results');
          setResults([
            { type: 'identity', identity: MOCK_IDENTITY, relevanceScore: 0.95 },
            { type: 'entity', entity: MOCK_ENTITY, relevanceScore: 0.80 },
          ]);
        }
      } catch (error) {
        console.error('Search error:', error);
        // Fallback to mock data
        setResults([
          { type: 'identity', identity: MOCK_IDENTITY, relevanceScore: 0.95 },
          { type: 'entity', entity: MOCK_ENTITY, relevanceScore: 0.80 },
        ]);
      } finally {
        setIsLoading(false);
      }
    }

    performSearch();
  }, [query, activeTab]);

  const identityResults = results.filter(r => r.type === 'identity');
  const entityResults = results.filter(r => r.type === 'entity');

  return (
    <div className="min-h-screen py-8 sm:py-12">
      <div className="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8">
        {/* Search Header */}
        <div className="mb-8">
          <h1 className="text-2xl font-bold text-[var(--text-primary)] mb-4">
            {query ? `Search results for "${query}"` : 'Explore GNS'}
          </h1>
          <SearchBar size="lg" placeholder="Search @handle, name, or place..." />
        </div>

        {/* Tabs */}
        <div className="flex gap-2 mb-6 border-b border-[var(--border)]">
          <TabButton 
            active={activeTab === 'all'} 
            onClick={() => setActiveTab('all')}
            count={results.length}
          >
            All
          </TabButton>
          <TabButton 
            active={activeTab === 'identity'} 
            onClick={() => setActiveTab('identity')}
            count={identityResults.length}
          >
            👤 People
          </TabButton>
          <TabButton 
            active={activeTab === 'entity'} 
            onClick={() => setActiveTab('entity')}
            count={entityResults.length}
          >
            📍 Places
          </TabButton>
        </div>

        {/* Results */}
        {isLoading ? (
          <div className="flex items-center justify-center py-20">
            <div className="animate-spin rounded-full h-8 w-8 border-2 border-gns-primary border-t-transparent"></div>
          </div>
        ) : results.length > 0 ? (
          <div className="space-y-4">
            {results.map((result, index) => (
              result.type === 'identity' && result.identity ? (
                <IdentityResultCard key={index} identity={result.identity} />
              ) : result.type === 'entity' && result.entity ? (
                <EntityResultCard key={index} entity={result.entity} />
              ) : null
            ))}
          </div>
        ) : query ? (
          <EmptyState query={query} />
        ) : (
          <DiscoverSection />
        )}
      </div>
    </div>
  );
}

// Tab Button Component
function TabButton({ 
  active, 
  onClick, 
  count, 
  children 
}: { 
  active: boolean; 
  onClick: () => void; 
  count: number;
  children: React.ReactNode;
}) {
  return (
    <button
      onClick={onClick}
      className={`
        px-4 py-3 font-medium text-sm transition-colors relative
        ${active 
          ? 'text-gns-primary' 
          : 'text-[var(--text-muted)] hover:text-[var(--text-secondary)]'
        }
      `}
    >
      {children}
      {count > 0 && (
        <span className={`ml-2 px-2 py-0.5 rounded-full text-xs ${
          active ? 'bg-gns-primary/10' : 'bg-[var(--surface)]'
        }`}>
          {count}
        </span>
      )}
      {active && (
        <div className="absolute bottom-0 left-0 right-0 h-0.5 bg-gns-primary" />
      )}
    </button>
  );
}

// Identity Result Card
function IdentityResultCard({ identity }: { identity: GnsIdentity }) {
  return (
    <Link href={`/${identity.handle}`}>
      <div className="gns-card hover:border-gns-primary/50 transition-colors cursor-pointer">
        <div className="flex items-center gap-4">
          {/* Avatar */}
          <div className="w-14 h-14 rounded-full bg-gradient-to-br from-gns-primary to-gns-secondary flex items-center justify-center text-white text-xl font-medium flex-shrink-0">
            {identity.avatarUrl ? (
              <img 
                src={identity.avatarUrl} 
                alt={identity.displayName || ''} 
                className="w-full h-full rounded-full object-cover"
              />
            ) : (
              (identity.displayName || identity.handle || '?')[0].toUpperCase()
            )}
          </div>

          {/* Info */}
          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-2">
              <h3 className="font-semibold text-[var(--text-primary)] truncate">
                {identity.displayName || `@${identity.handle}`}
              </h3>
              {identity.isVerified && (
                <span className="text-gns-secondary">✓</span>
              )}
            </div>
            {identity.handle && (
              <p className="text-sm text-gns-primary">@{identity.handle}</p>
            )}
            {identity.bio && (
              <p className="text-sm text-[var(--text-muted)] truncate mt-1">
                {identity.bio}
              </p>
            )}
          </div>

          {/* Stats */}
          <div className="hidden sm:flex items-center gap-4 text-sm text-[var(--text-muted)]">
            <span>{getTrustEmoji(identity.trustScore)} {identity.trustScore}%</span>
            <span>🍞 {identity.breadcrumbCount}</span>
          </div>

          {/* Arrow */}
          <svg className="w-5 h-5 text-[var(--text-muted)]" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5l7 7-7 7" />
          </svg>
        </div>
      </div>
    </Link>
  );
}

// Entity Result Card
function EntityResultCard({ entity }: { entity: GnsEntity }) {
  const entityTypeEmoji = {
    place: '📍',
    business: '🏪',
    artwork: '🎨',
    device: '📱',
    media: '🎬',
    person: '👤',
    website: '🌐',
  }[entity.entityType] || '�';

  return (
    <Link href={`/entity/${entity.slug}`}>
      <div className="gns-card hover:border-gns-primary/50 transition-colors cursor-pointer">
        <div className="flex items-center gap-4">
          {/* Image/Icon */}
          <div className="w-14 h-14 rounded-xl bg-gns-primary/10 flex items-center justify-center flex-shrink-0 overflow-hidden">
            {entity.imageUrl ? (
              <img 
                src={entity.imageUrl} 
                alt={entity.primaryName} 
                className="w-full h-full object-cover"
              />
            ) : (
              <span className="text-2xl">{entityTypeEmoji}</span>
            )}
          </div>

          {/* Info */}
          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-2">
              <h3 className="font-semibold text-[var(--text-primary)] truncate">
                {entity.primaryName}
              </h3>
              {entity.isVerified && (
                <span className="text-gns-secondary">✓</span>
              )}
            </div>
            <p className="text-sm text-[var(--text-muted)] capitalize">
              {entity.entityType} • {entity.city}, {entity.country}
            </p>
          </div>

          {/* Stats */}
          <div className="hidden sm:flex items-center gap-4 text-sm text-[var(--text-muted)]">
            <span>👀 {entity.visitorCount.toLocaleString()}</span>
          </div>

          {/* Arrow */}
          <svg className="w-5 h-5 text-[var(--text-muted)]" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5l7 7-7 7" />
          </svg>
        </div>
      </div>
    </Link>
  );
}

// Empty State
function EmptyState({ query }: { query: string }) {
  return (
    <div className="text-center py-20">
      <span className="text-5xl mb-4 block">🔍</span>
      <h3 className="text-xl font-semibold text-[var(--text-primary)] mb-2">
        No results for "{query}"
      </h3>
      <p className="text-[var(--text-muted)] mb-6">
        Try searching for a different @handle or place name.
      </p>
      <div className="text-sm text-[var(--text-muted)]">
        <p>Tips:</p>
        <ul className="mt-2 space-y-1">
          <li>• Search by @handle (e.g., @caterve)</li>
          <li>• Search by name or location</li>
          <li>• Try fewer or different keywords</li>
        </ul>
      </div>
    </div>
  );
}

// Discover Section (when no query)
function DiscoverSection() {
  return (
    <div className="space-y-8">
      {/* Categories */}
      <div>
        <h2 className="text-lg font-semibold text-[var(--text-primary)] mb-4">
          Browse by Category
        </h2>
        <div className="grid grid-cols-2 sm:grid-cols-3 gap-4">
          <CategoryCard emoji="👤" title="People" href="/search?type=identity" />
          <CategoryCard emoji="📍" title="Places" href="/search?type=entity&entityType=place" />
          <CategoryCard emoji="🏪" title="Businesses" href="/search?type=entity&entityType=business" />
          <CategoryCard emoji="🎨" title="Artwork" href="/search?type=entity&entityType=artwork" />
          <CategoryCard emoji="📱" title="Devices" href="/search?type=entity&entityType=device" />
          <CategoryCard emoji="🎬" title="Media" href="/search?type=entity&entityType=media" />
        </div>
      </div>

      {/* Popular Searches */}
      <div>
        <h2 className="text-lg font-semibold text-[var(--text-primary)] mb-4">
          Popular Searches
        </h2>
        <div className="flex flex-wrap gap-2">
          {['Rome', 'Colosseum', 'Paris', 'Tokyo', 'New York'].map((term) => (
            <Link
              key={term}
              href={`/search?q=${term}`}
              className="px-4 py-2 rounded-full bg-[var(--surface)] border border-[var(--border)] text-sm text-[var(--text-secondary)] hover:border-gns-primary transition-colors"
            >
              {term}
            </Link>
          ))}
        </div>
      </div>
    </div>
  );
}

// Category Card
function CategoryCard({ emoji, title, href }: { emoji: string; title: string; href: string }) {
  return (
    <Link
      href={href}
      className="gns-card flex flex-col items-center justify-center py-6 hover:border-gns-primary/50 transition-colors"
    >
      <span className="text-3xl mb-2">{emoji}</span>
      <span className="text-sm font-medium text-[var(--text-primary)]">{title}</span>
    </Link>
  );
}
