// ===========================================
// GNS HOME HUB - RECOVERY MANAGER
// Handles identity recovery via TV PIN
// ===========================================

import { EventEmitter } from 'events';
import { RecoverySession } from './types';
import { generatePin, sha256 } from './crypto';
import * as vaultStorage from './vault-storage';

const PIN_EXPIRY_MS = 5 * 60 * 1000; // 5 minutes
const MAX_ATTEMPTS = 3;

export class RecoveryManager extends EventEmitter {
  private sessions: Map<string, RecoverySession & { attempts: number }> = new Map();
  private displayCallback?: (pin: string, handle: string) => void;

  constructor() {
    super();
    
    // Clean up expired sessions every minute
    setInterval(() => this.cleanupExpiredSessions(), 60000);
  }

  /**
   * Set callback to display PIN on TV
   */
  setDisplayCallback(callback: (pin: string, handle: string) => void): void {
    this.displayCallback = callback;
  }

  /**
   * Initiate recovery for a handle
   */
  initiateRecovery(
    claimedHandle: string,
    newDeviceKey: string
  ): { success: boolean; sessionId?: string; error?: string } {
    // Find vault by handle
    const vault = vaultStorage.getVaultByHandle(claimedHandle);
    
    if (!vault) {
      console.log(`❌ Recovery failed: No vault for @${claimedHandle}`);
      return { 
        success: false, 
        error: `No backup found for @${claimedHandle}` 
      };
    }

    // Check if there's already an active session for this handle
    for (const [id, session] of this.sessions) {
      if (session.claimedHandle === claimedHandle && !session.verified) {
        // Cancel old session
        this.sessions.delete(id);
      }
    }

    // Generate session
    const sessionId = sha256(`${claimedHandle}:${newDeviceKey}:${Date.now()}`).substring(0, 32);
    const pin = generatePin();
    
    const session: RecoverySession & { attempts: number } = {
      id: sessionId,
      claimedHandle,
      newDeviceKey,
      pin,
      expiresAt: Date.now() + PIN_EXPIRY_MS,
      verified: false,
      attempts: 0,
    };
    
    this.sessions.set(sessionId, session);
    
    // Display PIN on TV
    if (this.displayCallback) {
      this.displayCallback(pin, claimedHandle);
    }
    
    this.emit('recovery_started', { handle: claimedHandle, sessionId });
    console.log(`🔐 Recovery initiated for @${claimedHandle}`);
    console.log(`📺 PIN: ${pin} (expires in 5 minutes)`);
    
    return { success: true, sessionId };
  }

  /**
   * Verify PIN and complete recovery
   */
  verifyPin(
    sessionId: string,
    pin: string
  ): { 
    success: boolean; 
    backup?: { encryptedSeed: string; nonce: string; snapshot?: string };
    error?: string;
  } {
    const session = this.sessions.get(sessionId);
    
    if (!session) {
      return { success: false, error: 'Session not found or expired' };
    }
    
    // Check expiry
    if (Date.now() > session.expiresAt) {
      this.sessions.delete(sessionId);
      return { success: false, error: 'PIN expired' };
    }
    
    // Check attempts
    session.attempts++;
    if (session.attempts > MAX_ATTEMPTS) {
      this.sessions.delete(sessionId);
      console.log(`❌ Recovery failed: Too many attempts for @${session.claimedHandle}`);
      return { success: false, error: 'Too many attempts' };
    }
    
    // Verify PIN
    if (pin !== session.pin) {
      console.log(`❌ Wrong PIN for @${session.claimedHandle} (attempt ${session.attempts}/${MAX_ATTEMPTS})`);
      return { 
        success: false, 
        error: `Wrong PIN (${MAX_ATTEMPTS - session.attempts} attempts remaining)` 
      };
    }
    
    // PIN correct! Get the backup
    const vault = vaultStorage.getVaultByHandle(session.claimedHandle);
    if (!vault) {
      return { success: false, error: 'Vault not found' };
    }
    
    const backup = vaultStorage.getBackupForRecovery(vault.publicKey);
    if (!backup) {
      return { success: false, error: 'Backup not found' };
    }
    
    // Mark session as verified
    session.verified = true;
    
    // Clear display
    if (this.displayCallback) {
      this.displayCallback('', ''); // Clear PIN from TV
    }
    
    this.emit('recovery_completed', { handle: session.claimedHandle });
    console.log(`✅ Recovery completed for @${session.claimedHandle}`);
    
    // Clean up session after a delay (allow retry of download)
    setTimeout(() => {
      this.sessions.delete(sessionId);
    }, 60000);
    
    return { success: true, backup };
  }

  /**
   * Cancel a recovery session
   */
  cancelRecovery(sessionId: string): boolean {
    const session = this.sessions.get(sessionId);
    if (!session) return false;
    
    this.sessions.delete(sessionId);
    
    // Clear display
    if (this.displayCallback) {
      this.displayCallback('', '');
    }
    
    console.log(`❌ Recovery cancelled for @${session.claimedHandle}`);
    return true;
  }

  /**
   * Get session status (without PIN)
   */
  getSessionStatus(sessionId: string): {
    exists: boolean;
    handle?: string;
    expiresIn?: number;
    verified?: boolean;
    attemptsRemaining?: number;
  } {
    const session = this.sessions.get(sessionId);
    
    if (!session) {
      return { exists: false };
    }
    
    return {
      exists: true,
      handle: session.claimedHandle,
      expiresIn: Math.max(0, session.expiresAt - Date.now()),
      verified: session.verified,
      attemptsRemaining: MAX_ATTEMPTS - session.attempts,
    };
  }

  /**
   * Clean up expired sessions
   */
  private cleanupExpiredSessions(): void {
    const now = Date.now();
    let cleaned = 0;
    
    for (const [id, session] of this.sessions) {
      if (now > session.expiresAt && !session.verified) {
        this.sessions.delete(id);
        cleaned++;
      }
    }
    
    if (cleaned > 0) {
      console.log(`🧹 Cleaned up ${cleaned} expired recovery session(s)`);
    }
  }
}

// Singleton
let recoveryManager: RecoveryManager | null = null;

export function getRecoveryManager(): RecoveryManager {
  if (!recoveryManager) {
    recoveryManager = new RecoveryManager();
  }
  return recoveryManager;
}
