// ===========================================
// GNS NODE - CRYPTOGRAPHIC UTILITIES
// Ed25519 signature verification
// ===========================================

import nacl from 'tweetnacl';
import { encodeUTF8, decodeUTF8 } from 'tweetnacl-util';
import { GNS_CONSTANTS } from '../types';

// ===========================================
// Hex Utilities
// ===========================================

/**
 * Convert hex string to Uint8Array
 */
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

/**
 * Convert Uint8Array to hex string
 */
export function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes)
    .map(b => b.toString(16).padLeft(2, '0'))
    .join('');
}

/**
 * Convert string to Uint8Array (UTF-8)
 */
export function stringToBytes(str: string): Uint8Array {
  return new TextEncoder().encode(str);
}

/**
 * Convert Uint8Array to string (UTF-8)
 */
export function bytesToString(bytes: Uint8Array): string {
  return new TextDecoder().decode(bytes);
}

// ===========================================
// Ed25519 Signature Verification
// ===========================================

/**
 * Verify an Ed25519 signature
 * 
 * @param publicKeyHex - 64 character hex string (32 bytes)
 * @param message - The message that was signed
 * @param signatureHex - 128 character hex string (64 bytes)
 * @returns true if signature is valid
 */
export function verifySignature(
  publicKeyHex: string,
  message: string | Uint8Array,
  signatureHex: string
): boolean {
  try {
    // Validate inputs
    if (publicKeyHex.length !== GNS_CONSTANTS.PK_LENGTH) {
      console.error(`Invalid public key length: ${publicKeyHex.length}, expected ${GNS_CONSTANTS.PK_LENGTH}`);
      return false;
    }
    
    if (signatureHex.length !== GNS_CONSTANTS.SIGNATURE_LENGTH) {
      console.error(`Invalid signature length: ${signatureHex.length}, expected ${GNS_CONSTANTS.SIGNATURE_LENGTH}`);
      return false;
    }

    // Convert to bytes
    const publicKey = hexToBytes(publicKeyHex);
    const signature = hexToBytes(signatureHex);
    const messageBytes = typeof message === 'string' 
      ? stringToBytes(message)
      : message;

    // Verify using TweetNaCl
    return nacl.sign.detached.verify(messageBytes, signature, publicKey);
  } catch (error) {
    console.error('Signature verification error:', error);
    return false;
  }
}

/**
 * Verify a signed GNS record
 */
export function verifyGnsRecord(
  pkRoot: string,
  recordJson: object,
  signature: string
): boolean {
  // The data to verify is the canonical JSON representation
  const dataToVerify = canonicalJson(recordJson);
  return verifySignature(pkRoot, dataToVerify, signature);
}

/**
 * Verify a signed alias claim
 */
export function verifyAliasClaim(
  pkRoot: string,
  claim: { handle: string; identity: string; proof: object },
  signature: string
): boolean {
  const dataToVerify = canonicalJson({
    handle: claim.handle,
    identity: claim.identity,
    proof: claim.proof,
  });
  return verifySignature(pkRoot, dataToVerify, signature);
}

/**
 * Verify a signed epoch header
 */
export function verifyEpochHeader(
  pkRoot: string,
  epoch: object,
  signature: string
): boolean {
  const dataToVerify = canonicalJson(epoch);
  return verifySignature(pkRoot, dataToVerify, signature);
}

/**
 * Verify a signed message
 */
export function verifyMessage(
  fromPk: string,
  message: { to_pk: string; payload: string; created_at?: string },
  signature: string
): boolean {
  const dataToVerify = canonicalJson({
    to_pk: message.to_pk,
    payload: message.payload,
  });
  return verifySignature(fromPk, dataToVerify, signature);
}

// ===========================================
// Canonical JSON
// ===========================================

/**
 * Create a canonical JSON representation for signing
 * Keys are sorted alphabetically
 */
export function canonicalJson(obj: unknown): string {
  return sortedJsonStringify(obj);
}

/**
 * Create a sorted, deterministic JSON string
 */
export function sortedJsonStringify(obj: unknown): string {
  if (obj === null || typeof obj !== 'object') {
    return JSON.stringify(obj);
  }
  
  if (Array.isArray(obj)) {
    return '[' + obj.map(sortedJsonStringify).join(',') + ']';
  }
  
  const keys = Object.keys(obj as Record<string, unknown>).sort();
  const pairs = keys.map(key => {
    const value = (obj as Record<string, unknown>)[key];
    return `"${key}":${sortedJsonStringify(value)}`;
  });
  
  return '{' + pairs.join(',') + '}';
}

// ===========================================
// Hashing
// ===========================================

/**
 * Compute SHA-256 hash
 */
export function sha256(data: string | Uint8Array): Uint8Array {
  const bytes = typeof data === 'string' ? stringToBytes(data) : data;
  return nacl.hash(bytes).slice(0, 32); // TweetNaCl uses SHA-512, take first 32 bytes
}

/**
 * Compute SHA-256 hash and return as hex string
 */
export function sha256Hex(data: string | Uint8Array): string {
  return bytesToHex(sha256(data));
}

// ===========================================
// Validation Utilities
// ===========================================

/**
 * Validate public key format
 */
export function isValidPublicKey(pk: string): boolean {
  if (typeof pk !== 'string') return false;
  if (pk.length !== GNS_CONSTANTS.PK_LENGTH) return false;
  return /^[0-9a-f]+$/i.test(pk);
}

/**
 * Validate signature format
 */
export function isValidSignature(sig: string): boolean {
  if (typeof sig !== 'string') return false;
  if (sig.length !== GNS_CONSTANTS.SIGNATURE_LENGTH) return false;
  return /^[0-9a-f]+$/i.test(sig);
}

/**
 * Validate handle format
 */
export function isValidHandle(handle: string): boolean {
  if (typeof handle !== 'string') return false;
  return GNS_CONSTANTS.HANDLE_REGEX.test(handle);
}

/**
 * Generate a random nonce for auth challenges
 */
export function generateNonce(): string {
  const bytes = nacl.randomBytes(32);
  return bytesToHex(bytes);
}

// ===========================================
// GNS ID Utilities
// ===========================================

/**
 * Generate GNS ID from public key
 */
export function pkToGnsId(pk: string): string {
  return `gns_${pk.substring(0, 16)}`;
}

/**
 * Check if identity matches pk_root
 */
export function identityMatchesPk(identity: string, pkRoot: string): boolean {
  // Identity in record should match the pk_root
  return identity.toLowerCase() === pkRoot.toLowerCase();
}

// Add String.prototype.padLeft if not exists
declare global {
  interface String {
    padLeft(length: number, char: string): string;
  }
}

String.prototype.padLeft = function(length: number, char: string): string {
  let result = this.toString();
  while (result.length < length) {
    result = char + result;
  }
  return result;
};
