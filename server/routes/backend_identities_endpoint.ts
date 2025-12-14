// ===================================================================
// GET /identities/:publicKey - Fetch Identity Information
// ===================================================================
// 
// Purpose: Return public identity info including encryption key
// Used by: Flutter app to get encryption keys for messaging
// 
// Add this to your Railway Express backend
// ===================================================================

import { Request, Response } from 'express';
import { createClient } from '@supabase/supabase-js';

// Initialize Supabase client (use your credentials)
const supabase = createClient(
  process.env.SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_KEY! // Use service key for backend
);

/**
 * GET /identities/:publicKey
 * 
 * Fetch public identity information by public key
 * Returns encryption key needed for E2E encrypted messaging
 */
export async function getIdentity(req: Request, res: Response) {
  try {
    const { publicKey } = req.params;
    
    // Validate input
    if (!publicKey || publicKey.length !== 64) {
      return res.status(400).json({
        success: false,
        error: 'Invalid public key format',
        path: `/identities/${publicKey}`,
      });
    }
    
    // Query database for identity
    const { data, error } = await supabase
      .from('records')
      .select('*')
      .eq('pk_root', publicKey)
      .single();
    
    if (error || !data) {
      return res.status(404).json({
        success: false,
        error: 'Not found',
        path: `/identities/${publicKey}`,
      });
    }
    
    // Parse record_json if it's a string
    let recordData = data.record_json;
    if (typeof recordData === 'string') {
      try {
        recordData = JSON.parse(recordData);
      } catch (e) {
        recordData = {};
      }
    }
    
    // Return public identity info
    return res.status(200).json({
      success: true,
      data: {
        public_key: data.pk_root,
        encryption_key: data.encryption_key,  // ✅ CRITICAL for messaging!
        handle: data.handle,
        display_name: recordData?.display_name || null,
        bio: recordData?.bio || null,
        avatar_url: recordData?.avatar_url || null,
        trust_score: data.trust_score,
        breadcrumb_count: data.breadcrumb_count,
        created_at: data.created_at,
      },
    });
    
  } catch (error) {
    console.error('Error fetching identity:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
      path: `/identities/${req.params.publicKey}`,
    });
  }
}

// ===================================================================
// ROUTE REGISTRATION
// ===================================================================
// 
// Add to your Express app:
// 
// import { getIdentity } from './routes/identities';
// app.get('/identities/:publicKey', getIdentity);
// 
// ===================================================================
