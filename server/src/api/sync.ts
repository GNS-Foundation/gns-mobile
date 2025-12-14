// ===========================================
// GNS NODE - SYNC API
// /sync endpoints (node-to-node gossip)
// ===========================================

import { Router, Request, Response } from 'express';
import { sinceSchema } from '../lib/validation';
import * as db from '../lib/db';
import { ApiResponse } from '../types';

const router = Router();

// ===========================================
// GET /sync/records?since={ts}
// Get records updated since timestamp
// ===========================================
router.get('/records', async (req: Request, res: Response) => {
  try {
    const parseResult = sinceSchema.safeParse(req.query);
    
    if (!parseResult.success) {
      return res.status(400).json({
        success: false,
        error: 'Invalid query parameters',
      } as ApiResponse);
    }
    
    const { since, limit } = parseResult.data;
    const sinceDate = since || new Date(0).toISOString();
    
    const records = await db.getRecordsSince(sinceDate, limit);
    
    return res.json({
      success: true,
      data: records,
      count: records.length,
      since: sinceDate,
      node_id: process.env.NODE_ID || 'unknown',
    } as ApiResponse);
    
  } catch (error) {
    console.error('GET /sync/records error:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
    } as ApiResponse);
  }
});

// ===========================================
// GET /sync/aliases?since={ts}
// Get aliases created since timestamp
// ===========================================
router.get('/aliases', async (req: Request, res: Response) => {
  try {
    const parseResult = sinceSchema.safeParse(req.query);
    
    if (!parseResult.success) {
      return res.status(400).json({
        success: false,
        error: 'Invalid query parameters',
      } as ApiResponse);
    }
    
    const { since, limit } = parseResult.data;
    const sinceDate = since || new Date(0).toISOString();
    
    const aliases = await db.getAliasesSince(sinceDate, limit);
    
    return res.json({
      success: true,
      data: aliases,
      count: aliases.length,
      since: sinceDate,
      node_id: process.env.NODE_ID || 'unknown',
    } as ApiResponse);
    
  } catch (error) {
    console.error('GET /sync/aliases error:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
    } as ApiResponse);
  }
});

// ===========================================
// GET /sync/epochs?since={ts}
// Get epochs published since timestamp
// ===========================================
router.get('/epochs', async (req: Request, res: Response) => {
  try {
    const parseResult = sinceSchema.safeParse(req.query);
    
    if (!parseResult.success) {
      return res.status(400).json({
        success: false,
        error: 'Invalid query parameters',
      } as ApiResponse);
    }
    
    const { since, limit } = parseResult.data;
    const sinceDate = since || new Date(0).toISOString();
    
    const epochs = await db.getEpochsSince(sinceDate, limit);
    
    return res.json({
      success: true,
      data: epochs,
      count: epochs.length,
      since: sinceDate,
      node_id: process.env.NODE_ID || 'unknown',
    } as ApiResponse);
    
  } catch (error) {
    console.error('GET /sync/epochs error:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
    } as ApiResponse);
  }
});

// ===========================================
// POST /sync/push
// Receive batch of items from peer
// ===========================================
router.post('/push', async (req: Request, res: Response) => {
  try {
    const { type, items, node_id } = req.body;
    
    if (!type || !items || !Array.isArray(items)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid sync payload',
      } as ApiResponse);
    }
    
    console.log(`Sync push from ${node_id}: ${items.length} ${type}`);
    
    let processed = 0;
    let skipped = 0;
    
    // Process based on type
    switch (type) {
      case 'records':
        for (const item of items) {
          try {
            // Check if we have a newer version
            const existing = await db.getRecord(item.pk_root);
            if (existing) {
              const existingUpdated = new Date(existing.record_json.updated_at);
              const newUpdated = new Date(item.record_json.updated_at);
              if (newUpdated <= existingUpdated) {
                skipped++;
                continue;
              }
            }
            
            // TODO: Verify signature before storing
            await db.upsertRecord(item.pk_root, item.record_json, item.signature);
            processed++;
          } catch (e) {
            console.error('Error processing synced record:', e);
            skipped++;
          }
        }
        break;
        
      case 'aliases':
        for (const item of items) {
          try {
            // First valid claim wins - don't overwrite existing
            const existing = await db.getAlias(item.handle);
            if (existing) {
              skipped++;
              continue;
            }
            
            // TODO: Verify signature and PoT proof before storing
            await db.createAlias(item.handle, item.pk_root, item.pot_proof, item.signature);
            processed++;
          } catch (e) {
            console.error('Error processing synced alias:', e);
            skipped++;
          }
        }
        break;
        
      case 'epochs':
        for (const item of items) {
          try {
            // Check if epoch already exists
            const existing = await db.getEpoch(item.pk_root, item.epoch_index);
            if (existing) {
              skipped++;
              continue;
            }
            
            // TODO: Verify signature and chain linkage before storing
            await db.createEpoch(item.pk_root, item, item.signature);
            processed++;
          } catch (e) {
            console.error('Error processing synced epoch:', e);
            skipped++;
          }
        }
        break;
        
      default:
        return res.status(400).json({
          success: false,
          error: `Unknown sync type: ${type}`,
        } as ApiResponse);
    }
    
    return res.json({
      success: true,
      data: {
        type,
        processed,
        skipped,
        total: items.length,
      },
      message: `Processed ${processed}/${items.length} ${type}`,
    } as ApiResponse);
    
  } catch (error) {
    console.error('POST /sync/push error:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
    } as ApiResponse);
  }
});

// ===========================================
// GET /sync/status
// Get node sync status
// ===========================================
router.get('/status', async (req: Request, res: Response) => {
  try {
    const peers = await db.getAllPeers();
    
    return res.json({
      success: true,
      data: {
        node_id: process.env.NODE_ID || 'unknown',
        peers: peers.map(p => ({
          peer_id: p.peer_id,
          status: p.status,
          last_sync_at: p.last_sync_at,
          error_count: p.error_count,
        })),
        peer_count: peers.length,
      },
    } as ApiResponse);
    
  } catch (error) {
    console.error('GET /sync/status error:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
    } as ApiResponse);
  }
});

export default router;
