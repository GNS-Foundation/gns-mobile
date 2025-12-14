// ===========================================
// GNS World Browser - API Client
// ===========================================

import { GnsIdentity, GnsEntity, SearchResponse, ApiResponse } from './types';

const API_BASE_URL = process.env.NEXT_PUBLIC_API_URL || 'https://gns-browser-production.up.railway.app';

// Generic fetch wrapper with error handling
async function fetchApi<T>(
  endpoint: string,
  options?: RequestInit
): Promise<ApiResponse<T>> {
  try {
    const response = await fetch(`${API_BASE_URL}${endpoint}`, {
      ...options,
      headers: {
        'Content-Type': 'application/json',
        ...options?.headers,
      },
    });

    if (!response.ok) {
      const errorData = await response.json().catch(() => ({}));
      return {
        success: false,
        error: errorData.message || `HTTP ${response.status}: ${response.statusText}`,
      };
    }

    const json = await response.json();
    
    // API returns {success, data} - unwrap it
    if (json.success && json.data) {
      return {
        success: true,
        data: json.data,
      };
    }
    
    // Fallback for non-wrapped responses
    return {
      success: true,
      data: json,
    };
  } catch (error) {
    console.error(`API Error [${endpoint}]:`, error);
    return {
      success: false,
      error: error instanceof Error ? error.message : 'Network error',
    };
  }
}

// ===========================================
// Identity Endpoints
// ===========================================

/**
 * Get identity by @handle
 * GET /web/profile/{handle}
 */
export async function getIdentityByHandle(handle: string): Promise<ApiResponse<GnsIdentity>> {
  // Remove @ prefix if present
  const cleanHandle = handle.replace(/^@/, '');
  return fetchApi<GnsIdentity>(`/web/profile/${cleanHandle}`);
}

/**
 * Get identity by public key
 * GET /records/{publicKey}
 */
export async function getIdentityByPublicKey(publicKey: string): Promise<ApiResponse<GnsIdentity>> {
  return fetchApi<GnsIdentity>(`/records/${publicKey}`);
}

/**
 * Resolve handle to public key
 * GET /aliases/{handle}
 */
export async function resolveHandle(handle: string): Promise<ApiResponse<{ publicKey: string }>> {
  const cleanHandle = handle.replace(/^@/, '');
  return fetchApi<{ publicKey: string }>(`/aliases/${cleanHandle}`);
}

/**
 * Check if handle is available
 * GET /aliases?check={handle}
 */
export async function checkHandleAvailability(handle: string): Promise<ApiResponse<{ available: boolean }>> {
  const cleanHandle = handle.replace(/^@/, '');
  return fetchApi<{ available: boolean }>(`/aliases?check=${cleanHandle}`);
}

// ===========================================
// Entity Endpoints
// ===========================================

/**
 * Get entity by slug
 * GET /web/entity/{slug}
 */
export async function getEntityBySlug(slug: string): Promise<ApiResponse<GnsEntity>> {
  return fetchApi<GnsEntity>(`/web/entity/${slug}`);
}

/**
 * Get entities by type
 * GET /web/entities?type={type}&limit={limit}
 */
export async function getEntitiesByType(
  type: string,
  limit = 20,
  offset = 0
): Promise<ApiResponse<GnsEntity[]>> {
  return fetchApi<GnsEntity[]>(`/web/entities?type=${type}&limit=${limit}&offset=${offset}`);
}

/**
 * Get featured entities (for homepage)
 * GET /web/featured
 */
export async function getFeaturedEntities(): Promise<ApiResponse<GnsEntity[]>> {
  return fetchApi<GnsEntity[]>('/web/featured');
}

// ===========================================
// Search Endpoints
// ===========================================

/**
 * Search identities and entities
 * GET /web/search?q={query}&type={type}&limit={limit}
 */
export async function search(
  query: string,
  options?: {
    type?: 'all' | 'identity' | 'entity';
    limit?: number;
    page?: number;
  }
): Promise<ApiResponse<SearchResponse>> {
  const params = new URLSearchParams({
    q: query,
    type: options?.type || 'all',
    limit: String(options?.limit || 20),
  });
  
  // Note: Changed from /search to /web/search
  return fetchApi<SearchResponse>(`/web/search?${params}`);
}

// ===========================================
// Stats Endpoints
// ===========================================

/**
 * Get global GNS stats
 * GET /web/stats
 */
export async function getGlobalStats(): Promise<ApiResponse<{
  totalIdentities: number;
  totalEntities: number;
  totalBreadcrumbs: number;
  activeToday: number;
}>> {
  return fetchApi('/web/stats');
}

// ===========================================
// Mock Data (for development without backend)
// ===========================================

export const MOCK_IDENTITY: GnsIdentity = {
  publicKey: '26b9c6a8eda4130a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a',
  gnsId: 'gns_26b9c6a8',
  handle: 'caterve',
  displayName: 'Camilo Ayerbe',
  bio: 'Building identity through presence. Creator of GNS.',
  avatarUrl: undefined,
  links: [
    { type: 'github', url: 'https://github.com/caterve' },
    { type: 'twitter', url: 'https://twitter.com/caterve' },
    { type: 'website', url: 'https://gns.xyz' },
  ],
  trustScore: 85,
  breadcrumbCount: 106,
  daysSinceCreation: 45,
  lastLocationRegion: 'Rome, Italy',
  lastSeen: new Date().toISOString(),
  isVerified: true,
  createdAt: '2024-10-27T00:00:00Z',
};

export const MOCK_ENTITY: GnsEntity = {
  publicKey: '7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a2b3c4d5e6f7a8b',
  entityType: 'website',
  slug: 'colosseum',
  primaryName: 'Colosseum',
  description: 'Ancient Roman amphitheater in the center of Rome, Italy.',
  city: 'Rome',
  country: 'Italy',
  tags: ['landmark', 'history', 'rome', 'ancient'],
  imageUrl: 'https://upload.wikimedia.org/wikipedia/commons/thumb/d/de/Colosseo_2020.jpg/1280px-Colosseo_2020.jpg',
  trustScore: 99,
  visitorCount: 12453,
  recentVisitors: [],
  createdAt: '2024-01-01T00:00:00Z',
  isVerified: true,
  isClaimed: true,
  owner: undefined,
};

/**
 * Use mock data when API is unavailable
 */
export async function getIdentityWithFallback(handle: string): Promise<GnsIdentity | null> {
  const response = await getIdentityByHandle(handle);
  
  if (response.success && response.data) {
    const data = response.data as any;
    // Add computed/default fields
    return {
      ...data,
      handle: data.handle?.replace(/^@/, '') || handle,
      avatarUrl: data.avatarUrl || data.avatar || undefined,
      isVerified: data.isVerified ?? data.verified ?? false,
      daysSinceCreation: data.createdAt 
        ? Math.floor((Date.now() - new Date(data.createdAt).getTime()) / (1000 * 60 * 60 * 24))
        : 0,
      lastLocationRegion: data.lastLocationRegion || 'Unknown',
    };
  }
  
  // In development, return mock data
  if (process.env.NODE_ENV === 'development') {
    console.log('Using mock data for handle:', handle);
    return { ...MOCK_IDENTITY, handle };
  }
  
  return null;
}

export async function getEntityWithFallback(slug: string): Promise<GnsEntity | null> {
  const response = await getEntityBySlug(slug);
  
  if (response.success && response.data) {
    return response.data;
  }
  
  // In development, return mock data
  if (process.env.NODE_ENV === 'development') {
    console.log('Using mock data for entity:', slug);
    return { ...MOCK_ENTITY, slug };
  }
  
  return null;
}
