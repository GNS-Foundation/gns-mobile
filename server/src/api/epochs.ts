// ===========================================
// GNS NODE - EPOCHS API
// /epochs endpoints
// ===========================================

import { Router, Request, Response } from 'express';
import { signedEpochSchema, pkRootSchema } from '../lib/validation';
import { verifyEpochHeader, isValidPublicKey } from '../lib/crypto';
import * as db from '../lib/db';
import { ApiResponse, DbEpoch } from '../types';

const router = Router();

// ===========================================
// GET /epochs/:pk
// List all epochs for an identity
// ===========================================
router.get('/:pk', async (req: Request, res: Response) => {
  try {
    const pk = req.params.pk?.toLowerCase();
    
    // Validate pk format
    if (!isValidPublicKey(pk)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid public key format',
      } as ApiResponse);
    }
    
    // Fetch epochs
    const epochs = await db.getEpochs(pk);
    
    return res.json({
      success: true,
      data: epochs.map(e => ({
        epoch_index: e.epoch_index,
        merkle_root: e.merkle_root,
        start_time: e.start_time,
        end_time: e.end_time,
        block_count: e.block_count,
        epoch_hash: e.epoch_hash,
        published_at: e.published_at,
      })),
      total: epochs.length,
    } as ApiResponse);
    
  } catch (error) {
    console.error('GET /epochs/:pk error:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
    } as ApiResponse);
  }
});

// ===========================================
// GET /epochs/:pk/:index
// Get specific epoch by index
// ===========================================
router.get('/:pk/:index', async (req: Request, res: Response) => {
  try {
    const pk = req.params.pk?.toLowerCase();
    const epochIndex = parseInt(req.params.index, 10);
    
    // Validate pk format
    if (!isValidPublicKey(pk)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid public key format',
      } as ApiResponse);
    }
    
    // Validate epoch index
    if (isNaN(epochIndex) || epochIndex < 0) {
      return res.status(400).json({
        success: false,
        error: 'Invalid epoch index',
      } as ApiResponse);
    }
    
    // Fetch epoch
    const epoch = await db.getEpoch(pk, epochIndex);
    
    if (!epoch) {
      return res.status(404).json({
        success: false,
        error: 'Epoch not found',
      } as ApiResponse);
    }
    
    return res.json({
      success: true,
      data: {
        pk_root: epoch.pk_root,
        epoch_index: epoch.epoch_index,
        merkle_root: epoch.merkle_root,
        start_time: epoch.start_time,
        end_time: epoch.end_time,
        block_count: epoch.block_count,
        prev_epoch_hash: epoch.prev_epoch_hash,
        signature: epoch.signature,
        epoch_hash: epoch.epoch_hash,
        published_at: epoch.published_at,
      },
    } as ApiResponse);
    
  } catch (error) {
    console.error('GET /epochs/:pk/:index error:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
    } as ApiResponse);
  }
});

// ===========================================
// PUT /epochs/:pk/:index
// Publish epoch commitment
// ===========================================
router.put('/:pk/:index', async (req: Request, res: Response) => {
  try {
    const pk = req.params.pk?.toLowerCase();
    const epochIndex = parseInt(req.params.index, 10);
    
    // Validate pk format
    if (!isValidPublicKey(pk)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid public key format',
      } as ApiResponse);
    }
    
    // Validate epoch index
    if (isNaN(epochIndex) || epochIndex < 0) {
      return res.status(400).json({
        success: false,
        error: 'Invalid epoch index',
      } as ApiResponse);
    }
    
    // Validate request body
    const epoch = {
      ...req.body.epoch,
      epoch_index: epochIndex,
      identity: pk,
    };
    
    const parseResult = signedEpochSchema.safeParse({
      pk_root: pk,
      epoch,
      signature: req.body.signature || epoch.signature,
    });
    
    if (!parseResult.success) {
      return res.status(400).json({
        success: false,
        error: 'Validation failed',
        message: parseResult.error.errors.map(e => e.message).join(', '),
      } as ApiResponse);
    }
    
    const validatedEpoch = parseResult.data.epoch;
    const signature = parseResult.data.signature;
    
    // Check that identity has a record
    const record = await db.getRecord(pk);
    if (!record) {
      return res.status(404).json({
        success: false,
        error: 'Identity not found. Publish a GNS Record first.',
      } as ApiResponse);
    }
    
    // Check if epoch already exists
    const existingEpoch = await db.getEpoch(pk, epochIndex);
    if (existingEpoch) {
      return res.status(409).json({
        success: false,
        error: 'Epoch already exists. Epochs are append-only.',
      } as ApiResponse);
    }
    
    // If not first epoch, verify chain linkage
    if (epochIndex > 0) {
      const prevEpoch = await db.getEpoch(pk, epochIndex - 1);
      
      if (!prevEpoch) {
        return res.status(400).json({
          success: false,
          error: `Previous epoch ${epochIndex - 1} must exist before publishing epoch ${epochIndex}`,
        } as ApiResponse);
      }
      
      if (validatedEpoch.prev_epoch_hash !== prevEpoch.epoch_hash) {
        return res.status(400).json({
          success: false,
          error: 'prev_epoch_hash does not match previous epoch',
        } as ApiResponse);
      }
    }
    
    // Verify signature
    const epochDataToVerify = {
      identity: validatedEpoch.identity,
      epoch_index: validatedEpoch.epoch_index,
      start_time: validatedEpoch.start_time,
      end_time: validatedEpoch.end_time,
      merkle_root: validatedEpoch.merkle_root,
      block_count: validatedEpoch.block_count,
      prev_epoch_hash: validatedEpoch.prev_epoch_hash,
    };
    
    const isValid = verifyEpochHeader(pk, epochDataToVerify, signature);
    
    if (!isValid) {
      return res.status(401).json({
        success: false,
        error: 'Invalid signature',
      } as ApiResponse);
    }
    
    // Create epoch
    const saved = await db.createEpoch(pk, validatedEpoch, signature);
    
    console.log(`Epoch published: ${pk.substring(0, 16)}... epoch #${epochIndex}`);
    
    return res.status(201).json({
      success: true,
      data: {
        pk_root: saved.pk_root,
        epoch_index: saved.epoch_index,
        epoch_hash: saved.epoch_hash,
        published_at: saved.published_at,
      },
      message: `Epoch ${epochIndex} published`,
    } as ApiResponse);
    
  } catch (error) {
    console.error('PUT /epochs/:pk/:index error:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
    } as ApiResponse);
  }
});

export default router;
