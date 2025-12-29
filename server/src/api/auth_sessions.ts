// ===========================================
// GNS NODE - AUTH SESSIONS API v2
// Secure QR-based browser pairing WITH MESSAGE SYNC
// 
// Phase B: Mobile sends pre-decrypted message history
// ===========================================

import { Router, Request, Response } from 'express';
import { randomBytes } from 'crypto';
import { verifySignature, isValidPublicKey, canonicalJson } from '../lib/crypto';
import * as db from '../lib/db';
import { ApiResponse } from '../types';
import { connectedClients } from './messages';

const router = Router();

// ===========================================
// TYPES
// ===========================================

interface DecryptedMessage {
  id: string;
  direction: 'incoming' | 'outgoing';
  text: string;
  timestamp: number;
  status?: string;
}

interface ConversationSync {
  withPublicKey: string;
  withHandle?: string;
  messages: DecryptedMessage[];
  lastSyncedAt: number;
}

interface MessageSync {
  conversations: ConversationSync[];
  totalMessages: number;
  syncedAt: number;
}

interface PendingSession {
  id: string;
  challenge: string;
  browserInfo: string;
  createdAt: number;
  expiresAt: number;
  status: 'pending' | 'approved' | 'rejected' | 'expired';
  // Filled when approved:
  publicKey?: string;
  handle?: string;
  sessionToken?: string;
  approvedAt?: number;
  // NEW: Session encryption keys (temporary, per-session)
  sessionEncryptionKey?: string;
  sessionEncryptionPrivateKey?: string;
  // NEW: Pre-decrypted message history from mobile
  messageSync?: MessageSync;
}

const pendingSessions = new Map<string, PendingSession>();

// Clean expired sessions every minute
setInterval(() => {
  const now = Date.now();
  for (const [id, session] of pendingSessions) {
    if (now > session.expiresAt) {
      pendingSessions.delete(id);
    }
  }
}, 60000);

// ===========================================
// POST /auth/sessions/request
// Browser requests a new login session
// ===========================================
router.post('/request', async (req: Request, res: Response) => {
  try {
    const { browserInfo } = req.body;

    const sessionId = randomBytes(16).toString('hex');
    const challenge = randomBytes(32).toString('hex');

    const now = Date.now();
    const expiresAt = now + 5 * 60 * 1000; // 5 minutes

    const session: PendingSession = {
      id: sessionId,
      challenge,
      browserInfo: browserInfo || 'Unknown Browser',
      createdAt: now,
      expiresAt,
      status: 'pending',
    };

    pendingSessions.set(sessionId, session);

    console.log(`🔐 Auth session created: ${sessionId.substring(0, 8)}...`);

    return res.status(201).json({
      success: true,
      data: {
        sessionId,
        challenge,
        expiresAt,
        expiresIn: 300,
        qrData: JSON.stringify({
          type: 'gns_browser_auth',
          version: 2,  // Bumped version for message sync support
          sessionId,
          challenge,
          browserInfo: session.browserInfo,
          expiresAt,
        }),
      },
    } as ApiResponse);

  } catch (error) {
    console.error('POST /auth/sessions/request error:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
    } as ApiResponse);
  }
});

// ===========================================
// GET /auth/sessions/:id
// Browser polls for session status
// NOW RETURNS: Pre-decrypted message history!
// ===========================================
router.get('/:id', async (req: Request, res: Response) => {
  try {
    const sessionId = req.params.id;
    const session = pendingSessions.get(sessionId);

    if (!session) {
      return res.status(404).json({
        success: false,
        error: 'Session not found or expired',
      } as ApiResponse);
    }

    if (Date.now() > session.expiresAt) {
      session.status = 'expired';
      pendingSessions.delete(sessionId);
      return res.status(410).json({
        success: false,
        error: 'Session expired',
      } as ApiResponse);
    }

    const responseData: any = {
      sessionId: session.id,
      status: session.status,
      expiresAt: session.expiresAt,
    };

    // If approved, include ALL session data
    if (session.status === 'approved') {
      responseData.publicKey = session.publicKey;
      responseData.handle = session.handle;
      responseData.sessionToken = session.sessionToken;
      responseData.approvedAt = session.approvedAt;

      // Mobile's permanent encryption key for dual encryption
      responseData.encryptionKey = session.sessionEncryptionKey;  // Browser expects 'encryptionKey'


      // NEW: Pre-decrypted message history from mobile
      if (session.messageSync) {
        responseData.messageSync = session.messageSync;
        console.log(`📨 Sending ${session.messageSync.totalMessages} pre-decrypted messages to browser`);
      }

      // Clean up after browser receives approval
      setTimeout(() => {
        pendingSessions.delete(sessionId);
      }, 30000);
    }

    return res.json({
      success: true,
      data: responseData,
    } as ApiResponse);

  } catch (error) {
    console.error('GET /auth/sessions/:id error:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
    } as ApiResponse);
  }
});

// ===========================================
// POST /auth/sessions/approve
// Mobile approves a browser session
// NOW ACCEPTS: Pre-decrypted message history!
// ===========================================
router.post('/approve', async (req: Request, res: Response) => {
  try {
    const {
      sessionId,
      publicKey,
      signature,
      deviceInfo,
      // Mobile's permanent X25519 encryption key for dual encryption
      encryptionKey,
      // Pre-decrypted message history
      messageSync,
    } = req.body;

    // Validate inputs
    if (!sessionId || !publicKey || !signature) {
      return res.status(400).json({
        success: false,
        error: 'Missing required fields: sessionId, publicKey, signature',
      } as ApiResponse);
    }

    if (!isValidPublicKey(publicKey)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid public key format',
      } as ApiResponse);
    }

    const session = pendingSessions.get(sessionId);

    if (!session) {
      return res.status(404).json({
        success: false,
        error: 'Session not found or expired',
      } as ApiResponse);
    }

    if (session.status !== 'pending') {
      return res.status(409).json({
        success: false,
        error: `Session already ${session.status}`,
      } as ApiResponse);
    }

    if (Date.now() > session.expiresAt) {
      session.status = 'expired';
      return res.status(410).json({
        success: false,
        error: 'Session expired',
      } as ApiResponse);
    }

    // Verify signature
    const signedData = {
      action: 'approve',
      challenge: session.challenge,
      publicKey: publicKey.toLowerCase(),
      sessionId,
    };

    const isValid = verifySignature(
      publicKey,
      canonicalJson(signedData),
      signature
    );

    if (!isValid) {
      console.warn(`❌ Invalid signature for session ${sessionId.substring(0, 8)}...`);
      return res.status(401).json({
        success: false,
        error: 'Invalid signature - approval rejected',
      } as ApiResponse);
    }

    // Get user's identity info
    const identity = await db.getIdentity(publicKey);

    if (!identity) {
      return res.status(404).json({
        success: false,
        error: 'Identity not found - register on mobile app first',
      } as ApiResponse);
    }

    const alias = await db.getAliasByIdentity(publicKey);
    const sessionToken = randomBytes(32).toString('hex');

    // Update session with approval data
    session.status = 'approved';
    session.publicKey = publicKey.toLowerCase();
    session.handle = alias?.handle || undefined;
    session.sessionToken = sessionToken;
    session.approvedAt = Date.now();

    // Store mobile's permanent encryption key for dual encryption
    if (encryptionKey) {
      session.sessionEncryptionKey = encryptionKey;  // Store as sessionEncryptionKey for backwards compat
      console.log(`🔐 Mobile encryption key stored for ${sessionId.substring(0, 8)}`);
    }

    // NEW: Store pre-decrypted message history
    if (messageSync && messageSync.conversations) {
      session.messageSync = {
        conversations: messageSync.conversations,
        totalMessages: messageSync.conversations.reduce(
          (sum: number, c: ConversationSync) => sum + c.messages.length,
          0
        ),
        syncedAt: Date.now(),
      };
      console.log(`📨 Stored ${session.messageSync.totalMessages} pre-decrypted messages`);
    }

    // Store browser session in database
    await db.createBrowserSession({
      sessionToken,
      publicKey: publicKey.toLowerCase(),
      handle: session.handle,
      browserInfo: session.browserInfo,
      deviceInfo,
      createdAt: new Date(),
      expiresAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000), // 7 days
    });

    console.log(`✅ Auth session approved: ${sessionId.substring(0, 8)}... by @${session.handle || publicKey.substring(0, 8)}`);
    if (session.messageSync) {
      console.log(`   📨 With ${session.messageSync.totalMessages} synced messages`);
    }

    // Notify browser via WebSocket if connected
    const browserWs = connectedClients.get(`session:${sessionId}`);
    if (browserWs) {
      browserWs.forEach(ws => {
        ws.send(JSON.stringify({
          type: 'session_approved',
          sessionId,
          publicKey: session.publicKey,
          handle: session.handle,
          sessionToken,
          encryptionKey: session.sessionEncryptionKey,  // Browser expects 'encryptionKey'
          messageSync: session.messageSync,
        }));
      });
    }

    return res.json({
      success: true,
      message: 'Browser session approved',
      data: {
        sessionId,
        browserInfo: session.browserInfo,
        approvedAt: session.approvedAt,
        messagesSynced: session.messageSync?.totalMessages || 0,
      },
    } as ApiResponse);

  } catch (error) {
    console.error('POST /auth/sessions/approve error:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
    } as ApiResponse);
  }
});

// ===========================================
// POST /auth/sessions/reject
// ===========================================
router.post('/reject', async (req: Request, res: Response) => {
  try {
    const { sessionId, publicKey, signature } = req.body;

    const session = pendingSessions.get(sessionId);

    if (!session) {
      return res.status(404).json({
        success: false,
        error: 'Session not found',
      } as ApiResponse);
    }

    if (publicKey && signature) {
      const signedData = {
        action: 'reject',
        challenge: session.challenge,
        publicKey: publicKey.toLowerCase(),
        sessionId,
      };

      const isValid = verifySignature(publicKey, canonicalJson(signedData), signature);
      if (!isValid) {
        return res.status(401).json({
          success: false,
          error: 'Invalid signature',
        } as ApiResponse);
      }
    }

    session.status = 'rejected';

    console.log(`❌ Auth session rejected: ${sessionId.substring(0, 8)}...`);

    return res.json({
      success: true,
      message: 'Session rejected',
    } as ApiResponse);

  } catch (error) {
    console.error('POST /auth/sessions/reject error:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
    } as ApiResponse);
  }
});

// ===========================================
// DELETE /auth/sessions/:token
// Browser logs out
// ===========================================
router.delete('/:token', async (req: Request, res: Response) => {
  try {
    const sessionToken = req.params.token;

    await db.revokeBrowserSession(sessionToken);

    return res.json({
      success: true,
      message: 'Session revoked',
    } as ApiResponse);

  } catch (error) {
    console.error('DELETE /auth/sessions/:token error:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
    } as ApiResponse);
  }
});

// ===========================================
// GET /auth/sessions (list active sessions)
// ===========================================
router.get('/', async (req: Request, res: Response) => {
  try {
    const publicKey = req.headers['x-gns-publickey'] as string;

    if (!publicKey || !isValidPublicKey(publicKey)) {
      return res.status(401).json({
        success: false,
        error: 'Missing or invalid X-GNS-PublicKey header',
      } as ApiResponse);
    }

    const sessions = await db.getBrowserSessions(publicKey);

    return res.json({
      success: true,
      data: sessions.map(s => ({
        sessionToken: s.sessionToken.substring(0, 8) + '...',
        browserInfo: s.browserInfo,
        createdAt: s.createdAt,
        lastUsedAt: s.lastUsedAt,
        isActive: s.isActive,
      })),
    } as ApiResponse);

  } catch (error) {
    console.error('GET /auth/sessions error:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
    } as ApiResponse);
  }
});

// ===========================================
// POST /auth/sessions/revoke-all
// ===========================================
router.post('/revoke-all', async (req: Request, res: Response) => {
  try {
    const publicKey = req.headers['x-gns-publickey'] as string;

    if (!publicKey || !isValidPublicKey(publicKey)) {
      return res.status(401).json({
        success: false,
        error: 'Missing or invalid public key',
      } as ApiResponse);
    }

    const count = await db.revokeAllBrowserSessions(publicKey);

    console.log(`🔒 Revoked ${count} browser sessions for ${publicKey.substring(0, 8)}...`);

    return res.json({
      success: true,
      message: `Revoked ${count} browser session(s)`,
      data: { revokedCount: count },
    } as ApiResponse);

  } catch (error) {
    console.error('POST /auth/sessions/revoke-all error:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
    } as ApiResponse);
  }
});

// ===========================================
// MIDDLEWARE: Verify Browser Session
// ===========================================
export async function verifyBrowserSession(
  req: Request,
  res: Response,
  next: Function
) {
  try {
    const sessionToken = req.headers['x-gns-session'] as string;

    if (!sessionToken) {
      return res.status(401).json({
        success: false,
        error: 'Missing X-GNS-Session header',
      } as ApiResponse);
    }

    const session = await db.getBrowserSession(sessionToken);

    if (!session || session.status !== 'approved') {
      return res.status(401).json({
        success: false,
        error: 'Invalid or expired session',
      } as ApiResponse);
    }

    if (new Date() > new Date(session.expires_at)) {
      await db.revokeBrowserSession(sessionToken);
      return res.status(401).json({
        success: false,
        error: 'Session expired',
      } as ApiResponse);
    }

    await db.updateBrowserSessionLastUsed(sessionToken);

    (req as any).browserSession = session;
    (req as any).gnsPublicKey = session.public_key;

    next();
  } catch (error) {
    console.error('Session verification error:', error);
    return res.status(500).json({
      success: false,
      error: 'Session verification failed',
    } as ApiResponse);
  }
}

export default router;
