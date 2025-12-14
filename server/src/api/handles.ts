// ===========================================
// GNS NODE - HANDLES API
// /handles endpoints for handle resolution
// ===========================================

import { Router, Request, Response } from 'express';
import * as db from '../lib/db';
import { ApiResponse } from '../types';
import { isValidPublicKey, isValidHandle } from '../lib/crypto';
import echoBot from '../services/echo_bot';

// Note: This file goes in src/api/handles.ts

const router = Router();

// ===========================================
// GET /handles/:handle
// Resolve handle to public key
// ===========================================
router.get('/:handle', async (req: Request, res: Response) => {
  try {
    const handle = req.params.handle?.toLowerCase().replace(/^@/, '');
    
    // Validate handle format
    if (!handle || !isValidHandle(handle)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid handle format',
      } as ApiResponse);
    }
    
    // Check if it's @echo (compare with config handle)
    const echoHandle = echoBot.getHandle();
    if (echoHandle && handle === echoHandle.handle) {
      return res.json({
        success: true,
        data: {
          handle: `@${handle}`,
          public_key: echoHandle.publicKey,
          encryption_key: echoHandle.encryptionKey,  // X25519 for encryption
          is_system: echoHandle.isSystem,
          type: echoHandle.type,
        },
      } as ApiResponse);
    }
    
    // Look up in database
    const alias = await db.getAlias(handle);
    
    if (!alias) {
      return res.status(404).json({
        success: false,
        error: 'Handle not found',
      } as ApiResponse);
    }
    
    // Get record for additional info (including encryption key)
    const record = await db.getRecord(alias.pk_root);
    
    // ✅ PHASE 7: encryption_key is stored as a column in records table
    const encryptionKey = record?.encryption_key || null;
    
    return res.json({
      success: true,
      data: {
        handle: `@${alias.handle}`,
        public_key: alias.pk_root,
        encryption_key: encryptionKey,  // ✅ X25519 key for user-to-user messaging!
        is_system: (alias as any).is_system || false,
      },
    } as ApiResponse);
    
  } catch (error) {
    console.error('GET /handles/:handle error:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
    } as ApiResponse);
  }
});

// ===========================================
// GET /handles/pk/:public_key
// Reverse lookup: public key to handle
// ===========================================
router.get('/pk/:public_key', async (req: Request, res: Response) => {
  try {
    const pk = req.params.public_key?.toLowerCase();
    
    // Validate pk format
    if (!pk || !isValidPublicKey(pk)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid public key format',
      } as ApiResponse);
    }
    
    // Check if it's @echo's public key
    const echoHandle = echoBot.getHandle();
    if (echoHandle && pk === echoHandle.publicKey.toLowerCase()) {
      return res.json({
        success: true,
        data: {
          handle: `@${echoHandle.handle}`,
          public_key: pk,
          encryption_key: echoHandle.encryptionKey,  // X25519 for encryption
          is_system: echoHandle.isSystem,
          type: echoHandle.type,
        },
      } as ApiResponse);
    }
    
    // Look up in database
    const alias = await db.getAliasByPk(pk);
    
    if (!alias) {
      return res.status(404).json({
        success: false,
        error: 'No handle associated with this public key',
      } as ApiResponse);
    }
    
    // ✅ PHASE 7: Get record for encryption key (stored as column)
    const record = await db.getRecord(alias.pk_root);
    const encryptionKey = record?.encryption_key || null;
    
    return res.json({
      success: true,
      data: {
        handle: `@${alias.handle}`,
        public_key: alias.pk_root,
        encryption_key: encryptionKey,  // ✅ X25519 key for messaging!
        is_system: (alias as any).is_system || false,
      },
    } as ApiResponse);
    
  } catch (error) {
    console.error('GET /handles/pk/:public_key error:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
    } as ApiResponse);
  }
});

// ===========================================
// GET /handles/system/all
// List all system handles
// ===========================================
router.get('/system/all', async (req: Request, res: Response) => {
  try {
    // Return hardcoded system handles with their public keys
    const echoHandle = echoBot.getHandle();
    
    const systemHandles = [
      echoHandle ? {
        handle: '@echo',
        public_key: echoHandle.publicKey,
        encryption_key: echoHandle.encryptionKey,  // X25519 for encryption
        type: 'echo_bot',
        description: 'Test bot that echoes messages back',
        can_message: true,
      } : null,
      // Future system handles
      {
        handle: '@gns',
        public_key: null, // Not yet implemented
        type: 'system',
        description: 'GNS Network announcements (broadcast only)',
        can_message: false,
      },
      {
        handle: '@support',
        public_key: null, // Not yet implemented
        type: 'support',
        description: 'GNS Support channel',
        can_message: true,
      },
    ].filter(h => h !== null && h.public_key !== null);
    
    return res.json({
      success: true,
      data: systemHandles,
    } as ApiResponse);
    
  } catch (error) {
    console.error('GET /handles/system/all error:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
    } as ApiResponse);
  }
});

export default router;
