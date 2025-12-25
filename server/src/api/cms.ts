// ===========================================
// GNS-CMS API ROUTES
// ===========================================
// Location: src/api/cms.ts
// Theme management, media, and gSite theming
// ===========================================

import { Router, Request, Response } from 'express';
import * as db from '../lib/db';
import { verifySignature } from '../lib/crypto';

const router = Router();

// ===========================================
// THEMES
// ===========================================

/**
 * GET /cms/themes
 * List all available themes with optional filtering
 */
router.get('/themes', async (req: Request, res: Response) => {
  try {
    const { 
      entityType, 
      category, 
      license,
      author,
      limit = '50',
      offset = '0'
    } = req.query;

    console.log(`📚 GET /cms/themes`);

    const supabase = db.getSupabase();
    let query = supabase
      .from('themes')
      .select('id, name, description, version, author, entity_types, categories, license, price_amount, price_currency, thumbnail_url, install_count, rating_avg, rating_count, is_default')
      .eq('is_published', true)
      .order('is_default', { ascending: false })
      .order('install_count', { ascending: false })
      .range(parseInt(offset as string), parseInt(offset as string) + parseInt(limit as string) - 1);

    // Apply filters
    if (entityType) {
      query = query.contains('entity_types', [entityType]);
    }
    if (category) {
      query = query.contains('categories', [category]);
    }
    if (license) {
      query = query.eq('license', license);
    }
    if (author) {
      query = query.eq('author', author);
    }

    const { data, error } = await query;

    if (error) {
      console.error('❌ Supabase error:', error);
      return res.status(500).json({ success: false, error: 'Failed to fetch themes' });
    }

    res.json({
      success: true,
      data: data || [],
      count: data?.length || 0
    });

  } catch (err) {
    console.error('❌ GET /cms/themes error:', err);
    res.status(500).json({ success: false, error: 'Failed to fetch themes' });
  }
});

/**
 * GET /cms/themes/:id
 * Get full theme definition by ID
 */
router.get('/themes/:id', async (req: Request, res: Response) => {
  try {
    const { id } = req.params;

    console.log(`🎨 GET /cms/themes/${id}`);

    const supabase = db.getSupabase();
    const { data, error } = await supabase
      .from('themes')
      .select('*')
      .eq('id', id)
      .single();

    if (error || !data) {
      return res.status(404).json({ success: false, error: 'Theme not found' });
    }

    // Build full theme object
    const theme = {
      id: data.id,
      name: data.name,
      description: data.description,
      version: data.version,
      author: data.author,
      license: data.license,
      price: data.price_amount > 0 ? {
        amount: data.price_amount,
        currency: data.price_currency
      } : null,
      entityTypes: data.entity_types,
      categories: data.categories,
      tokens: data.tokens,
      components: data.components,
      layout: data.layout,
      darkMode: data.dark_mode,
      preview: {
        thumbnail: data.thumbnail_url,
        screenshots: data.screenshots
      },
      stats: {
        installs: data.install_count,
        rating: data.rating_avg,
        reviews: data.rating_count
      },
      signature: data.signature
    };

    res.json({ success: true, data: theme });

  } catch (err) {
    console.error('❌ GET /cms/themes/:id error:', err);
    res.status(500).json({ success: false, error: 'Failed to fetch theme' });
  }
});

/**
 * POST /cms/themes
 * Create a new theme (marketplace submission)
 */
router.post('/themes', async (req: Request, res: Response) => {
  try {
    const themeData: any = req.body;

    console.log(`📝 POST /cms/themes: ${themeData.id}`);

    // Basic validation
    if (!themeData.id || !themeData.name || !themeData.version || !themeData.entityTypes || !themeData.tokens) {
      return res.status(400).json({
        success: false,
        error: 'Missing required fields: id, name, version, entityTypes, tokens'
      });
    }

    // Verify signature
    const publicKey = req.headers['x-gns-publickey'] as string;
    const signature = req.headers['x-gns-signature'] as string;
    const timestamp = req.headers['x-gns-timestamp'] as string;

    if (!publicKey || !signature || !timestamp) {
      return res.status(401).json({
        success: false,
        error: 'Missing auth headers'
      });
    }

    // Verify ownership
    const message = `POST:/cms/themes:${themeData.id}:${timestamp}`;
    if (!verifySignature(publicKey, message, signature)) {
      return res.status(401).json({ success: false, error: 'Invalid signature' });
    }

    const supabase = db.getSupabase();

    // Check if theme ID exists
    const { data: existing } = await supabase
      .from('themes')
      .select('id')
      .eq('id', themeData.id)
      .single();

    if (existing) {
      return res.status(409).json({ success: false, error: 'Theme ID already exists' });
    }

    // Insert theme
    const { data, error } = await supabase
      .from('themes')
      .insert({
        id: themeData.id,
        name: themeData.name,
        description: themeData.description || null,
        version: themeData.version,
        author: themeData.author || null,
        author_pk: publicKey,
        signature: themeData.signature || null,
        entity_types: themeData.entityTypes,
        categories: themeData.categories || [],
        license: themeData.license || 'free',
        price_amount: themeData.price?.amount || 0,
        price_currency: themeData.price?.currency || 'USD',
        tokens: themeData.tokens,
        components: themeData.components || null,
        layout: themeData.layout || null,
        dark_mode: themeData.darkMode || null,
        thumbnail_url: themeData.preview?.thumbnail || null,
        screenshots: themeData.preview?.screenshots || [],
        is_default: false,
        is_published: false // Requires review
      })
      .select()
      .single();

    if (error) {
      console.error('❌ Supabase error:', error);
      return res.status(500).json({ success: false, error: 'Failed to create theme' });
    }

    console.log(`✅ Theme created: ${themeData.id}`);

    res.status(201).json({
      success: true,
      data: { id: data.id, name: data.name },
      message: 'Theme submitted for review'
    });

  } catch (err) {
    console.error('❌ POST /cms/themes error:', err);
    res.status(500).json({ success: false, error: 'Failed to create theme' });
  }
});

/**
 * POST /cms/themes/:id/validate
 * Validate a theme without saving
 */
router.post('/themes/:id/validate', async (req: Request, res: Response) => {
  try {
    const themeData: any = req.body;
    const errors: string[] = [];
    const warnings: string[] = [];

    // Basic validation
    if (!themeData.id) errors.push('Missing id');
    if (!themeData.name) errors.push('Missing name');
    if (!themeData.version) errors.push('Missing version');
    if (!themeData.entityTypes?.length) errors.push('Missing entityTypes');
    if (!themeData.tokens) errors.push('Missing tokens');
    if (!themeData.tokens?.colors) errors.push('Missing tokens.colors');

    // Warnings
    if (!themeData.darkMode) {
      warnings.push('Consider adding dark mode support');
    }
    if (!themeData.preview?.thumbnail) {
      warnings.push('Themes with thumbnails get 3x more installs');
    }

    res.json({
      success: true,
      valid: errors.length === 0,
      errors,
      warnings
    });

  } catch (err) {
    res.status(500).json({ success: false, error: 'Validation failed' });
  }
});

// ===========================================
// GSITE THEMING
// ===========================================

/**
 * GET /cms/gsite/:identifier/theme
 * Get the theme applied to a gSite
 */
router.get('/gsite/:identifier/theme', async (req: Request, res: Response) => {
  try {
    const identifier = decodeURIComponent(req.params.identifier).toLowerCase();

    console.log(`🎨 GET theme for: ${identifier}`);

    const supabase = db.getSupabase();

    // Get gSite theme assignment
    const { data: assignment } = await supabase
      .from('gsite_themes')
      .select('theme_id, overrides')
      .eq('identifier', identifier)
      .single();

    // Default theme based on entity type
    let themeId = 'profile-minimal';
    let overrides = null;

    if (assignment) {
      themeId = assignment.theme_id;
      overrides = assignment.overrides;
    } else {
      // Get gSite to determine entity type
      const { data: gsite } = await supabase
        .from('gsites')
        .select('type')
        .eq('identifier', identifier)
        .order('version', { ascending: false })
        .limit(1)
        .single();

      if (gsite) {
        // Map entity type to default theme
        const defaultThemes: Record<string, string> = {
          'Person': 'profile-minimal',
          'Business': 'storefront-modern',
          'Store': 'storefront-modern',
          'Service': 'storefront-modern',
          'Organization': 'storefront-modern'
        };
        themeId = defaultThemes[gsite.type] || 'profile-minimal';
      }
    }

    // Get full theme
    const { data: theme, error } = await supabase
      .from('themes')
      .select('*')
      .eq('id', themeId)
      .single();

    if (error || !theme) {
      return res.status(404).json({ success: false, error: 'Theme not found' });
    }

    // Merge overrides
    let finalTokens = theme.tokens;
    if (overrides?.colors) {
      finalTokens = {
        ...theme.tokens,
        colors: { ...theme.tokens.colors, ...overrides.colors }
      };
    }

    res.json({
      success: true,
      data: {
        id: theme.id,
        name: theme.name,
        tokens: finalTokens,
        components: overrides?.components || theme.components,
        layout: overrides?.layout || theme.layout,
        darkMode: theme.dark_mode,
        overrides: overrides || null
      }
    });

  } catch (err) {
    console.error('❌ GET /cms/gsite/:id/theme error:', err);
    res.status(500).json({ success: false, error: 'Failed to fetch theme' });
  }
});

/**
 * PUT /cms/gsite/:identifier/theme
 * Apply a theme to a gSite (with optional overrides)
 */
router.put('/gsite/:identifier/theme', async (req: Request, res: Response) => {
  try {
    const identifier = decodeURIComponent(req.params.identifier).toLowerCase();
    const { themeId, overrides } = req.body;

    console.log(`🎨 PUT theme for: ${identifier} → ${themeId}`);

    if (!themeId) {
      return res.status(400).json({ success: false, error: 'Missing themeId' });
    }

    // Verify ownership
    const publicKey = req.headers['x-gns-publickey'] as string;
    const signature = req.headers['x-gns-signature'] as string;
    const timestamp = req.headers['x-gns-timestamp'] as string;

    if (!publicKey || !signature || !timestamp) {
      return res.status(401).json({ success: false, error: 'Missing auth headers' });
    }

    const message = `PUT:/cms/gsite/${identifier}/theme:${timestamp}`;
    if (!verifySignature(publicKey, message, signature)) {
      return res.status(401).json({ success: false, error: 'Invalid signature' });
    }

    const supabase = db.getSupabase();

    // Verify theme exists
    const { data: theme } = await supabase
      .from('themes')
      .select('id, license, price_amount')
      .eq('id', themeId)
      .single();

    if (!theme) {
      return res.status(404).json({ success: false, error: 'Theme not found' });
    }

    // Check if paid theme requires purchase
    if (theme.license !== 'free' && theme.price_amount > 0) {
      const { data: purchase } = await supabase
        .from('theme_purchases')
        .select('id')
        .eq('theme_id', themeId)
        .eq('buyer_pk', publicKey)
        .single();

      if (!purchase) {
        return res.status(402).json({
          success: false,
          error: 'Theme requires purchase',
          price: theme.price_amount
        });
      }
    }

    // Upsert theme assignment
    const { error } = await supabase
      .from('gsite_themes')
      .upsert({
        identifier,
        theme_id: themeId,
        overrides: overrides || null,
        updated_at: new Date().toISOString()
      }, { onConflict: 'identifier' });

    if (error) {
      console.error('❌ Supabase error:', error);
      return res.status(500).json({ success: false, error: 'Failed to apply theme' });
    }

    console.log(`✅ Theme applied: ${identifier} → ${themeId}`);

    res.json({
      success: true,
      data: { identifier, themeId, overrides }
    });

  } catch (err) {
    console.error('❌ PUT /cms/gsite/:id/theme error:', err);
    res.status(500).json({ success: false, error: 'Failed to apply theme' });
  }
});

// ===========================================
// THEME RATINGS
// ===========================================

/**
 * POST /cms/themes/:id/rate
 * Rate a theme
 */
router.post('/themes/:id/rate', async (req: Request, res: Response) => {
  try {
    const { id } = req.params;
    const { rating, review } = req.body;

    if (!rating || rating < 1 || rating > 5) {
      return res.status(400).json({ success: false, error: 'Rating must be 1-5' });
    }

    const publicKey = req.headers['x-gns-publickey'] as string;
    if (!publicKey) {
      return res.status(401).json({ success: false, error: 'Missing public key' });
    }

    const supabase = db.getSupabase();

    // Upsert rating
    const { error } = await supabase
      .from('theme_ratings')
      .upsert({
        theme_id: id,
        rater_pk: publicKey,
        rating,
        review: review || null
      }, { onConflict: 'theme_id,rater_pk' });

    if (error) {
      return res.status(500).json({ success: false, error: 'Failed to save rating' });
    }

    res.json({ success: true, message: 'Rating saved' });

  } catch (err) {
    res.status(500).json({ success: false, error: 'Failed to rate theme' });
  }
});

/**
 * GET /cms/themes/:id/ratings
 * Get ratings for a theme
 */
router.get('/themes/:id/ratings', async (req: Request, res: Response) => {
  try {
    const { id } = req.params;
    const limit = parseInt(req.query.limit as string) || 10;

    const supabase = db.getSupabase();
    const { data, error } = await supabase
      .from('theme_ratings')
      .select('rating, review, rater_handle, created_at')
      .eq('theme_id', id)
      .order('created_at', { ascending: false })
      .limit(limit);

    if (error) {
      return res.status(500).json({ success: false, error: 'Failed to fetch ratings' });
    }

    res.json({ success: true, data: data || [] });

  } catch (err) {
    res.status(500).json({ success: false, error: 'Failed to fetch ratings' });
  }
});

export default router;
