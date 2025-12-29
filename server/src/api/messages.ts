// ===========================================
// GNS NODE - MESSAGES API (PHASE C - BIDIRECTIONAL SYNC)
// 
// Enhanced WebSocket with device-type routing:
// - Mobile connections: device=mobile (decrypts messages)
// - Browser connections: device=browser (display only)
// - Real-time sync between devices
// 
// Endpoints:
// - POST /messages/send (session auth) - Send dual-encrypted message
// - GET /messages/inbox (session auth) - Fetch inbox
// - GET /messages/conversation (session auth) - Fetch conversation
// - + Legacy endpoints for backward compatibility
// ===========================================

import { Router, Request, Response } from 'express';
import { messageSchema, pkRootSchema } from '../lib/validation';
import { verifyMessage, verifySignature, isValidPublicKey, canonicalJson } from '../lib/crypto';
import * as db from '../lib/db';
import { ApiResponse, DbMessage } from '../types';
import { WebSocketServer, WebSocket } from 'ws';
import { IncomingMessage } from 'http';
import { Server } from 'http';
import echoBot from '../services/echo_bot';

const router = Router();

// ===========================================
// SESSION TOKEN VALIDATION
// ===========================================

interface AuthenticatedRequest extends Request {
  gnsPublicKey?: string;
  gnsSession?: string;
}

/**
 * Verify session token from QR pairing
 */
const verifySessionAuth = async (
  req: AuthenticatedRequest,
  res: Response,
  next: Function
) => {
  try {
    const sessionToken = req.headers['x-gns-session'] as string;
    const publicKey = (req.headers['x-gns-publickey'] as string)?.toLowerCase();

    if (sessionToken && publicKey) {
      // Validate session token exists in database
      const session = await db.getBrowserSession(sessionToken);

      if (session && session.public_key?.toLowerCase() === publicKey && session.status === 'approved') {
        req.gnsPublicKey = publicKey;
        req.gnsSession = sessionToken;
        return next();
      }
    }

    // Fallback to legacy auth
    return verifyGnsAuth(req, res, next);
  } catch (error) {
    console.error('Session auth error:', error);
    return verifyGnsAuth(req, res, next);
  }
};

/**
 * Legacy GNS authentication headers
 */
const verifyGnsAuth = async (
  req: AuthenticatedRequest,
  res: Response,
  next: Function
) => {
  try {
    const publicKey = (req.headers['x-gns-publickey'] as string)?.toLowerCase();
    const identity = (req.headers['x-gns-identity'] as string)?.toLowerCase();

    const pk = publicKey || identity;

    if (!pk || !isValidPublicKey(pk)) {
      return res.status(401).json({
        success: false,
        error: 'Missing or invalid X-GNS-PublicKey header',
      } as ApiResponse);
    }

    req.gnsPublicKey = pk;
    next();
  } catch (error) {
    console.error('Auth error:', error);
    res.status(401).json({ success: false, error: 'Authentication failed' });
  }
};

// ===========================================
// PHASE C: ENHANCED WEBSOCKET STATE
// ===========================================

// Connection with device metadata
interface GnsConnection {
  ws: WebSocket;
  publicKey: string;
  deviceType: 'mobile' | 'browser' | 'unknown';
  sessionToken?: string;
  connectedAt: Date;
  isAlive: boolean;
}

// Map: publicKey -> array of connections (can have multiple devices)
const connections = new Map<string, GnsConnection[]>();

// Legacy export for backward compatibility
const connectedClients = new Map<string, Set<WebSocket>>();
export { connectedClients };

// ===========================================
// PHASE C: CONNECTION HELPERS
// ===========================================

function addConnection(publicKey: string, conn: GnsConnection) {
  const pk = publicKey.toLowerCase();

  // Add to new structure
  const existing = connections.get(pk) || [];
  existing.push(conn);
  connections.set(pk, existing);

  // Also maintain legacy structure
  if (!connectedClients.has(pk)) {
    connectedClients.set(pk, new Set());
  }
  connectedClients.get(pk)!.add(conn.ws);
}

function removeConnection(publicKey: string, ws: WebSocket) {
  const pk = publicKey.toLowerCase();

  // Remove from new structure
  const existing = connections.get(pk) || [];
  const filtered = existing.filter(c => c.ws !== ws);
  if (filtered.length > 0) {
    connections.set(pk, filtered);
  } else {
    connections.delete(pk);
  }

  // Remove from legacy structure
  const clients = connectedClients.get(pk);
  if (clients) {
    clients.delete(ws);
    if (clients.size === 0) {
      connectedClients.delete(pk);
    }
  }
}

function getConnections(publicKey: string): GnsConnection[] {
  return connections.get(publicKey.toLowerCase()) || [];
}

function getMobileConnections(publicKey: string): GnsConnection[] {
  return getConnections(publicKey).filter(c => c.deviceType === 'mobile');
}

function getBrowserConnections(publicKey: string): GnsConnection[] {
  return getConnections(publicKey).filter(c => c.deviceType === 'browser');
}

function getConnectionStatus(publicKey: string): { mobile: boolean; browsers: number } {
  const conns = getConnections(publicKey);
  return {
    mobile: conns.some(c => c.deviceType === 'mobile'),
    browsers: conns.filter(c => c.deviceType === 'browser').length,
  };
}

function sendToConnection(conn: GnsConnection, message: any) {
  if (conn.ws.readyState === WebSocket.OPEN) {
    conn.ws.send(JSON.stringify(message));
  }
}

export function broadcastToUser(publicKey: string, message: any) {
  const conns = getConnections(publicKey);
  for (const conn of conns) {
    sendToConnection(conn, message);
  }
}

function broadcastConnectionStatus(publicKey: string) {
  const status = getConnectionStatus(publicKey);
  broadcastToUser(publicKey, {
    type: 'connection_status',
    data: status,
  });
}

// ===========================================
// GET /messages - Fetch pending messages (for MOBILE)
// ===========================================

router.get('/', verifyGnsAuth, async (req: AuthenticatedRequest, res: Response) => {
  try {
    const pk = req.gnsPublicKey!;
    const since = req.query.since as string | undefined;
    const limit = Math.min(parseInt(req.query.limit as string) || 100, 200);

    console.log(`📥 Fetching pending messages for: ${pk.substring(0, 16)}...`);

    // Get pending envelopes for this recipient
    const messages = await db.getPendingEnvelopes(pk, since, limit);

    console.log(`   Found ${messages.length} pending messages`);

    // Transform to envelope format expected by mobile
    const envelopes = messages.map((m: any) => ({
      id: m.id,
      fromPublicKey: m.from_pk,
      toPublicKeys: [m.to_pk],
      envelope: m.envelope,
      encryptedPayload: m.envelope?.encryptedPayload || m.payload,
      ephemeralPublicKey: m.envelope?.ephemeralPublicKey,
      nonce: m.envelope?.nonce,
      signature: m.envelope?.signature || m.signature,
      timestamp: new Date(m.created_at).getTime(),
      threadId: m.thread_id,
      payloadType: m.envelope?.payloadType || 'gns/text.plain',
    }));

    return res.json({
      success: true,
      messages: envelopes,  // For mobile app compatibility
      data: envelopes,      // For browser/other clients
      count: envelopes.length,
    } as ApiResponse);

  } catch (error) {
    console.error('GET /messages error:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
    } as ApiResponse);
  }
});

// ===========================================
// POST /messages/send - DUAL ENCRYPTED SEND
// ===========================================

/**
 * POST /messages/send
 * Send a dual-encrypted message (session token auth)
 * 
 * Body:
 *   to: recipient public key
 *   envelope: encrypted envelope with BOTH copies
 *   threadId: optional thread ID
 */
router.post('/send', verifySessionAuth, async (req: AuthenticatedRequest, res: Response) => {
  try {
    const { to, envelope, threadId } = req.body;
    const senderPk = req.gnsPublicKey!;

    if (!to || !isValidPublicKey(to)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid recipient public key',
      } as ApiResponse);
    }

    if (!envelope) {
      return res.status(400).json({
        success: false,
        error: 'Missing envelope',
      } as ApiResponse);
    }

    const toPk = to.toLowerCase();

    // Extract encryption fields from envelope
    const messageData = {
      from_pk: senderPk,
      to_pk: toPk,
      envelope: envelope,
      thread_id: threadId || envelope.threadId || null,

      // Recipient encryption (existing)
      encrypted_payload: envelope.encryptedPayload,
      ephemeral_public_key: envelope.ephemeralPublicKey,
      nonce: envelope.nonce,

      // Sender encryption (NEW - for dual encryption)
      sender_encrypted_payload: envelope.senderEncryptedPayload || null,
      sender_ephemeral_public_key: envelope.senderEphemeralPublicKey || null,
      sender_nonce: envelope.senderNonce || null,
    };

    // Store message with dual encryption
    const message = await db.createDualEncryptedMessage(messageData);

    console.log(`📧 DUAL encrypted message: ${senderPk.substring(0, 8)}... → ${toPk.substring(0, 8)}...`);
    console.log(`   Has sender copy: ${!!envelope.senderEncryptedPayload}`);

    // Notify recipient via WebSocket
    notifyRecipients([toPk], {
      type: 'message',
      from_pk: senderPk,
      envelope: envelope,
    });

    // ===========================================
    // PHASE C: Notify sender's OTHER devices
    // ===========================================

    // If sent from browser, notify mobile to decrypt & store
    const senderMobiles = getMobileConnections(senderPk);
    if (senderMobiles.length > 0) {
      console.log(`   📱 Notifying ${senderMobiles.length} mobile device(s) to sync`);
      for (const mobile of senderMobiles) {
        sendToConnection(mobile, {
          type: 'new_message_from_browser',
          messageId: message.id,
          conversationWith: toPk,
          envelope: envelope,
          timestamp: Date.now(),
        });
      }
    }

    return res.status(201).json({
      success: true,
      data: {
        messageId: message.id,
        threadId: message.thread_id,
        dualEncrypted: !!envelope.senderEncryptedPayload,
      },
      message: 'Message sent',
    } as ApiResponse);

  } catch (error) {
    console.error('POST /messages/send error:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
    } as ApiResponse);
  }
});

// ===========================================
// GET /messages/conversation - DUAL DECRYPTION
// ===========================================

/**
 * GET /messages/conversation
 * Fetch conversation with a specific user
 * Returns the correct encrypted copy for each message
 * 
 * Query:
 *   with: other party's public key
 *   limit: max messages (default 50)
 *   before: pagination cursor
 */
router.get('/conversation', verifySessionAuth, async (req: AuthenticatedRequest, res: Response) => {
  try {
    const pk = req.gnsPublicKey!;
    const withPk = (req.query.with as string)?.toLowerCase();
    const limit = Math.min(parseInt(req.query.limit as string) || 50, 200);
    const before = req.query.before as string | undefined;

    if (!withPk || !isValidPublicKey(withPk)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid "with" public key',
      } as ApiResponse);
    }

    // Get all messages between these two users
    const messages = await db.getConversation(pk, withPk, limit, before);

    // Transform messages - return correct encrypted copy based on direction
    const transformed = messages.map((m: any) => {
      const isOutgoing = m.from_pk?.toLowerCase() === pk;

      // Build envelope with correct encryption fields
      const envelope: any = {
        id: m.id,
        fromPublicKey: m.from_pk,
        toPublicKeys: [m.to_pk],
        timestamp: new Date(m.created_at).getTime(),
        threadId: m.thread_id,
      };


      if (isOutgoing && m.sender_encrypted_payload) {
        // OUTGOING: Use sender's encrypted copy (we can decrypt)
        envelope.encryptedPayload = m.sender_encrypted_payload;
        envelope.ephemeralPublicKey = m.sender_ephemeral_public_key;
        envelope.nonce = m.sender_nonce;
        envelope.isSenderCopy = true;
        // ✅ CRITICAL FIX: Also set sender fields so they're available at top level
        envelope.senderEncryptedPayload = m.sender_encrypted_payload;
        envelope.senderEphemeralPublicKey = m.sender_ephemeral_public_key;
        envelope.senderNonce = m.sender_nonce;
      } else {
        // INCOMING: Use recipient's encrypted copy OR legacy envelope OR payload column
        const env = m.envelope || {};
        envelope.encryptedPayload = env.encryptedPayload || m.encrypted_payload || m.payload;
        envelope.ephemeralPublicKey = env.ephemeralPublicKey || m.ephemeral_public_key;
        envelope.nonce = env.nonce || m.nonce;

        // DEBUG: Log what we found
        console.log(`📨 Loading incoming message ${m.id}:`);
        console.log(`   env.encryptedPayload: ${env.encryptedPayload ? 'YES' : 'NO'}`);
        console.log(`   m.encrypted_payload: ${m.encrypted_payload ? 'YES' : 'NO'}`);
        console.log(`   m.payload: ${m.payload ? 'YES' : 'NO'}`);
        console.log(`   Final encryptedPayload: ${envelope.encryptedPayload ? 'YES' : 'NO'}`);
      }


      return {
        id: m.id,
        from_pk: m.from_pk,
        to_pk: m.to_pk,
        created_at: m.created_at,
        thread_id: m.thread_id,
        isOutgoing: isOutgoing,
        envelope: envelope,
        // Also include at top level for easier access
        encryptedPayload: envelope.encryptedPayload,
        ephemeralPublicKey: envelope.ephemeralPublicKey,
        nonce: envelope.nonce,
        // ✅ FIX: Also include sender fields at top level for outgoing messages
        senderEncryptedPayload: envelope.senderEncryptedPayload || null,
        senderEphemeralPublicKey: envelope.senderEphemeralPublicKey || null,
        senderNonce: envelope.senderNonce || null,
      };
    });

    return res.json({
      success: true,
      data: transformed,
      count: transformed.length,
      hasMore: transformed.length >= limit,
    } as ApiResponse);

  } catch (error) {
    console.error('GET /messages/conversation error:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
    } as ApiResponse);
  }
});

// ===========================================
// GET /messages/inbox - INBOX WITH DUAL SUPPORT
// ===========================================

router.get('/inbox', verifySessionAuth, async (req: AuthenticatedRequest, res: Response) => {
  try {
    const pk = req.gnsPublicKey!;
    const limit = Math.min(parseInt(req.query.limit as string) || 50, 200);
    const since = req.query.since as string | undefined;

    // Get all messages where user is sender OR recipient
    const messages = await db.getAllUserMessages(pk, limit, since);

    // Transform with correct encryption copy AND fetch handles
    const transformed = await Promise.all(messages.map(async (m: any) => {
      const isOutgoing = m.from_pk?.toLowerCase() === pk;

      const envelope: any = m.envelope || {
        id: m.id,
        fromPublicKey: m.from_pk,
        toPublicKeys: [m.to_pk],
        timestamp: new Date(m.created_at).getTime(),
      };

      // Use sender copy for outgoing messages
      if (isOutgoing && m.sender_encrypted_payload) {
        envelope.encryptedPayload = m.sender_encrypted_payload;
        envelope.ephemeralPublicKey = m.sender_ephemeral_public_key;
        envelope.nonce = m.sender_nonce;
      } else {
        // ✅ INCOMING messages - use individual columns as fallback
        envelope.encryptedPayload = envelope.encryptedPayload || m.encrypted_payload || m.payload;
        envelope.ephemeralPublicKey = envelope.ephemeralPublicKey || m.ephemeral_public_key;
        envelope.nonce = envelope.nonce || m.nonce;
      }

      // ✅ FIX: Fetch handles for sender and recipient
      const fromAlias = await db.getAliasByPk(m.from_pk);
      const toAlias = await db.getAliasByPk(m.to_pk);

      return {
        ...envelope,
        id: m.id,
        from_pk: m.from_pk,
        from_handle: fromAlias?.handle,  // ✅ Add handle
        to_pk: m.to_pk,
        to_handle: toAlias?.handle,      // ✅ Add handle
        created_at: m.created_at,
        isOutgoing: isOutgoing,
      };
    }));


    return res.json({
      success: true,
      messages: transformed,  // For mobile app compatibility
      data: transformed,      // For browser/other clients
      total: transformed.length,
    } as ApiResponse);

  } catch (error) {
    console.error('GET /messages/inbox error:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
    } as ApiResponse);
  }
});

// ===========================================
// LEGACY ENDPOINTS (Backward Compatible)
// ===========================================

// POST /messages/ack - Acknowledge received messages (MUST be before /:to_pk!)
router.post('/ack', verifyGnsAuth, async (req: AuthenticatedRequest, res: Response) => {
  try {
    const pk = req.gnsPublicKey!;
    const { messageIds } = req.body;

    if (!messageIds || !Array.isArray(messageIds)) {
      return res.status(400).json({
        success: false,
        error: 'messageIds array required',
      } as ApiResponse);
    }

    console.log(`✅ ACK ${messageIds.length} messages for ${pk.substring(0, 16)}...`);

    // Mark each message as delivered
    for (const msgId of messageIds) {
      try {
        await db.markMessageDelivered(msgId);
      } catch (error) {
        console.error(`Failed to mark message ${msgId} as delivered:`, error);
      }
    }

    return res.json({
      success: true,
      acknowledged: messageIds.length,
    } as ApiResponse);

  } catch (error) {
    console.error('POST /ack error:', error);
    return res.status(500).json({
      success: false,
      error: 'Failed to acknowledge messages',
    } as ApiResponse);
  }
});

// POST /messages/:to_pk - Send message (original format)
router.post('/:to_pk', async (req: Request, res: Response) => {
  try {
    const toPk = req.params.to_pk?.toLowerCase();

    if (!isValidPublicKey(toPk)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid recipient public key format',
      } as ApiResponse);
    }

    const parseResult = messageSchema.safeParse({
      from_pk: req.body.from_pk,
      to_pk: toPk,
      payload: req.body.payload,
      signature: req.body.signature,
    });

    if (!parseResult.success) {
      return res.status(400).json({
        success: false,
        error: 'Validation failed',
        message: parseResult.error.errors.map(e => e.message).join(', '),
      } as ApiResponse);
    }

    const { from_pk, payload, signature } = parseResult.data;

    // Verify signature
    const isValid = verifyMessage(from_pk, { to_pk: toPk, payload }, signature);

    if (!isValid) {
      return res.status(401).json({
        success: false,
        error: 'Invalid signature',
      } as ApiResponse);
    }

    // Create message
    const message = await db.createEnvelopeMessage(from_pk, toPk, payload, signature);

    // Notify via WebSocket if recipient is connected
    notifyRecipients([toPk], {
      type: 'message',
      data: {
        id: message.id,
        from_pk: from_pk,
        payload: payload,
        created_at: message.created_at,
      },
    });

    console.log(`Message queued: ${from_pk.substring(0, 8)}... → ${toPk.substring(0, 8)}...`);

    return res.status(201).json({
      success: true,
      data: {
        id: message.id,
        created_at: message.created_at,
        expires_at: message.expires_at,
      },
      message: 'Message queued for delivery',
    } as ApiResponse);

  } catch (error) {
    console.error('POST /messages/:to_pk error:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
    } as ApiResponse);
  }
});

// POST /messages - Envelope-based message (legacy)
router.post('/', verifyGnsAuth, async (req: AuthenticatedRequest, res: Response) => {
  try {
    const { envelope, recipients } = req.body;

    if (!envelope) {
      return res.status(400).json({
        success: false,
        error: 'Missing envelope',
      } as ApiResponse);
    }

    const senderKey = envelope.fromPublicKey?.toLowerCase();
    if (senderKey !== req.gnsPublicKey) {
      return res.status(403).json({
        success: false,
        error: 'Sender mismatch',
      } as ApiResponse);
    }

    const recipientList: string[] = recipients ||
      [...(envelope.toPublicKeys || []), ...(envelope.ccPublicKeys || [])];

    if (recipientList.length === 0) {
      return res.status(400).json({
        success: false,
        error: 'No recipients specified',
      } as ApiResponse);
    }

    const storedIds: string[] = [];

    for (const recipientKey of recipientList) {
      const message = await db.createEnvelopeMessage(
        senderKey,
        recipientKey.toLowerCase(),
        envelope,
        envelope.threadId || null
      );
      storedIds.push(message.id);

      notifyRecipients([recipientKey], {
        type: 'message',
        envelope: envelope,
      });
    }

    console.log(`Envelope sent: ${senderKey.substring(0, 8)}... → ${recipientList.length} recipients`);

    return res.status(201).json({
      success: true,
      data: {
        messageId: envelope.id,
        storedCount: storedIds.length,
      },
      message: 'Message sent',
    } as ApiResponse);

  } catch (error) {
    console.error('POST /messages error:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
    } as ApiResponse);
  }
});

// DELETE /messages/:id - Acknowledge
router.delete('/:id', verifyGnsAuth, async (req: AuthenticatedRequest, res: Response) => {
  try {
    const messageId = req.params.id;
    await db.markMessageDelivered(messageId);

    return res.json({
      success: true,
      message: 'Message acknowledged',
    } as ApiResponse);

  } catch (error) {
    console.error('DELETE /messages/:id error:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
    } as ApiResponse);
  }
});

// ===========================================
// NOTIFICATION HELPERS
// ===========================================

export function notifyRecipients(publicKeys: string[], message: any) {
  const data = JSON.stringify(message);

  for (const key of publicKeys) {
    const normalizedKey = key.toLowerCase();
    const clients = connectedClients.get(normalizedKey);
    if (clients) {
      clients.forEach(ws => {
        if (ws.readyState === WebSocket.OPEN) {
          ws.send(data);
        }
      });
    }
  }
}

// ===========================================
// PHASE C: WEBSOCKET SETUP WITH DEVICE ROUTING
// ===========================================

export function setupWebSocket(server: Server): WebSocketServer {
  const wss = new WebSocketServer({
    server,
    path: '/ws'
  });

  wss.on('connection', (ws: WebSocket, req: IncomingMessage) => {
    const url = new URL(req.url || '', `http://${req.headers.host}`);

    // Support both 'pubkey' (legacy) and 'pk' (new) parameters
    const publicKey = (url.searchParams.get('pk') || url.searchParams.get('pubkey'))?.toLowerCase();
    const deviceType = (url.searchParams.get('device') as 'mobile' | 'browser') || 'unknown';
    const sessionToken = url.searchParams.get('session') || undefined;

    if (!publicKey || !isValidPublicKey(publicKey)) {
      ws.close(4001, 'Missing or invalid public key');
      return;
    }

    // Create connection object
    const conn: GnsConnection = {
      ws,
      publicKey,
      deviceType,
      sessionToken,
      connectedAt: new Date(),
      isAlive: true,
    };

    // Add to connection tracking
    addConnection(publicKey, conn);

    const deviceLabel = deviceType.toUpperCase();
    console.log(`🔌 ${deviceLabel} WebSocket connected: ${publicKey.substring(0, 16)}...`);
    console.log(`   Total connections for user: ${getConnections(publicKey).length}`);

    // Update presence
    db.updatePresence(publicKey, 'online').catch(console.error);

    // Send welcome with connection status
    sendToConnection(conn, {
      type: 'welcome',
      publicKey,
      deviceType,
      connectedDevices: getConnectionStatus(publicKey),
      timestamp: Date.now(),
    });

    // Notify other devices of new connection
    broadcastConnectionStatus(publicKey);

    // Handle messages
    ws.on('message', async (data: Buffer) => {
      try {
        const message = JSON.parse(data.toString());
        await handleWebSocketMessage(conn, message);
      } catch (error) {
        console.error('WebSocket message error:', error);
      }
    });

    // Handle disconnect
    ws.on('close', () => {
      removeConnection(publicKey, ws);
      console.log(`🔌 ${deviceLabel} WebSocket disconnected: ${publicKey.substring(0, 16)}...`);

      // Update presence if no more connections
      if (getConnections(publicKey).length === 0) {
        db.updatePresence(publicKey, 'offline').catch(console.error);
      }

      // Notify other devices
      broadcastConnectionStatus(publicKey);
    });

    ws.on('error', (error) => {
      console.error(`WebSocket error for ${publicKey.substring(0, 16)}...:`, error);
    });

    // Handle pong for heartbeat
    ws.on('pong', () => {
      conn.isAlive = true;
    });
  });

  // Heartbeat interval
  const heartbeatInterval = setInterval(() => {
    for (const [pk, conns] of connections.entries()) {
      for (const conn of conns) {
        if (!conn.isAlive) {
          console.log(`💀 Terminating stale connection: ${pk.substring(0, 16)}...`);
          conn.ws.terminate();
          continue;
        }
        conn.isAlive = false;
        if (conn.ws.readyState === WebSocket.OPEN) {
          conn.ws.ping();
        }
      }
    }
  }, 30000);

  wss.on('close', () => {
    clearInterval(heartbeatInterval);
  });

  console.log('✅ WebSocket server initialized on /ws (Phase C: device routing enabled)');
  return wss;
}

// ===========================================
// PHASE C: ENHANCED MESSAGE HANDLING
// ===========================================

async function handleWebSocketMessage(conn: GnsConnection, message: any) {
  const { publicKey, deviceType } = conn;

  switch (message.type) {
    case 'ping':
      sendToConnection(conn, { type: 'pong', timestamp: Date.now() });
      break;

    // ===========================================
    // PHASE C: Browser wants to sync message to mobile
    // ===========================================
    case 'sync_to_mobile': {
      console.log(`📤 Browser requesting sync to mobile: ${message.messageId}`);

      const mobileConns = getMobileConnections(publicKey);

      if (mobileConns.length === 0) {
        console.log('   ⚠️ No mobile connected');
        sendToConnection(conn, {
          type: 'sync_pending',
          reason: 'mobile_offline',
          messageId: message.messageId,
        });
        return;
      }

      // Forward to mobile(s)
      for (const mobile of mobileConns) {
        sendToConnection(mobile, {
          type: 'new_message_from_browser',
          messageId: message.messageId,
          conversationWith: message.conversationWith,
          decryptedText: message.decryptedText,  // ← Forward plaintext!
          timestamp: message.timestamp,
        });
      }

      console.log(`   ✅ Sent to ${mobileConns.length} mobile device(s)`);
      break;
    }

    // ===========================================
    // PHASE C: Mobile syncing decrypted message to browser
    // ===========================================
    case 'sync_to_browser': {
      console.log(`📤 Mobile syncing to browser: ${message.messageId}`);

      const browserConns = getBrowserConnections(publicKey);

      if (browserConns.length === 0) {
        console.log('   ⚠️ No browsers connected');
        return;
      }

      // Forward pre-decrypted message to browser(s)
      for (const browser of browserConns) {
        sendToConnection(browser, {
          type: 'message_synced',
          messageId: message.messageId,
          conversationWith: message.conversationWith,
          decryptedText: message.decryptedText,  // Already decrypted by mobile!
          direction: message.direction,
          timestamp: message.timestamp,
          fromHandle: message.fromHandle,
        });
      }

      console.log(`   ✅ Synced to ${browserConns.length} browser(s)`);
      break;
    }

    // ===========================================
    // PHASE C: Browser requesting sync from mobile
    // ===========================================
    case 'request_sync': {
      console.log(`🔄 Browser requesting sync`);

      const mobileConns = getMobileConnections(publicKey);

      for (const mobile of mobileConns) {
        sendToConnection(mobile, {
          type: 'sync_request',
          fromDevice: 'browser',
          conversationWith: message.conversationWith,
          limit: message.limit || 50,
        });
      }
      break;
    }

    // ===========================================
    // Legacy: Send message via WebSocket
    // ===========================================
    case 'message': {
      const envelope = message.envelope;
      if (!envelope) break;

      const recipients = [
        ...(envelope.toPublicKeys || []),
        ...(envelope.ccPublicKeys || []),
      ];

      for (const recipientKey of recipients) {
        await db.createEnvelopeMessage(
          publicKey,
          recipientKey.toLowerCase(),
          envelope,
          envelope.threadId
        );
      }

      notifyRecipients(recipients, {
        type: 'message',
        envelope: envelope,
      });

      // PHASE C: Also notify sender's other devices
      if (deviceType === 'browser') {
        const mobileConns = getMobileConnections(publicKey);
        for (const mobile of mobileConns) {
          sendToConnection(mobile, {
            type: 'new_message_from_browser',
            messageId: envelope.id,
            conversationWith: recipients[0]?.toLowerCase(),
            envelope: envelope,
            timestamp: Date.now(),
          });
        }
      }
      break;
    }

    // ===========================================
    // Typing indicator
    // ===========================================
    case 'typing':
      await db.updateTypingStatus(message.threadId, publicKey, message.isTyping);
      break;

    default:
      console.log(`Unknown WS message type: ${message.type}`);
  }
}

// ===========================================
// PHASE C: EXPORT HELPERS FOR OTHER MODULES
// ===========================================

export function notifyUserDevices(publicKey: string, message: any) {
  broadcastToUser(publicKey, message);
}

export function notifyMobileDevices(publicKey: string, message: any) {
  const mobiles = getMobileConnections(publicKey);
  for (const mobile of mobiles) {
    sendToConnection(mobile, message);
  }
}

export function notifyBrowserDevices(publicKey: string, message: any) {
  const browsers = getBrowserConnections(publicKey);
  for (const browser of browsers) {
    sendToConnection(browser, message);
  }
}

export function getWebSocketStats() {
  let totalConnections = 0;
  let mobileConnections = 0;
  let browserConnections = 0;

  for (const conns of connections.values()) {
    totalConnections += conns.length;
    mobileConnections += conns.filter(c => c.deviceType === 'mobile').length;
    browserConnections += conns.filter(c => c.deviceType === 'browser').length;
  }

  return {
    uniqueUsers: connections.size,
    totalConnections,
    mobileConnections,
    browserConnections,
  };
}

export default router;
