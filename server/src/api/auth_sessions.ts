// ===========================================
// GNS NODE - AUTH SESSIONS API
// Secure QR-based browser pairing
// 
// Location: routes/auth_sessions.ts
// ===========================================

import { Router, Request, Response } from 'express';
import { randomBytes } from 'crypto';
import { verifySignature, isValidPublicKey, canonicalJson } from '../lib/crypto';
import * as db from '../lib/db';
import { ApiResponse } from '../types';
import { connectedClients } from './messages';

const router = Router();

// ===========================================
// IN-MEMORY SESSION STORE
// In production, use Redis or database
// ===========================================

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
  encryptionKey?: string;
  sessionToken?: string;
  approvedAt?: number;
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
// POST /auth/session/request
// Browser requests a new login session
// Returns QR code data
// ===========================================
router.post('/request', async (req: Request, res: Response) => {
  try {
    const { browserInfo } = req.body;

    // Generate session ID and challenge
    const sessionId = randomBytes(16).toString('hex');
    const challenge = randomBytes(32).toString('hex');

    // Session expires in 5 minutes
    const now = Date.now();
    const expiresAt = now + 5 * 60 * 1000;

    // Store pending session
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

    // Return QR data
    return res.status(201).json({
      success: true,
      data: {
        sessionId,
        challenge,
        expiresAt,
        expiresIn: 300, // seconds
        // QR code should encode this URL:
        qrData: JSON.stringify({
          type: 'gns_browser_auth',
          version: 1,
          sessionId,
          challenge,
          browserInfo: session.browserInfo,
          expiresAt,
        }),
      },
    } as ApiResponse);

  } catch (error) {
    console.error('POST /auth/session/request error:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
    } as ApiResponse);
  }
});

// ===========================================
// GET /auth/session/:id
// Browser polls for session status
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

    // Check if expired
    if (Date.now() > session.expiresAt) {
      session.status = 'expired';
      pendingSessions.delete(sessionId);
      return res.status(410).json({
        success: false,
        error: 'Session expired',
      } as ApiResponse);
    }

    // Return current status
    const responseData: any = {
      sessionId: session.id,
      status: session.status,
      expiresAt: session.expiresAt,
    };

    // If approved, include the session data
    if (session.status === 'approved') {
      responseData.publicKey = session.publicKey;
      responseData.handle = session.handle;
      responseData.encryptionKey = session.encryptionKey;
      responseData.sessionToken = session.sessionToken;
      responseData.approvedAt = session.approvedAt;

      // Clean up after browser receives approval
      // Give 30 seconds to receive before cleanup
      setTimeout(() => {
        pendingSessions.delete(sessionId);
      }, 30000);
    }

    return res.json({
      success: true,
      data: responseData,
    } as ApiResponse);

  } catch (error) {
    console.error('GET /auth/session/:id error:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
    } as ApiResponse);
  }
});

// ===========================================
// POST /auth/session/approve
// Mobile approves a browser session
// ===========================================
router.post('/approve', async (req: Request, res: Response) => {
  try {
    const { sessionId, publicKey, signature, deviceInfo } = req.body;

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

    // Find session
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
    // Mobile must sign: canonicalJson({ sessionId, challenge, publicKey, action: 'approve' })
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

    // Get user's identity info (handle, encryption key)
    const identity = await db.getIdentity(publicKey);

    if (!identity) {
      return res.status(404).json({
        success: false,
        error: 'Identity not found - register on mobile app first',
      } as ApiResponse);
    }

    // Get handle if exists
    const alias = await db.getAliasByIdentity(publicKey);

    // Generate session token
    const sessionToken = randomBytes(32).toString('hex');

    // Update session
    session.status = 'approved';
    session.publicKey = publicKey.toLowerCase();
    session.handle = alias?.handle || undefined;
    session.encryptionKey = identity.encryption_key;
    session.sessionToken = sessionToken;
    session.approvedAt = Date.now();

    // Store browser session in database for future validation
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

    // Notify browser via WebSocket if connected
    // (Browser might be polling, but WebSocket is faster)
    const browserWs = connectedClients.get(`session:${sessionId}`);
    if (browserWs) {
      browserWs.forEach(ws => {
        ws.send(JSON.stringify({
          type: 'session_approved',
          sessionId,
          publicKey: session.publicKey,
          handle: session.handle,
          sessionToken,
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
      },
    } as ApiResponse);

  } catch (error) {
    console.error('POST /auth/session/approve error:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
    } as ApiResponse);
  }
});

// ===========================================
// POST /auth/session/reject
// Mobile rejects a browser session
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

    // Verify ownership (signature optional for rejection)
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
    console.error('POST /auth/session/reject error:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
    } as ApiResponse);
  }
});

// ===========================================
// DELETE /auth/session/:token
// Browser logs out / revokes session
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
    console.error('DELETE /auth/session/:token error:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
    } as ApiResponse);
  }
});

// ===========================================
// GET /auth/sessions
// Mobile: List active browser sessions
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
        sessionToken: s.sessionToken.substring(0, 8) + '...', // Partial for security
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
// Mobile: Revoke all browser sessions
// ===========================================
router.post('/revoke-all', async (req: Request, res: Response) => {
  try {
    const publicKey = req.headers['x-gns-publickey'] as string;
    const signature = req.headers['x-gns-signature'] as string;

    if (!publicKey || !isValidPublicKey(publicKey)) {
      return res.status(401).json({
        success: false,
        error: 'Missing or invalid public key',
      } as ApiResponse);
    }

    // TODO: Verify signature for this sensitive operation

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
// Use this to protect browser-specific endpoints
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

    if (!session || !session.isActive) {
      return res.status(401).json({
        success: false,
        error: 'Invalid or expired session',
      } as ApiResponse);
    }

    // Check expiry
    if (new Date() > session.expiresAt) {
      await db.revokeBrowserSession(sessionToken);
      return res.status(401).json({
        success: false,
        error: 'Session expired',
      } as ApiResponse);
    }

    // Update last used
    await db.updateBrowserSessionLastUsed(sessionToken);

    // Attach to request
    (req as any).browserSession = session;
    (req as any).gnsPublicKey = session.publicKey;

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
