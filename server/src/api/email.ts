// ===========================================
// GNS NODE - EMAIL GATEWAY SERVICE
// Receives inbound emails from Cloudflare Worker
// Sends outbound emails via SMTP
// Routes GNS-to-GNS emails internally
// ===========================================

import { Router, Request, Response } from 'express';
import * as crypto from 'crypto';
import nacl from 'tweetnacl';
import sodium from 'libsodium-wrappers';
import * as db from '../lib/db';
import { notifyRecipients } from './messages';
import { ApiResponse } from '../types';
import { createTransport, Transporter } from 'nodemailer';

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
  domain: 'gcrumbs.com',
};

// ===========================================
// SMTP CONFIGURATION (OUTBOUND)
// ===========================================

const SMTP_CONFIG = {
  host: process.env.SMTP_HOST || 'smtp.mailgun.org',
  port: parseInt(process.env.SMTP_PORT || '587'),
  user: process.env.SMTP_USER || '',
  pass: process.env.SMTP_PASS || '',
};

let smtpTransporter: Transporter | null = null;

function getSmtpTransporter(): Transporter | null {
  if (!SMTP_CONFIG.user || !SMTP_CONFIG.pass) {
    return null;
  }
  
  if (!smtpTransporter) {
    smtpTransporter = createTransport({
      host: SMTP_CONFIG.host,
      port: SMTP_CONFIG.port,
      secure: SMTP_CONFIG.port === 465,
      auth: {
        user: SMTP_CONFIG.user,
        pass: SMTP_CONFIG.pass,
      },
    });
    
    // Verify connection
    smtpTransporter.verify((error) => {
      if (error) {
        console.error('❌ SMTP connection error:', error);
        smtpTransporter = null;
      } else {
        console.log('✅ SMTP server ready for outbound email');
      }
    });
  }
  
  return smtpTransporter;
}

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
  const derivedKey = crypto.hkdfSync(
    'sha256',
    Buffer.from(sharedSecret),
    Buffer.alloc(0),
    Buffer.from(info, 'utf8'),
    KEY_LENGTH
  );
  return new Uint8Array(derivedKey);
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
  const sharedSecret = nacl.scalarMult(ephemeralKeypair.secretKey, recipientX25519PublicKey);

  // DEBUG: Log keys for troubleshooting
  console.log(`   🔑 Recipient X25519: ${toHex(recipientX25519PublicKey).substring(0, 16)}...`);
  console.log(`   🔑 Ephemeral public: ${toHex(ephemeralKeypair.publicKey).substring(0, 16)}...`);
  console.log(`   🔑 Shared secret: ${toHex(sharedSecret).substring(0, 16)}...`);

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
    ephemeralPublicKey: Buffer.from(ephemeralKeypair.publicKey).toString('base64'),
    nonce: nonce.toString('base64'),
  };
}

/**
 * Create canonical JSON string for signing (ALPHABETICAL ORDER - must match Flutter!)
 */
function createCanonicalEnvelopeString(envelope: EnvelopeData): string {
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
  to?: string;
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
  signature?: string;
}

interface AuthenticatedRequest extends Request {
  gnsPublicKey?: string;
  gnsHandle?: string;
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
  
  // Check SMTP config
  if (SMTP_CONFIG.user && SMTP_CONFIG.pass) {
    console.log(`   SMTP: ${SMTP_CONFIG.host}:${SMTP_CONFIG.port} ✅`);
    getSmtpTransporter(); // Initialize
  } else {
    console.log(`   SMTP: Not configured (outbound disabled)`);
  }

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
// MIDDLEWARE
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

const verifyGnsAuth = async (
  req: AuthenticatedRequest, 
  res: Response, 
  next: Function
) => {
  try {
    const publicKey = (req.headers['x-gns-publickey'] as string)?.toLowerCase();
    const timestamp = req.headers['x-gns-timestamp'] as string;
    const signature = req.headers['x-gns-signature'] as string;

    if (!publicKey || publicKey.length !== 64) {
      return res.status(401).json({
        success: false,
        error: 'Missing or invalid X-GNS-PublicKey header',
      } as ApiResponse);
    }

    // Look up handle for this public key
    const alias = await db.getAliasByPk(publicKey);
    if (!alias) {
      return res.status(403).json({
        success: false,
        error: 'No handle claimed for this public key. Claim a handle first to send emails.',
      } as ApiResponse);
    }

    req.gnsPublicKey = publicKey;
    req.gnsHandle = alias.handle;
    next();
  } catch (error) {
    console.error('Auth error:', error);
    res.status(401).json({ success: false, error: 'Authentication failed' });
  }
};

// ===========================================
// PARSE EMAIL BODY FROM RAW MIME
// ===========================================

function decodeQuotedPrintable(str: string): string {
  return str
    .replace(/=\r?\n/g, '')
    .replace(/=([0-9A-F]{2})/gi, (_, hex) =>
      String.fromCharCode(parseInt(hex, 16))
    );
}

function parseEmailBody(rawBase64: string): { text: string; html?: string } {
  try {
    const raw = Buffer.from(rawBase64, 'base64').toString('utf-8');

    const boundaryMatch = raw.match(/boundary="?([^"\r\n]+)"?/i);

    if (boundaryMatch) {
      const boundary = boundaryMatch[1];
      const parts = raw.split(`--${boundary}`);

      let textBody = '';
      let htmlBody = '';

      for (const part of parts) {
        if (part.includes('Content-Type: text/plain')) {
          const bodyStart = part.indexOf('\r\n\r\n');
          if (bodyStart !== -1) {
            textBody = part.substring(bodyStart + 4).trim();
            textBody = textBody.replace(/--$/, '').trim();
            if (part.includes('Content-Transfer-Encoding: quoted-printable')) {
              textBody = decodeQuotedPrintable(textBody);
            }
          }
        } else if (part.includes('Content-Type: text/html')) {
          const bodyStart = part.indexOf('\r\n\r\n');
          if (bodyStart !== -1) {
            htmlBody = part.substring(bodyStart + 4).trim();
            htmlBody = htmlBody.replace(/--$/, '').trim();
            if (part.includes('Content-Transfer-Encoding: quoted-printable')) {
              htmlBody = decodeQuotedPrintable(htmlBody);
            }
          }
        }
      }

      return {
        text: textBody || htmlBody || '[No content]',
        html: htmlBody || undefined
      };
    }

    const parts = raw.split('\r\n\r\n');
    if (parts.length > 1) {
      return { text: parts.slice(1).join('\r\n\r\n') };
    }

    return { text: raw };
  } catch (error) {
    console.error('Error parsing email body:', error);
    return { text: '[Could not parse email body]' };
  }
}

// ===========================================
// POST /email/inbound - RECEIVE FROM CLOUDFLARE
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
      to: webhook.to,
      messageId: webhook.headers?.messageId,
      receivedAt: webhook.receivedAt,
    };

    const payloadBuffer = Buffer.from(JSON.stringify(emailPayload), 'utf8');

    // 5. Encrypt for recipient
    const recipientX25519 = toBytes(record.encryption_key);
    const encrypted = encryptForRecipient(payloadBuffer, recipientX25519);

    // 6. Create GNS Envelope
    const envelopeId = generateUUID();
    const timestamp = Date.now();

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

    // 7. Sign envelope
    const dataToSign = createCanonicalEnvelopeString(envelope);
    const hash = crypto.createHash('sha256').update(dataToSign, 'utf8').digest();
    console.log(`   📋 Canonical (first 100): ${dataToSign.substring(0, 100)}...`);
    console.log(`   🔢 Hash (first 16 bytes): ${hash.slice(0, 16).toString('hex')}...`);
    const signatureBytes = nacl.sign.detached(hash, gatewayKeypair!.secretKey);
    const signatureHex = toHex(signatureBytes);

    envelope.signature = signatureHex;

    console.log(`   🔐 Signed envelope (sig: ${signatureHex.substring(0, 16)}...)`);

    // 8. Store message
    const message = await db.createEnvelopeMessage(
      gatewayEd25519PublicKeyHex,
      alias.pk_root,
      envelope,
      threadId
    );

    // 9. Notify via WebSocket
    notifyRecipients([alias.pk_root], {
      type: 'message',
      envelope: envelope,
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
// POST /email/send - SEND OUTBOUND EMAIL
// ===========================================

router.post('/send', verifyGnsAuth, async (req: AuthenticatedRequest, res: Response) => {
  try {
    const { to, subject, body, bodyFormat, inReplyTo, references } = req.body;
    
    // Validate required fields
    if (!to || !body) {
      return res.status(400).json({
        success: false,
        error: 'Missing required fields: to, body',
      } as ApiResponse);
    }
    
    // Validate email format
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(to)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid recipient email address',
      } as ApiResponse);
    }
    
    // Check if recipient is a GNS handle (internal routing)
    const toMatch = to.match(/^([^@]+)@gcrumbs\.com$/i);
    if (toMatch) {
      // Internal GNS-to-GNS email
      return await sendInternalEmail(req, res, toMatch[1], subject, body, bodyFormat);
    }
    
    // External email - use SMTP
    const smtp = getSmtpTransporter();
    if (!smtp) {
      return res.status(503).json({
        success: false,
        error: 'Outbound email service not configured. SMTP credentials required.',
      } as ApiResponse);
    }
    
    // Build from address
    const fromEmail = `${req.gnsHandle}@${EMAIL_CONFIG.domain}`;
    const fromAddress = `${req.gnsHandle} <${fromEmail}>`;
    
    // Build email headers
    const headers: Record<string, string> = {
      'X-GNS-PublicKey': req.gnsPublicKey!,
      'X-GNS-Handle': `@${req.gnsHandle}`,
      'X-Mailer': 'GNS Email Gateway',
    };
    
    if (inReplyTo) {
      headers['In-Reply-To'] = inReplyTo;
    }
    if (references && Array.isArray(references)) {
      headers['References'] = references.join(' ');
    }
    
    // Send email
    const mailOptions = {
      from: fromAddress,
      to: to,
      subject: subject || '(No subject)',
      text: bodyFormat === 'html' ? undefined : body,
      html: bodyFormat === 'html' ? body : undefined,
      headers: headers,
      replyTo: fromEmail,
    };
    
    console.log(`📤 Sending outbound email:`);
    console.log(`   From: ${fromEmail}`);
    console.log(`   To: ${to}`);
    console.log(`   Subject: ${subject}`);
    
    const result = await smtp.sendMail(mailOptions);
    
    console.log(`✅ Email sent: ${result.messageId}`);
    
    return res.json({
      success: true,
      data: {
        messageId: result.messageId,
        from: fromEmail,
        to: to,
        subject: subject || '(No subject)',
        sentAt: new Date().toISOString(),
      },
      message: 'Email sent successfully',
    } as ApiResponse);
    
  } catch (error: any) {
    console.error('❌ POST /email/send error:', error);
    
    if (error.code === 'ECONNREFUSED') {
      return res.status(503).json({
        success: false,
        error: 'Email server unavailable',
      } as ApiResponse);
    }
    
    if (error.responseCode === 550) {
      return res.status(400).json({
        success: false,
        error: 'Recipient address rejected by mail server',
      } as ApiResponse);
    }
    
    return res.status(500).json({
      success: false,
      error: 'Failed to send email',
    } as ApiResponse);
  }
});

// ===========================================
// INTERNAL GNS-TO-GNS EMAIL
// ===========================================

async function sendInternalEmail(
  req: AuthenticatedRequest,
  res: Response,
  recipientHandle: string,
  subject: string,
  body: string,
  bodyFormat?: string
): Promise<Response> {
  try {
    const handle = recipientHandle.toLowerCase().replace(/^@/, '');
    
    // Look up recipient
    const alias = await db.getAliasByHandle(handle);
    if (!alias) {
      return res.status(404).json({
        success: false,
        error: `Recipient @${handle} not found`,
      } as ApiResponse);
    }
    
    // Get recipient's encryption key
    const record = await db.getRecord(alias.pk_root);
    if (!record || !record.encryption_key) {
      return res.status(400).json({
        success: false,
        error: 'Recipient has no encryption key configured',
      } as ApiResponse);
    }
    
    console.log(`📧 Internal GNS email: @${req.gnsHandle} → @${handle}`);
    
    // Create email payload
    const emailPayload: EmailPayload = {
      type: 'email',
      subject: subject || '(No subject)',
      body: body,
      bodyFormat: (bodyFormat as 'plain' | 'html') || 'plain',
      from: `${req.gnsHandle}@${EMAIL_CONFIG.domain}`,
      to: `${handle}@${EMAIL_CONFIG.domain}`,
      receivedAt: new Date().toISOString(),
    };
    
    const payloadBuffer = Buffer.from(JSON.stringify(emailPayload), 'utf8');
    
    // Encrypt for recipient
    const recipientX25519 = toBytes(record.encryption_key);
    const encrypted = encryptForRecipient(payloadBuffer, recipientX25519);
    
    // Create envelope
    const envelopeId = generateUUID();
    const timestamp = Date.now();
    
    // Thread ID for GNS-to-GNS emails (different from external)
    const threadId = crypto
      .createHash('sha256')
      .update(`gns-email:${req.gnsPublicKey}:${alias.pk_root}`)
      .digest('hex')
      .substring(0, 32);
    
    const envelope: EnvelopeData = {
      id: envelopeId,
      version: 1,
      fromPublicKey: req.gnsPublicKey!,  // Sender's key, not gateway
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
    
    // Sign with gateway key for now (TODO: client-side signing)
    const dataToSign = createCanonicalEnvelopeString(envelope);
    const hash = crypto.createHash('sha256').update(dataToSign, 'utf8').digest();
    const signatureBytes = nacl.sign.detached(hash, gatewayKeypair!.secretKey);
    envelope.signature = toHex(signatureBytes);
    
    // Store message
    await db.createEnvelopeMessage(
      req.gnsPublicKey!,
      alias.pk_root,
      envelope,
      threadId
    );
    
    // Notify via WebSocket
    notifyRecipients([alias.pk_root], {
      type: 'message',
      envelope: envelope,
    });
    
    console.log(`✅ Internal email delivered: ${envelopeId.substring(0, 8)}...`);
    
    return res.json({
      success: true,
      data: {
        messageId: envelopeId,
        from: `${req.gnsHandle}@${EMAIL_CONFIG.domain}`,
        to: `${handle}@${EMAIL_CONFIG.domain}`,
        subject: subject || '(No subject)',
        sentAt: new Date().toISOString(),
        internal: true,
      },
      message: 'Email delivered internally via GNS',
    } as ApiResponse);
    
  } catch (error) {
    console.error('❌ Internal email error:', error);
    return res.status(500).json({
      success: false,
      error: 'Failed to deliver internal email',
    } as ApiResponse);
  }
}

// ===========================================
// STATUS ENDPOINTS
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

router.get('/address', verifyGnsAuth, async (req: AuthenticatedRequest, res: Response) => {
  try {
    const emailAddress = `${req.gnsHandle}@${EMAIL_CONFIG.domain}`;
    const smtp = getSmtpTransporter();
    
    return res.json({
      success: true,
      data: {
        handle: req.gnsHandle,
        email: emailAddress,
        domain: EMAIL_CONFIG.domain,
        publicKey: req.gnsPublicKey,
        canSend: smtp !== null,
        canReceive: true,
      },
    } as ApiResponse);
    
  } catch (error) {
    console.error('GET /email/address error:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
    } as ApiResponse);
  }
});

router.get('/gateway/status', (req: Request, res: Response) => {
  const smtp = getSmtpTransporter();
  
  return res.json({
    success: true,
    data: {
      ...getEmailGatewayStatus(),
      smtp: {
        configured: !!(SMTP_CONFIG.user && SMTP_CONFIG.pass),
        ready: smtp !== null,
        host: SMTP_CONFIG.host,
      },
      features: {
        inbound: true,
        outbound: smtp !== null,
        internalRouting: true,
      },
    },
  } as ApiResponse);
});

// ===========================================
// EXPORT
// ===========================================

export default router;
