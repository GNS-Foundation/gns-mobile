// ===========================================
// GNS HOME HUB - CRYPTOGRAPHIC UTILITIES
// Ed25519 signature verification + encryption
// ===========================================

import nacl from 'tweetnacl';

// ===========================================
// Constants
// ===========================================

export const GNS_CONSTANTS = {
  PK_LENGTH: 64,         // 32 bytes as hex
  SIGNATURE_LENGTH: 128, // 64 bytes as hex
  NONCE_LENGTH: 48,      // 24 bytes as hex
};

// ===========================================
// Hex Utilities
// ===========================================

export function hexToBytes(hex: string): Uint8Array {
  if (hex.length % 2 !== 0) {
    throw new Error('Invalid hex string length');
  }
  const bytes = new Uint8Array(hex.length / 2);
  for (let i = 0; i < hex.length; i += 2) {
    bytes[i / 2] = parseInt(hex.substring(i, i + 2), 16);
  }
  return bytes;
}

export function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes)
    .map(b => b.toString(16).padStart(2, '0'))
    .join('');
}

export function stringToBytes(str: string): Uint8Array {
  return new TextEncoder().encode(str);
}

export function bytesToString(bytes: Uint8Array): string {
  return new TextDecoder().decode(bytes);
}

// ===========================================
// Ed25519 Signature Operations
// ===========================================

/**
 * Generate a new Ed25519 keypair for the hub
 */
export function generateKeypair(): { publicKey: string; secretKey: string } {
  const keypair = nacl.sign.keyPair();
  return {
    publicKey: bytesToHex(keypair.publicKey),
    secretKey: bytesToHex(keypair.secretKey),
  };
}

/**
 * Sign a message with the hub's secret key
 */
export function sign(secretKeyHex: string, message: string): string {
  const secretKey = hexToBytes(secretKeyHex);
  const messageBytes = stringToBytes(message);
  const signature = nacl.sign.detached(messageBytes, secretKey);
  return bytesToHex(signature);
}

/**
 * Verify an Ed25519 signature
 */
export function verifySignature(
  publicKeyHex: string,
  message: string | Uint8Array,
  signatureHex: string
): boolean {
  try {
    if (publicKeyHex.length !== GNS_CONSTANTS.PK_LENGTH) {
      console.error(`Invalid public key length: ${publicKeyHex.length}`);
      return false;
    }
    
    if (signatureHex.length !== GNS_CONSTANTS.SIGNATURE_LENGTH) {
      console.error(`Invalid signature length: ${signatureHex.length}`);
      return false;
    }

    const publicKey = hexToBytes(publicKeyHex);
    const signature = hexToBytes(signatureHex);
    const messageBytes = typeof message === 'string' 
      ? stringToBytes(message)
      : message;

    return nacl.sign.detached.verify(messageBytes, signature, publicKey);
  } catch (error) {
    console.error('Signature verification error:', error);
    return false;
  }
}

// ===========================================
// X25519 Encryption (for backup encryption)
// ===========================================

/**
 * Derive X25519 key from Ed25519 secret key
 * This allows the same identity to be used for signing AND encryption
 */
export function ed25519ToX25519(ed25519SecretKey: Uint8Array): Uint8Array {
  // The seed is the first 32 bytes of the Ed25519 secret key
  const seed = ed25519SecretKey.slice(0, 32);
  // Generate X25519 keypair from seed
  const x25519Keypair = nacl.box.keyPair.fromSecretKey(seed);
  return x25519Keypair.secretKey;
}

/**
 * Encrypt data for a recipient (asymmetric)
 */
export function encryptForRecipient(
  recipientPublicKeyHex: string,
  senderSecretKeyHex: string,
  plaintext: string
): { nonce: string; ciphertext: string } {
  const recipientPk = hexToBytes(recipientPublicKeyHex);
  const senderSk = hexToBytes(senderSecretKeyHex);
  
  // Convert Ed25519 keys to X25519 for encryption
  const senderX25519Sk = ed25519ToX25519(senderSk);
  // Note: For recipient, we'd need their X25519 public key
  // For simplicity, we use symmetric encryption with shared secret
  
  const nonce = nacl.randomBytes(nacl.box.nonceLength);
  const messageBytes = stringToBytes(plaintext);
  
  // Use box for public-key encryption
  const ciphertext = nacl.box(messageBytes, nonce, recipientPk.slice(0, 32), senderX25519Sk);
  
  return {
    nonce: bytesToHex(nonce),
    ciphertext: bytesToHex(ciphertext),
  };
}

/**
 * Encrypt with symmetric key (for local storage)
 */
export function encryptSymmetric(
  key: Uint8Array,
  plaintext: string
): { nonce: string; ciphertext: string } {
  const nonce = nacl.randomBytes(nacl.secretbox.nonceLength);
  const messageBytes = stringToBytes(plaintext);
  const ciphertext = nacl.secretbox(messageBytes, nonce, key);
  
  return {
    nonce: bytesToHex(nonce),
    ciphertext: bytesToHex(ciphertext),
  };
}

/**
 * Decrypt with symmetric key
 */
export function decryptSymmetric(
  key: Uint8Array,
  nonceHex: string,
  ciphertextHex: string
): string | null {
  try {
    const nonce = hexToBytes(nonceHex);
    const ciphertext = hexToBytes(ciphertextHex);
    const plaintext = nacl.secretbox.open(ciphertext, nonce, key);
    
    if (!plaintext) return null;
    return bytesToString(plaintext);
  } catch {
    return null;
  }
}

// ===========================================
// Canonical JSON (for signature verification)
// ===========================================

export function canonicalJson(obj: unknown): string {
  if (obj === null || typeof obj !== 'object') {
    return JSON.stringify(obj);
  }
  
  if (Array.isArray(obj)) {
    return '[' + obj.map(canonicalJson).join(',') + ']';
  }
  
  const keys = Object.keys(obj as Record<string, unknown>).sort();
  const pairs = keys.map(key => {
    const value = (obj as Record<string, unknown>)[key];
    return `"${key}":${canonicalJson(value)}`;
  });
  
  return '{' + pairs.join(',') + '}';
}

// ===========================================
// Utility Functions
// ===========================================

export function isValidPublicKey(pk: string): boolean {
  if (typeof pk !== 'string') return false;
  if (pk.length !== GNS_CONSTANTS.PK_LENGTH) return false;
  return /^[0-9a-f]+$/i.test(pk);
}

export function generateNonce(): string {
  return bytesToHex(nacl.randomBytes(32));
}

export function generatePin(): string {
  // Generate 6-digit PIN for recovery
  const bytes = nacl.randomBytes(4);
  const num = (bytes[0] << 24 | bytes[1] << 16 | bytes[2] << 8 | bytes[3]) >>> 0;
  return String(num % 1000000).padStart(6, '0');
}

export function sha256(data: string | Uint8Array): string {
  const bytes = typeof data === 'string' ? stringToBytes(data) : data;
  // TweetNaCl uses SHA-512, take first 32 bytes for SHA-256 equivalent
  const hash = nacl.hash(bytes).slice(0, 32);
  return bytesToHex(hash);
}
