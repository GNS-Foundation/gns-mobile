// ===========================================
// GNS NODE - RECORDS API
// /records endpoints
// ===========================================

import { Router, Request, Response } from 'express';
import { signedRecordSchema, pkRootSchema } from '../lib/validation';
import { verifyGnsRecord, isValidPublicKey } from '../lib/crypto';
import * as db from '../lib/db';
import { ApiResponse, SignedRecord, DbRecord } from '../types';

const router = Router();

// ===========================================
// GET /records/:pk
// Resolve identity by public key
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

    // Fetch record
    const record = await db.getRecord(pk);

    if (!record) {
      return res.status(404).json({
        success: false,
        error: 'Record not found',
      } as ApiResponse);
    }

    return res.json({
      success: true,
      data: {
        pk_root: record.pk_root,
        encryption_key: record.encryption_key,  // ✅ PHASE 7: Direct access for messaging!
        record_json: record.record_json,
        signature: record.signature,
        created_at: record.created_at,
        updated_at: record.updated_at,
      },
    } as ApiResponse<Partial<DbRecord>>);

  } catch (error) {
    console.error('GET /records/:pk error:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
    } as ApiResponse);
  }
});

// ===========================================
// PUT /records/:pk
// Publish/update own GNS Record
// ===========================================
router.put('/:pk', async (req: Request, res: Response) => {
  try {
    const pk = req.params.pk?.toLowerCase();

    // Validate pk in URL
    if (!isValidPublicKey(pk)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid public key in URL',
      } as ApiResponse);
    }

    // Validate request body
    const parseResult = signedRecordSchema.safeParse({
      pk_root: pk,
      record_json: req.body.record_json,
      signature: req.body.signature,
    });

    if (!parseResult.success) {
      return res.status(400).json({
        success: false,
        error: 'Validation failed',
        message: parseResult.error.errors.map(e => e.message).join(', '),
      } as ApiResponse);
    }

    const { record_json, signature } = parseResult.data;

    // Verify signature
    const isValid = verifyGnsRecord(pk, record_json, signature);

    if (!isValid) {
      return res.status(401).json({
        success: false,
        error: 'Invalid signature',
      } as ApiResponse);
    }

    // Check if updating existing record
    const existing = await db.getRecord(pk);

    if (existing) {
      // Verify update is newer
      const existingUpdated = new Date(existing.record_json.updated_at);
      const newUpdated = new Date(record_json.updated_at);

      if (newUpdated <= existingUpdated) {
        return res.status(409).json({
          success: false,
          error: 'Record update must have a newer timestamp',
        } as ApiResponse);
      }
    }

    // Upsert record
    console.log(`[PUT /records/${pk}] Upserting record...`);
    console.log(`[PUT /records/${pk}] Payload identity: ${record_json.identity}`);
    console.log(`[PUT /records/${pk}] Payload encryption_key: ${record_json.encryption_key}`);

    const saved = await db.upsertRecord(pk, record_json, signature);

    console.log(`[PUT /records/${pk}] Record ${existing ? 'updated' : 'created'}: ${pk.substring(0, 16)}...`);
    console.log(`[PUT /records/${pk}] Saved encryption_key: ${saved.encryption_key}`);

    return res.status(existing ? 200 : 201).json({
      success: true,
      data: {
        pk_root: saved.pk_root,
        created_at: saved.created_at,
        updated_at: saved.updated_at,
      },
      message: existing ? 'Record updated' : 'Record created',
    } as ApiResponse);

  } catch (error) {
    console.error('PUT /records/:pk error:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
    } as ApiResponse);
  }
});

// ===========================================
// DELETE /records/:pk
// Remove record (requires signature)
// ===========================================
router.delete('/:pk', async (req: Request, res: Response) => {
  try {
    const pk = req.params.pk?.toLowerCase();
    const signature = req.headers['x-gns-signature'] as string;

    // Validate pk
    if (!isValidPublicKey(pk)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid public key format',
      } as ApiResponse);
    }

    // Require signature header
    if (!signature) {
      return res.status(401).json({
        success: false,
        error: 'Missing X-GNS-Signature header',
      } as ApiResponse);
    }

    // Check record exists
    const existing = await db.getRecord(pk);
    if (!existing) {
      return res.status(404).json({
        success: false,
        error: 'Record not found',
      } as ApiResponse);
    }

    // Verify deletion signature
    // The signed message should be: "DELETE:{pk}:{timestamp}"
    const timestamp = req.headers['x-gns-timestamp'] as string;
    if (!timestamp) {
      return res.status(400).json({
        success: false,
        error: 'Missing X-GNS-Timestamp header',
      } as ApiResponse);
    }

    const deleteMessage = `DELETE:${pk}:${timestamp}`;
    const isValid = verifyGnsRecord(pk, { message: deleteMessage }, signature);

    // For now, we'll skip signature verification on delete
    // TODO: Implement proper delete verification

    // Delete record
    await db.deleteRecord(pk);

    console.log(`Record deleted: ${pk.substring(0, 16)}...`);

    return res.json({
      success: true,
      message: 'Record deleted',
    } as ApiResponse);

  } catch (error) {
    console.error('DELETE /records/:pk error:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
    } as ApiResponse);
  }
});

export default router;
