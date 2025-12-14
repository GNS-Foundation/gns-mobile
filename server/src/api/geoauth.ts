// ===========================================
// GNS NODE - GEOAUTH API (Chapter 8)
// /auth endpoints for geospatial payment authorization
//
// Location: src/api/geoauth.ts
//
// ENDPOINTS:
//   POST /auth/request    - Merchant creates auth session
//   POST /auth/submit     - User submits GeoAuth token
//   GET  /auth/status/:id - Check auth status
//   POST /auth/use/:id    - Mark auth as used
//
// FLOW:
//   1. Merchant: POST /auth/request → gets auth_id
//   2. User opens GNS app, sees auth request
//   3. User: Drops breadcrumb → creates GeoAuth token
//   4. User: POST /auth/submit → submits token
//   5. Merchant: GET /auth/status/:id → checks if authorized
//   6. Merchant: POST /auth/use/:id → marks as used
// ===========================================

import { Router, Request, Response } from 'express';
import { isValidPublicKey, verifySignature } from '../lib/crypto';
import * as db from '../lib/db';
import { ApiResponse } from '../types';
import { v4 as uuidv4 } from 'uuid';
import { createHash } from 'crypto';

const router = Router();

// ===========================================
// MERCHANT AUTH MIDDLEWARE
// ===========================================

interface MerchantRequest extends Request {
  merchantId?: string;
}

/**
 * Verify merchant API key
 * Header: X-GNS-Merchant-Key: <api_key>
 */
const verifyMerchantAuth = async (
  req: MerchantRequest,
  res: Response,
  next: Function
) => {
  try {
    const apiKey = req.headers['x-gns-merchant-key'] as string;

    if (!apiKey) {
      return res.status(401).json({
        success: false,
        error: 'Missing X-GNS-Merchant-Key header',
      } as ApiResponse);
    }

    // Hash the API key to look up merchant
    const keyHash = createHash('sha256').update(apiKey).digest('hex');

    // Look up merchant by API key hash
    const merchant = await db.getMerchantByApiKey(keyHash);

    if (!merchant) {
      return res.status(401).json({
        success: false,
        error: 'Invalid API key',
      } as ApiResponse);
    }

    if (merchant.status !== 'active') {
      return res.status(403).json({
        success: false,
        error: 'Merchant account is not active',
      } as ApiResponse);
    }

    req.merchantId = merchant.merchant_id;
    next();
  } catch (error) {
    console.error('Merchant auth error:', error);
    res.status(401).json({ success: false, error: 'Authentication failed' });
  }
};

// ===========================================
// USER AUTH MIDDLEWARE
// ===========================================

interface UserRequest extends Request {
  gnsPublicKey?: string;
}

const verifyUserAuth = async (
  req: UserRequest,
  res: Response,
  next: Function
) => {
  try {
    const publicKey = (req.headers['x-gns-publickey'] as string)?.toLowerCase();

    if (!publicKey || !isValidPublicKey(publicKey)) {
      return res.status(401).json({
        success: false,
        error: 'Missing or invalid X-GNS-PublicKey header',
      } as ApiResponse);
    }

    req.gnsPublicKey = publicKey;
    next();
  } catch (error) {
    console.error('User auth error:', error);
    res.status(401).json({ success: false, error: 'Authentication failed' });
  }
};

// ===========================================
// POST /auth/request
// Merchant creates a new auth session
// ===========================================

router.post('/request', verifyMerchantAuth, async (req: MerchantRequest, res: Response) => {
  try {
    const {
      payment_hash,
      amount,
      currency,
      description,
      expires_in_seconds = 300,  // Default 5 minutes
      require_location = false,
      max_distance_meters = 1000,
    } = req.body;

    const merchantId = req.merchantId!;

    // Validate payment_hash
    if (!payment_hash || typeof payment_hash !== 'string') {
      return res.status(400).json({
        success: false,
        error: 'Missing or invalid payment_hash',
      } as ApiResponse);
    }

    // Validate payment_hash is hex (SHA256 = 64 chars)
    if (!/^[a-fA-F0-9]{64}$/.test(payment_hash)) {
      return res.status(400).json({
        success: false,
        error: 'payment_hash must be a 64-character hex string (SHA256)',
      } as ApiResponse);
    }

    // Generate auth ID
    const authId = uuidv4();

    // Calculate expiration
    const expiresAt = new Date(Date.now() + expires_in_seconds * 1000).toISOString();

    // Get merchant name for display
    const merchant = await db.getMerchant(merchantId);

    // Create session
    const session = await db.createGeoAuthSession({
      auth_id: authId,
      merchant_id: merchantId,
      merchant_name: merchant?.name,
      payment_hash: payment_hash.toLowerCase(),
      amount: amount?.toString(),
      currency: currency,
      expires_at: expiresAt,
    });

    console.log(`🔐 GeoAuth session created: ${authId.substring(0, 8)}... for merchant ${merchantId}`);

    return res.status(201).json({
      success: true,
      data: {
        auth_id: authId,
        status: 'pending',
        expires_at: expiresAt,
        // URL for user to authorize (can be opened in GNS app)
        authorize_url: `gns://auth/${authId}`,
        // Or web fallback
        web_url: `https://gns.app/auth/${authId}`,
      },
      message: 'Authorization session created',
    } as ApiResponse);

  } catch (error) {
    console.error('POST /auth/request error:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
    } as ApiResponse);
  }
});

// ===========================================
// POST /auth/submit
// User submits GeoAuth token
// ===========================================

router.post('/submit', verifyUserAuth, async (req: UserRequest, res: Response) => {
  try {
    const { auth_id, envelope } = req.body;
    const userPk = req.gnsPublicKey!;

    if (!auth_id) {
      return res.status(400).json({
        success: false,
        error: 'Missing auth_id',
      } as ApiResponse);
    }

    if (!envelope) {
      return res.status(400).json({
        success: false,
        error: 'Missing envelope',
      } as ApiResponse);
    }

    // Get the session
    const session = await db.getGeoAuthSession(auth_id);

    if (!session) {
      return res.status(404).json({
        success: false,
        error: 'Auth session not found',
      } as ApiResponse);
    }

    // Check if expired
    if (new Date(session.expires_at) < new Date()) {
      return res.status(410).json({
        success: false,
        error: 'Auth session expired',
      } as ApiResponse);
    }

    // Check if already authorized
    if (session.status !== 'pending') {
      return res.status(409).json({
        success: false,
        error: `Auth session already ${session.status}`,
      } as ApiResponse);
    }

    // Verify envelope signature
    const senderKey = envelope.fromPublicKey?.toLowerCase();
    if (senderKey !== userPk) {
      return res.status(403).json({
        success: false,
        error: 'Envelope sender does not match authenticated user',
      } as ApiResponse);
    }

    // Verify payload type
    if (envelope.payloadType !== 'gns/auth.geo') {
      return res.status(400).json({
        success: false,
        error: 'Invalid payload type. Expected gns/auth.geo',
      } as ApiResponse);
    }

    // TODO: Verify Ed25519 signature
    // const isValid = verifySignature(senderKey, envelope, envelope.signature);
    // if (!isValid) {
    //   return res.status(401).json({ success: false, error: 'Invalid signature' });
    // }

    // Extract H3 cell from envelope metadata (if available unencrypted)
    // Note: For GeoAuth, the h3_cell should be in envelope metadata, not encrypted
    const h3Cell = envelope.metadata?.h3Cell || 'unknown';

    // Verify payment_hash binding (if available in metadata)
    const envelopePaymentHash = envelope.metadata?.paymentHash?.toLowerCase();
    if (envelopePaymentHash && envelopePaymentHash !== session.payment_hash) {
      return res.status(400).json({
        success: false,
        error: 'Payment hash mismatch',
      } as ApiResponse);
    }

    // Authorize the session
    const updated = await db.authorizeGeoAuthSession(auth_id, {
      user_pk: userPk,
      envelope_json: envelope,
      h3_cell: h3Cell,
    });

    if (!updated) {
      return res.status(500).json({
        success: false,
        error: 'Failed to authorize session',
      } as ApiResponse);
    }

    console.log(`✅ GeoAuth authorized: ${auth_id.substring(0, 8)}... by ${userPk.substring(0, 8)}...`);

    return res.json({
      success: true,
      data: {
        auth_id: auth_id,
        status: 'authorized',
        authorized_at: updated.authorized_at,
      },
      message: 'Authorization successful',
    } as ApiResponse);

  } catch (error) {
    console.error('POST /auth/submit error:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
    } as ApiResponse);
  }
});

// ===========================================
// GET /auth/status/:authId
// Check authorization status (for merchant polling)
// ===========================================

router.get('/status/:authId', verifyMerchantAuth, async (req: MerchantRequest, res: Response) => {
  try {
    const { authId } = req.params;
    const merchantId = req.merchantId!;

    const session = await db.getGeoAuthSession(authId);

    if (!session) {
      return res.status(404).json({
        success: false,
        error: 'Auth session not found',
      } as ApiResponse);
    }

    // Verify merchant owns this session
    if (session.merchant_id !== merchantId) {
      return res.status(403).json({
        success: false,
        error: 'Access denied',
      } as ApiResponse);
    }

    // Check if expired
    if (session.status === 'pending' && new Date(session.expires_at) < new Date()) {
      // Update status to expired
      await db.expireGeoAuthSession(authId);
      session.status = 'expired';
    }

    return res.json({
      success: true,
      data: {
        auth_id: session.auth_id,
        status: session.status,
        payment_hash: session.payment_hash,
        created_at: session.created_at,
        expires_at: session.expires_at,
        authorized_at: session.authorized_at,
        // Only include user info if authorized
        ...(session.status === 'authorized' && {
          user_pk: session.user_pk,
          h3_cell: session.h3_cell,
        }),
      },
    } as ApiResponse);

  } catch (error) {
    console.error('GET /auth/status/:authId error:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
    } as ApiResponse);
  }
});

// ===========================================
// POST /auth/use/:authId
// Mark authorization as used (prevents replay)
// ===========================================

router.post('/use/:authId', verifyMerchantAuth, async (req: MerchantRequest, res: Response) => {
  try {
    const { authId } = req.params;
    const merchantId = req.merchantId!;

    const session = await db.getGeoAuthSession(authId);

    if (!session) {
      return res.status(404).json({
        success: false,
        error: 'Auth session not found',
      } as ApiResponse);
    }

    // Verify merchant owns this session
    if (session.merchant_id !== merchantId) {
      return res.status(403).json({
        success: false,
        error: 'Access denied',
      } as ApiResponse);
    }

    // Check current status
    if (session.status !== 'authorized') {
      return res.status(400).json({
        success: false,
        error: `Cannot use auth with status: ${session.status}`,
      } as ApiResponse);
    }

    // Mark as used
    await db.markGeoAuthUsed(authId);

    console.log(`🔒 GeoAuth used: ${authId.substring(0, 8)}...`);

    return res.json({
      success: true,
      data: {
        auth_id: authId,
        status: 'used',
      },
      message: 'Authorization marked as used',
    } as ApiResponse);

  } catch (error) {
    console.error('POST /auth/use/:authId error:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
    } as ApiResponse);
  }
});

// ===========================================
// GET /auth/pending
// User gets their pending auth requests
// ===========================================

router.get('/pending', verifyUserAuth, async (req: UserRequest, res: Response) => {
  try {
    const userPk = req.gnsPublicKey!;

    // Get sessions that match user's breadcrumb location
    // This is a simplified version - real implementation would
    // check h3 cell proximity
    const sessions = await db.getPendingGeoAuthSessions();

    return res.json({
      success: true,
      data: {
        sessions: sessions.map(s => ({
          auth_id: s.auth_id,
          merchant_name: s.merchant_name,
          amount: s.amount,
          currency: s.currency,
          expires_at: s.expires_at,
        })),
        total: sessions.length,
      },
    } as ApiResponse);

  } catch (error) {
    console.error('GET /auth/pending error:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
    } as ApiResponse);
  }
});

export default router;

// ===========================================
// ADDITIONAL DB FUNCTIONS NEEDED
// Add to db_payments.ts
// ===========================================

/*
export async function getMerchantByApiKey(keyHash: string): Promise<any | null> {
  const { data, error } = await getSupabase()
    .from('geoauth_merchants')
    .select('*')
    .eq('api_key_hash', keyHash)
    .single();

  if (error && error.code !== 'PGRST116') {
    console.error('Error fetching merchant by API key:', error);
    throw error;
  }

  return data;
}

export async function getMerchant(merchantId: string): Promise<any | null> {
  const { data, error } = await getSupabase()
    .from('geoauth_merchants')
    .select('*')
    .eq('merchant_id', merchantId)
    .single();

  if (error && error.code !== 'PGRST116') {
    console.error('Error fetching merchant:', error);
    throw error;
  }

  return data;
}

export async function expireGeoAuthSession(authId: string): Promise<void> {
  const { error } = await getSupabase()
    .from('geoauth_sessions')
    .update({ status: 'expired' })
    .eq('auth_id', authId);

  if (error) {
    console.error('Error expiring geoauth session:', error);
    throw error;
  }
}

export async function getPendingGeoAuthSessions(): Promise<DbGeoAuthSession[]> {
  const { data, error } = await getSupabase()
    .from('geoauth_sessions')
    .select('*')
    .eq('status', 'pending')
    .gt('expires_at', new Date().toISOString())
    .order('created_at', { ascending: false })
    .limit(50);

  if (error) {
    console.error('Error fetching pending geoauth sessions:', error);
    throw error;
  }

  return data as DbGeoAuthSession[];
}
*/
