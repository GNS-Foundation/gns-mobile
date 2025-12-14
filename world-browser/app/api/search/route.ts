// app/api/search/route.ts
import { NextRequest, NextResponse } from 'next/server';
import { GnsIdentity, GnsEntity, SearchResult, SearchResponse, ProfileLink } from '@/lib/types';

const GATEWAY_API = process.env.GATEWAY_API_URL || 'http://localhost:3001';

// Mock data for development
const MOCK_IDENTITY: GnsIdentity = {
  publicKey: '26b9c6a8f1e2d3c4b5a6978869605f4e3d2c1b0a9f8e7d6c5b4a3928171d2e3f4a',
  gnsId: 'gns_26b9c6a8',
  handle: 'camiloayerbe',
  displayName: 'Camilo Ayerbe',
  bio: 'Building identity through presence. Creator of GNS.',
  avatarUrl: undefined,
  links: [
    { type: 'github', url: 'https://github.com/caterve' },
    { type: 'twitter', url: 'https://twitter.com/caterve' },
    { type: 'website', url: 'https://gns.xyz' },
  ] as ProfileLink[],
  trustScore: 85,
  breadcrumbCount: 106,
  daysSinceCreation: 45,
  lastLocationRegion: 'Rome, Italy',
  isVerified: true,
  createdAt: '2024-10-27T00:00:00Z',
};

const MOCK_ENTITY: GnsEntity = {
  publicKey: 'entity_colosseum_001',
  entityType: 'website',
  slug: 'colosseum',
  primaryName: 'Colosseum',
  description: 'Ancient Roman amphitheater in the center of Rome',
  city: 'Rome',
  country: 'Italy',
  tags: ['landmark', 'history', 'rome'],
  imageUrl: 'https://upload.wikimedia.org/wikipedia/commons/thumb/d/de/Colosseo_2020.jpg/1280px-Colosseo_2020.jpg',
  trustScore: 99,
  visitorCount: 12453,
  createdAt: '2024-01-01T00:00:00Z',
  isVerified: true,
  isClaimed: true,
  recentVisitors: [],
};

export async function GET(request: NextRequest) {
  const { searchParams } = new URL(request.url);
  const query = searchParams.get('q') || '';
  const type = searchParams.get('type') || 'all';

  if (!query) {
    // Return mock results for empty query
    const mockResults: SearchResponse = {
      query,
      results: [
        {
          type: 'identity' as const,
          identity: { ...MOCK_IDENTITY, handle: 'caterve' },
          relevanceScore: 1.0,
        },
        {
          type: 'entity' as const,
          entity: MOCK_ENTITY,
          relevanceScore: 0.9,
        },
      ],
      totalCount: 2,
      page: 1,
      pageSize: 20,
    };
    return NextResponse.json(mockResults);
  }

  try {
    // Try to fetch from gateway API
    const response = await fetch(`${GATEWAY_API}/search?q=${encodeURIComponent(query)}&type=${type}`, {
      next: { revalidate: 30 },
    });

    if (response.ok) {
      const data = await response.json();
      if (data.success && data.data) {
        return NextResponse.json(data.data);
      }
    }
  } catch (error) {
    console.log('Gateway API not available, using mock data');
  }

  // Fallback to mock search
  const results: SearchResult[] = [];
  const lowerQuery = query.toLowerCase();

  // Search mock identity
  if (type === 'all' || type === 'identity') {
    if (
      MOCK_IDENTITY.handle?.toLowerCase().includes(lowerQuery) ||
      MOCK_IDENTITY.displayName?.toLowerCase().includes(lowerQuery)
    ) {
      results.push({
        type: 'identity' as const,
        identity: MOCK_IDENTITY,
        relevanceScore: 0.9,
      });
    }
  }

  // Search mock entity
  if (type === 'all' || type === 'entity') {
    if (
      MOCK_ENTITY.primaryName.toLowerCase().includes(lowerQuery) ||
      MOCK_ENTITY.city?.toLowerCase().includes(lowerQuery) ||
      MOCK_ENTITY.slug.toLowerCase().includes(lowerQuery)
    ) {
      results.push({
        type: 'entity' as const,
        entity: MOCK_ENTITY,
        relevanceScore: 0.8,
      });
    }
  }

  const searchResponse: SearchResponse = {
    query,
    results,
    totalCount: results.length,
    page: 1,
    pageSize: 20,
  };

  return NextResponse.json(searchResponse);
}
