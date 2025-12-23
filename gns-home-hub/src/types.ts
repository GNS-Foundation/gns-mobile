// ===========================================
// GNS HOME HUB - TYPE DEFINITIONS
// ===========================================

// ===========================================
// Hub Identity & Configuration
// ===========================================

export interface HubIdentity {
  publicKey: string;
  secretKey: string;
  name: string;
  createdAt: string;
}

export interface HubConfig {
  name: string;
  owner: string;        // Owner's GNS public key
  relayUrl: string;     // GNS relay server URL
  localPort: number;    // Local HTTP server port
  autoSync: boolean;    // Auto-sync when phones detected
  devices: DeviceConfig[];
}

// ===========================================
// User Vaults (Identity Backup)
// ===========================================

export interface UserVault {
  publicKey: string;          // User's GNS public key
  handle?: string;            // @handle if known
  role: 'owner' | 'member';
  permissions: DevicePermissions;
  
  // Encrypted backup (only user can decrypt)
  backup: {
    version: number;
    encryptedSeed: string;    // Encrypted identity seed
    nonce: string;
    lastSync: string;
    
    // Full state snapshot (also encrypted)
    snapshot?: {
      nonce: string;
      ciphertext: string;
    };
  };
  
  createdAt: string;
  lastSeen: string;
}

export interface DevicePermissions {
  [deviceId: string]: string[];  // deviceId -> allowed actions
}

// ===========================================
// IoT Devices
// ===========================================

export interface DeviceConfig {
  id: string;
  name: string;
  type: 'tv' | 'lights' | 'thermostat' | 'lock' | 'camera' | 'custom';
  brand: string;
  protocol: 'samsungtvws' | 'hue' | 'mqtt' | 'http' | 'custom';
  
  // Connection details
  connection: {
    ip?: string;
    port?: number;
    mac?: string;           // For Wake-on-LAN
    token?: string;         // API token if needed
    bridgeIp?: string;      // For Hue bridge
  };
  
  capabilities: string[];   // ['power', 'volume', 'apps', etc.]
  status: DeviceStatus;
}

export interface DeviceStatus {
  online: boolean;
  lastSeen: string;
  state: Record<string, any>;  // Device-specific state
}

// ===========================================
// GNS Messages (IoT Commands)
// ===========================================

export interface HomeCommand {
  type: 'home_command';
  id: string;
  from: string;             // Sender's public key
  to: string;               // home@handle (facet address)
  timestamp: number;
  
  payload: {
    device: string;         // Device ID
    action: string;         // 'power', 'volume', etc.
    value?: any;            // Action-specific value
  };
  
  signature: string;
}

export interface HomeQuery {
  type: 'home_query';
  id: string;
  from: string;
  to: string;
  timestamp: number;
  
  payload: {
    device?: string;        // Specific device or all
    query: 'status' | 'list' | 'capabilities';
  };
  
  signature: string;
}

export interface HomeResponse {
  type: 'home_response';
  id: string;
  from: string;             // Hub's public key
  to: string;               // Requester's public key
  replyTo: string;          // Original message ID
  timestamp: number;
  
  payload: {
    success: boolean;
    data?: any;
    error?: string;
  };
  
  signature: string;
}

// ===========================================
// Recovery Flow
// ===========================================

export interface RecoveryRequest {
  type: 'recovery_request';
  id: string;
  claimedHandle: string;    // "I am @camiloayerbe"
  newDeviceKey: string;     // Temporary public key
  timestamp: number;
}

export interface RecoverySession {
  id: string;
  claimedHandle: string;
  newDeviceKey: string;
  pin: string;              // 6-digit PIN shown on TV
  expiresAt: number;        // PIN valid for 5 minutes
  verified: boolean;
}

// ===========================================
// Sync Protocol
// ===========================================

export interface SyncRequest {
  type: 'sync_request';
  from: string;
  lastSync?: string;        // ISO timestamp of last sync
  signature: string;
}

export interface SyncDelta {
  type: 'sync_delta';
  since: string;
  changes: {
    breadcrumbs?: any[];
    contacts?: any[];
    facets?: any[];
    messages?: any[];
  };
}

export interface BackupPackage {
  version: number;
  createdAt: string;
  ownerPublicKey: string;
  
  // The crown jewels (encrypted with user's recovery key)
  identitySeed: {
    nonce: string;
    ciphertext: string;
  };
  
  // Full state snapshot
  snapshot: {
    handle?: string;
    facets: any[];
    contacts: any[];
    breadcrumbs: {
      count: number;
      chainHead: string;
      blocks: any[];
    };
  };
}

// ===========================================
// Samsung TV Specific
// ===========================================

export interface SamsungTVState {
  power: 'on' | 'off' | 'unknown';
  volume: number;
  muted: boolean;
  currentApp?: string;
  input?: string;
}

export type SamsungTVAction = 
  | 'power'
  | 'volume_up'
  | 'volume_down'
  | 'mute'
  | 'channel_up'
  | 'channel_down'
  | 'home'
  | 'back'
  | 'enter'
  | 'up'
  | 'down'
  | 'left'
  | 'right'
  | 'play'
  | 'pause'
  | 'stop'
  | 'app';

// ===========================================
// Hub Events
// ===========================================

export type HubEvent = 
  | { type: 'device_online'; device: string }
  | { type: 'device_offline'; device: string }
  | { type: 'user_arrived'; publicKey: string }
  | { type: 'user_left'; publicKey: string }
  | { type: 'command_executed'; device: string; action: string }
  | { type: 'recovery_started'; handle: string }
  | { type: 'recovery_completed'; handle: string }
  | { type: 'backup_synced'; publicKey: string };
