// ============================================================
// GNS gSITE API ROUTES (FIXED)
// ============================================================
// Location: src/api/gsite.ts
// Works with existing db.ts and crypto.ts
// ============================================================

import { Router, Request, Response } from 'express';
import * as db from '../lib/db';
import { verifySignature } from '../lib/crypto';

const router = Router();

// Valid entity types
const VALID_TYPES = [
  'Person', 'Business', 'Store', 'Service', 'Publication',
  'Community', 'Organization', 'Event', 'Product', 'Place'
];

// ============================================================
// INLINE VALIDATION (no external dependency)
// ============================================================

interface ValidationResult {
  valid: boolean;
  errors: string[];
  warnings: string[];
}

function validateGSite(data: any): ValidationResult {
  const errors: string[] = [];
  const warnings: string[] = [];

  // Required fields
  if (!data['@context']) errors.push('Missing @context');
  if (!data['@type']) errors.push('Missing @type');
  if (!data['@id']) errors.push('Missing @id');
  if (!data.name) errors.push('Missing name');

  // Validate @context
  if (data['@context'] && data['@context'] !== 'https://schema.gns.network/v1') {
    errors.push('Invalid @context');
  }

  // Validate @type
  if (data['@type'] && !VALID_TYPES.includes(data['@type'])) {
    errors.push(`Invalid @type. Must be one of: ${VALID_TYPES.join(', ')}`);
  }

  // Validate @id format
  if (data['@id'] && !data['@id'].startsWith('@') && !data['@id'].endsWith('@')) {
    errors.push('@id must start with @ (handle) or end with @ (namespace)');
  }

  // Warnings (recommendations)
  if (!data.bio) warnings.push('Consider adding a bio');
  if (!data.avatar) warnings.push('gSites with avatars get more engagement');

  return {
    valid: errors.length === 0,
    errors,
    warnings,
  };
}

// ============================================================
// GET /gsite/:identifier - Retrieve a gSite
// ============================================================

router.get('/:identifier', async (req: Request, res: Response) => {
  try {
    const identifier = decodeURIComponent(req.params.identifier).toLowerCase();
    const version = req.query.version as string | undefined;

    console.log(`📋 GET gSite: ${identifier}`);

    const supabase = db.getSupabase();

    // Query gsites table
    let query = supabase
      .from('gsites')
      .select('*')
      .eq('identifier', identifier);

    if (version) {
      query = query.eq('version', parseInt(version));
    } else {
      query = query.order('version', { ascending: false }).limit(1);
    }

    const { data, error } = await query.single();

    if (error || !data) {
      // Fallback: Build gSite from existing record/alias
      const fallbackGSite = await buildFallbackGSite(identifier);
      
      if (fallbackGSite) {
        return res.json({
          success: true,
          data: fallbackGSite,
          source: 'fallback',
        });
      }
      
      return res.status(404).json({
        success: false,
        error: `gSite not found: ${identifier}`,
      });
    }

    res.json({
      success: true,
      data: data.content,
      version: data.version,
    });
  } catch (err) {
    console.error('❌ GET /gsite error:', err);
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
    const identifier = decodeURIComponent(req.params.identifier).toLowerCase();
    const gsiteData = req.body;

    console.log(`📝 PUT gSite: ${identifier}`);

    // 1. Validate
    const validation = validateGSite(gsiteData);
    if (!validation.valid) {
      return res.status(400).json({
        success: false,
        error: 'gSite validation failed',
        errors: validation.errors,
      });
    }

    // 2. Check signature exists in body
    if (!gsiteData.signature) {
      return res.status(400).json({
        success: false,
        error: 'gSite must be signed',
      });
    }

    // 3. Verify ownership via headers
    const publicKey = req.headers['x-gns-publickey'] as string;
    const signature = req.headers['x-gns-signature'] as string;
    const timestamp = req.headers['x-gns-timestamp'] as string;

    if (!publicKey || !signature || !timestamp) {
      return res.status(401).json({
        success: false,
        error: 'Missing auth headers: X-GNS-PublicKey, X-GNS-Signature, X-GNS-Timestamp',
      });
    }

    // Check timestamp (5 min window)
    const requestTime = parseInt(timestamp);
    if (Math.abs(Date.now() - requestTime) > 5 * 60 * 1000) {
      return res.status(401).json({
        success: false,
        error: 'Request timestamp expired',
      });
    }

    // Verify signature
    const message = `PUT:/gsite/${identifier}:${timestamp}`;
    if (!verifySignature(publicKey, message, signature)) {
      return res.status(401).json({
        success: false,
        error: 'Invalid signature',
      });
    }

    // 4. Check ownership
    const isOwner = await checkOwnership(identifier, publicKey);
    if (!isOwner) {
      return res.status(403).json({
        success: false,
        error: 'Not authorized to update this gSite',
      });
    }

    const supabase = db.getSupabase();

    // 5. Get current version
    const { data: existing } = await supabase
      .from('gsites')
      .select('version')
      .eq('identifier', identifier)
      .order('version', { ascending: false })
      .limit(1)
      .single();

    const newVersion = (existing?.version || 0) + 1;

    // 6. Save
    const { data, error } = await supabase
      .from('gsites')
      .insert({
        identifier,
        content: gsiteData,
        version: newVersion,
        type: gsiteData['@type'],
        owner_pk: publicKey,
        signature: gsiteData.signature,
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

    console.log(`✅ gSite saved: ${identifier} v${newVersion}`);

    res.json({
      success: true,
      version: newVersion,
      warnings: validation.warnings,
      data: data.content,
    });

  } catch (err) {
    console.error('❌ PUT /gsite error:', err);
    res.status(500).json({
      success: false,
      error: 'Failed to update gSite',
    });
  }
});

// ============================================================
// POST /gsite/:identifier/validate
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
    res.status(500).json({ success: false, error: 'Validation failed' });
  }
});

// ============================================================
// GET /gsite/:identifier/history
// ============================================================

router.get('/:identifier/history', async (req: Request, res: Response) => {
  try {
    const identifier = decodeURIComponent(req.params.identifier).toLowerCase();
    const limit = Math.min(parseInt(req.query.limit as string) || 10, 50);

    const supabase = db.getSupabase();
    const { data, error } = await supabase
      .from('gsites')
      .select('version, updated_at, type')
      .eq('identifier', identifier)
      .order('version', { ascending: false })
      .limit(limit);

    if (error) {
      return res.status(500).json({ success: false, error: 'Failed to fetch history' });
    }

    res.json({
      success: true,
      identifier,
      versions: data || [],
    });
  } catch (err) {
    res.status(500).json({ success: false, error: 'Failed to fetch history' });
  }
});

// ============================================================
// HELPERS
// ============================================================

async function checkOwnership(identifier: string, publicKey: string): Promise<boolean> {
  const supabase = db.getSupabase();
  const pk = publicKey.toLowerCase();
  
  // @handle -> check aliases
  if (identifier.startsWith('@')) {
    const handle = identifier.slice(1);
    const { data } = await supabase
      .from('aliases')
      .select('pk_root')
      .eq('handle', handle)
      .single();
    return data?.pk_root?.toLowerCase() === pk;
  }
  
  // namespace@ -> check namespaces
  if (identifier.endsWith('@')) {
    const namespace = identifier.slice(0, -1);
    const { data } = await supabase
      .from('namespaces')
      .select('admin_pk')
      .eq('namespace', namespace)
      .single();
    return data?.admin_pk?.toLowerCase() === pk;
  }
  
  return false;
}

async function buildFallbackGSite(identifier: string): Promise<any | null> {
  if (!identifier.startsWith('@')) return null;
  
  const handle = identifier.slice(1);
  const supabase = db.getSupabase();
  
  // Get alias
  const { data: alias } = await supabase
    .from('aliases')
    .select('pk_root, verified')
    .eq('handle', handle)
    .single();
  
  if (!alias) return null;
  
  // Get record
  const { data: record } = await supabase
    .from('records')
    .select('record_json, trust_score, created_at')
    .eq('pk_root', alias.pk_root)
    .single();
  
  if (!record) return null;
  
  // Extract profile
  const profile = record.record_json?.modules?.find(
    (m: any) => m.schema === 'gns.module.profile/v1'
  )?.config || {};
  
  return {
    '@context': 'https://schema.gns.network/v1',
    '@type': 'Person',
    '@id': identifier,
    name: profile.display_name || handle,
    bio: profile.bio || null,
    avatar: profile.avatar ? { url: profile.avatar } : null,
    status: profile.status || null,
    skills: profile.skills || [],
    links: profile.links || [],
    trust: {
      score: record.trust_score || 0,
      breadcrumbs: record.record_json?.breadcrumb_count || 0,
      since: record.created_at?.split('T')[0],
    },
    verified: alias.verified || false,
    publicKey: alias.pk_root,
    signature: 'ed25519:fallback',
  };
}

export default router;
