// ===========================================
// GNS NODE - WEB API
// /web endpoints for World Browser
// ===========================================

import { Router, Request, Response } from 'express';
import * as db from '../lib/db';
import { ApiResponse } from '../types';

const router = Router();

// ===========================================
// GET /web/profile/:handle
// Get profile data for World Browser display
// Handles can be with or without @ prefix
// ===========================================
router.get('/profile/:handle', async (req: Request, res: Response) => {
  try {
    let handle = req.params.handle.toLowerCase();
    
    // Strip @ prefix if present
    if (handle.startsWith('@')) {
      handle = handle.substring(1);
    }
    
    // Look up alias to get public key
    const alias = await db.getAlias(handle);
    
    if (!alias) {
      return res.status(404).json({
        success: false,
        error: 'Identity not found',
      } as ApiResponse);
    }
    
    // Get the full record
    const record = await db.getRecord(alias.pk_root);
    
    if (!record) {
      return res.status(404).json({
        success: false,
        error: 'Record not found',
      } as ApiResponse);
    }
    
    // Extract profile module if exists
    const profileModule = record.record_json.modules?.find(
      (m: any) => m.schema === 'gns.module.profile/v1'
    );
    
    // Build World Browser profile response (matching GnsIdentity type)
    const profile = {
      handle: handle,  // No @ prefix
      publicKey: alias.pk_root,
      displayName: profileModule?.config?.display_name || handle,  // snake_case
      bio: profileModule?.config?.bio || null,
      avatarUrl: profileModule?.config?.avatar || null,  // avatarUrl not avatar
      coverImage: profileModule?.config?.coverImage || null,
      location: profileModule?.config?.location || null,
      website: profileModule?.config?.website || null,
      trustScore: record.record_json.trust_score || 0,
      breadcrumbCount: record.record_json.breadcrumb_count || 0,
      isVerified: alias.verified || false,  // isVerified not verified
      createdAt: record.created_at,
      updatedAt: record.updated_at,
      modules: record.record_json.modules || [],
      endpoints: record.record_json.endpoints || [],
      epochRoots: record.record_json.epoch_roots || [],
    };
    
    return res.json({
      success: true,
      data: profile,
    } as ApiResponse);
    
  } catch (error) {
    console.error('GET /web/profile error:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
    } as ApiResponse);
  }
});

// ===========================================
// GET /web/entity/:slug
// Get entity data for World Browser display
// ===========================================
router.get('/entity/:slug', async (req: Request, res: Response) => {
  try {
    const slug = req.params.slug.toLowerCase();
    
    // For now, entities are stored as aliases with special prefix
    // or in a dedicated entities table
    // TODO: Implement entity storage
    
    // Check if it's actually a handle (identity)
    const alias = await db.getAlias(slug);
    
    if (alias) {
      // Redirect to profile endpoint
      return res.redirect(307, `/web/profile/${slug}`);
    }
    
    // TODO: Look up in entities table when implemented
    // const entity = await db.getEntity(slug);
    
    return res.status(404).json({
      success: false,
      error: 'Entity not found',
    } as ApiResponse);
    
  } catch (error) {
    console.error('GET /web/entity error:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
    } as ApiResponse);
  }
});

// ===========================================
// GET /web/search
// Search identities and entities
// ===========================================
router.get('/search', async (req: Request, res: Response) => {
  try {
    const query = (req.query.q as string || '').toLowerCase().trim();
    const type = req.query.type as string || 'all';
    const limit = Math.min(parseInt(req.query.limit as string) || 20, 50);
    
    if (!query || query.length < 2) {
      return res.status(400).json({
        success: false,
        error: 'Query must be at least 2 characters',
      } as ApiResponse);
    }
    
    // Strip @ if searching for handle
    const searchQuery = query.startsWith('@') ? query.substring(1) : query;
    
    const results: any[] = [];
    
    // Search aliases
    if (type === 'all' || type === 'identity') {
      const aliases = await db.searchAliases(searchQuery, limit);
      
      for (const alias of aliases) {
        const record = await db.getRecord(alias.pk_root);
        const profileModule = record?.record_json.modules?.find(
          (m: any) => m.schema === 'gns.module.profile/v1'
        );
        
        results.push({
          type: 'identity',
          identity: {
            handle: alias.handle,
            publicKey: alias.pk_root,
            displayName: profileModule?.config?.displayName || alias.handle,
            bio: profileModule?.config?.bio || null,
            avatarUrl: profileModule?.config?.avatar || null,
            trustScore: record?.record_json.trust_score || 0,
            breadcrumbCount: record?.record_json.breadcrumb_count || 0,
            isVerified: alias.verified || false,
          },
          relevanceScore: 1.0,
        });
      }
    }
    
    // TODO: Search entities when implemented
    // if (type === 'all' || type === 'entity') {
    //   const entities = await db.searchEntities(searchQuery, limit);
    //   results.push(...entities.map(e => ({ type: 'entity', ...e })));
    // }
    
    return res.json({
      success: true,
      data: {
        results,
        query,
        count: results.length,
      },
    } as ApiResponse);
    
  } catch (error) {
    console.error('GET /web/search error:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
    } as ApiResponse);
  }
});

// ===========================================
// GET /web/featured
// Get featured identities and entities
// ===========================================
router.get('/featured', async (req: Request, res: Response) => {
  try {
    // Get top identities by trust score
    const topIdentities = await db.getTopIdentities(10);
    
    const featured = {
      identities: topIdentities.map((record: any) => ({
        handle: record.handle ? `@${record.handle}` : null,
        publicKey: record.pk_root,
        trustScore: record.trust_score,
        breadcrumbCount: record.breadcrumb_count,
      })),
      entities: [], // TODO: Add featured entities
    };
    
    return res.json({
      success: true,
      data: featured,
    } as ApiResponse);
    
  } catch (error) {
    console.error('GET /web/featured error:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
    } as ApiResponse);
  }
});

export default router;
