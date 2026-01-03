// ===========================================
// GNS NETWORK - TYPE DEFINITIONS
// ===========================================

// ===========================================
// GNS Record (Identity Manifest)
// ===========================================
export interface GnsRecord {
  version: number;
  identity: string;
  handle?: string | null;
  encryption_key?: string | null;
  modules: GnsModule[];
  endpoints: GnsEndpoint[];
  epoch_roots: string[];
  trust_score: number;
  breadcrumb_count: number;
  created_at: string;
  updated_at: string;
}

export interface GnsModule {
  id: string;
  schema: string;
  name?: string;
  description?: string;
  data_url?: string;
  is_public: boolean;
  config?: Record<string, unknown>;
}

export interface GnsEndpoint {
  type: 'direct' | 'relay' | 'onion';
  protocol: 'quic' | 'wss' | 'https';
  address: string;
  port?: number;
  priority: number;           // Lower = preferred
  is_active: boolean;
}

// ===========================================
// Signed Record (for API)
// ===========================================
export interface SignedRecord {
  pk_root: string;            // 64 hex chars
  record_json: GnsRecord;
  signature: string;          // 128 hex chars (Ed25519)
}

// ===========================================
// Alias Claim
// ===========================================
export interface AliasClaim {
  handle: string;             // Without @, lowercase
  identity: string;           // PK_root
  proof: PoTProof;
  signature: string;
}

export interface PoTProof {
  breadcrumb_count: number;   // Must be >= 100
  trust_score: number;        // Must be >= 20
  first_breadcrumb_at: string;
  latest_epoch_root?: string;
}

// ===========================================
// Epoch Header
// ===========================================
export interface EpochHeader {
  identity: string;           // PK_root
  epoch_index: number;
  start_time: string;
  end_time: string;
  merkle_root: string;
  block_count: number;
  prev_epoch_hash?: string | null;
  signature: string;
  epoch_hash: string;
}

export interface SignedEpoch {
  pk_root: string;
  epoch: EpochHeader;
  signature: string;
}

// ===========================================
// Messages
// ===========================================
export interface GnsMessage {
  id?: string;
  from_pk: string;
  to_pk: string;
  payload: string;            // Encrypted, base64
  signature: string;
  created_at?: string;
}

// ===========================================
// API Responses
// ===========================================
export interface ApiResponse<T = unknown> {
  success: boolean;
  data?: T;
  error?: string;
  message?: string;
}

export interface PaginatedResponse<T> extends ApiResponse<T[]> {
  total: number;
  page: number;
  limit: number;
  has_more: boolean;
}

// ===========================================
// Database Types
// ===========================================
export interface DbRecord {
  pk_root: string;
  record_json: GnsRecord;
  signature: string;
  version: number;
  handle?: string | null;
  encryption_key?: string | null;
  trust_score: number;
  breadcrumb_count: number;
  created_at: string;
  updated_at: string;
}

export interface DbAlias {
  handle: string;
  pk_root: string;
  pot_proof: PoTProof;
  signature: string;
  created_at: string;
  verified: boolean;
}

export interface DbEpoch {
  id: number;
  pk_root: string;
  epoch_index: number;
  merkle_root: string;
  start_time: string;
  end_time: string;
  block_count: number;
  prev_epoch_hash?: string | null;
  signature: string;
  epoch_hash: string;
  published_at: string;
}

export interface DbMessage {
  id: string;
  from_pk: string;
  to_pk: string;
  payload: string;
  signature: string;
  envelope?: any;           // Full envelope JSON
  thread_id?: string;       // Thread grouping
  status?: string;          // pending, delivered, read, expired
  fetched_at?: string;      // When recipient fetched
  relay_id?: string;
  created_at: string;
  delivered_at?: string;
  expires_at: string;
}

// ===========================================
// Payments
// ===========================================
export interface DbPaymentIntent {
  id: string;
  payment_id: string;
  from_pk: string;
  to_pk: string;
  envelope_json: any;
  payload_type: string;
  currency?: string;
  route_type?: string;
  status: 'pending' | 'delivered' | 'accepted' | 'rejected' | 'expired';
  created_at: string;
  delivered_at?: string;
  acked_at?: string;
  expires_at?: string;
}

export interface DbPaymentAck {
  id: string;
  payment_id: string;
  from_pk: string;
  status: 'accepted' | 'rejected';
  reason?: string;
  envelope_json?: any;
  created_at: string;
}

export interface DbGeoAuthSession {
  id: string;
  auth_id: string;
  merchant_id: string;
  merchant_name?: string;
  payment_hash: string;
  amount?: string;
  currency?: string;
  status: 'pending' | 'authorized' | 'expired' | 'rejected' | 'used';
  user_pk?: string;
  envelope_json?: any;
  h3_cell?: string;
  created_at: string;
  authorized_at?: string;
  expires_at: string;
}

export interface DbBrowserSession {
  id: number;
  session_token: string;
  public_key: string;
  handle?: string;
  browser_info: string;
  device_info?: any;
  created_at: Date;
  expires_at: Date;
  last_used_at: Date;
  is_active: boolean;
  revoked_at?: Date;
}


// ===========================================
// Sync / Gossip
// ===========================================
export interface SyncState {
  peer_id: string;
  peer_url: string;
  last_sync_at?: string;
  last_records_at?: string;
  last_aliases_at?: string;
  last_epochs_at?: string;
  status: 'active' | 'inactive' | 'error';
  error_count: number;
}

export interface SyncPayload {
  type: 'records' | 'aliases' | 'epochs';
  items: unknown[];
  since?: string;
  node_id: string;
}

// ===========================================
// Auth
// ===========================================
export interface AuthChallenge {
  nonce: string;
  timestamp: string;
  expires_at: string;
}

export interface AuthRequest {
  pk: string;
  nonce: string;
  timestamp: string;
  signature: string;
}

// ===========================================
// Constants
// ===========================================
export const GNS_CONSTANTS = {
  MIN_BREADCRUMBS_FOR_HANDLE: 100,
  MIN_TRUST_SCORE_FOR_HANDLE: 20,
  HANDLE_RESERVATION_DAYS: 30,
  MESSAGE_EXPIRY_DAYS: 7,
  PK_LENGTH: 64,
  SIGNATURE_LENGTH: 128,
  HANDLE_MIN_LENGTH: 3,
  HANDLE_MAX_LENGTH: 20,
  HANDLE_REGEX: /^[a-z0-9_]{3,20}$/,
} as const;

export const RESERVED_HANDLES = [
  'admin', 'root', 'system', 'gns', 'layer',
  'browser', 'support', 'help', 'official', 'verified'
] as const;

export interface DbBreadcrumb {
  id: number;
  pk_root: string;
  payload: string;      // Encrypted JSON
  signature: string;
  created_at: string;
}
