// ===========================================
// GNS NODE - MESSAGES API (UPGRADED)
// /messages endpoints + WebSocket
// 
// CHANGES FROM ORIGINAL:
// - Added /api/v1/messages (envelope-based)
// - Added WebSocket support
// - Added typing indicators
// - Added presence
// - Kept original endpoints for backward compatibility
// 
// FIXED: Route order - specific routes BEFORE wildcard /:to_pk
// ===========================================

import { Router, Request, Response } from 'express';
import { messageSchema, pkRootSchema } from '../lib/validation';
import { verifyMessage, verifySignature, isValidPublicKey, canonicalJson } from '../lib/crypto';
import * as db from '../lib/db';
import { ApiResponse, DbMessage } from '../types';
import { WebSocketServer, WebSocket } from 'ws';
import { IncomingMessage } from 'http';
import { Server } from 'http';

const router = Router();

// ===========================================
// WEBSOCKET STATE
// ===========================================

// Connected clients: Map<publicKey, Set<WebSocket>>
const connectedClients = new Map<string, Set<WebSocket>>();

// Export for use in index.ts
export { connectedClients };

// ===========================================
// AUTH MIDDLEWARE
// ===========================================

interface AuthenticatedRequest extends Request {
  gnsPublicKey?: string;
  browserSession?: any;
}

/**
 * Verify authentication - supports both browser sessions and signature-based auth
 * 
 * Browser clients (authenticated via QR):
 *   X-GNS-Session: session token from browser pairing
 * 
 * Mobile/native clients (signature-based):
 *   X-GNS-PublicKey: sender's public key (hex)
 *   X-GNS-Timestamp: unix timestamp (ms)
 *   X-GNS-Signature: signature of "timestamp:publicKey"
 */
const verifyAuth = async (
  req: AuthenticatedRequest,
  res: Response,
  next: Function
) => {
  try {
    // Try browser session first
    const sessionToken = req.headers['x-gns-session'] as string;

    if (sessionToken) {
      // Browser session authentication
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
      req.browserSession = session;
      req.gnsPublicKey = session.publicKey;
      return next();
    }

    // Fall back to signature-based auth
    const publicKey = (req.headers['x-gns-publickey'] as string)?.toLowerCase();
    const identity = (req.headers['x-gns-identity'] as string)?.toLowerCase();
    const pk = publicKey || identity;

    if (!pk || !isValidPublicKey(pk)) {
      return res.status(401).json({
        success: false,
        error: 'Missing authentication (X-GNS-Session or X-GNS-PublicKey required)',
      } as ApiResponse);
    }

    // For now, trust the public key
    // TODO: Verify signature in production
    req.gnsPublicKey = pk;
    next();
  } catch (error) {
    console.error('Auth error:', error);
    res.status(401).json({ success: false, error: 'Authentication failed' });
  }
};

/**
 * Legacy signature-based auth (kept for backward compatibility)
 */
const verifyGnsAuth = verifyAuth;

// ===========================================
// SPECIFIC ROUTES (MUST BE BEFORE WILDCARD)
// ===========================================

/**
 * POST /messages/ack
 * Acknowledge message receipt (batch)
 */
router.post('/ack', verifyGnsAuth, async (req: AuthenticatedRequest, res: Response) => {
  try {
    const { messageIds } = req.body;
    const pk = req.gnsPublicKey!;

    if (!messageIds || !Array.isArray(messageIds)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid messageIds',
      } as ApiResponse);
    }

    const acknowledged = await db.acknowledgeMessages(pk, messageIds);

    return res.json({
      success: true,
      data: { acknowledged },
    } as ApiResponse);

  } catch (error) {
    console.error('POST /messages/ack error:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
    } as ApiResponse);
  }
});

/**
 * POST /messages/read
 * Mark messages as read
 */
router.post('/read', verifyGnsAuth, async (req: AuthenticatedRequest, res: Response) => {
  try {
    const { messageIds } = req.body;
    const pk = req.gnsPublicKey!;

    if (!messageIds || !Array.isArray(messageIds)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid messageIds',
      } as ApiResponse);
    }

    const marked = await db.markMessagesRead(pk, messageIds);

    // Notify senders about read status
    // TODO: Get sender keys and notify them

    return res.json({
      success: true,
      data: { markedRead: marked },
    } as ApiResponse);

  } catch (error) {
    console.error('POST /messages/read error:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
    } as ApiResponse);
  }
});

/**
 * POST /messages/typing
 * Update typing status
 */
router.post('/typing', verifyGnsAuth, async (req: AuthenticatedRequest, res: Response) => {
  try {
    const { threadId, isTyping } = req.body;
    const pk = req.gnsPublicKey!;

    if (!threadId) {
      return res.status(400).json({
        success: false,
        error: 'Missing threadId',
      } as ApiResponse);
    }

    await db.updateTypingStatus(threadId, pk, isTyping);

    // Broadcast via WebSocket to thread participants
    broadcastTyping(threadId, pk, isTyping);

    return res.json({ success: true } as ApiResponse);

  } catch (error) {
    console.error('POST /messages/typing error:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
    } as ApiResponse);
  }
});

/**
 * POST /messages/presence
 * Update presence status
 */
router.post('/presence', verifyGnsAuth, async (req: AuthenticatedRequest, res: Response) => {
  try {
    const { status, deviceInfo } = req.body;
    const pk = req.gnsPublicKey!;

    await db.updatePresence(pk, status || 'online', deviceInfo);

    return res.json({ success: true } as ApiResponse);

  } catch (error) {
    console.error('POST /messages/presence error:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
    } as ApiResponse);
  }
});

/**
 * POST /messages/send
 * Simplified message sending for QR-paired browsers
 * Uses session token instead of signature-based auth
 */
router.post('/send', async (req: Request, res: Response) => {
  try {
    const sessionToken = req.headers['x-gns-session'] as string;
    const publicKey = (req.headers['x-gns-publickey'] as string)?.toLowerCase();

    if (!sessionToken) {
      return res.status(401).json({
        success: false,
        error: 'Missing X-GNS-Session header',
      } as ApiResponse);
    }

    // Verify session is valid
    const session = await db.getBrowserSession(sessionToken);

    if (!session || !session.isActive) {
      return res.status(401).json({
        success: false,
        error: 'Invalid or expired session',
      } as ApiResponse);
    }

    // Verify publicKey matches session (if provided)
    if (publicKey && session.publicKey !== publicKey) {
      return res.status(401).json({
        success: false,
        error: 'Public key mismatch',
      } as ApiResponse);
    }

    // Check session expiry
    if (new Date() > session.expiresAt) {
      await db.revokeBrowserSession(sessionToken);
      return res.status(401).json({
        success: false,
        error: 'Session expired',
      } as ApiResponse);
    }

    // Update last used
    await db.updateBrowserSessionLastUsed(sessionToken);

    // Get message content
    const { to, content, threadId } = req.body;

    if (!to || !content) {
      return res.status(400).json({
        success: false,
        error: 'Missing required fields: to, content',
      } as ApiResponse);
    }

    if (!isValidPublicKey(to)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid recipient public key',
      } as ApiResponse);
    }

    // Get sender's identity
    const senderHandle = session.handle || session.publicKey.substring(0, 8);
    const recipientKey = to.toLowerCase();

    // Create message envelope
    const messageId = `msg_${Date.now()}_${Math.random().toString(36).substring(2, 8)}`;
    const actualThreadId = threadId || `thread_${session.publicKey}_${recipientKey}`;

    const envelope = {
      id: messageId,
      type: 'direct',
      fromPublicKey: session.publicKey,
      fromHandle: senderHandle,
      toPublicKeys: [recipientKey],
      payloadType: 'gns/text.plain',
      encryptedPayload: content, // Note: Should be encrypted in production
      threadId: actualThreadId,
      timestamp: Date.now(),
    };

    // Store message in database
    const message = await db.createEnvelopeMessage(
      session.publicKey,
      recipientKey,
      envelope,
      actualThreadId
    );

    // Deliver via WebSocket if recipient is connected
    notifyRecipients([recipientKey], {
      type: 'message',
      data: envelope,
    });

    console.log(`📨 Browser message: ${senderHandle} → ${recipientKey.substring(0, 8)}...`);

    return res.json({
      success: true,
      message: 'Message sent',
      data: {
        messageId: messageId,
        threadId: actualThreadId,
        timestamp: envelope.timestamp,
        created_at: message.created_at,
      },
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
// WILDCARD ROUTE (MUST BE AFTER SPECIFIC ROUTES)
// ===========================================

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

// ===========================================
// OTHER ORIGINAL ENDPOINTS
// ===========================================

// GET /messages/inbox - Fetch pending (original format)
router.get('/inbox', verifyGnsAuth, async (req: AuthenticatedRequest, res: Response) => {
  try {
    const pk = req.gnsPublicKey!;
    const messages = await db.getInbox(pk);

    return res.json({
      success: true,
      data: messages.map(m => {
        // Prioritize full envelope if it exists, otherwise fallback to old format
        const env = m.envelope || {
          id: m.id,
          fromPublicKey: m.from_pk,
          toPublicKeys: [m.to_pk],
          payloadType: 'gns/text.plain',
          encryptedPayload: m.payload,
          timestamp: new Date(m.created_at).getTime(),
          signature: m.signature,
        };

        // CRITICAL: Ensure encryptedPayload is a string, not an object
        // JSONB may parse JSON-like strings into objects
        if (env.encryptedPayload && typeof env.encryptedPayload === 'object') {
          env.encryptedPayload = JSON.stringify(env.encryptedPayload);
        }

        // ALWAYS include from_pk for grouping
        return {
          ...env,
          from_pk: m.from_pk,
          fromPublicKey: env.fromPublicKey || m.from_pk,
          created_at: m.created_at,
        };
      }),
      total: messages.length,
    } as ApiResponse);

  } catch (error) {
    console.error('GET /messages/inbox error:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
    } as ApiResponse);
  }
});

// DELETE /messages/:id - Acknowledge (original format)
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
// NEW ENVELOPE-BASED ENDPOINTS
// ===========================================

/**
 * POST /messages
 * Send envelope-based message (new format)
 */
router.post('/', verifyGnsAuth, async (req: AuthenticatedRequest, res: Response) => {
  try {
    const { envelope, recipients } = req.body;

    if (!envelope) {
      return res.status(400).json({
        success: false,
        error: 'Missing envelope',
      } as ApiResponse);
    }

    // Verify sender matches authenticated user
    const senderKey = envelope.fromPublicKey?.toLowerCase();
    if (senderKey !== req.gnsPublicKey) {
      return res.status(403).json({
        success: false,
        error: 'Sender mismatch',
      } as ApiResponse);
    }

    // Get recipients from envelope or request body
    const recipientList: string[] = recipients ||
      [...(envelope.toPublicKeys || []), ...(envelope.ccPublicKeys || [])];

    if (recipientList.length === 0) {
      return res.status(400).json({
        success: false,
        error: 'No recipients specified',
      } as ApiResponse);
    }

    // Store message for each recipient
    const storedIds: string[] = [];

    for (const recipientKey of recipientList) {
      const message = await db.createEnvelopeMessage(
        senderKey,
        recipientKey.toLowerCase(),
        envelope,
        envelope.threadId || null
      );
      storedIds.push(message.id);

      // Notify via WebSocket
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

/**
 * GET /messages
 * Fetch pending messages (envelope format)
 */
router.get('/', verifyGnsAuth, async (req: AuthenticatedRequest, res: Response) => {
  try {
    const pk = req.gnsPublicKey!;
    const since = req.query.since as string | undefined;
    const limit = Math.min(parseInt(req.query.limit as string) || 100, 500);

    const messages = await db.getPendingEnvelopes(pk, since, limit);

    return res.json({
      success: true,
      messages: messages.map(m => {
        const env = m.envelope || {
          // Fallback for old-format messages without envelope column
          id: m.id,
          fromPublicKey: m.from_pk,
          toPublicKeys: [m.to_pk],
          payloadType: 'gns/text.plain',
          encryptedPayload: m.payload,
          timestamp: new Date(m.created_at).getTime(),
          signature: m.signature,
        };

        // CRITICAL FIX: Ensure encryptedPayload is a string, not an object
        // JSONB may parse JSON-like strings into objects, but for signature verification
        // to work, encryptedPayload MUST be a string (the ciphertext)
        if (env.encryptedPayload && typeof env.encryptedPayload === 'object') {
          env.encryptedPayload = JSON.stringify(env.encryptedPayload);
        }

        return env;
      }),
      count: messages.length,
      hasMore: messages.length >= limit,
    } as ApiResponse);

  } catch (error) {
    console.error('GET /messages error:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
    } as ApiResponse);
  }
});

/**
 * GET /messages/thread/:threadId
 * Get messages in a thread
 */
router.get('/thread/:threadId', verifyGnsAuth, async (req: AuthenticatedRequest, res: Response) => {
  try {
    const { threadId } = req.params;
    const pk = req.gnsPublicKey!;
    const limit = Math.min(parseInt(req.query.limit as string) || 50, 200);
    const before = req.query.before as string | undefined;

    const messages = await db.getThreadMessages(threadId, pk, limit, before);

    return res.json({
      success: true,
      messages: messages.map(m => {
        const env = m.envelope || {
          id: m.id,
          fromPublicKey: m.from_pk,
          toPublicKeys: [m.to_pk],
          payloadType: 'gns/text.plain',
          encryptedPayload: m.payload,
          timestamp: new Date(m.created_at).getTime(),
          signature: m.signature,
        };

        // CRITICAL: Ensure encryptedPayload is a string, not an object
        if (env.encryptedPayload && typeof env.encryptedPayload === 'object') {
          env.encryptedPayload = JSON.stringify(env.encryptedPayload);
        }

        return env;
      }),
      count: messages.length,
      hasMore: messages.length >= limit,
    } as ApiResponse);

  } catch (error) {
    console.error('GET /messages/thread/:threadId error:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
    } as ApiResponse);
  }
});

/**
 * GET /messages/conversation
 * Get messages between authenticated user and another user
 */
router.get('/conversation', verifyAuth, async (req: AuthenticatedRequest, res: Response) => {
  try {
    const pk = req.gnsPublicKey!;
    const withPk = (req.query.with as string)?.toLowerCase();
    const limit = Math.min(parseInt(req.query.limit as string) || 50, 200);

    if (!withPk || !isValidPublicKey(withPk)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid or missing "with" public key',
      } as ApiResponse);
    }

    // Get messages where user is sender or recipient with the other party
    const messages = await db.getConversation(pk, withPk, limit);

    return res.json({
      success: true,
      data: messages.map(m => {
        const env = m.envelope || {
          id: m.id,
          fromPublicKey: m.from_pk,
          toPublicKeys: [m.to_pk],
          payloadType: 'gns/text.plain',
          encryptedPayload: m.payload,
          timestamp: new Date(m.created_at).getTime(),
        };

        if (env.encryptedPayload && typeof env.encryptedPayload === 'object') {
          env.encryptedPayload = JSON.stringify(env.encryptedPayload);
        }

        return {
          ...env,
          from_pk: m.from_pk,
          to_pk: m.to_pk,
          created_at: m.created_at,
        };
      }),
    } as ApiResponse);

  } catch (error) {
    console.error('GET /messages/conversation error:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
    } as ApiResponse);
  }
});

/**
 * GET /messages/presence/:publicKey
 * Get user presence
 */
router.get('/presence/:publicKey', async (req: Request, res: Response) => {
  try {
    const pk = req.params.publicKey?.toLowerCase();

    if (!isValidPublicKey(pk)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid public key',
      } as ApiResponse);
    }

    const presence = await db.getPresence(pk);

    return res.json({
      success: true,
      data: presence || {
        publicKey: pk,
        status: 'offline',
        lastSeen: null,
      },
    } as ApiResponse);

  } catch (error) {
    console.error('GET /messages/presence/:publicKey error:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
    } as ApiResponse);
  }
});

// ===========================================
// WEBSOCKET SETUP
// ===========================================

/**
 * Setup WebSocket server
 * Call from index.ts: setupWebSocket(httpServer)
 */
export function setupWebSocket(server: Server): WebSocketServer {
  const wss = new WebSocketServer({
    server,
    path: '/ws'
  });

  wss.on('connection', (ws: WebSocket, req: IncomingMessage) => {
    // Parse auth from query params
    const url = new URL(req.url || '', `http://${req.headers.host}`);
    const publicKey = url.searchParams.get('pubkey')?.toLowerCase();
    const timestamp = url.searchParams.get('timestamp');
    const signature = url.searchParams.get('sig');

    if (!publicKey || !isValidPublicKey(publicKey)) {
      ws.close(4001, 'Missing or invalid public key');
      return;
    }

    // TODO: Verify signature in production
    // const message = `${timestamp}:${publicKey}`;
    // if (!verifySignature(publicKey, message, signature)) {
    //   ws.close(4002, 'Invalid signature');
    //   return;
    // }

    // Register client
    if (!connectedClients.has(publicKey)) {
      connectedClients.set(publicKey, new Set());
    }
    connectedClients.get(publicKey)!.add(ws);

    console.log(`WebSocket connected: ${publicKey.substring(0, 16)}...`);

    // Update presence
    db.updatePresence(publicKey, 'online').catch(console.error);

    // Handle messages
    ws.on('message', async (data: Buffer) => {
      try {
        const message = JSON.parse(data.toString());
        await handleWebSocketMessage(ws, publicKey, message);
      } catch (error) {
        console.error('WebSocket message error:', error);
      }
    });

    // Handle disconnect
    ws.on('close', () => {
      const clients = connectedClients.get(publicKey);
      if (clients) {
        clients.delete(ws);
        if (clients.size === 0) {
          connectedClients.delete(publicKey);
          db.updatePresence(publicKey, 'offline').catch(console.error);
        }
      }
      console.log(`WebSocket disconnected: ${publicKey.substring(0, 16)}...`);
    });

    // Handle errors
    ws.on('error', (error) => {
      console.error(`WebSocket error for ${publicKey.substring(0, 16)}...:`, error);
    });

    // Send welcome
    ws.send(JSON.stringify({
      type: 'connected',
      publicKey,
      timestamp: Date.now(),
    }));
  });

  // Heartbeat to keep connections alive
  const heartbeatInterval = setInterval(() => {
    wss.clients.forEach((ws: WebSocket & { isAlive?: boolean }) => {
      if (ws.isAlive === false) {
        return ws.terminate();
      }
      ws.isAlive = false;
      ws.ping();
    });
  }, 30000);

  wss.on('connection', (ws: WebSocket & { isAlive?: boolean }) => {
    ws.isAlive = true;
    ws.on('pong', () => {
      ws.isAlive = true;
    });
  });

  wss.on('close', () => {
    clearInterval(heartbeatInterval);
  });

  console.log('WebSocket server initialized on /ws');
  return wss;
}

/**
 * Handle incoming WebSocket message
 */
async function handleWebSocketMessage(
  ws: WebSocket,
  publicKey: string,
  message: any
) {
  switch (message.type) {
    case 'ping':
      ws.send(JSON.stringify({ type: 'pong', timestamp: Date.now() }));
      break;

    case 'message':
      // Store and forward envelope
      const envelope = message.envelope;
      if (!envelope) break;

      const recipients = [
        ...(envelope.toPublicKeys || []),
        ...(envelope.ccPublicKeys || []),
      ];

      // Store for each recipient
      for (const recipientKey of recipients) {
        await db.createEnvelopeMessage(
          publicKey,
          recipientKey.toLowerCase(),
          envelope,
          envelope.threadId
        );
      }

      // Forward to connected recipients
      notifyRecipients(recipients, {
        type: 'message',
        envelope: envelope,
      });
      break;

    case 'typing':
      await db.updateTypingStatus(message.threadId, publicKey, message.isTyping);
      broadcastTyping(message.threadId, publicKey, message.isTyping);
      break;

    case 'ack':
      // Notify sender about delivery
      if (message.senderId) {
        notifyRecipients([message.senderId], {
          type: 'status',
          messageId: message.messageId,
          status: 'delivered',
        });
      }
      break;

    case 'read':
      // Notify sender about read
      if (message.senderId) {
        notifyRecipients([message.senderId], {
          type: 'status',
          messageId: message.messageId,
          status: 'read',
        });
      }
      break;
  }
}

// ===========================================
// NOTIFICATION HELPERS
// ===========================================

/**
 * Send message to specific recipients
 */
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

/**
 * Broadcast typing status
 */
function broadcastTyping(threadId: string, fromPublicKey: string, isTyping: boolean) {
  // For now, broadcast to all connected clients
  // TODO: Track thread participants and only notify them
  const data = JSON.stringify({
    type: 'typing',
    threadId,
    fromPublicKey,
    isTyping,
    timestamp: Date.now(),
  });

  connectedClients.forEach((clients, key) => {
    if (key !== fromPublicKey) {
      clients.forEach(ws => {
        if (ws.readyState === WebSocket.OPEN) {
          ws.send(data);
        }
      });
    }
  });
}

export default router;
