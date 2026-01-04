// ===========================================
// GNS NODE - @echo SERVICE BOT (CLEAN DUAL-KEY)
// Uses direct X25519 keys (no Ed25519→X25519 conversion)
// Ed25519: Identity and signatures only
// X25519: Encryption only (fetched from database)
// 
// ✅ FIXED: Handles BOTH snake_case (Tauri/Rust) and camelCase (Flutter) field names
// ===========================================

import * as crypto from 'crypto';
import nacl from 'tweetnacl';
import { encodeBase64, decodeBase64 } from 'tweetnacl-util';
import sodium from 'libsodium-wrappers';
import * as db from '../lib/db';
import { hexToBytes, bytesToHex } from '../lib/crypto';
import { broadcastToUser } from '../api/messages';

// ===========================================
// @echo Bot Configuration
// ===========================================

interface EchoBotConfig {
  handle: string;
  pollIntervalMs: number;
  enabled: boolean;
}

const ECHO_CONFIG: EchoBotConfig = {
  handle: 'echo',
  pollIntervalMs: 5000,
  enabled: true,
};

// ===========================================
// Crypto Constants (match Flutter)
// ===========================================

// HKDF info now built dynamically in deriveKey() to include public keys
const NONCE_LENGTH = 12;  // ChaCha20-Poly1305 uses 12-byte nonce
const MAC_LENGTH = 16;    // Poly1305 MAC is 16 bytes
const KEY_LENGTH = 32;    // ChaCha20 key is 32 bytes

// ===========================================
// Types
// ===========================================

interface EnvelopeData {
  id: string;
  version: number;
  fromPublicKey: string;
  fromHandle?: string;
  toPublicKeys: string[];
  ccPublicKeys: string[] | null;
  payloadType: string;
  encryptedPayload: any;
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
}

// ===========================================
// Helper Functions
// ===========================================

/**
 * Generate a UUID v4
 */
function generateUUID(): string {
  return crypto.randomUUID();
}

/**
 * Create canonical string for envelope signing
 * Uses deterministic JSON serialization (alphabetically sorted keys)
 */
function createCanonicalEnvelopeString(envelope: EnvelopeData): string {
  const canonicalData = {
    id: envelope.id,
    version: envelope.version,
    fromPublicKey: envelope.fromPublicKey,
    fromHandle: envelope.fromHandle || null,
    toPublicKeys: [...envelope.toPublicKeys].sort(),
    ccPublicKeys: envelope.ccPublicKeys ? [...envelope.ccPublicKeys].sort() : null,
    payloadType: envelope.payloadType,
    encryptedPayload: envelope.encryptedPayload,
    payloadSize: envelope.payloadSize,
    threadId: envelope.threadId,
    replyToId: envelope.replyToId,
    forwardOfId: envelope.forwardOfId,
    timestamp: envelope.timestamp,
    expiresAt: envelope.expiresAt,
    ephemeralPublicKey: envelope.ephemeralPublicKey,
    recipientKeys: envelope.recipientKeys,
    nonce: envelope.nonce,
    priority: envelope.priority,
  };

  // Custom canonicalization that EXCLUDES null values (matches Dart client)
  function canonicalize(value: any): string {
    if (value === null) return 'null';
    if (typeof value === 'boolean') return value.toString();
    if (typeof value === 'number') return value.toString();
    if (typeof value === 'string') return JSON.stringify(value);
    if (Array.isArray(value)) {
      const items = value.map(canonicalize).join(',');
      return `[${items}]`;
    }
    if (typeof value === 'object') {
      const keys = Object.keys(value).sort();
      const pairs = keys
        .filter(k => value[k] !== null)  // ✅ CRITICAL: Filter out null values
        .map(k => `${JSON.stringify(k)}:${canonicalize(value[k])}`)
        .join(',');
      return `{${pairs}}`;
    }
    return JSON.stringify(value);
  }

  return canonicalize(canonicalData);
}

// ===========================================
// Bot Keypair Management (DUAL-KEY)
// ===========================================

let echoKeypair: nacl.SignKeyPair | null = null;
let echoEd25519PublicKeyHex: string = '';
let echoEd25519PrivateKeyHex: string = '';
let echoX25519PublicKeyHex: string = '';
let echoX25519PrivateKey: Uint8Array | null = null;
let pollInterval: NodeJS.Timeout | null = null;

/**
 * Initialize or generate the @echo bot keypair
 * ✅ CLEAN: Bot generates SEPARATE X25519 keys for encryption
 */
export async function initializeEchoBot(): Promise<{ publicKey: string; privateKey: string }> {
  // Initialize libsodium before using crypto functions
  await sodium.ready;

  const envPrivateKey = process.env.ECHO_PRIVATE_KEY;
  const envX25519PrivateKey = process.env.ECHO_X25519_PRIVATE_KEY;

  if (envPrivateKey && envPrivateKey.length === 128) {
    const secretKey = hexToBytes(envPrivateKey);
    echoKeypair = {
      publicKey: secretKey.slice(32),
      secretKey: secretKey,
    };
    echoEd25519PublicKeyHex = bytesToHex(echoKeypair.publicKey);
    echoEd25519PrivateKeyHex = envPrivateKey;

    // Load or generate X25519 key (SEPARATE from Ed25519)
    if (envX25519PrivateKey && envX25519PrivateKey.length === 64) {
      echoX25519PrivateKey = hexToBytes(envX25519PrivateKey);
      const x25519Kp = nacl.box.keyPair.fromSecretKey(echoX25519PrivateKey);
      echoX25519PublicKeyHex = bytesToHex(x25519Kp.publicKey);
    } else {
      // Generate new X25519 keypair (SEPARATE)
      const x25519Kp = nacl.box.keyPair();
      echoX25519PrivateKey = x25519Kp.secretKey;
      echoX25519PublicKeyHex = bytesToHex(x25519Kp.publicKey);

      console.log(`   ⚠️  SAVE THIS TO RAILWAY ENV AS ECHO_X25519_PRIVATE_KEY:`);
      console.log(`   ${bytesToHex(echoX25519PrivateKey)}`);
    }

    console.log(`🤖 @echo bot initialized with existing keypair`);
    console.log(`   Ed25519 (identity): ${echoEd25519PublicKeyHex.substring(0, 16)}...`);
    console.log(`   X25519 (encryption): ${echoX25519PublicKeyHex.substring(0, 16)}...`);
    console.log(`   ✅ Using DUAL-KEY architecture (no Ed→X conversion)`);
  } else {
    // Generate new Ed25519 keypair
    echoKeypair = nacl.sign.keyPair();
    echoEd25519PublicKeyHex = bytesToHex(echoKeypair.publicKey);
    echoEd25519PrivateKeyHex = bytesToHex(echoKeypair.secretKey);

    // Generate new X25519 keypair (SEPARATE)
    const x25519Kp = nacl.box.keyPair();
    echoX25519PrivateKey = x25519Kp.secretKey;
    echoX25519PublicKeyHex = bytesToHex(x25519Kp.publicKey);

    console.log(`🤖 @echo bot generated NEW dual keypair`);
    console.log(`   ⚠️  SAVE THESE TO RAILWAY ENV:`);
    console.log(`   ECHO_PRIVATE_KEY=${echoEd25519PrivateKeyHex}`);
    console.log(`   ECHO_X25519_PRIVATE_KEY=${bytesToHex(echoX25519PrivateKey)}`);
    console.log(`   Ed25519 Public: ${echoEd25519PublicKeyHex}`);
    console.log(`   X25519 Public: ${echoX25519PublicKeyHex}`);
  }

  console.log(`   Handle: @${ECHO_CONFIG.handle}`);

  return {
    publicKey: echoEd25519PublicKeyHex,
    privateKey: echoEd25519PrivateKeyHex,
  };
}

/**
 * Get the @echo bot's public key
 */
export function getEchoPublicKey(): string {
  return echoEd25519PublicKeyHex;
}

/**
 * Get handle info for @echo (used by handles.ts)
 */
export function getHandle(): { handle: string; publicKey: string; encryptionKey: string; isSystem: boolean; type: string } | null {
  if (!echoEd25519PublicKeyHex) return null;
  return {
    handle: ECHO_CONFIG.handle,
    publicKey: echoEd25519PublicKeyHex,         // Ed25519 identity key
    encryptionKey: echoX25519PublicKeyHex,      // X25519 encryption key (SEPARATE)
    isSystem: true,
    type: 'echo_bot',
  };
}

/**
 * Register @echo handle in database
 */
export async function registerHandle(): Promise<boolean> {
  console.log(`📝 @${ECHO_CONFIG.handle} handle available (in-memory, pk: ${echoEd25519PublicKeyHex.substring(0, 16)}...)`);
  return true;
}

/**
 * Get bot status for health endpoint
 */
export function getEchoBotStatus() {
  return {
    enabled: ECHO_CONFIG.enabled,
    running: pollInterval !== null,
    publicKey: echoEd25519PublicKeyHex,           // Ed25519 identity
    encryptionKey: echoX25519PublicKeyHex,        // X25519 encryption (SEPARATE)
    handle: `@${ECHO_CONFIG.handle}`,
  };
}

// ===========================================
// Crypto Helper Functions
// ===========================================

/**
 * Generate ephemeral X25519 keypair
 */
function generateEphemeralKeyPair(): { publicKey: Uint8Array; privateKey: Uint8Array } {
  const keypair = nacl.box.keyPair();
  return {
    publicKey: keypair.publicKey,
    privateKey: keypair.secretKey,
  };
}

/**
 * Perform X25519 key exchange
 */
function x25519SharedSecret(privateKey: Uint8Array, publicKey: Uint8Array): Buffer {
  // Use nacl scalarMult for X25519 Diffie-Hellman
  const shared = nacl.scalarMult(privateKey, publicKey);
  return Buffer.from(shared);
}

/**
 * Derive encryption key using HKDF (SHA256)
 * ✅ FIXED: Match Tauri/Rust format - info includes public keys
 */
function deriveKey(
  sharedSecret: Buffer,
  ephemeralPublicKey: Buffer,
  recipientPublicKey: Buffer
): Buffer {
  // Info = "gns-envelope-v1:" + ephemeral_pub (32 bytes) + recipient_pub (32 bytes)
  // This MUST match the Rust implementation!
  const info = Buffer.concat([
    Buffer.from('gns-envelope-v1:'),
    ephemeralPublicKey,
    recipientPublicKey
  ]);

  const derivedKey = crypto.hkdfSync(
    'sha256',
    sharedSecret,
    Buffer.alloc(0),  // No salt
    info,
    KEY_LENGTH
  );
  return Buffer.from(derivedKey);
}

/**
 * Decrypt with ChaCha20-Poly1305 (Flutter-compatible)
 * 🚨 CRITICAL: This function decrypts incoming messages to the bot
 * ✅ FIXED: Use correct HKDF info with public keys
 */
function decryptFromSender(
  encryptedPayload: string,
  ephemeralPublicKey: string,
  nonceStr: string
): Buffer | null {
  try {
    // FIXED:
    const encrypted = Buffer.from(encryptedPayload, 'base64');
    const ephemeralPub = Buffer.from(ephemeralPublicKey, 'base64');
    const nonce = Buffer.from(nonceStr, 'base64');

    // 1. Check for the SEPARATE X25519 private key
    if (!echoX25519PrivateKey) {
      throw new Error('Echo X25519 private key not initialized for decryption');
    }

    // 2. Get bot's X25519 public key (recipient)
    const botX25519PublicKey = Buffer.from(hexToBytes(echoX25519PublicKeyHex));

    // 3. Derive shared secret using the correct private key
    const sharedSecret = x25519SharedSecret(
      echoX25519PrivateKey, // 🔑 Bot's X25519 Private Key
      ephemeralPub
    );

    // 4. Derive decryption key with HKDF (including public keys in info!)
    const decryptionKey = deriveKey(sharedSecret, ephemeralPub, botX25519PublicKey);

    // 5. Decrypt payload
    const ciphertext = encrypted.slice(0, encrypted.length - MAC_LENGTH);
    const authTag = encrypted.slice(encrypted.length - MAC_LENGTH);

    const decipher = crypto.createDecipheriv('chacha20-poly1305', decryptionKey, nonce, {
      authTagLength: MAC_LENGTH,
    });
    decipher.setAuthTag(authTag);

    const decrypted = Buffer.concat([
      decipher.update(ciphertext),
      decipher.final(),
    ]);

    return decrypted;
  } catch (error) {
    console.error('   ⚠️ Decryption error (MAC FAILED):', error);
    return null;
  }
}

/**
 * Decrypt with ChaCha20-Poly1305 (Tauri/Rust format - HEX encoded)
 * 🚨 CRITICAL: Tauri sends HEX, not Base64!
 * ✅ FIXED: Use correct HKDF info with public keys
 */
function decryptFromSenderHex(
  ciphertextHex: string,
  ephemeralPublicKeyHex: string,
  nonceHex: string
): Buffer | null {
  try {
    const encrypted = Buffer.from(ciphertextHex, 'hex');
    const ephemeralPub = Buffer.from(ephemeralPublicKeyHex, 'hex');
    const nonce = Buffer.from(nonceHex, 'hex');

    // 1. Check for the SEPARATE X25519 private key
    if (!echoX25519PrivateKey) {
      throw new Error('Echo X25519 private key not initialized for decryption');
    }

    // 2. Get bot's X25519 public key (recipient)
    const botX25519PublicKey = Buffer.from(hexToBytes(echoX25519PublicKeyHex));

    // 3. Derive shared secret using the correct private key
    const sharedSecret = x25519SharedSecret(
      echoX25519PrivateKey, // 🔑 Bot's X25519 Private Key
      ephemeralPub
    );

    // 4. Derive decryption key with HKDF (including public keys in info!)
    const decryptionKey = deriveKey(sharedSecret, ephemeralPub, botX25519PublicKey);

    // 5. Decrypt payload (ciphertext includes auth tag at the end)
    const ciphertext = encrypted.slice(0, encrypted.length - MAC_LENGTH);
    const authTag = encrypted.slice(encrypted.length - MAC_LENGTH);

    const decipher = crypto.createDecipheriv('chacha20-poly1305', decryptionKey, nonce, {
      authTagLength: MAC_LENGTH,
    });
    decipher.setAuthTag(authTag);

    const decrypted = Buffer.concat([
      decipher.update(ciphertext),
      decipher.final(),
    ]);

    return decrypted;
  } catch (error) {
    console.error('   ⚠️ Decryption error (HEX format):', error);
    console.error(`      ciphertext length: ${ciphertextHex?.length}`);
    console.error(`      ephKey type: ${typeof ephemeralPublicKeyHex}, length: ${ephemeralPublicKeyHex?.length}, value: ${ephemeralPublicKeyHex?.substring(0, 16)}...`);
    console.error(`      nonce length: ${nonceHex?.length}`);
    return null;
  }
}

/**
 * Encrypt for recipient using ChaCha20-Poly1305
 * ✅ FIXED: Use correct HKDF info with public keys
 */
function encryptForRecipient(
  payload: Buffer,
  recipientX25519PublicKey: Uint8Array
): {
  encryptedPayload: string;
  ephemeralPublicKey: string;
  nonce: string;
} {
  // 1. Generate ephemeral keypair
  const ephemeral = generateEphemeralKeyPair();

  // 2. Derive shared secret
  const sharedSecret = x25519SharedSecret(ephemeral.privateKey, recipientX25519PublicKey);

  // 3. Derive encryption key with HKDF (including public keys in info!)
  const ephemeralPubBuffer = Buffer.from(ephemeral.publicKey);
  const recipientPubBuffer = Buffer.from(recipientX25519PublicKey);
  const encryptionKey = deriveKey(sharedSecret, ephemeralPubBuffer, recipientPubBuffer);

  // 4. Generate random nonce
  const nonce = crypto.randomBytes(NONCE_LENGTH);

  // 5. Encrypt with ChaCha20-Poly1305
  const cipher = crypto.createCipheriv('chacha20-poly1305', encryptionKey, nonce, {
    authTagLength: MAC_LENGTH,
  });

  const encrypted = Buffer.concat([
    cipher.update(payload),
    cipher.final(),
    cipher.getAuthTag(),
  ]);

  return {
    encryptedPayload: encrypted.toString('base64'),
    ephemeralPublicKey: encodeBase64(ephemeral.publicKey),  // ✅ BASE64 (matches client)
    nonce: nonce.toString('base64'),
  };
}

// ===========================================
// Message Processing
// ===========================================

/**
 * Create an echo response message
 * ✅ CLEAN: Uses recipient's X25519 key directly from database (NO conversion)
 */
async function createEchoResponse(
  originalFromPk: string,
  originalContent: string | null
): Promise<{
  envelope: EnvelopeData;
  signature: string;
}> {
  // Create response content
  const responseContent = {
    type: 'text',
    text: originalContent
      ? `📣 Echo: "${originalContent.substring(0, 100)}${originalContent.length > 100 ? '...' : ''}"`
      : '📣 Echo received your message!',
    format: 'plain',
  };

  const payload = Buffer.from(JSON.stringify(responseContent), 'utf8');

  // ✅ CLEAN: Fetch recipient's X25519 encryption key directly from database
  // NO Ed25519→X25519 conversion needed!
  console.log(`   Fetching recipient X25519 key from database...`);
  const recipientRecord = await db.getRecord(originalFromPk);

  if (!recipientRecord) {
    throw new Error(`Recipient record not found: ${originalFromPk}`);
  }

  if (!recipientRecord.encryption_key) {
    throw new Error(`Recipient has no X25519 encryption_key: ${originalFromPk}`);
  }

  const recipientX25519 = hexToBytes(recipientRecord.encryption_key);

  console.log(`   ✅ Using recipient's X25519 key directly from database`);
  console.log(`   Ed25519 (identity):  ${originalFromPk.substring(0, 16)}...`);
  console.log(`   X25519 (encryption): ${recipientRecord.encryption_key.substring(0, 16)}...`);

  // Encrypt using recipient's X25519 key (no conversion!)
  const encrypted = encryptForRecipient(payload, recipientX25519);

  // Create envelope data
  const envelopeId = generateUUID();
  const timestamp = Date.now();

  const envelope: EnvelopeData = {
    id: envelopeId,
    version: 1,
    fromPublicKey: echoEd25519PublicKeyHex,  // Ed25519 for identity
    fromHandle: ECHO_CONFIG.handle,
    toPublicKeys: [originalFromPk],
    ccPublicKeys: null,
    payloadType: 'gns/text.plain',
    // ✅ FIXED: Nested encryptedPayload for Tauri/Rust compatibility (HEX encoding)
    encryptedPayload: {
      ciphertext: Buffer.from(encrypted.encryptedPayload, 'base64').toString('hex'),
      ephemeralPublicKey: Buffer.from(encrypted.ephemeralPublicKey, 'base64').toString('hex'),
      nonce: Buffer.from(encrypted.nonce, 'base64').toString('hex'),
    },
    payloadSize: payload.length,
    threadId: null,
    replyToId: null,
    forwardOfId: null,
    timestamp: timestamp,
    expiresAt: null,
    // Keep top-level fields for legacy compatibility (optional)
    ephemeralPublicKey: encrypted.ephemeralPublicKey,
    recipientKeys: null,
    nonce: encrypted.nonce,
    priority: 1,
  };

  // Sign envelope with Ed25519 key
  const dataToSign = createCanonicalEnvelopeString(envelope);

  // Hash with SHA256 (CRITICAL: Must match client verification)
  // Client verifies: algorithm.verify(SHA256(canonicalJSON), signature)
  const canonicalHash = crypto.createHash('sha256')
    .update(dataToSign, 'utf8')
    .digest();

  const signature = nacl.sign.detached(
    canonicalHash,  // Sign the HASH, not raw bytes
    echoKeypair!.secretKey
  );

  console.log(`   ✅ Response envelope created: ${envelopeId.substring(0, 8)}...`);
  console.log(`   ✅ Encrypted with recipient's X25519 key (no conversion)`);

  return {
    envelope,
    signature: bytesToHex(signature),
  };
}

// ===========================================
// Message Processing
// ===========================================

/**
 * Process incoming messages and send echo responses
 * ✅ FIXED: Handles BOTH snake_case (Tauri/Rust) and camelCase (Flutter) field names
 */
async function processIncomingMessages(): Promise<void> {
  if (!ECHO_CONFIG.enabled) return;

  try {
    // Fetch unread messages for the bot
    const messages = await db.getInbox(echoEd25519PublicKeyHex);

    if (!messages || messages.length === 0) {
      return;
    }

    console.log(`📨 @echo processing ${messages.length} message(s)`);

    for (const msg of messages) {
      try {
        // ✅ CRITICAL FIX: Skip messages FROM the bot itself!
        if (msg.from_pk === echoEd25519PublicKeyHex) {
          console.log(`   ⏭️  Skipping message from self: ${msg.id.substring(0, 8)}...`);
          await db.markMessageDelivered(msg.id);
          continue;
        }

        // Get envelope from JSONB column (already parsed)
        let envelope: any = msg.envelope;

        if (!envelope) {
          console.warn(`   ⚠️ Message ${msg.id} has no envelope, skipping`);
          continue;
        }

        // =====================================================
        // ✅ FIXED: Handle BOTH snake_case and camelCase field names
        // Tauri/Rust sends: encrypted_payload, ephemeral_public_key, from_public_key
        // Flutter sends: encryptedPayload, ephemeralPublicKey, fromPublicKey
        // =====================================================

        // Try camelCase first (Flutter), then snake_case (Tauri)
        let encPayload = envelope.encryptedPayload || envelope.encrypted_payload;
        let ephKey = envelope.ephemeralPublicKey || envelope.ephemeral_public_key;
        let nonceVal = envelope.nonce;
        let payloadType = envelope.payloadType || envelope.payload_type || 'gns/text.plain';
        let fromPk = envelope.fromPublicKey || envelope.from_public_key || msg.from_pk;

        // Debug: Log what format we received
        console.log(`   📩 Message ${msg.id.substring(0, 8)}... format check:`);
        console.log(`      encryptedPayload (camel): ${envelope.encryptedPayload ? 'YES' : 'NO'}`);
        console.log(`      encrypted_payload (snake): ${envelope.encrypted_payload ? 'YES' : 'NO'}`);

        let isTauriFormat = false;

        // If encryptedPayload is an object (Rust nested format), extract inner fields
        if (typeof encPayload === 'object' && encPayload !== null) {
          console.log(`      Detected nested encrypted_payload object (Tauri format)`);
          isTauriFormat = true;
          // Tauri sends: { ciphertext, ephemeral_public_key, nonce }
          ephKey = encPayload.ephemeral_public_key || encPayload.ephemeralPublicKey || ephKey;
          nonceVal = encPayload.nonce || nonceVal;
          encPayload = encPayload.ciphertext;
        }

        if (!encPayload || !ephKey || !nonceVal) {
          console.warn(`   ⚠️ Message ${msg.id} missing encryption fields, skipping`);
          continue;
        }

        // =====================================================
        // ✅ FIXED: Detect encoding format (HEX vs Base64)
        // Tauri sends HEX, Flutter sends Base64
        // =====================================================

        let decrypted: Buffer | null = null;

        // Check if it looks like HEX (only 0-9, a-f characters)
        const isHex = /^[0-9a-fA-F]+$/.test(encPayload);

        // Force Hex if we detected Tauri format, OR if it looks like Hex and is long enough
        if (isTauriFormat || (isHex && encPayload.length > 100)) {
          // Tauri/Rust format: HEX encoded
          console.log(`      Detected HEX encoding (Tauri format)`);
          decrypted = decryptFromSenderHex(encPayload, ephKey, nonceVal);
        } else {
          // Flutter format: Base64 encoded
          console.log(`      Detected Base64 encoding (Flutter format)`);
          decrypted = decryptFromSender(encPayload, ephKey, nonceVal);
        }

        if (!decrypted) {
          console.warn(`   ⚠️ Failed to decrypt message ${msg.id}, skipping`);
          continue;
        }

        // Parse decrypted content
        let content: any;
        try {
          content = JSON.parse(decrypted.toString('utf8'));
        } catch {
          content = { type: 'unknown', text: decrypted.toString('utf8') };
        }

        console.log(`   📩 Decrypted message from ${(fromPk || msg.from_pk).substring(0, 16)}...`);
        console.log(`   Type: ${content.type}, Text: ${content.text?.substring(0, 50) || 'N/A'}`);

        // Skip delete messages, reactions, receipts, typing indicators, etc.
        if (payloadType !== 'gns/text.plain' && payloadType !== 'text/plain') {
          console.log(`   ⏭️  Skipping non-text message type: ${payloadType}`);
          await db.markMessageDelivered(msg.id);
          continue;
        }
        console.log(`   ✅ Processing text message for echo response...`);

        // Create and send echo response
        const response = await createEchoResponse(
          msg.from_pk,
          content.text || null
        );

        // Add signature to envelope
        const envelopeWithSignature = {
          ...response.envelope,
          signature: response.signature,
        };

        // Store response in database using envelope method
        await db.createEnvelopeMessage(
          response.envelope.fromPublicKey,
          response.envelope.toPublicKeys[0],
          envelopeWithSignature,
          null  // threadId
        );

        console.log(`   ✅ Echo response sent to ${msg.from_pk.substring(0, 16)}...`);

        // ✅ NEW: Notify mobile via WebSocket
        try {
          broadcastToUser(msg.from_pk, {
            type: 'message',
            data: envelopeWithSignature
          });
          console.log(`   📱 Notified mobile of echo response via WebSocket`);
        } catch (wsError) {
          console.warn(`   ⚠️ Failed to notify via WebSocket (non-fatal):`, wsError);
        }

        // Mark original message as delivered
        await db.markMessageDelivered(msg.id);

      } catch (error: any) {
        console.error(`   ❌ Error processing message ${msg.id}:`, error);

        // ✅ FIXED: If recipient not found (orphaned identity), mark as delivered to stop infinite retries
        if (error.message && error.message.includes('Recipient record not found')) {
          console.warn(`   ⚠️ Orphaned message from unknown identity ${msg.from_pk.substring(0, 16)}... - Marking as delivered to clear queue`);
          await db.markMessageDelivered(msg.id);
        }
      }
    }
  } catch (error) {
    console.error('❌ Error in processIncomingMessages:', error);
  }
}

// ===========================================
// Polling Control
// ===========================================

/**
 * Start polling for incoming messages
 */
export function startPolling(): void {
  if (pollInterval) {
    console.log('⚠️ @echo polling already running');
    return;
  }

  if (!ECHO_CONFIG.enabled) {
    console.log('⚠️ @echo bot is disabled');
    return;
  }

  console.log(`🔄 @echo polling started (interval: ${ECHO_CONFIG.pollIntervalMs}ms)`);

  // Process immediately, then start interval
  processIncomingMessages().catch(err => {
    console.error('Error in initial message processing:', err);
  });

  pollInterval = setInterval(() => {
    processIncomingMessages().catch(err => {
      console.error('Error in message processing:', err);
    });
  }, ECHO_CONFIG.pollIntervalMs);
}

/**
 * Stop polling for incoming messages
 */
export function stopPolling(): void {
  if (!pollInterval) {
    console.log('⚠️ @echo polling not running');
    return;
  }

  clearInterval(pollInterval);
  pollInterval = null;
  console.log('🛑 @echo polling stopped');
}

// ===========================================
// Exports
// ===========================================

export default {
  initializeEchoBot,
  startPolling,
  stopPolling,
  getHandle,
  getEchoPublicKey,
  registerHandle,
  getEchoBotStatus,
};
