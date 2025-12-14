// ===========================================
// GNS World Browser - Type Definitions
// ===========================================

// Identity Types
export interface GnsIdentity {
  publicKey: string;
  gnsId: string;
  handle?: string;
  displayName?: string;
  bio?: string;
  avatarUrl?: string;
  links: ProfileLink[];
  trustScore: number;
  breadcrumbCount: number;
  daysSinceCreation: number;
  lastLocationRegion?: string;
  lastSeen?: string;
  isVerified: boolean;
  createdAt: string;
}

export interface ProfileLink {
  type: 'website' | 'github' | 'twitter' | 'linkedin' | 'custom';
  label?: string;
  url: string;
  icon?: string;
}

// Entity Types
export type EntityType = 'person' | 'place' | 'business' | 'artwork' | 'device' | 'media' | 'website';

export interface GnsEntity {
  publicKey: string;
  entityType: EntityType;
  slug: string;
  primaryName: string;
  description?: string;
  city?: string;
  country?: string;
  tags: string[];
  imageUrl?: string;
  trustScore: number;
  visitorCount: number;
  recentVisitors: GnsIdentity[];
  createdAt: string;
  isVerified: boolean;
  isClaimed: boolean;
  owner?: GnsIdentity;
}

// Search Types
export interface SearchResult {
  type: 'identity' | 'entity';
  identity?: GnsIdentity;
  entity?: GnsEntity;
  relevanceScore: number;
}

export interface SearchResponse {
  query: string;
  results: SearchResult[];
  totalCount: number;
  page: number;
  pageSize: number;
}

// API Response Types
export interface ApiResponse<T> {
  success: boolean;
  data?: T;
  error?: string;
  message?: string;
}

// Trust Level Helpers
export type TrustLevel = 'genesis' | 'present' | 'established' | 'trusted' | 'verified';

export function getTrustLevel(score: number): TrustLevel {
  if (score >= 90) return 'verified';
  if (score >= 70) return 'trusted';
  if (score >= 50) return 'established';
  if (score >= 20) return 'present';
  return 'genesis';
}

export function getTrustEmoji(score: number): string {
  const level = getTrustLevel(score);
  switch (level) {
    case 'verified': return '💎';
    case 'trusted': return '⭐';
    case 'established': return '🌟';
    case 'present': return '✨';
    default: return '🌱';
  }
}

export function getTrustColor(score: number): string {
  if (score >= 70) return 'text-gns-secondary';
  if (score >= 40) return 'text-gns-accent';
  return 'text-gns-text-muted-light';
}

// Link Type Helpers
export function getLinkIcon(type: string): string {
  switch (type) {
    case 'github': return '🐙';
    case 'twitter': return '🐦';
    case 'linkedin': return '💼';
    case 'website': return '🌐';
    default: return '🔗';
  }
}

// Format Helpers
export function formatNumber(num: number): string {
  if (num >= 1000000) return `${(num / 1000000).toFixed(1)}M`;
  if (num >= 1000) return `${(num / 1000).toFixed(1)}K`;
  return num.toString();
}

export function formatTimeAgo(dateString: string): string {
  const date = new Date(dateString);
  const now = new Date();
  const seconds = Math.floor((now.getTime() - date.getTime()) / 1000);
  
  if (seconds < 60) return 'just now';
  if (seconds < 3600) return `${Math.floor(seconds / 60)}m ago`;
  if (seconds < 86400) return `${Math.floor(seconds / 3600)}h ago`;
  if (seconds < 604800) return `${Math.floor(seconds / 86400)}d ago`;
  
  return date.toLocaleDateString();
}

export function truncateAddress(address: string, chars = 6): string {
  if (address.length <= chars * 2) return address;
  return `${address.slice(0, chars)}...${address.slice(-chars)}`;
}
