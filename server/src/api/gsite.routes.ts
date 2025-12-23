// ============================================================
// GNS gSITE API ROUTES
// ============================================================
// Location: server/src/routes/gsite.routes.ts
// Purpose: CRUD operations for gSites with validation
// ============================================================

import { Router, Request, Response } from 'express';
import { createClient } from '@supabase/supabase-js';
import { validateGSite, validateTheme, ValidationResult } from '../validation/gsite-validator';
import { verifyGNSSignature } from '../crypto/verify';

const router = Router();

// Supabase client
const supabase = createClient(
  process.env.SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_KEY!
);

// ============================================================
// GET /gsite/:identifier - Retrieve a gSite
// ============================================================

router.get('/:identifier', async (req: Request, res: Response) => {
  try {
    const { identifier } = req.params;
    const { version } = req.query;

    console.log(`📋 GET gSite: ${identifier}`);

    // Query Supabase
    let query = supabase
      .from('gsites')
      .select('*')
      .eq('identifier', identifier);

    if (version) {
      query = query.eq('version', parseInt(version as string));
    } else {
      query = query.order('version', { ascending: false }).limit(1);
    }

    const { data, error } = await query.single();

    if (error || !data) {
      return res.status(404).json({
        code: 'NOT_FOUND',
        message: `gSite not found: ${identifier}`,
      });
    }

    res.json(data.content);
  } catch (err) {
    console.error('❌ Error fetching gSite:', err);
    res.status(500).json({
      code: 'INTERNAL_ERROR',
      message: 'Failed to fetch gSite',
    });
  }
});

// ============================================================
// PUT /gsite/:identifier - Update a gSite
// ============================================================

router.put('/:identifier', async (req: Request, res: Response) => {
  try {
    const { identifier } = req.params;
    const gsiteData = req.body;

    console.log(`📝 PUT gSite: ${identifier}`);

    // 1. Validate against schema
    const validation = validateGSite(gsiteData);
    
    if (!validation.valid) {
      return res.status(400).json({
        code: 'VALIDATION_ERROR',
        message: 'gSite validation failed',
        errors: validation.errors,
      });
    }

    // 2. Verify ownership (signature check)
    const authHeader = req.headers.authorization;
    if (!authHeader?.startsWith('GNS-Ed25519 ')) {
      return res.status(401).json({
        code: 'UNAUTHORIZED',
        message: 'Missing or invalid authorization',
      });
    }

    // Parse: "GNS-Ed25519 handle:timestamp:signature"
    const authParts = authHeader.replace('GNS-Ed25519 ', '').split(':');
    if (authParts.length !== 3) {
      return res.status(401).json({
        code: 'UNAUTHORIZED',
        message: 'Invalid authorization format',
      });
    }

    const [handle, timestamp, signature] = authParts;

    // Verify the request is from the owner
    const isOwner = await verifyOwnership(identifier, handle, timestamp, signature, req);
    if (!isOwner) {
      return res.status(403).json({
        code: 'FORBIDDEN',
        message: 'Not authorized to update this gSite',
      });
    }

    // 3. Verify gSite signature
    if (!gsiteData.signature) {
      return res.status(400).json({
        code: 'MISSING_SIGNATURE',
        message: 'gSite must be signed',
      });
    }

    // 4. Get current version
    const { data: existing } = await supabase
      .from('gsites')
      .select('version')
      .eq('identifier', identifier)
      .order('version', { ascending: false })
      .limit(1)
      .single();

    const newVersion = (existing?.version || 0) + 1;

    // 5. Save to Supabase
    const { data, error } = await supabase
      .from('gsites')
      .insert({
        identifier,
        content: gsiteData,
        version: newVersion,
        type: gsiteData['@type'],
        updated_at: new Date().toISOString(),
      })
      .select()
      .single();

    if (error) {
      console.error('❌ Supabase error:', error);
      return res.status(500).json({
        code: 'DATABASE_ERROR',
        message: 'Failed to save gSite',
      });
    }

    // 6. Return with warnings if any
    res.json({
      success: true,
      version: newVersion,
      warnings: validation.warnings,
      gsite: data.content,
    });

  } catch (err) {
    console.error('❌ Error updating gSite:', err);
    res.status(500).json({
      code: 'INTERNAL_ERROR',
      message: 'Failed to update gSite',
    });
  }
});

// ============================================================
// POST /gsite/:identifier/validate - Validate without saving
// ============================================================

router.post('/:identifier/validate', async (req: Request, res: Response) => {
  try {
    const gsiteData = req.body;

    console.log(`✅ Validating gSite: ${req.params.identifier}`);

    const validation = validateGSite(gsiteData);

    res.json({
      valid: validation.valid,
      errors: validation.errors,
      warnings: validation.warnings,
    });

  } catch (err) {
    console.error('❌ Error validating gSite:', err);
    res.status(500).json({
      code: 'INTERNAL_ERROR',
      message: 'Failed to validate gSite',
    });
  }
});

// ============================================================
// GET /gsite/:identifier/history - Version history
// ============================================================

router.get('/:identifier/history', async (req: Request, res: Response) => {
  try {
    const { identifier } = req.params;
    const limit = parseInt(req.query.limit as string) || 10;
    const offset = parseInt(req.query.offset as string) || 0;

    const { data, error } = await supabase
      .from('gsites')
      .select('version, updated_at, content->signature')
      .eq('identifier', identifier)
      .order('version', { ascending: false })
      .range(offset, offset + limit - 1);

    if (error) {
      return res.status(500).json({
        code: 'DATABASE_ERROR',
        message: 'Failed to fetch history',
      });
    }

    res.json({
      identifier,
      versions: data.map(v => ({
        version: v.version,
        updated: v.updated_at,
        hash: v.signature?.substring(0, 16) + '...',
      })),
    });

  } catch (err) {
    console.error('❌ Error fetching history:', err);
    res.status(500).json({
      code: 'INTERNAL_ERROR',
      message: 'Failed to fetch history',
    });
  }
});

// ============================================================
// HELPER: Verify Ownership
// ============================================================

async function verifyOwnership(
  identifier: string,
  handle: string,
  timestamp: string,
  signature: string,
  req: Request
): Promise<boolean> {
  // 1. Check timestamp is recent (within 5 minutes)
  const requestTime = parseInt(timestamp);
  const now = Date.now();
  if (Math.abs(now - requestTime) > 5 * 60 * 1000) {
    return false;
  }

  // 2. Get public key for the handle
  const { data: identity } = await supabase
    .from('identities')
    .select('public_key')
    .eq('handle', handle.replace('@', ''))
    .single();

  if (!identity) {
    return false;
  }

  // 3. Check if handle owns the identifier
  // For @handle: handle must match
  // For namespace@: handle must be admin
  if (identifier.startsWith('@')) {
    if (`@${handle}` !== identifier && handle !== identifier) {
      return false;
    }
  } else {
    // Check namespace admin
    const namespace = identifier.replace('@', '');
    const { data: ns } = await supabase
      .from('namespaces')
      .select('admin_handle')
      .eq('namespace', namespace)
      .single();
    
    if (!ns || ns.admin_handle !== handle) {
      return false;
    }
  }

  // 4. Verify signature
  const message = `PUT:/gsite/${identifier}:${timestamp}`;
  return verifyGNSSignature(message, signature, identity.public_key);
}

export default router;
