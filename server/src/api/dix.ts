// ===========================================
// GNS NODE - DIX WEB API
// /web/dix endpoints for Globe Posts Web Viewer
// 
// Add to: gns_browser/server/src/api/dix.ts
//
// Routes:
//   GET /web/dix/timeline     - Public timeline
//   GET /web/dix/@:handle     - User's dix posts
//   GET /web/dix/pk/:pk       - Posts by public key
//   GET /web/dix/post/:id     - Single post
//   GET /web/dix/tag/:tag     - Hashtag feed
//   GET /web/dix/stats        - DIX statistics
// ===========================================

import { Router, Request, Response } from 'express';
import { getSupabase } from '../lib/db';

// Get supabase client
const supabase = getSupabase();

const router = Router();

// ===========================================
// TYPES
// ===========================================

interface WebPost {
  id: string;
  author: {
    publicKey: string;
    handle: string | null;
    displayName: string | null;
    avatarUrl: string | null;
    trustScore: number;
    breadcrumbCount: number;
    isVerified: boolean;
  };
  facet: string;
  content: {
    text: string;
    media: Array<{ type: string; url: string; alt?: string }>;
    links: Array<{ url: string; title?: string; image?: string }>;
    tags: string[];
    mentions: string[];
    location?: string;
  };
  engagement: {
    likes: number;
    replies: number;
    reposts: number;
    quotes: number;
    views: number;
  };
  meta: {
    signature: string;
    trustScoreAtPost: number;
    breadcrumbsAtPost: number;
    ipfsCid?: string;
    createdAt: string;
  };
  thread?: {
    replyToId: string | null;
    quoteOfId: string | null;
  };
  brand?: {
    id: string;
    role?: string;
  };
}

// ===========================================
// HELPERS
// ===========================================

/**
 * Get author profile from records table
 */
async function getAuthorProfile(pk: string): Promise<{
  displayName: string | null;
  avatarUrl: string | null;
  trustScore: number;
  breadcrumbCount: number;
  handle: string | null;
  isVerified: boolean;
}> {
  try {
    const { data: record } = await supabase
      .from('records')
      .select('handle, trust_score, breadcrumb_count, record_json')
      .eq('pk_root', pk)
      .single();

    if (!record) {
      return {
        displayName: null,
        avatarUrl: null,
        trustScore: 0,
        breadcrumbCount: 0,
        handle: null,
        isVerified: false,
      };
    }

    const recordJson = typeof record.record_json === 'string'
      ? JSON.parse(record.record_json)
      : record.record_json || {};

    // Find profile module
    const profileModule = recordJson.modules?.find(
      (m: any) => m.schema === 'gns.module.profile/v1'
    );

    return {
      displayName: profileModule?.config?.display_name || null,
      avatarUrl: profileModule?.config?.avatar || null,
      trustScore: record.trust_score || 0,
      breadcrumbCount: record.breadcrumb_count || 0,
      handle: record.handle || null,
      isVerified: !!record.handle,
    };
  } catch (e) {
    return {
      displayName: null,
      avatarUrl: null,
      trustScore: 0,
      breadcrumbCount: 0,
      handle: null,
      isVerified: false,
    };
  }
}

/**
 * Transform database post to web-friendly format
 */
async function transformPost(dbPost: any, includeAuthorDetails = true): Promise<WebPost> {
  let authorProfile = {
    displayName: null as string | null,
    avatarUrl: null as string | null,
    trustScore: dbPost.trust_score || 0,
    breadcrumbCount: dbPost.breadcrumb_count || 0,
    handle: dbPost.author_handle || null,
    isVerified: false,
  };

  if (includeAuthorDetails && dbPost.author_public_key) {
    authorProfile = await getAuthorProfile(dbPost.author_public_key);
  }

  const payload = typeof dbPost.payload_json === 'string'
    ? JSON.parse(dbPost.payload_json)
    : dbPost.payload_json || {};

  return {
    id: dbPost.id,
    author: {
      publicKey: dbPost.author_public_key,
      handle: dbPost.author_handle || authorProfile.handle,
      displayName: authorProfile.displayName,
      avatarUrl: authorProfile.avatarUrl,
      trustScore: authorProfile.trustScore || dbPost.trust_score || 0,
      breadcrumbCount: authorProfile.breadcrumbCount || dbPost.breadcrumb_count || 0,
      isVerified: authorProfile.isVerified,
    },
    facet: dbPost.facet_id,
    content: {
      text: dbPost.content || payload.text || '',
      media: payload.media || [],
      links: payload.links || [],
      tags: payload.tags || [],
      mentions: payload.mentions || [],
      location: payload.location_label,
    },
    engagement: {
      likes: dbPost.like_count || 0,
      replies: dbPost.reply_count || 0,
      reposts: dbPost.repost_count || 0,
      quotes: dbPost.quote_count || 0,
      views: dbPost.view_count || 0,
    },
    meta: {
      signature: dbPost.signature,
      trustScoreAtPost: dbPost.trust_score || 0,
      breadcrumbsAtPost: dbPost.breadcrumb_count || 0,
      ipfsCid: payload.ipfs_cid,
      createdAt: dbPost.created_at,
    },
    thread: (dbPost.reply_to_post_id || dbPost.quote_of_id) ? {
      replyToId: dbPost.reply_to_post_id,
      quoteOfId: dbPost.quote_of_id,
    } : undefined,
    brand: dbPost.brand_id ? {
      id: dbPost.brand_id,
      role: dbPost.brand_role,
    } : undefined,
  };
}

/**
 * Transform multiple posts
 */
async function transformPosts(dbPosts: any[]): Promise<WebPost[]> {
  return Promise.all(dbPosts.map(p => transformPost(p)));
}

// ===========================================
// ROUTES
// ===========================================

/**
 * POST /web/dix/publish
 * Publish a new DIX post
 */
// Direct insert to dix_posts table (NOT RPC!)
router.post('/publish', async (req: Request, res: Response) => {
  try {
    const {
      post_id,
      facet_id,
      author_public_key,
      author_handle,
      content,
      media,
      created_at,
      tags,
      mentions,
      signature,
      reply_to_id
    } = req.body;

    // Direct insert to dix_posts table (NOT RPC!)
    const { data, error } = await supabase.from('dix_posts').insert({
      id: post_id,
      facet_id: facet_id || 'dix',
      author_public_key: author_public_key,
      author_handle: author_handle,
      content: content,
      media: media || [],
      tags: tags || [],
      mentions: mentions || [],
      signature: signature,
      created_at: created_at || new Date().toISOString(),
      reply_to_post_id: reply_to_id || null,
      visibility: 'public',
      is_deleted: false,
    }).select().single();

    if (error) {
      console.error('DIX insert error:', error);
      return res.status(500).json({ success: false, error: error.message });
    }

    // If this is a reply, increment reply_count on parent
    if (reply_to_id) {
      const { data: parent } = await supabase
        .from('dix_posts')
        .select('reply_count')
        .eq('id', reply_to_id)
        .single();

      if (parent) {
        await supabase
          .from('dix_posts')
          .update({ reply_count: (parent.reply_count || 0) + 1 })
          .eq('id', reply_to_id);
      }
    }

    return res.json({
      success: true,
      data: {
        message: 'Post published successfully',
        post_id: data.id,
        success: true,
        network_post_id: data.id
      }
    });
  } catch (error) {
    console.error('POST /web/dix/publish error:', error);
    return res.status(500).json({ success: false, error: 'Internal server error' });
  }
});

/**
 * POST /web/dix/like
 * Like a post
 */
router.post('/like', async (req: Request, res: Response) => {
  try {
    const { post_id, author_public_key, signature } = req.body;

    if (!post_id || !author_public_key) {
      return res.status(400).json({ success: false, error: 'Missing required fields' });
    }

    // Call Supabase RPC
    const { error: rpcError } = await supabase.rpc('like_dix_post', {
      p_post_id: post_id,
      p_author_public_key: author_public_key,
      p_signature: signature
    });

    if (rpcError) {
      console.error('RPC like_dix_post error:', rpcError);
      return res.status(500).json({ success: false, error: rpcError.message });
    }

    return res.json({ success: true });
  } catch (error) {
    console.error('POST /web/dix/like error:', error);
    return res.status(500).json({ success: false, error: 'Internal server error' });
  }
});

/**
 * POST /web/dix/repost
 * Repost a post
 */
router.post('/repost', async (req: Request, res: Response) => {
  try {
    const { post_id, author_public_key, signature } = req.body;

    // Call Supabase RPC
    const { error: rpcError } = await supabase.rpc('repost_dix_post', {
      p_post_id: post_id,
      p_author_public_key: author_public_key,
      p_signature: signature
    });

    if (rpcError) {
      console.error('RPC repost_dix_post error:', rpcError);
      // If RPC missing, fallback? No, assume RPC exists if enforcing signatures.
      return res.status(500).json({ success: false, error: rpcError.message });
    }

    return res.json({ success: true });
  } catch (error) {
    console.error('POST /web/dix/repost error:', error);
    return res.status(500).json({ success: false, error: 'Internal server error' });
  }
});

/**
 * GET /web/dix/timeline
 * Public DIX timeline
 */
router.get('/timeline', async (req: Request, res: Response) => {
  try {
    const limit = Math.min(parseInt(req.query.limit as string) || 20, 50);
    const before = req.query.before as string | undefined;

    let query = supabase
      .from('dix_posts')
      .select('*')
      .eq('facet_id', 'dix')
      .eq('is_deleted', false)
      .order('created_at', { ascending: false })
      .limit(limit);

    if (before) {
      query = query.lt('created_at', before);
    }

    const { data: dbPosts, error } = await query;

    if (error) {
      console.error('Timeline query error:', error);
      return res.status(500).json({ success: false, error: 'Database error' });
    }

    const posts = await transformPosts(dbPosts || []);

    // Get stats (only on first page)
    let stats;
    if (!before) {
      const { count: totalPosts } = await supabase
        .from('dix_posts')
        .select('*', { count: 'exact', head: true })
        .eq('facet_id', 'dix')
        .eq('is_deleted', false);

      const today = new Date();
      today.setHours(0, 0, 0, 0);

      const { count: postsToday } = await supabase
        .from('dix_posts')
        .select('*', { count: 'exact', head: true })
        .eq('facet_id', 'dix')
        .eq('is_deleted', false)
        .gte('created_at', today.toISOString());

      stats = {
        totalPosts: totalPosts || 0,
        postsToday: postsToday || 0,
      };
    }

    return res.json({
      success: true,
      data: {
        posts,
        cursor: posts.length > 0 ? posts[posts.length - 1].meta.createdAt : null,
        hasMore: posts.length === limit,
        stats,
      },
    });
  } catch (error) {
    console.error('GET /web/dix/timeline error:', error);
    return res.status(500).json({ success: false, error: 'Internal server error' });
  }
});

/**
 * GET /web/dix/@:handle
 * User's DIX posts by handle
 */
router.get('/@:handle', async (req: Request, res: Response) => {
  try {
    let handle = req.params.handle.toLowerCase();
    if (handle.startsWith('@')) {
      handle = handle.substring(1);
    }

    const limit = Math.min(parseInt(req.query.limit as string) || 20, 50);
    const before = req.query.before as string | undefined;

    // Get user from aliases
    const { data: alias } = await supabase
      .from('aliases')
      .select('*')
      .eq('handle', handle)
      .single();

    if (!alias) {
      return res.status(404).json({ success: false, error: 'User not found' });
    }

    // Get user profile
    const profile = await getAuthorProfile(alias.pk_root);

    // Get posts
    let query = supabase
      .from('dix_posts')
      .select('*')
      .eq('author_handle', handle)
      .eq('facet_id', 'dix')
      .eq('is_deleted', false)
      .order('created_at', { ascending: false })
      .limit(limit);

    if (before) {
      query = query.lt('created_at', before);
    }

    const { data: dbPosts, error } = await query;

    if (error) {
      console.error('User posts query error:', error);
      return res.status(500).json({ success: false, error: 'Database error' });
    }

    const posts = await transformPosts(dbPosts || []);

    // Get user stats
    const { count: totalPosts } = await supabase
      .from('dix_posts')
      .select('*', { count: 'exact', head: true })
      .eq('author_public_key', alias.pk_root)
      .eq('is_deleted', false);

    return res.json({
      success: true,
      data: {
        user: {
          publicKey: alias.pk_root,
          handle,
          displayName: profile.displayName || handle,
          avatarUrl: profile.avatarUrl,
          trustScore: profile.trustScore,
          breadcrumbCount: profile.breadcrumbCount,
          isVerified: profile.isVerified,
        },
        posts,
        stats: {
          totalPosts: totalPosts || 0,
        },
        cursor: posts.length > 0 ? posts[posts.length - 1].meta.createdAt : null,
        hasMore: posts.length === limit,
      },
    });
  } catch (error) {
    console.error('GET /web/dix/@:handle error:', error);
    return res.status(500).json({ success: false, error: 'Internal server error' });
  }
});

/**
 * GET /web/dix/pk/:publicKey
 * Posts by public key
 */
router.get('/pk/:publicKey', async (req: Request, res: Response) => {
  try {
    const pk = req.params.publicKey.toLowerCase();
    const limit = Math.min(parseInt(req.query.limit as string) || 20, 50);
    const before = req.query.before as string | undefined;

    if (!/^[0-9a-f]{64}$/.test(pk)) {
      return res.status(400).json({ success: false, error: 'Invalid public key format' });
    }

    // Get profile
    const profile = await getAuthorProfile(pk);

    // Get posts
    let query = supabase
      .from('dix_posts')
      .select('*')
      .eq('author_public_key', pk)
      .eq('facet_id', 'dix')
      .eq('is_deleted', false)
      .order('created_at', { ascending: false })
      .limit(limit);

    if (before) {
      query = query.lt('created_at', before);
    }

    const { data: dbPosts, error } = await query;

    if (error) {
      console.error('PK posts query error:', error);
      return res.status(500).json({ success: false, error: 'Database error' });
    }

    const posts = await transformPosts(dbPosts || []);

    return res.json({
      success: true,
      data: {
        user: {
          publicKey: pk,
          handle: profile.handle,
          displayName: profile.displayName,
          avatarUrl: profile.avatarUrl,
          trustScore: profile.trustScore,
          breadcrumbCount: profile.breadcrumbCount,
          isVerified: profile.isVerified,
        },
        posts,
        cursor: posts.length > 0 ? posts[posts.length - 1].meta.createdAt : null,
        hasMore: posts.length === limit,
      },
    });
  } catch (error) {
    console.error('GET /web/dix/pk/:pk error:', error);
    return res.status(500).json({ success: false, error: 'Internal server error' });
  }
});

/**
 * GET /web/dix/post/:id
 * Single post with replies
 */
router.get('/post/:id', async (req: Request, res: Response) => {
  try {
    const postId = req.params.id;

    // Validate UUID
    if (!/^[0-9a-f-]{36}$/i.test(postId)) {
      return res.status(400).json({ success: false, error: 'Invalid post ID format' });
    }

    // Get post
    const { data: dbPost, error } = await supabase
      .from('dix_posts')
      .select('*')
      .eq('id', postId)
      .single();

    if (error || !dbPost) {
      return res.status(404).json({ success: false, error: 'Post not found' });
    }

    if (dbPost.is_deleted === true) {
      return res.status(410).json({ success: false, error: 'Post has been retracted' });
    }

    const post = await transformPost(dbPost);

    // Get replies
    const { data: replyData } = await supabase
      .from('dix_posts')
      .select('*')
      .eq('reply_to_post_id', postId)
      .eq('is_deleted', false)
      .order('created_at', { ascending: true })
      .limit(50);

    const replies = await transformPosts(replyData || []);

    // Increment view count (fire and forget)
    supabase
      .from('dix_posts')
      .update({ view_count: (dbPost.view_count || 0) + 1 })
      .eq('id', postId)
      .then(() => { });

    return res.json({
      success: true,
      data: {
        post,
        replies,
        replyCount: replies.length,
      },
    });
  } catch (error) {
    console.error('GET /web/dix/post/:id error:', error);
    return res.status(500).json({ success: false, error: 'Internal server error' });
  }
});

/**
 * GET /web/dix/tag/:tag
 * Posts by hashtag
 */
router.get('/tag/:tag', async (req: Request, res: Response) => {
  try {
    let tag = req.params.tag.toLowerCase();
    if (tag.startsWith('#')) {
      tag = tag.substring(1);
    }

    const limit = Math.min(parseInt(req.query.limit as string) || 20, 50);

    // Search posts with tag in payload_json
    const { data: dbPosts, error } = await supabase
      .from('dix_posts')
      .select('*')
      .eq('facet_id', 'dix')
      .eq('is_deleted', false)
      .contains('payload_json', { tags: [tag] })
      .order('created_at', { ascending: false })
      .limit(limit);

    if (error) {
      console.error('Tag search error:', error);
      return res.status(500).json({ success: false, error: 'Database error' });
    }

    const posts = await transformPosts(dbPosts || []);

    return res.json({
      success: true,
      data: {
        tag: `#${tag}`,
        posts,
        count: posts.length,
      },
    });
  } catch (error) {
    console.error('GET /web/dix/tag/:tag error:', error);
    return res.status(500).json({ success: false, error: 'Internal server error' });
  }
});

/**
 * GET /web/dix/search
 * Search posts
 */
router.get('/search', async (req: Request, res: Response) => {
  try {
    const query = (req.query.q as string || '').trim();

    if (!query || query.length < 2) {
      return res.status(400).json({ success: false, error: 'Query must be at least 2 characters' });
    }

    const limit = Math.min(parseInt(req.query.limit as string) || 20, 50);

    // Full-text search using ILIKE on text content
    const { data: dbPosts, error } = await supabase
      .from('dix_posts')
      .select('*')
      .eq('facet_id', 'dix')
      .eq('is_deleted', false)
      .ilike('payload_json->>text', `%${query}%`)
      .order('created_at', { ascending: false })
      .limit(limit);

    if (error) {
      console.error('Search error:', error);
      return res.status(500).json({ success: false, error: 'Database error' });
    }

    const posts = await transformPosts(dbPosts || []);

    return res.json({
      success: true,
      data: {
        query,
        posts,
        count: posts.length,
      },
    });
  } catch (error) {
    console.error('GET /web/dix/search error:', error);
    return res.status(500).json({ success: false, error: 'Internal server error' });
  }
});

/**
 * GET /web/dix/stats
 * DIX statistics
 */
router.get('/stats', async (req: Request, res: Response) => {
  try {
    // Total posts
    const { count: totalPosts } = await supabase
      .from('dix_posts')
      .select('*', { count: 'exact', head: true })
      .eq('facet_id', 'dix')
      .eq('is_deleted', false);

    // Posts today
    const today = new Date();
    today.setHours(0, 0, 0, 0);

    const { count: postsToday } = await supabase
      .from('dix_posts')
      .select('*', { count: 'exact', head: true })
      .eq('facet_id', 'dix')
      .eq('is_deleted', false)
      .gte('created_at', today.toISOString());

    // Active users today (distinct authors)
    const { data: activeUsers } = await supabase
      .from('dix_posts')
      .select('author_public_key')
      .eq('facet_id', 'dix')
      .eq('is_deleted', false)
      .gte('created_at', today.toISOString());

    const uniqueAuthors = new Set(activeUsers?.map((p: { author_public_key: string }) => p.author_public_key) || []);

    return res.json({
      success: true,
      data: {
        totalPosts: totalPosts || 0,
        postsToday: postsToday || 0,
        activeUsersToday: uniqueAuthors.size,
      },
    });
  } catch (error) {
    console.error('GET /web/dix/stats error:', error);
    return res.status(500).json({ success: false, error: 'Internal server error' });
  }
});

export default router;
// Force backend rebuild
