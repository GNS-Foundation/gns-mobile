// ===========================================
// GNS NODE - ALIASES API
// /aliases endpoints
// ===========================================

import { Router, Request, Response } from 'express';
import { aliasClaimSchema, handleSchema } from '../lib/validation';
import { verifyAliasClaim, isValidHandle } from '../lib/crypto';
import * as db from '../lib/db';
import { ApiResponse, GNS_CONSTANTS } from '../types';
import stellarService from '../services/stellar_service';

const router = Router();

// ===========================================
// GET /aliases/airdrop/status
// Check airdrop service status
// MUST BE BEFORE /:handle route!
// ===========================================
router.get('/airdrop/status', async (req: Request, res: Response) => {
  try {
    const isConfigured = stellarService.isConfigured();
    const distributionAddress = stellarService.getDistributionAddress();
    const balances = await stellarService.getDistributionBalances();
    
    return res.json({
      success: true,
      data: {
        enabled: isConfigured,
        distribution_wallet: distributionAddress,
        balances: balances,
        amounts: {
          xlm_per_user: '2',
          gns_per_user: '200',
        },
      },
    } as ApiResponse);
    
  } catch (error) {
    console.error('GET /aliases/airdrop/status error:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
    } as ApiResponse);
  }
});

// ===========================================
// GET /aliases/:handle
// Resolve @handle → PK_root
// ===========================================
router.get('/:handle', async (req: Request, res: Response) => {
  try {
    const handle = req.params.handle?.toLowerCase().replace('@', '');
    
    // Validate handle format
    if (!isValidHandle(handle)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid handle format',
      } as ApiResponse);
    }
    
    // Fetch alias
    const alias = await db.getAlias(handle);
    
    if (!alias) {
      // Check if it's reserved but not claimed
      const reservation = await db.getReservation(handle);
      
      if (reservation) {
        return res.status(404).json({
          success: false,
          error: 'Handle is reserved but not yet claimed',
          data: {
            reserved: true,
            expires_at: reservation.expires_at,
          },
        } as ApiResponse);
      }
      
      return res.status(404).json({
        success: false,
        error: 'Handle not found',
      } as ApiResponse);
    }
    
    return res.json({
      success: true,
      data: {
        handle: alias.handle,
        pk_root: alias.pk_root,
        created_at: alias.created_at,
        verified: alias.verified,
      },
    } as ApiResponse);
    
  } catch (error) {
    console.error('GET /aliases/:handle error:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
    } as ApiResponse);
  }
});

// ===========================================
// GET /aliases?check=:handle
// Check if handle is available
// ===========================================
router.get('/', async (req: Request, res: Response) => {
  try {
    const handle = (req.query.check as string)?.toLowerCase().replace('@', '');
    
    if (!handle) {
      return res.status(400).json({
        success: false,
        error: 'Missing check query parameter',
      } as ApiResponse);
    }
    
    // Validate handle format
    const validationResult = handleSchema.safeParse(handle);
    if (!validationResult.success) {
      return res.status(400).json({
        success: false,
        error: 'Invalid handle format',
        message: validationResult.error.errors.map(e => e.message).join(', '),
      } as ApiResponse);
    }
    
    // Check availability
    const available = await db.isHandleAvailable(handle);
    
    return res.json({
      success: true,
      data: {
        handle,
        available,
      },
    } as ApiResponse);
    
  } catch (error) {
    console.error('GET /aliases?check error:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
    } as ApiResponse);
  }
});

// ===========================================
// PUT /aliases/:handle
// Claim handle (requires PoT proof)
// ===========================================
router.put('/:handle', async (req: Request, res: Response) => {
  try {
    const handle = req.params.handle?.toLowerCase().replace('@', '');
    
    // Validate request body
    const parseResult = aliasClaimSchema.safeParse({
      handle,
      identity: req.body.identity,
      proof: req.body.proof,
      signature: req.body.signature,
    });
    
    if (!parseResult.success) {
      return res.status(400).json({
        success: false,
        error: 'Validation failed',
        message: parseResult.error.errors.map(e => e.message).join(', '),
      } as ApiResponse);
    }
    
    const { identity, proof, signature } = parseResult.data;
    
    // Check if handle is available
    const existingAlias = await db.getAlias(handle);
    if (existingAlias) {
      return res.status(409).json({
        success: false,
        error: 'Handle already claimed',
      } as ApiResponse);
    }
    
    // Check reservation (if exists, must match pk)
    const reservation = await db.getReservation(handle);
    if (reservation && reservation.pk_root.toLowerCase() !== identity.toLowerCase()) {
      return res.status(409).json({
        success: false,
        error: 'Handle is reserved by another identity',
      } as ApiResponse);
    }
    
    // Verify PoT requirements
    if (proof.breadcrumb_count < GNS_CONSTANTS.MIN_BREADCRUMBS_FOR_HANDLE) {
      return res.status(403).json({
        success: false,
        error: `Need at least ${GNS_CONSTANTS.MIN_BREADCRUMBS_FOR_HANDLE} breadcrumbs`,
        data: {
          required: GNS_CONSTANTS.MIN_BREADCRUMBS_FOR_HANDLE,
          current: proof.breadcrumb_count,
        },
      } as ApiResponse);
    }
    
    if (proof.trust_score < GNS_CONSTANTS.MIN_TRUST_SCORE_FOR_HANDLE) {
      return res.status(403).json({
        success: false,
        error: `Trust score must be at least ${GNS_CONSTANTS.MIN_TRUST_SCORE_FOR_HANDLE}`,
        data: {
          required: GNS_CONSTANTS.MIN_TRUST_SCORE_FOR_HANDLE,
          current: proof.trust_score,
        },
      } as ApiResponse);
    }
    
    // Verify signature
    const isValid = verifyAliasClaim(identity, { handle, identity, proof }, signature);
    
    if (!isValid) {
      return res.status(401).json({
        success: false,
        error: 'Invalid signature',
      } as ApiResponse);
    }
    
    // Check that identity has a record
    const record = await db.getRecord(identity);
    if (!record) {
      return res.status(404).json({
        success: false,
        error: 'Identity not found. Publish a GNS Record first.',
      } as ApiResponse);
    }
    
    // Create alias
    const alias = await db.createAlias(handle, identity, proof, signature);
    
    console.log(`Handle claimed: @${handle} → ${identity.substring(0, 16)}...`);
    
    // ===========================================
    // AUTOMATIC AIRDROP ON HANDLE CLAIM
    // ===========================================
    let airdropResult = null;
    
    if (stellarService.isConfigured()) {
      console.log(`[Airdrop] Processing welcome airdrop for @${handle}...`);
      
      // Run airdrop in background (don't block response)
      stellarService.airdropToNewUser(identity)
        .then(result => {
          if (result.success) {
            console.log(`[Airdrop] ✅ @${handle} received welcome tokens!`);
            console.log(`[Airdrop]    Stellar: ${result.stellarAddress}`);
            console.log(`[Airdrop]    XLM tx: ${result.xlmTx}`);
            console.log(`[Airdrop]    GNS tx: ${result.gnsTx}`);
          } else {
            console.error(`[Airdrop] ❌ Failed for @${handle}: ${result.error}`);
          }
        })
        .catch(err => {
          console.error(`[Airdrop] ❌ Error for @${handle}:`, err.message);
        });
      
      airdropResult = { status: 'processing', message: 'Welcome tokens being sent!' };
    } else {
      console.warn(`[Airdrop] Skipped for @${handle} - distribution wallet not configured`);
      airdropResult = { status: 'skipped', message: 'Airdrop not configured' };
    }
    // ===========================================
    
    return res.status(201).json({
      success: true,
      data: {
        handle: alias.handle,
        pk_root: alias.pk_root,
        created_at: alias.created_at,
        airdrop: airdropResult,
      },
      message: `@${handle} is now yours!`,
    } as ApiResponse);
    
  } catch (error) {
    console.error('PUT /aliases/:handle error:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
    } as ApiResponse);
  }
});

// ===========================================
// POST /aliases/:handle/reserve
// Reserve a handle (30-day hold)
// ===========================================
router.post('/:handle/reserve', async (req: Request, res: Response) => {
  try {
    const handle = req.params.handle?.toLowerCase().replace('@', '');
    const identity = req.body.identity?.toLowerCase();
    const signature = req.body.signature;
    
    // Validate handle
    const validationResult = handleSchema.safeParse(handle);
    if (!validationResult.success) {
      return res.status(400).json({
        success: false,
        error: 'Invalid handle format',
        message: validationResult.error.errors.map(e => e.message).join(', '),
      } as ApiResponse);
    }
    
    // Validate identity
    if (!identity || identity.length !== GNS_CONSTANTS.PK_LENGTH) {
      return res.status(400).json({
        success: false,
        error: 'Invalid identity',
      } as ApiResponse);
    }
    
    // TODO: Verify signature for reservation
    // For MVP, we'll trust the identity
    
    // Attempt reservation
    const result = await db.reserveHandle(handle, identity);
    
    if (!result.reserved) {
      return res.status(409).json({
        success: false,
        error: result.error || 'Reservation failed',
      } as ApiResponse);
    }
    
    console.log(`Handle reserved: @${handle} for ${identity.substring(0, 16)}... until ${result.expires_at}`);
    
    return res.status(201).json({
      success: true,
      data: {
        handle,
        expires_at: result.expires_at,
      },
      message: `@${handle} reserved for 30 days`,
    } as ApiResponse);
    
  } catch (error) {
    console.error('POST /aliases/:handle/reserve error:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
    } as ApiResponse);
  }
});

export default router;
