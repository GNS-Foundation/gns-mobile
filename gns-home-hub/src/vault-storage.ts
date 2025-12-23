// ===========================================
// GNS HOME HUB - VAULT STORAGE
// Stores encrypted identity backups for users
// ===========================================

import * as fs from 'fs';
import * as path from 'path';
import { UserVault, BackupPackage, DevicePermissions } from './types';
import { sha256 } from './crypto';

const DATA_DIR = process.env.GNS_DATA_DIR || './data';
const VAULTS_FILE = path.join(DATA_DIR, 'vaults.json');

// In-memory cache
let vaults: Map<string, UserVault> = new Map();

// ===========================================
// Initialization
// ===========================================

export function initVaultStorage(): void {
  // Ensure data directory exists
  if (!fs.existsSync(DATA_DIR)) {
    fs.mkdirSync(DATA_DIR, { recursive: true });
    console.log(`📁 Created data directory: ${DATA_DIR}`);
  }
  
  // Load existing vaults
  if (fs.existsSync(VAULTS_FILE)) {
    try {
      const data = JSON.parse(fs.readFileSync(VAULTS_FILE, 'utf-8'));
      vaults = new Map(Object.entries(data));
      console.log(`🔐 Loaded ${vaults.size} user vault(s)`);
    } catch (error) {
      console.error('Failed to load vaults:', error);
      vaults = new Map();
    }
  }
}

function saveVaults(): void {
  const data = Object.fromEntries(vaults);
  fs.writeFileSync(VAULTS_FILE, JSON.stringify(data, null, 2));
}

// ===========================================
// Vault Operations
// ===========================================

/**
 * Create or update a user vault
 */
export function upsertVault(
  publicKey: string,
  data: Partial<UserVault>
): UserVault {
  const pk = publicKey.toLowerCase();
  const existing = vaults.get(pk);
  
  const vault: UserVault = {
    publicKey: pk,
    handle: data.handle || existing?.handle,
    role: data.role || existing?.role || 'member',
    permissions: data.permissions || existing?.permissions || {},
    backup: data.backup || existing?.backup || {
      version: 1,
      encryptedSeed: '',
      nonce: '',
      lastSync: new Date().toISOString(),
    },
    createdAt: existing?.createdAt || new Date().toISOString(),
    lastSeen: new Date().toISOString(),
  };
  
  vaults.set(pk, vault);
  saveVaults();
  
  console.log(`🔐 Vault ${existing ? 'updated' : 'created'} for ${pk.substring(0, 16)}...`);
  return vault;
}

/**
 * Get a user's vault
 */
export function getVault(publicKey: string): UserVault | null {
  return vaults.get(publicKey.toLowerCase()) || null;
}

/**
 * Get all vaults
 */
export function getAllVaults(): UserVault[] {
  return Array.from(vaults.values());
}

/**
 * Get vault by handle
 */
export function getVaultByHandle(handle: string): UserVault | null {
  for (const vault of vaults.values()) {
    if (vault.handle?.toLowerCase() === handle.toLowerCase()) {
      return vault;
    }
  }
  return null;
}

/**
 * Check if user has permission for device action
 */
export function hasPermission(
  publicKey: string,
  deviceId: string,
  action: string
): boolean {
  const vault = getVault(publicKey);
  if (!vault) return false;
  
  // Owner has all permissions
  if (vault.role === 'owner') return true;
  
  const devicePerms = vault.permissions[deviceId];
  if (!devicePerms) return false;
  
  return devicePerms.includes('all') || devicePerms.includes(action);
}

/**
 * Update user's backup
 */
export function updateBackup(
  publicKey: string,
  backup: UserVault['backup']
): void {
  const vault = getVault(publicKey);
  if (!vault) {
    throw new Error('Vault not found');
  }
  
  vault.backup = {
    ...backup,
    lastSync: new Date().toISOString(),
  };
  vault.lastSeen = new Date().toISOString();
  
  vaults.set(publicKey.toLowerCase(), vault);
  saveVaults();
  
  console.log(`💾 Backup updated for ${publicKey.substring(0, 16)}...`);
}

/**
 * Store full backup package
 */
export function storeBackupPackage(
  publicKey: string,
  pkg: BackupPackage
): void {
  const vault = getVault(publicKey);
  if (!vault) {
    throw new Error('Vault not found');
  }
  
  // Store the full package as snapshot
  const snapshotJson = JSON.stringify(pkg);
  
  vault.backup = {
    version: pkg.version,
    encryptedSeed: pkg.identitySeed.ciphertext,
    nonce: pkg.identitySeed.nonce,
    lastSync: new Date().toISOString(),
    snapshot: {
      nonce: pkg.identitySeed.nonce, // Reuse nonce or generate new
      ciphertext: snapshotJson, // In real impl, this would be encrypted
    },
  };
  
  vaults.set(publicKey.toLowerCase(), vault);
  saveVaults();
  
  console.log(`📦 Full backup package stored for ${publicKey.substring(0, 16)}...`);
}

/**
 * Update last seen timestamp
 */
export function touchVault(publicKey: string): void {
  const vault = getVault(publicKey);
  if (vault) {
    vault.lastSeen = new Date().toISOString();
    vaults.set(publicKey.toLowerCase(), vault);
    saveVaults();
  }
}

/**
 * Set user permissions
 */
export function setPermissions(
  publicKey: string,
  permissions: DevicePermissions
): void {
  const vault = getVault(publicKey);
  if (!vault) {
    throw new Error('Vault not found');
  }
  
  vault.permissions = permissions;
  vaults.set(publicKey.toLowerCase(), vault);
  saveVaults();
  
  console.log(`🔑 Permissions updated for ${publicKey.substring(0, 16)}...`);
}

/**
 * Delete a vault (dangerous!)
 */
export function deleteVault(publicKey: string): boolean {
  const pk = publicKey.toLowerCase();
  const existed = vaults.has(pk);
  vaults.delete(pk);
  
  if (existed) {
    saveVaults();
    console.log(`🗑️ Vault deleted for ${pk.substring(0, 16)}...`);
  }
  
  return existed;
}

// ===========================================
// Recovery Support
// ===========================================

/**
 * Get backup for recovery (called after PIN verification)
 */
export function getBackupForRecovery(publicKey: string): {
  encryptedSeed: string;
  nonce: string;
  snapshot?: string;
} | null {
  const vault = getVault(publicKey);
  if (!vault?.backup) return null;
  
  return {
    encryptedSeed: vault.backup.encryptedSeed,
    nonce: vault.backup.nonce,
    snapshot: vault.backup.snapshot?.ciphertext,
  };
}

// Initialize on import
initVaultStorage();
