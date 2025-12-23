// ============================================================
// GNS gSITE API ROUTES
// ============================================================
// Location: server/src/api/gsite.ts
// Purpose: CRUD operations for gSites with validation
// ============================================================

import { Router, Request, Response } from 'express';
import { validateGSite, validateTheme } from '../lib/gsite-validator';
import { getSupabase } from '../lib/db';
import { verifySignature } from '../lib/crypto';

const router = Router();

// Get Supabase client
const supabase = getSupabase();

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
        success: false,
        error: `gSite not found: ${identifier}`,
      });
    }

    res.json({
      success: true,
      data: data.content,
    });
  } catch (err) {
    console.error('❌ Error fetching gSite:', err);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch gSite',
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
        success: false,
        error: 'gSite validation failed',
        errors: validation.errors,
      });
    }

    // 2. Verify signature exists
    if (!gsiteData.signature) {
      return res.status(400).json({
        success: false,
        error: 'gSite must be signed',
      });
    }

    // 3. Verify ownership via header
    const publicKey = req.headers['x-gns-publickey'] as string;
    const signature = req.headers['x-gns-signature'] as string;
    const timestamp = req.headers['x-gns-timestamp'] as string;

    if (!publicKey || !signature || !timestamp) {
      return res.status(401).json({
        success: false,
        error: 'Missing authentication headers (X-GNS-PublicKey, X-GNS-Signature, X-GNS-Timestamp)',
      });
    }

    // Check timestamp is recent (within 5 minutes)
    const requestTime = parseInt(timestamp);
    const now = Date.now();
    if (Math.abs(now - requestTime) > 5 * 60 * 1000) {
      return res.status(401).json({
        success: false,
        error: 'Request timestamp expired',
      });
    }

    // Verify signature
    const message = `PUT:/gsite/${identifier}:${timestamp}`;
    const isValidSig = verifySignature(message, signature, publicKey);
    if (!isValidSig) {
      return res.status(401).json({
        success: false,
        error: 'Invalid signature',
      });
    }

    // 4. Check ownership (handle must belong to this public key)
    const isOwner = await checkOwnership(identifier, publicKey);
    if (!isOwner) {
      return res.status(403).json({
        success: false,
        error: 'Not authorized to update this gSite',
      });
    }

    // 5. Get current version
    const { data: existing } = await supabase
      .from('gsites')
      .select('version')
      .eq('identifier', identifier)
      .order('version', { ascending: false })
      .limit(1)
      .single();

    const newVersion = (existing?.version || 0) + 1;

    // 6. Save to Supabase
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
        success: false,
        error: 'Failed to save gSite',
      });
    }

    // 7. Return with warnings if any
    res.json({
      success: true,
      version: newVersion,
      warnings: validation.warnings,
      data: data.content,
    });

  } catch (err) {
    console.error('❌ Error updating gSite:', err);
    res.status(500).json({
      success: false,
      error: 'Failed to update gSite',
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
      success: true,
      valid: validation.valid,
      errors: validation.errors,
      warnings: validation.warnings,
    });

  } catch (err) {
    console.error('❌ Error validating gSite:', err);
    res.status(500).json({
      success: false,
      error: 'Failed to validate gSite',
    });
  }
});

// ============================================================
// POST /gsite/theme/validate - Validate a theme
// ============================================================

router.post('/theme/validate', async (req: Request, res: Response) => {
  try {
    const themeData = req.body;

    console.log(`🎨 Validating theme`);

    const validation = validateTheme(themeData);

    res.json({
      success: true,
      valid: validation.valid,
      errors: validation.errors,
      warnings: validation.warnings,
    });

  } catch (err) {
    console.error('❌ Error validating theme:', err);
    res.status(500).json({
      success: false,
      error: 'Failed to validate theme',
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
      .select('version, updated_at')
      .eq('identifier', identifier)
      .order('version', { ascending: false })
      .range(offset, offset + limit - 1);

    if (error) {
      return res.status(500).json({
        success: false,
        error: 'Failed to fetch history',
      });
    }

    res.json({
      success: true,
      identifier,
      versions: data?.map(v => ({
        version: v.version,
        updated: v.updated_at,
      })) || [],
    });

  } catch (err) {
    console.error('❌ Error fetching history:', err);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch history',
    });
  }
});

// ============================================================
// HELPER: Check Ownership
// ============================================================

async function checkOwnership(identifier: string, publicKey: string): Promise<boolean> {
  // For @handle: check aliases table (your existing table)
  if (identifier.startsWith('@')) {
    const handle = identifier.replace('@', '');
    const { data } = await supabase
      .from('aliases')
      .select('pk_root')
      .eq('handle', handle)
      .single();
    
    return data?.pk_root === publicKey;
  }
  
  // For namespace@: check namespaces table
  const namespace = identifier.replace('@', '');
  const { data } = await supabase
    .from('namespaces')
    .select('admin_pk')
    .eq('namespace', namespace)
    .single();
  
  return data?.admin_pk === publicKey;
}

export default router;
