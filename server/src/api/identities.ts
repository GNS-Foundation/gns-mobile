// ===========================================
// GNS NODE - IDENTITIES API
// /identities endpoints for identity resolution
// 
// ✅ FIXED: Properly extract encryption_key from record_json
// ===========================================

import { Router, Request, Response } from 'express';
import * as db from '../lib/db';
import { ApiResponse } from '../types';
import { isValidPublicKey } from '../lib/crypto';
import echoBot from '../services/echo_bot';

const router = Router();

// ===========================================
// GET /identities/:publicKey
// Fetch identity information by public key
// Returns encryption key needed for E2E messaging
// ===========================================
router.get('/:publicKey', async (req: Request, res: Response) => {
  try {
    const publicKey = req.params.publicKey?.toLowerCase();
    
    // Validate public key format (64 hex characters)
    if (!publicKey || !isValidPublicKey(publicKey)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid public key format',
        path: `/identities/${publicKey}`,
      } as ApiResponse);
    }
    
    // Check if it's @echo's public key
    const echoHandle = echoBot.getHandle();
    if (echoHandle && publicKey === echoHandle.publicKey.toLowerCase()) {
      return res.json({
        success: true,
        data: {
          public_key: echoHandle.publicKey,
          encryption_key: echoHandle.encryptionKey,  // X25519 for encryption
          handle: echoHandle.handle,
          display_name: 'Echo Bot',
          bio: 'Test bot that echoes messages back',
          is_system: true,
          trust_score: 100.0,
          breadcrumb_count: 999,
        },
      } as ApiResponse);
    }
    
    // Query database for identity record
    const record = await db.getRecord(publicKey);
    
    if (!record) {
      return res.status(404).json({
        success: false,
        error: 'Not found',
        path: `/identities/${publicKey}`,
      } as ApiResponse);
    }
    
    // Parse record_json (it's already an object in most cases)
    const recordData = record.record_json || {};
    
    // Get handle if exists
    const alias = await db.getAliasByPk(publicKey);
    
    // ✅ FIX: Get encryption_key from BOTH record column AND record_json
    // The encryption_key might be stored in either place depending on when the record was created
    const encryptionKey = (record as any).encryption_key 
      || (recordData as any)?.encryption_key 
      || null;
    
    // Debug log for troubleshooting
    if (!encryptionKey) {
      console.log(`⚠️ No encryption_key found for ${publicKey.substring(0, 16)}...`);
      console.log(`   record.encryption_key: ${(record as any).encryption_key}`);
      console.log(`   recordData.encryption_key: ${(recordData as any)?.encryption_key}`);
    }
    
    // Return identity data
    return res.json({
      success: true,
      data: {
        public_key: record.pk_root,
        encryption_key: encryptionKey,  // ✅ CRITICAL for messaging!
        handle: alias?.handle || (recordData as any)?.handle || null,
        display_name: (recordData as any)?.display_name || null,
        bio: (recordData as any)?.bio || null,
        avatar_url: (recordData as any)?.avatar_url || null,
        trust_score: record.trust_score,
        breadcrumb_count: record.breadcrumb_count,
        created_at: record.created_at,
      },
    } as ApiResponse);
    
  } catch (error) {
    console.error('GET /identities/:publicKey error:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
      path: `/identities/${req.params.publicKey}`,
    } as ApiResponse);
  }
});

export default router;
