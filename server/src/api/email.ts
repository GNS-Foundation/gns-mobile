// ===========================================
// GNS NODE - EMAIL GATEWAY SERVICE
// Receives inbound emails from Cloudflare Worker
// Routes to GNS users via encrypted envelopes
// ===========================================

import { Router, Request, Response } from 'express';
import * as crypto from 'crypto';
import nacl from 'tweetnacl';
import sodium from 'libsodium-wrappers';
import * as db from '../lib/db';
import { notifyRecipients } from './messages';
import { ApiResponse } from '../types';

const router = Router();

// ===========================================
// EMAIL GATEWAY CONFIGURATION
// ===========================================

interface EmailGatewayConfig {
  handle: string;
  webhookSecret: string;
  enabled: boolean;
  domain: string;
}

const EMAIL_CONFIG: EmailGatewayConfig = {
  handle: 'email-gateway',
  webhookSecret: process.env.EMAIL_WEBHOOK_SECRET || 'gns-email-webhook-secret',
  enabled: true,
  domain: '9lobe.com',
};

// ===========================================
// CRYPTO CONSTANTS (match Flutter)
// ===========================================

const HKDF_INFO_ENVELOPE = 'gns-envelope-v1';
const NONCE_LENGTH = 12;
const MAC_LENGTH = 16;
const KEY_LENGTH = 32;

// ===========================================
// GATEWAY KEYPAIR
// ===========================================

let gatewayKeypair: nacl.SignKeyPair | null = null;
let gatewayEd25519PublicKeyHex: string = '';
let gatewayEd25519PrivateKeyHex: string = '';
let gatewayX25519PublicKeyHex: string = '';
let gatewayX25519PrivateKey: Uint8Array | null = null;

// ===========================================
// CRYPTO HELPERS (local to this module)
// ===========================================

function toBytes(hex: string): Uint8Array {
  const bytes = new Uint8Array(hex.length / 2);
  for (let i = 0; i < hex.length; i += 2) {
    bytes[i / 2] = parseInt(hex.substr(i, 2), 16);
  }
  return bytes;
}

function toHex(bytes: Uint8Array): string {
  return Array.from(bytes).map(b => b.toString(16).padStart(2, '0')).join('');
}

function generateUUID(): string {
  return crypto.randomUUID();
}

/**
 * HKDF key derivation
 */
function hkdfDerive(sharedSecret: Uint8Array, info: string): Uint8Array {
  const hkdf = crypto.createHmac('sha256', Buffer.alloc(32, 0))
    .update(sharedSecret)
    .digest();
  
  const prk = crypto.createHmac('sha256', hkdf)
    .update(Buffer.concat([Buffer.from(info), Buffer.from([1])]))
    .digest();
  
  return new Uint8Array(prk.slice(0, KEY_LENGTH));
}

/**
 * Encrypt payload for recipient using their X25519 public key
 */
function encryptForRecipient(
  payload: Buffer,
  recipientX25519PublicKey: Uint8Array
): { encryptedPayload: string; ephemeralPublicKey: string; nonce: string } {
  // Generate ephemeral X25519 keypair
  const ephemeralKeypair = nacl.box.keyPair();
  
  // X25519 shared secret
  const sharedSecret = nacl.box.before(recipientX25519PublicKey, ephemeralKeypair.secretKey);
  
  // Derive encryption key via HKDF
  const derivedKey = hkdfDerive(sharedSecret, HKDF_INFO_ENVELOPE);
  
  // Generate nonce
  const nonce = crypto.randomBytes(NONCE_LENGTH);
  
  // Encrypt with ChaCha20-Poly1305
  const cipher = crypto.createCipheriv('chacha20-poly1305', derivedKey, nonce, {
    authTagLength: MAC_LENGTH,
  });
  
  const encrypted = Buffer.concat([
    cipher.update(payload),
    cipher.final(),
    cipher.getAuthTag(),
  ]);
  
  return {
    encryptedPayload: encrypted.toString('base64'),
    ephemeralPublicKey: Buffer.from(ephemeralKeypair.publicKey).toString('base64'),  // ✅ BASE64
    nonce: nonce.toString('base64'),
  };
}

/**
 * Create canonical JSON string for signing (ALPHABETICAL ORDER - must match Flutter!)
 */
function createCanonicalEnvelopeString(envelope: EnvelopeData): string {
  // CRITICAL: Fields MUST be in alphabetical order to match Flutter's verification
  const canonical: Record<string, any> = {};
  
  if (envelope.ccPublicKeys != null) canonical.ccPublicKeys = envelope.ccPublicKeys;
  canonical.encryptedPayload = envelope.encryptedPayload;
  canonical.ephemeralPublicKey = envelope.ephemeralPublicKey;
  if (envelope.expiresAt != null) canonical.expiresAt = envelope.expiresAt;
  if (envelope.forwardOfId != null) canonical.forwardOfId = envelope.forwardOfId;
  canonical.fromPublicKey = envelope.fromPublicKey;
  canonical.id = envelope.id;
  canonical.nonce = envelope.nonce;
  canonical.payloadSize = envelope.payloadSize;
  canonical.payloadType = envelope.payloadType;
  canonical.priority = envelope.priority;
  if (envelope.recipientKeys != null) canonical.recipientKeys = envelope.recipientKeys;
  if (envelope.replyToId != null) canonical.replyToId = envelope.replyToId;
  if (envelope.threadId != null) canonical.threadId = envelope.threadId;
  canonical.timestamp = envelope.timestamp;
  canonical.toPublicKeys = envelope.toPublicKeys;
  canonical.version = envelope.version;
  
  return JSON.stringify(canonical);
}

// ===========================================
// EMAIL PAYLOAD TYPES
// ===========================================

interface InboundEmailWebhook {
  to: string;
  handle: string;
  from: string;
  subject: string;
  headers?: {
    messageId?: string;
    date?: string;
    replyTo?: string;
    contentType?: string;
  };
  rawEmail?: string;
  textBody?: string;
  htmlBody?: string;
  receivedAt: string;
}

interface EmailPayload {
  type: 'email';
  subject: string;
  body: string;
  bodyFormat: 'plain' | 'markdown' | 'html';
  from: string;
  messageId?: string;
  inReplyTo?: string;
  references?: string[];
  receivedAt: string;
  attachments?: Array<{
    filename: string;
    contentType: string;
    size: number;
    content?: string;
  }>;
}

interface EnvelopeData {
  id: string;
  version: number;
  fromPublicKey: string;
  toPublicKeys: string[];
  ccPublicKeys: string[] | null;
  payloadType: string;
  encryptedPayload: string;
  payloadSize: number;
  threadId: string | null;
  replyToId: string | null;
  forwardOfId: string | null;
  timestamp: number;
  expiresAt: number | null;
  ephemeralPublicKey: string;
  recipientKeys: any | null;
  nonce: string;
  priority: number;
  signature?: string;  // ← ADDED: signature field
}

// ===========================================
// INITIALIZE EMAIL GATEWAY
// ===========================================

export async function initializeEmailGateway(): Promise<{ publicKey: string; encryptionKey: string }> {
  await sodium.ready;
  
  const envPrivateKey = process.env.EMAIL_GATEWAY_PRIVATE_KEY;
  const envX25519PrivateKey = process.env.EMAIL_GATEWAY_X25519_PRIVATE_KEY;
  
  if (envPrivateKey && envPrivateKey.length === 128) {
    const secretKey = toBytes(envPrivateKey);
    gatewayKeypair = {
      publicKey: secretKey.slice(32),
      secretKey: secretKey,
    };
    gatewayEd25519PublicKeyHex = toHex(gatewayKeypair.publicKey);
    gatewayEd25519PrivateKeyHex = envPrivateKey;
    
    if (envX25519PrivateKey && envX25519PrivateKey.length === 64) {
      gatewayX25519PrivateKey = toBytes(envX25519PrivateKey);
      const x25519Kp = nacl.box.keyPair.fromSecretKey(gatewayX25519PrivateKey);
      gatewayX25519PublicKeyHex = toHex(x25519Kp.publicKey);
    } else {
      const x25519Kp = nacl.box.keyPair();
      gatewayX25519PrivateKey = x25519Kp.secretKey;
      gatewayX25519PublicKeyHex = toHex(x25519Kp.publicKey);
      
      console.log(`   ⚠️  SAVE THIS TO RAILWAY ENV AS EMAIL_GATEWAY_X25519_PRIVATE_KEY:`);
      console.log(`   ${toHex(gatewayX25519PrivateKey)}`);
    }
    
    console.log(`📧 Email Gateway initialized with existing keypair`);
  } else {
    gatewayKeypair = nacl.sign.keyPair();
    gatewayEd25519PublicKeyHex = toHex(gatewayKeypair.publicKey);
    gatewayEd25519PrivateKeyHex = toHex(gatewayKeypair.secretKey);
    
    const x25519Kp = nacl.box.keyPair();
    gatewayX25519PrivateKey = x25519Kp.secretKey;
    gatewayX25519PublicKeyHex = toHex(x25519Kp.publicKey);
    
    console.log(`📧 Email Gateway generated NEW dual keypair`);
    console.log(`   ⚠️  SAVE THESE TO RAILWAY ENV:`);
    console.log(`   EMAIL_GATEWAY_PRIVATE_KEY=${gatewayEd25519PrivateKeyHex}`);
    console.log(`   EMAIL_GATEWAY_X25519_PRIVATE_KEY=${toHex(gatewayX25519PrivateKey)}`);
  }
  
  console.log(`   Ed25519 (identity): ${gatewayEd25519PublicKeyHex.substring(0, 16)}...`);
  console.log(`   X25519 (encryption): ${gatewayX25519PublicKeyHex.substring(0, 16)}...`);
  console.log(`   Domain: ${EMAIL_CONFIG.domain}`);
  
  return {
    publicKey: gatewayEd25519PublicKeyHex,
    encryptionKey: gatewayX25519PublicKeyHex,
  };
}

/**
 * Get gateway status
 */
export function getEmailGatewayStatus() {
  return {
    enabled: EMAIL_CONFIG.enabled,
    publicKey: gatewayEd25519PublicKeyHex,
    encryptionKey: gatewayX25519PublicKeyHex,
    domain: EMAIL_CONFIG.domain,
  };
}

// ===========================================
// WEBHOOK SECRET VERIFICATION
// ===========================================

function verifyWebhookSecret(req: Request, res: Response, next: Function) {
  const secret = req.headers['x-webhook-secret'] || req.query.secret;
  
  if (secret !== EMAIL_CONFIG.webhookSecret) {
    console.error('❌ Invalid webhook secret');
    return res.status(401).json({
      success: false,
      error: 'Invalid webhook secret',
    } as ApiResponse);
  }
  
  next();
}

// ===========================================
// PARSE EMAIL BODY FROM RAW MIME
// ===========================================

function parseEmailBody(rawBase64: string): { text: string; html?: string } {
  try {
    const raw = Buffer.from(rawBase64, 'base64').toString('utf-8');
    
    const parts = raw.split('\r\n\r\n');
    if (parts.length > 1) {
      const body = parts.slice(1).join('\r\n\r\n');
      
      if (raw.includes('Content-Type: text/html')) {
        return { text: body, html: body };
      }
      
      return { text: body };
    }
    
    return { text: raw };
  } catch (error) {
    console.error('Error parsing email body:', error);
    return { text: '[Could not parse email body]' };
  }
}

// ===========================================
// INBOUND EMAIL ENDPOINT
// ===========================================

router.post('/inbound', verifyWebhookSecret, async (req: Request, res: Response) => {
  try {
    const webhook: InboundEmailWebhook = req.body;
    
    console.log(`📧 Inbound email received:`);
    console.log(`   To: ${webhook.to}`);
    console.log(`   Handle: ${webhook.handle}`);
    console.log(`   From: ${webhook.from}`);
    console.log(`   Subject: ${webhook.subject}`);
    
    // 1. Resolve handle to GNS identity
    const handle = webhook.handle.toLowerCase().replace(/^@/, '');
    const alias = await db.getAliasByHandle(handle);
    
    if (!alias) {
      console.error(`❌ Handle not found: @${handle}`);
      return res.status(404).json({
        success: false,
        error: `Handle @${handle} not found`,
      } as ApiResponse);
    }
    
    // 2. Get recipient's record with encryption key
    const record = await db.getRecord(alias.pk_root);
    
    if (!record) {
      console.error(`❌ Record not found for: ${alias.pk_root}`);
      return res.status(404).json({
        success: false,
        error: 'Recipient record not found',
      } as ApiResponse);
    }
    
    if (!record.encryption_key) {
      console.error(`❌ No encryption key for: ${alias.pk_root}`);
      return res.status(400).json({
        success: false,
        error: 'Recipient has no encryption key',
      } as ApiResponse);
    }
    
    console.log(`   ✅ Resolved to: ${alias.pk_root.substring(0, 16)}...`);
    
    // 3. Parse email body
    let textBody = webhook.textBody || '';
    let htmlBody = webhook.htmlBody;
    
    if (!textBody && webhook.rawEmail) {
      const parsed = parseEmailBody(webhook.rawEmail);
      textBody = parsed.text;
      htmlBody = parsed.html;
    }
    
    // 4. Create EmailPayload
    const emailPayload: EmailPayload = {
      type: 'email',
      subject: webhook.subject,
      body: textBody || htmlBody || '[No content]',
      bodyFormat: htmlBody ? 'html' : 'plain',
      from: webhook.from,
      messageId: webhook.headers?.messageId,
      receivedAt: webhook.receivedAt,
    };
    
    const payloadBuffer = Buffer.from(JSON.stringify(emailPayload), 'utf8');
    
    // 5. Encrypt for recipient
    const recipientX25519 = toBytes(record.encryption_key);
    const encrypted = encryptForRecipient(payloadBuffer, recipientX25519);
    
    // 6. Create GNS Envelope (WITHOUT signature initially)
    const envelopeId = generateUUID();
    const timestamp = Date.now();
    
    // Generate thread ID from external sender + recipient for grouping
    const threadId = crypto
      .createHash('sha256')
      .update(`${webhook.from}:${alias.pk_root}`)
      .digest('hex')
      .substring(0, 32);
    
    const envelope: EnvelopeData = {
      id: envelopeId,
      version: 1,
      fromPublicKey: gatewayEd25519PublicKeyHex,
      toPublicKeys: [alias.pk_root],
      ccPublicKeys: null,
      payloadType: 'gns/email',
      encryptedPayload: encrypted.encryptedPayload,
      payloadSize: payloadBuffer.length,
      threadId: threadId,
      replyToId: null,
      forwardOfId: null,
      timestamp: timestamp,
      expiresAt: null,
      ephemeralPublicKey: encrypted.ephemeralPublicKey,
      recipientKeys: null,
      nonce: encrypted.nonce,
      priority: 1,
    };
    
    // 7. Sign envelope and ADD SIGNATURE TO ENVELOPE
    // ✅ CRITICAL FIX: Hash first, then sign (matching Flutter verification)
    const dataToSign = createCanonicalEnvelopeString(envelope);
    const hash = crypto.createHash('sha256').update(dataToSign, 'utf8').digest();
    console.log(`   📋 Canonical (first 100): ${dataToSign.substring(0, 100)}...`);
    console.log(`   🔢 Hash (first 16 bytes): ${hash.slice(0, 16).toString('hex')}...`);
    const signatureBytes = nacl.sign.detached(
      hash,  // ✅ Sign the HASH, not raw data
      gatewayKeypair!.secretKey
    );
    const signatureHex = toHex(signatureBytes);
    
    // ✅ ADD SIGNATURE TO ENVELOPE!
    envelope.signature = signatureHex;
    
    console.log(`   🔐 Signed envelope (sig: ${signatureHex.substring(0, 16)}...)`);
    
    // 8. Store message (now includes signature)
    const message = await db.createEnvelopeMessage(
      gatewayEd25519PublicKeyHex,
      alias.pk_root,
      envelope,  // ← Now includes signature!
      threadId
    );
    
    // 9. Notify via WebSocket (envelope now includes signature)
    notifyRecipients([alias.pk_root], {
      type: 'message',
      envelope: envelope,  // ← Now includes signature!
    });
    
    console.log(`   ✅ Email delivered as GNS envelope: ${envelopeId.substring(0, 8)}...`);
    console.log(`   Thread: ${threadId.substring(0, 8)}...`);
    
    return res.status(200).json({
      success: true,
      message: 'Email delivered',
      data: {
        envelopeId: envelopeId,
        threadId: threadId,
        recipientHandle: handle,
      },
    } as ApiResponse);
    
  } catch (error) {
    console.error('❌ Inbound email error:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
    } as ApiResponse);
  }
});

// ===========================================
// EMAIL STATUS ENDPOINTS
// ===========================================

router.post('/activate', async (req: Request, res: Response) => {
  try {
    const { handle, publicKey } = req.body;
    
    const normalizedHandle = handle.toLowerCase().replace(/^@/, '');
    const alias = await db.getAliasByHandle(normalizedHandle);
    
    if (!alias) {
      return res.status(404).json({
        success: false,
        error: 'Handle not found',
      } as ApiResponse);
    }
    
    if (alias.pk_root.toLowerCase() !== publicKey.toLowerCase()) {
      return res.status(403).json({
        success: false,
        error: 'Handle does not belong to this identity',
      } as ApiResponse);
    }
    
    const emailAddress = `${normalizedHandle}@${EMAIL_CONFIG.domain}`;
    
    console.log(`📧 Email activated: ${emailAddress}`);
    
    return res.json({
      success: true,
      data: {
        emailAddress: emailAddress,
        domain: EMAIL_CONFIG.domain,
        handle: normalizedHandle,
        activated: true,
      },
    } as ApiResponse);
    
  } catch (error) {
    console.error('Email activation error:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
    } as ApiResponse);
  }
});

router.get('/status/:handle', async (req: Request, res: Response) => {
  try {
    const handle = req.params.handle.toLowerCase().replace(/^@/, '');
    const alias = await db.getAliasByHandle(handle);
    
    if (!alias) {
      return res.status(404).json({
        success: false,
        error: 'Handle not found',
      } as ApiResponse);
    }
    
    return res.json({
      success: true,
      data: {
        handle: handle,
        emailAddress: `${handle}@${EMAIL_CONFIG.domain}`,
        active: true,
        domain: EMAIL_CONFIG.domain,
      },
    } as ApiResponse);
    
  } catch (error) {
    console.error('Email status error:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
    } as ApiResponse);
  }
});

router.get('/gateway/status', (req: Request, res: Response) => {
  return res.json({
    success: true,
    data: getEmailGatewayStatus(),
  } as ApiResponse);
});

// ===========================================
// EXPORT
// ===========================================

export default router;
