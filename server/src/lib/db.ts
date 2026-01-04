// ===========================================
// GNS NODE - DATABASE CLIENT
// Supabase PostgreSQL wrapper
// ===========================================

import { createClient, SupabaseClient } from '@supabase/supabase-js';
import {
  DbRecord, DbAlias, DbEpoch, DbMessage,
  GnsRecord, PoTProof, EpochHeader, SyncState,
  DbPaymentIntent, DbPaymentAck, DbGeoAuthSession,
  DbBreadcrumb
} from '../types';

// ===========================================
// Supabase Client Singleton
// ===========================================

let supabase: SupabaseClient | null = null;

export function getSupabase(): SupabaseClient {
  if (!supabase) {
    const url = process.env.SUPABASE_URL;
    const key = process.env.SUPABASE_SERVICE_KEY;

    if (!url || !key) {
      throw new Error('SUPABASE_URL and SUPABASE_SERVICE_KEY must be set');
    }

    supabase = createClient(url, key, {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
      },
    });
  }

  return supabase;
}

// ===========================================
// RECORDS
// ===========================================

export async function getRecord(pkRoot: string): Promise<DbRecord | null> {
  const { data, error } = await getSupabase()
    .from('records')
    .select('*')
    .eq('pk_root', pkRoot.toLowerCase())
    .single();

  if (error && error.code !== 'PGRST116') { // PGRST116 = not found
    console.error('Error fetching record:', error);
    throw error;
  }

  return data as DbRecord | null;
}

/**
 * Get identity info (public_key, encryption_key, handle) for messaging
 * This is used by the echo bot and messaging services to encrypt messages
 */
export async function getIdentity(pkRoot: string): Promise<{
  public_key: string;
  encryption_key: string;
  handle?: string;
} | null> {
  const { data, error } = await getSupabase()
    .from('records')
    .select('pk_root, encryption_key, handle')
    .eq('pk_root', pkRoot.toLowerCase())
    .single();

  if (error && error.code !== 'PGRST116') {
    console.error('Error fetching identity:', error);
    throw error;
  }

  if (!data) return null;

  return {
    public_key: data.pk_root,
    encryption_key: data.encryption_key,
    handle: data.handle || undefined,
  };
}

export async function upsertRecord(
  pkRoot: string,
  recordJson: GnsRecord,
  signature: string
): Promise<DbRecord> {
  const { data, error } = await getSupabase()
    .from('records')
    .upsert({
      pk_root: pkRoot.toLowerCase(),
      record_json: recordJson,
      signature: signature,
      version: recordJson.version || 1,
      handle: recordJson.handle?.toLowerCase() || null,
      encryption_key: recordJson.encryption_key || null,  // ✅ CRITICAL FIX!
      trust_score: recordJson.trust_score,
      breadcrumb_count: recordJson.breadcrumb_count,
    }, {
      onConflict: 'pk_root',
    })
    .select()
    .single();

  console.log(`[db.upsertRecord] Upsert result for ${pkRoot.substring(0, 16)}...`);
  if (error) console.error(`[db.upsertRecord] Error:`, error);
  if (data) console.log(`[db.upsertRecord] Success. Encryption key: ${data.encryption_key}`);

  if (error) {
    console.error('Error upserting record:', error);
    throw error;
  }

  return data as DbRecord;
}

export async function getRecordsSince(since: string, limit = 100): Promise<DbRecord[]> {
  const { data, error } = await getSupabase()
    .from('records')
    .select('*')
    .gt('updated_at', since)
    .order('updated_at', { ascending: true })
    .limit(limit);

  if (error) {
    console.error('Error fetching records since:', error);
    throw error;
  }

  return data as DbRecord[];
}

export async function deleteRecord(pkRoot: string): Promise<boolean> {
  const { error } = await getSupabase()
    .from('records')
    .delete()
    .eq('pk_root', pkRoot.toLowerCase());

  if (error) {
    console.error('Error deleting record:', error);
    throw error;
  }

  return true;
}

// ===========================================
// ALIASES
// ===========================================

export async function getAlias(handle: string): Promise<DbAlias | null> {
  const { data, error } = await getSupabase()
    .from('aliases')
    .select('*')
    .eq('handle', handle.toLowerCase())
    .single();

  if (error && error.code !== 'PGRST116') {
    console.error('Error fetching alias:', error);
    throw error;
  }

  return data as DbAlias | null;
}

export async function getAliasByPk(pkRoot: string): Promise<DbAlias | null> {
  const { data, error } = await getSupabase()
    .from('aliases')
    .select('*')
    .eq('pk_root', pkRoot.toLowerCase())
    .single();

  if (error && error.code !== 'PGRST116') {
    console.error('Error fetching alias by pk:', error);
    throw error;
  }

  return data as DbAlias | null;
}

export async function createAlias(
  handle: string,
  pkRoot: string,
  potProof: PoTProof,
  signature: string
): Promise<DbAlias> {
  const { data, error } = await getSupabase()
    .from('aliases')
    .insert({
      handle: handle.toLowerCase(),
      pk_root: pkRoot.toLowerCase(),
      pot_proof: potProof,
      signature: signature,
      verified: true,
    })
    .select()
    .single();

  if (error) {
    console.error('Error creating alias:', error);
    throw error;
  }

  // Update the record's handle field
  await getSupabase()
    .from('records')
    .update({ handle: handle.toLowerCase() })
    .eq('pk_root', pkRoot.toLowerCase());

  return data as DbAlias;
}

export async function isHandleAvailable(handle: string): Promise<boolean> {
  // Check aliases table
  const alias = await getAlias(handle);
  if (alias) return false;

  // Check reserved handles table
  const { data, error } = await getSupabase()
    .from('reserved_handles')
    .select('handle')
    .eq('handle', handle.toLowerCase())
    .single();

  if (error && error.code !== 'PGRST116') {
    console.error('Error checking reserved handles:', error);
    throw error;
  }

  return !data;
}

export async function getAliasesSince(since: string, limit = 100): Promise<DbAlias[]> {
  const { data, error } = await getSupabase()
    .from('aliases')
    .select('*')
    .gt('created_at', since)
    .order('created_at', { ascending: true })
    .limit(limit);

  if (error) {
    console.error('Error fetching aliases since:', error);
    throw error;
  }

  return data as DbAlias[];
}

// ===========================================
// ALIAS LOOKUP (for echo_bot & messaging)
// ===========================================

/**
 * Get alias by handle (alias for getAlias)
 */
export async function getAliasByHandle(handle: string): Promise<DbAlias | null> {
  return getAlias(handle);
}

/**
 * Create a system alias (for reserved handles like @echo, @support)
 * These don't require PoT proof
 */
export async function createSystemAlias(
  handle: string,
  pkRoot: string
): Promise<DbAlias> {
  const { data, error } = await getSupabase()
    .from('aliases')
    .upsert({
      handle: handle.toLowerCase(),
      pk_root: pkRoot.toLowerCase(),
      pot_proof: {
        // System handles have special proof
        breadcrumb_count: 999999,
        trust_score: 100,
        first_breadcrumb_at: '2025-01-01T00:00:00Z',
        system_handle: true,
      },
      signature: 'system',
      verified: true,
      is_system: true, // Add this column to your schema
    }, {
      onConflict: 'handle',
    })
    .select()
    .single();

  if (error) {
    console.error('Error creating system alias:', error);
    throw error;
  }

  return data as DbAlias;
}

/**
 * Get all system handles
 */
export async function getSystemAliases(): Promise<DbAlias[]> {
  const { data, error } = await getSupabase()
    .from('aliases')
    .select('*')
    .eq('is_system', true);

  if (error) {
    console.error('Error fetching system aliases:', error);
    throw error;
  }

  return data as DbAlias[] || [];
}

// ===========================================
// HANDLE RESOLUTION (for messaging)
// ===========================================

/**
 * Resolve handle to public key
 * Returns null if handle not found
 */
export async function resolveHandleToPublicKey(handle: string): Promise<string | null> {
  // Normalize handle (remove @ if present)
  const normalizedHandle = handle.toLowerCase().replace(/^@/, '');

  // Look up in aliases
  const alias = await getAlias(normalizedHandle);

  if (alias) {
    return alias.pk_root;
  }

  return null;
}

/**
 * Resolve public key to handle
 * Returns null if no handle claimed
 */
export async function resolvePublicKeyToHandle(pkRoot: string): Promise<string | null> {
  const alias = await getAliasByPk(pkRoot.toLowerCase());

  if (alias) {
    return `@${alias.handle}`;
  }

  return null;
}

// ===========================================
// HANDLE RESERVATIONS
// ===========================================

export async function reserveHandle(
  handle: string,
  pkRoot: string
): Promise<{ reserved: boolean; expires_at?: string; error?: string }> {
  // Check if available
  const available = await isHandleAvailable(handle);
  if (!available) {
    return { reserved: false, error: 'Handle not available' };
  }

  // Check if pk already has a reservation
  const { data: existing } = await getSupabase()
    .from('reserved_handles')
    .select('*')
    .eq('pk_root', pkRoot.toLowerCase())
    .single();

  if (existing) {
    // Delete old reservation
    await getSupabase()
      .from('reserved_handles')
      .delete()
      .eq('pk_root', pkRoot.toLowerCase());
  }

  // Create reservation
  const expiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString();

  const { error } = await getSupabase()
    .from('reserved_handles')
    .insert({
      handle: handle.toLowerCase(),
      pk_root: pkRoot.toLowerCase(),
      expires_at: expiresAt,
    });

  if (error) {
    console.error('Error reserving handle:', error);
    return { reserved: false, error: error.message };
  }

  return { reserved: true, expires_at: expiresAt };
}

export async function getReservation(handle: string): Promise<{
  handle: string;
  pk_root: string;
  expires_at: string;
} | null> {
  const now = new Date().toISOString();
  const { data, error } = await getSupabase()
    .from('reserved_handles')
    .select('*')
    .eq('handle', handle.toLowerCase())
    .or(`expires_at.is.null,expires_at.gt.${now}`)
    .single();

  if (error && error.code !== 'PGRST116') {
    console.error('Error fetching reservation:', error);
    throw error;
  }

  return data;
}

// ===========================================
// EPOCHS
// ===========================================

export async function getEpochs(pkRoot: string): Promise<DbEpoch[]> {
  const { data, error } = await getSupabase()
    .from('epochs')
    .select('*')
    .eq('pk_root', pkRoot.toLowerCase())
    .order('epoch_index', { ascending: true });

  if (error) {
    console.error('Error fetching epochs:', error);
    throw error;
  }

  return data as DbEpoch[];
}

export async function getEpoch(pkRoot: string, epochIndex: number): Promise<DbEpoch | null> {
  const { data, error } = await getSupabase()
    .from('epochs')
    .select('*')
    .eq('pk_root', pkRoot.toLowerCase())
    .eq('epoch_index', epochIndex)
    .single();

  if (error && error.code !== 'PGRST116') {
    console.error('Error fetching epoch:', error);
    throw error;
  }

  return data as DbEpoch | null;
}

export async function createEpoch(
  pkRoot: string,
  epoch: EpochHeader,
  signature: string
): Promise<DbEpoch> {
  const { data, error } = await getSupabase()
    .from('epochs')
    .insert({
      pk_root: pkRoot.toLowerCase(),
      epoch_index: epoch.epoch_index,
      merkle_root: epoch.merkle_root,
      start_time: epoch.start_time,
      end_time: epoch.end_time,
      block_count: epoch.block_count,
      prev_epoch_hash: epoch.prev_epoch_hash || null,
      signature: signature,
      epoch_hash: epoch.epoch_hash,
    })
    .select()
    .single();

  if (error) {
    console.error('Error creating epoch:', error);
    throw error;
  }

  return data as DbEpoch;
}

export async function getEpochsSince(since: string, limit = 100): Promise<DbEpoch[]> {
  const { data, error } = await getSupabase()
    .from('epochs')
    .select('*')
    .gt('published_at', since)
    .order('published_at', { ascending: true })
    .limit(limit);

  if (error) {
    console.error('Error fetching epochs since:', error);
    throw error;
  }

  return data as DbEpoch[];
}

// ===========================================
// MESSAGES
// ===========================================

export async function createMessage(
  fromPk: string,
  toPk: string,
  payload: string,
  signature: string,
  relayId?: string
): Promise<DbMessage> {
  const { data, error } = await getSupabase()
    .from('messages')
    .insert({
      from_pk: fromPk.toLowerCase(),
      to_pk: toPk.toLowerCase(),
      payload,
      signature: signature,
      relay_id: relayId || process.env.NODE_ID,
    })
    .select()
    .single();

  if (error) {
    console.error('Error creating message:', error);
    throw error;
  }

  return data as DbMessage;
}

export async function getInbox(pkRoot: string, limit = 50): Promise<DbMessage[]> {
  const { data, error } = await getSupabase()
    .from('messages')
    .select('*')
    .eq('to_pk', pkRoot.toLowerCase())
    .is('delivered_at', null)
    .order('created_at', { ascending: true })
    .limit(limit);

  if (error) {
    console.error('Error fetching inbox:', error);
    throw error;
  }

  return data as DbMessage[];
}

/**
 * Get conversation between two users
 */
export async function markMessageDelivered(messageId: string): Promise<void> {
  const { error } = await getSupabase()
    .from('messages')
    .update({
      delivered_at: new Date().toISOString(),
      status: 'delivered'  // ✅ FIX: Also update status so getPendingEnvelopes filters it out
    })
    .eq('id', messageId);

  if (error) {
    console.error('Error marking message delivered:', error);
    throw error;
  }
}

export async function deleteMessage(messageId: string): Promise<void> {
  const { error } = await getSupabase()
    .from('messages')
    .delete()
    .eq('id', messageId);

  if (error) {
    console.error('Error deleting message:', error);
    throw error;
  }
}

// ===========================================
// SYNC STATE
// ===========================================

export async function getSyncState(peerId: string): Promise<SyncState | null> {
  const { data, error } = await getSupabase()
    .from('sync_state')
    .select('*')
    .eq('peer_id', peerId)
    .single();

  if (error && error.code !== 'PGRST116') {
    console.error('Error fetching sync state:', error);
    throw error;
  }

  return data as SyncState | null;
}

export async function upsertSyncState(state: Partial<SyncState> & { peer_id: string; peer_url: string }): Promise<void> {
  const { error } = await getSupabase()
    .from('sync_state')
    .upsert(state, { onConflict: 'peer_id' });

  if (error) {
    console.error('Error upserting sync state:', error);
    throw error;
  }
}

export async function getAllPeers(): Promise<SyncState[]> {
  const { data, error } = await getSupabase()
    .from('sync_state')
    .select('*')
    .eq('status', 'active');

  if (error) {
    console.error('Error fetching peers:', error);
    throw error;
  }

  return data as SyncState[];
}

// ===========================================
// HEALTH CHECK
// ===========================================

export async function healthCheck(): Promise<boolean> {
  try {
    const { error } = await getSupabase()
      .from('records')
      .select('pk_root')
      .limit(1);

    return !error;
  } catch {
    return false;
  }
}

// ===========================================
// ENVELOPE-BASED MESSAGES
// ===========================================

/**
 * Create message with full envelope
 */
export async function createEnvelopeMessage(
  fromPk: string,
  toPk: string,
  envelope: any,
  threadId?: string | null
): Promise<DbMessage> {
  // CRITICAL: Ensure encryptedPayload is ALWAYS a string (base64 ciphertext)
  // Never store it as an object, as that breaks signature verification
  let payloadString = envelope.encryptedPayload || '';
  if (typeof payloadString === 'object') {
    // ✅ Handle nested object (Tauri format)
    if (payloadString.ciphertext) {
      payloadString = payloadString.ciphertext;
    } else {
      // Fallback for other objects
      payloadString = JSON.stringify(payloadString);
    }
  }

  const { data, error } = await getSupabase()
    .from('messages')
    .insert({
      from_pk: fromPk.toLowerCase(),
      to_pk: toPk.toLowerCase(),
      payload: payloadString,  // Always a string (base64 ciphertext)
      signature: envelope.signature || '',  // Don't lowercase - Base64 is case-sensitive!
      envelope: envelope,  // Full envelope in JSONB column
      thread_id: threadId || envelope.threadId || null,
      status: 'pending',
      relay_id: process.env.NODE_ID,
      expires_at: null,
      // ✅ Also populate individual columns for easier querying
      encrypted_payload: envelope.encryptedPayload || payloadString,
      ephemeral_public_key: envelope.ephemeralPublicKey || null,
      nonce: envelope.nonce || null,
    })
    .select()
    .single();

  if (error) {
    console.error('Error creating envelope message:', error);
    throw error;
  }

  return data as DbMessage;
}

/**
 * Get pending envelopes for a recipient
 */
export async function getPendingEnvelopes(
  recipientPk: string,
  since?: string,
  limit: number = 100
): Promise<DbMessage[]> {
  let query = getSupabase()
    .from('messages')
    .select('*')
    .eq('to_pk', recipientPk.toLowerCase())
    .eq('status', 'pending')
    .order('created_at', { ascending: true })
    .limit(limit);

  if (since) {
    const sinceDate = new Date(parseInt(since)).toISOString();
    query = query.gt('created_at', sinceDate);
  }

  const { data, error } = await query;

  if (error) {
    console.error('Error fetching pending envelopes:', error);
    throw error;
  }

  return data as DbMessage[];
}

export async function acknowledgeMessages(
  recipientPk: string,
  messageIds: string[]
): Promise<number> {
  if (messageIds.length === 0) return 0;

  try {
    const { data, error } = await getSupabase()
      .rpc('acknowledge_messages_text', {
        p_recipient_pk: recipientPk.toLowerCase(),
        p_message_ids: messageIds
      });

    if (error) {
      console.error('ACK error:', error);
      return 0;
    }

    console.log(`✅ Acknowledged ${data} messages`);
    return data || 0;
  } catch (err) {
    console.error('ACK exception:', err);
    return 0;
  }
}

/**
 * Mark messages as read (batch)
 * ✅ FIXED: Use .in() instead of massive OR chain
 */
export async function markMessagesRead(
  recipientPk: string,
  messageIds: string[]
): Promise<number> {
  // ✅ FIXED: Use .in() instead of massive OR chain

  const { data, error } = await getSupabase()
    .from('messages')
    .update({ status: 'read' })
    .eq('to_pk', recipientPk.toLowerCase())
    .in('id', messageIds)  // ✅ Use .in() - much faster and cleaner
    .select('id');

  if (error) {
    console.error('Error marking messages read:', error);
    throw error;
  }

  return data?.length || 0;
}

/**
 * Get messages in a thread
 */
export async function getThreadMessages(
  threadId: string,
  userPk: string,
  limit: number = 50,
  before?: string
): Promise<DbMessage[]> {
  let query = getSupabase()
    .from('messages')
    .select('*')
    .eq('thread_id', threadId)
    .or(`from_pk.eq.${userPk.toLowerCase()},to_pk.eq.${userPk.toLowerCase()}`)
    .order('created_at', { ascending: false })
    .limit(limit);

  if (before) {
    const beforeDate = new Date(parseInt(before)).toISOString();
    query = query.lt('created_at', beforeDate);
  }

  const { data, error } = await query;

  if (error) {
    console.error('Error fetching thread messages:', error);
    throw error;
  }

  // Return in chronological order
  return (data as DbMessage[]).reverse();
}

// ===========================================
// BREADCRUMBS (Cloud Sync)
// ===========================================

export async function createBreadcrumb(
  pkRoot: string,
  payload: string,
  signature: string
): Promise<DbBreadcrumb> {
  const { data, error } = await getSupabase()
    .from('breadcrumbs')
    .insert({
      pk_root: pkRoot.toLowerCase(),
      payload,
      signature,
    })
    .select()
    .single();

  if (error) {
    console.error('Error creating breadcrumb:', error);
    throw error;
  }

  return data as DbBreadcrumb;
}

export async function getBreadcrumbs(pkRoot: string): Promise<DbBreadcrumb[]> {
  const { data, error } = await getSupabase()
    .from('breadcrumbs')
    .select('*')
    .eq('pk_root', pkRoot.toLowerCase())
    .order('created_at', { ascending: true });

  if (error) {
    console.error('Error fetching breadcrumbs:', error);
    throw error;
  }

  return data as DbBreadcrumb[];
}

// ===========================================
// DUAL ENCRYPTION SUPPORT
// ===========================================

/**
 * Create message with DUAL encryption
 * Stores both recipient copy and sender copy
 */
export async function createDualEncryptedMessage(messageData: {
  from_pk: string;
  to_pk: string;
  envelope: any;
  thread_id?: string | null;
  encrypted_payload?: string;
  ephemeral_public_key?: string;
  nonce?: string;
  sender_encrypted_payload?: string | null;
  sender_ephemeral_public_key?: string | null;
  sender_nonce?: string | null;
}): Promise<DbMessage> {
  const { data, error } = await getSupabase()
    .from('messages')
    .insert({
      from_pk: messageData.from_pk.toLowerCase(),
      to_pk: messageData.to_pk.toLowerCase(),

      // Recipient encryption (existing fields)
      payload: messageData.encrypted_payload || messageData.envelope?.encryptedPayload || '',
      envelope: messageData.envelope,
      signature: messageData.envelope?.signature || '',

      // Sender encryption (NEW - dual encryption)
      sender_encrypted_payload: messageData.sender_encrypted_payload || null,
      sender_ephemeral_public_key: messageData.sender_ephemeral_public_key || null,
      sender_nonce: messageData.sender_nonce || null,

      thread_id: messageData.thread_id || messageData.envelope?.threadId || null,
      status: 'pending',
      relay_id: process.env.NODE_ID,
    })
    .select()
    .single();

  if (error) {
    console.error('Error creating dual encrypted message:', error);
    throw error;
  }

  return data as DbMessage;
}

/**
 * Get conversation between two users
 * Returns all messages (both directions) with dual encryption fields
 */
export async function getConversation(
  userPk: string,
  otherPk: string,
  limit: number = 50,
  before?: string
): Promise<any[]> {
  const userPkLower = userPk.toLowerCase();
  const otherPkLower = otherPk.toLowerCase();

  let query = getSupabase()
    .from('messages')
    .select('*')
    .or(
      `and(from_pk.eq.${userPkLower},to_pk.eq.${otherPkLower}),` +
      `and(from_pk.eq.${otherPkLower},to_pk.eq.${userPkLower})`
    )
    .order('created_at', { ascending: false })
    .limit(limit);

  if (before) {
    const beforeDate = new Date(parseInt(before)).toISOString();
    query = query.lt('created_at', beforeDate);
  }

  const { data, error } = await query;

  if (error) {
    console.error('Error fetching conversation:', error);
    throw error;
  }

  // Return in chronological order (oldest first)
  return (data || []).reverse();
}

/**
 * Get all messages for a user (inbox + sent)
 * For unified inbox view with dual encryption support
 */
export async function getAllUserMessages(
  userPk: string,
  limit: number = 50,
  since?: string
): Promise<any[]> {
  const userPkLower = userPk.toLowerCase();

  let query = getSupabase()
    .from('messages')
    .select('*')
    .or(`from_pk.eq.${userPkLower},to_pk.eq.${userPkLower}`)
    .neq('status', 'delivered')  // ✅ FIX: Exclude delivered messages to prevent polling loop
    .order('created_at', { ascending: false })
    .limit(limit);

  if (since) {
    const sinceDate = new Date(parseInt(since)).toISOString();
    query = query.gt('created_at', sinceDate);
  }

  const { data, error } = await query;

  if (error) {
    console.error('Error fetching all user messages:', error);
    throw error;
  }

  return data || [];
}

/**
 * Get browser session by token
 * For session-based authentication
 */
export async function getBrowserSession(sessionToken: string): Promise<{
  session_token: string;
  public_key: string;
  status: string;
  created_at: string;
  expires_at: string;
} | null> {
  const { data, error } = await getSupabase()
    .from('browser_sessions')
    .select('*')
    .eq('session_token', sessionToken)
    .single();

  if (error && error.code !== 'PGRST116') {
    console.error('Error fetching browser session:', error);
    throw error;
  }

  return data;
}

// ===========================================
// TYPING STATUS
// ===========================================

/**
 * Update typing status
 */
export async function updateTypingStatus(
  threadId: string,
  publicKey: string,
  isTyping: boolean
): Promise<void> {
  const { error } = await getSupabase()
    .from('typing_status')
    .upsert({
      thread_id: threadId,
      public_key: publicKey.toLowerCase(),
      is_typing: isTyping,
      updated_at: new Date().toISOString(),
    }, {
      onConflict: 'thread_id,public_key',
    });

  if (error) {
    console.error('Error updating typing status:', error);
    throw error;
  }
}

/**
 * Get typing status for a thread
 */
export async function getTypingStatus(threadId: string): Promise<Array<{
  public_key: string;
  is_typing: boolean;
  updated_at: string;
}>> {
  const { data, error } = await getSupabase()
    .from('typing_status')
    .select('*')
    .eq('thread_id', threadId)
    .eq('is_typing', true)
    .gt('updated_at', new Date(Date.now() - 10000).toISOString()); // Last 10 seconds

  if (error) {
    console.error('Error fetching typing status:', error);
    throw error;
  }

  return data || [];
}

// ===========================================
// PRESENCE
// ===========================================

/**
 * Update user presence
 */
export async function updatePresence(
  publicKey: string,
  status: 'online' | 'away' | 'offline',
  deviceInfo?: any
): Promise<void> {
  const { error } = await getSupabase()
    .from('presence')
    .upsert({
      public_key: publicKey.toLowerCase(),
      status,
      last_seen: new Date().toISOString(),
      device_info: deviceInfo || null,
    }, {
      onConflict: 'public_key',
    });

  if (error) {
    console.error('Error updating presence:', error);
    throw error;
  }
}

/**
 * Get user presence
 */
export async function getPresence(publicKey: string): Promise<{
  publicKey: string;
  status: string;
  lastSeen: string | null;
} | null> {
  const { data, error } = await getSupabase()
    .from('presence')
    .select('*')
    .eq('public_key', publicKey.toLowerCase())
    .single();

  if (error && error.code !== 'PGRST116') {
    console.error('Error fetching presence:', error);
    throw error;
  }

  if (!data) return null;

  return {
    publicKey: data.public_key,
    status: data.status,
    lastSeen: data.last_seen,
  };
}

/**
 * Get multiple users' presence
 */
export async function getMultiplePresence(publicKeys: string[]): Promise<Array<{
  publicKey: string;
  status: string;
  lastSeen: string | null;
}>> {
  const normalizedKeys = publicKeys.map(k => k.toLowerCase());

  const { data, error } = await getSupabase()
    .from('presence')
    .select('*')
    .in('public_key', normalizedKeys);

  if (error) {
    console.error('Error fetching multiple presence:', error);
    throw error;
  }

  return (data || []).map(d => ({
    publicKey: d.public_key,
    status: d.status,
    lastSeen: d.last_seen,
  }));
}

// ===========================================
// MIGRATION FUNCTIONS
// ===========================================

/**
 * Get all records (for migration)
 * Returns all records in the database
 */
export async function getAllRecords(): Promise<DbRecord[]> {
  const { data, error } = await getSupabase()
    .from('records')
    .select('*')
    .order('created_at', { ascending: true });

  if (error) {
    console.error('Error fetching all records:', error);
    throw error;
  }

  return data as DbRecord[];
}

/**
 * Update encryption_key for a record (for migration)
 * Updates the encryption_key field to use proper RFC 7748 derived key
 */
export async function updateEncryptionKey(
  pkRoot: string,
  encryptionKey: string
): Promise<void> {
  const { error } = await getSupabase()
    .from('records')
    .update({
      encryption_key: encryptionKey,
      updated_at: new Date().toISOString(),
    })
    .eq('pk_root', pkRoot.toLowerCase());

  if (error) {
    console.error('Error updating encryption key:', error);
    throw error;
  }
}

/**
 * Backup all encryption keys before migration
 * Creates a backup table with old encryption keys
 */
export async function backupEncryptionKeys(): Promise<void> {
  const { error } = await getSupabase().rpc('backup_encryption_keys');

  if (error) {
    console.error('Error backing up encryption keys:', error);
    throw error;
  }
}

// SQL to create backup table (run in Supabase SQL editor before migration):
/*
-- Create backup table
CREATE TABLE IF NOT EXISTS encryption_keys_backup (
  pk_root TEXT PRIMARY KEY,
  old_encryption_key TEXT NOT NULL,
  backed_up_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create backup function
CREATE OR REPLACE FUNCTION backup_encryption_keys()
RETURNS void AS $$
BEGIN
  INSERT INTO encryption_keys_backup (pk_root, old_encryption_key)
  SELECT pk_root, encryption_key
  FROM records
  ON CONFLICT (pk_root) DO UPDATE
  SET old_encryption_key = EXCLUDED.old_encryption_key,
      backed_up_at = NOW();
END;
$$ LANGUAGE plpgsql;
*/

// ===========================================
// PAYMENT INTENTS
// ===========================================

/**
 * Create a new payment intent
 */
export async function createPaymentIntent(data: {
  payment_id: string;
  from_pk: string;
  to_pk: string;
  envelope_json: any;
  payload_type: string;
  currency?: string | null;
  route_type?: string | null;
  expires_at?: string | null;
}): Promise<DbPaymentIntent> {
  const { data: result, error } = await getSupabase()
    .from('payment_intents')
    .insert({
      payment_id: data.payment_id,
      from_pk: data.from_pk.toLowerCase(),
      to_pk: data.to_pk.toLowerCase(),
      envelope_json: data.envelope_json,
      payload_type: data.payload_type,
      currency: data.currency || null,
      route_type: data.route_type || null,
      status: 'pending',
      expires_at: data.expires_at || null,
    })
    .select()
    .single();

  if (error) {
    console.error('Error creating payment intent:', error);
    throw error;
  }

  return result as DbPaymentIntent;
}

/**
 * Get payment intent by ID
 */
export async function getPaymentIntent(paymentId: string): Promise<DbPaymentIntent | null> {
  const { data, error } = await getSupabase()
    .from('payment_intents')
    .select('*')
    .eq('payment_id', paymentId)
    .single();

  if (error && error.code !== 'PGRST116') {
    console.error('Error fetching payment intent:', error);
    throw error;
  }

  return data as DbPaymentIntent | null;
}

/**
 * Get pending payments for a recipient
 */
export async function getPendingPayments(
  recipientPk: string,
  since?: string,
  limit: number = 50
): Promise<DbPaymentIntent[]> {
  let query = getSupabase()
    .from('payment_intents')
    .select('*')
    .eq('to_pk', recipientPk.toLowerCase())
    .in('status', ['pending', 'delivered'])
    .order('created_at', { ascending: true })
    .limit(limit);

  if (since) {
    query = query.gt('created_at', since);
  }

  const { data, error } = await query;

  if (error) {
    console.error('Error fetching pending payments:', error);
    throw error;
  }

  return data as DbPaymentIntent[];
}

/**
 * Mark payments as delivered
 */
export async function markPaymentsDelivered(paymentIds: string[]): Promise<void> {
  const { error } = await getSupabase()
    .from('payment_intents')
    .update({
      status: 'delivered',
      delivered_at: new Date().toISOString(),
    })
    .in('payment_id', paymentIds)
    .eq('status', 'pending');

  if (error) {
    console.error('Error marking payments delivered:', error);
    throw error;
  }
}

/**
 * Update payment status
 */
export async function updatePaymentStatus(
  paymentId: string,
  status: 'accepted' | 'rejected' | 'expired'
): Promise<void> {
  const { error } = await getSupabase()
    .from('payment_intents')
    .update({
      status: status,
      acked_at: new Date().toISOString(),
    })
    .eq('payment_id', paymentId);

  if (error) {
    console.error('Error updating payment status:', error);
    throw error;
  }
}

/**
 * Get payment history for a user
 */
export async function getPaymentHistory(
  publicKey: string,
  options: {
    direction?: 'sent' | 'received';
    status?: string;
    limit?: number;
    offset?: number;
  } = {}
): Promise<DbPaymentIntent[]> {
  const { direction, status, limit = 50, offset = 0 } = options;
  const pk = publicKey.toLowerCase();

  let query = getSupabase()
    .from('payment_intents')
    .select('*')
    .order('created_at', { ascending: false })
    .range(offset, offset + limit - 1);

  // Filter by direction
  if (direction === 'sent') {
    query = query.eq('from_pk', pk);
  } else if (direction === 'received') {
    query = query.eq('to_pk', pk);
  } else {
    // Both sent and received
    query = query.or(`from_pk.eq.${pk},to_pk.eq.${pk}`);
  }

  // Filter by status
  if (status) {
    query = query.eq('status', status);
  }

  const { data, error } = await query;

  if (error) {
    console.error('Error fetching payment history:', error);
    throw error;
  }

  return data as DbPaymentIntent[];
}

/**
 * Get outgoing pending payments
 */
export async function getOutgoingPendingPayments(
  senderPk: string
): Promise<DbPaymentIntent[]> {
  const { data, error } = await getSupabase()
    .from('payment_intents')
    .select('*')
    .eq('from_pk', senderPk.toLowerCase())
    .in('status', ['pending', 'delivered'])
    .order('created_at', { ascending: false });

  if (error) {
    console.error('Error fetching outgoing payments:', error);
    throw error;
  }

  return data as DbPaymentIntent[];
}

// ===========================================
// PAYMENT ACKS
// ===========================================

/**
 * Create payment acknowledgment
 */
export async function createPaymentAck(data: {
  payment_id: string;
  from_pk: string;
  status: 'accepted' | 'rejected';
  reason?: string | null;
  envelope_json?: any | null;
}): Promise<DbPaymentAck> {
  const { data: result, error } = await getSupabase()
    .from('payment_acks')
    .insert({
      payment_id: data.payment_id,
      from_pk: data.from_pk.toLowerCase(),
      status: data.status,
      reason: data.reason || null,
      envelope_json: data.envelope_json || null,
    })
    .select()
    .single();

  if (error) {
    console.error('Error creating payment ack:', error);
    throw error;
  }

  return result as DbPaymentAck;
}

/**
 * Get payment acknowledgment
 */
export async function getPaymentAck(paymentId: string): Promise<DbPaymentAck | null> {
  const { data, error } = await getSupabase()
    .from('payment_acks')
    .select('*')
    .eq('payment_id', paymentId)
    .single();

  if (error && error.code !== 'PGRST116') {
    console.error('Error fetching payment ack:', error);
    throw error;
  }

  return data as DbPaymentAck | null;
}

// ===========================================
// GEOAUTH SESSIONS (Chapter 8)
// ===========================================

/**
 * Create GeoAuth session (called by merchant)
 */
export async function createGeoAuthSession(data: {
  auth_id: string;
  merchant_id: string;
  merchant_name?: string;
  payment_hash: string;
  amount?: string;
  currency?: string;
  expires_at: string;
}): Promise<DbGeoAuthSession> {
  const { data: result, error } = await getSupabase()
    .from('geoauth_sessions')
    .insert({
      auth_id: data.auth_id,
      merchant_id: data.merchant_id,
      merchant_name: data.merchant_name || null,
      payment_hash: data.payment_hash,
      amount: data.amount || null,
      currency: data.currency || null,
      status: 'pending',
      expires_at: data.expires_at,
    })
    .select()
    .single();

  if (error) {
    console.error('Error creating geoauth session:', error);
    throw error;
  }

  return result as DbGeoAuthSession;
}

/**
 * Get GeoAuth session
 */
export async function getGeoAuthSession(authId: string): Promise<DbGeoAuthSession | null> {
  const { data, error } = await getSupabase()
    .from('geoauth_sessions')
    .select('*')
    .eq('auth_id', authId)
    .single();

  if (error && error.code !== 'PGRST116') {
    console.error('Error fetching geoauth session:', error);
    throw error;
  }

  return data as DbGeoAuthSession | null;
}

/**
 * Authorize GeoAuth session (called when user submits token)
 */
export async function authorizeGeoAuthSession(
  authId: string,
  data: {
    user_pk: string;
    envelope_json: any;
    h3_cell: string;
  }
): Promise<DbGeoAuthSession | null> {
  const { data: result, error } = await getSupabase()
    .from('geoauth_sessions')
    .update({
      status: 'authorized',
      user_pk: data.user_pk.toLowerCase(),
      envelope_json: data.envelope_json,
      h3_cell: data.h3_cell,
      authorized_at: new Date().toISOString(),
    })
    .eq('auth_id', authId)
    .eq('status', 'pending')
    .select()
    .single();

  if (error && error.code !== 'PGRST116') {
    console.error('Error authorizing geoauth session:', error);
    throw error;
  }

  return result as DbGeoAuthSession | null;
}

/**
 * Mark GeoAuth session as used
 */
export async function markGeoAuthUsed(authId: string): Promise<void> {
  const { error } = await getSupabase()
    .from('geoauth_sessions')
    .update({ status: 'used' })
    .eq('auth_id', authId)
    .eq('status', 'authorized');

  if (error) {
    console.error('Error marking geoauth used:', error);
    throw error;
  }
}

/**
 * Get pending GeoAuth sessions for merchant
 */
export async function getMerchantGeoAuthSessions(
  merchantId: string,
  status: string = 'pending'
): Promise<DbGeoAuthSession[]> {
  const { data, error } = await getSupabase()
    .from('geoauth_sessions')
    .select('*')
    .eq('merchant_id', merchantId)
    .eq('status', status)
    .order('created_at', { ascending: false });

  if (error) {
    console.error('Error fetching merchant geoauth sessions:', error);
    throw error;
  }

  return data as DbGeoAuthSession[];
}

// ===========================================
// GEOAUTH MERCHANTS (for Chapter 8)
// ===========================================

/**
 * Get merchant by API key hash
 */
export async function getMerchantByApiKey(keyHash: string): Promise<any | null> {
  const { data, error } = await getSupabase()
    .from('geoauth_merchants')
    .select('*')
    .eq('api_key_hash', keyHash)
    .single();

  if (error && error.code !== 'PGRST116') {
    console.error('Error fetching merchant by API key:', error);
    throw error;
  }

  return data;
}

/**
 * Get merchant by ID
 */
export async function getMerchant(merchantId: string): Promise<any | null> {
  const { data, error } = await getSupabase()
    .from('geoauth_merchants')
    .select('*')
    .eq('merchant_id', merchantId)
    .single();

  if (error && error.code !== 'PGRST116') {
    console.error('Error fetching merchant:', error);
    throw error;
  }

  return data;
}

/**
 * Expire a single GeoAuth session
 */
export async function expireGeoAuthSession(authId: string): Promise<void> {
  const { error } = await getSupabase()
    .from('geoauth_sessions')
    .update({ status: 'expired' })
    .eq('auth_id', authId);

  if (error) {
    console.error('Error expiring geoauth session:', error);
    throw error;
  }
}

/**
 * Get all pending GeoAuth sessions (for user discovery)
 */
export async function getPendingGeoAuthSessions(): Promise<DbGeoAuthSession[]> {
  const { data, error } = await getSupabase()
    .from('geoauth_sessions')
    .select('*')
    .eq('status', 'pending')
    .gt('expires_at', new Date().toISOString())
    .order('created_at', { ascending: false })
    .limit(50);

  if (error) {
    console.error('Error fetching pending geoauth sessions:', error);
    throw error;
  }

  return data as DbGeoAuthSession[];
}

// ===========================================
// CLEANUP FUNCTIONS
// ===========================================

/**
 * Expire old pending payments
 */
export async function expirePendingPayments(): Promise<number> {
  const { data, error } = await getSupabase()
    .from('payment_intents')
    .update({ status: 'expired' })
    .eq('status', 'pending')
    .not('expires_at', 'is', null)
    .lt('expires_at', new Date().toISOString())
    .select();

  if (error) {
    console.error('Error expiring payments:', error);
    return 0;
  }

  return data?.length || 0;
}

/**
 * Expire old geoauth sessions
 */
export async function expireGeoAuthSessions(): Promise<number> {
  const { data, error } = await getSupabase()
    .from('geoauth_sessions')
    .update({ status: 'expired' })
    .eq('status', 'pending')
    .lt('expires_at', new Date().toISOString())
    .select();

  if (error) {
    console.error('Error expiring geoauth sessions:', error);
    return 0;
  }

  return data?.length || 0;
}

// ===========================================
// EXISTING CLEANUP FUNCTIONS
// ===========================================

/**
 * Cleanup expired messages
 */
export async function cleanupExpiredMessages(): Promise<number> {
  // Mark expired
  await getSupabase()
    .from('messages')
    .update({ status: 'expired' })
    .lt('expires_at', new Date().toISOString())
    .eq('status', 'pending');

  // Delete old delivered messages
  const thirtyDaysAgo = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString();
  const { data } = await getSupabase()
    .from('messages')
    .delete()
    .lt('delivered_at', thirtyDaysAgo)
    .select('id');

  return data?.length || 0;
}

/**
 * Cleanup stale typing indicators
 */
export async function cleanupTypingStatus(): Promise<void> {
  const thirtySecondsAgo = new Date(Date.now() - 30000).toISOString();

  await getSupabase()
    .from('typing_status')
    .delete()
    .lt('updated_at', thirtySecondsAgo);
}

/**
 * Cleanup stale presence (mark offline)
 */
export async function cleanupStalePresence(): Promise<void> {
  const fiveMinutesAgo = new Date(Date.now() - 5 * 60 * 1000).toISOString();

  await getSupabase()
    .from('presence')
    .update({ status: 'offline' })
    .eq('status', 'online')
    .lt('last_seen', fiveMinutesAgo);
}

// ===========================================
// WEB API HELPERS (for World Browser)
// ===========================================

/**
 * Search aliases by handle prefix
 */
export async function searchAliases(query: string, limit = 20): Promise<DbAlias[]> {
  const { data, error } = await getSupabase()
    .from('aliases')
    .select('*')
    .ilike('handle', `${query}%`)
    .limit(limit);

  if (error) {
    console.error('Error searching aliases:', error);
    throw error;
  }

  return data as DbAlias[];
}

/**
 * Get top identities by trust score
 */
export async function getTopIdentities(limit = 10): Promise<DbRecord[]> {
  const { data, error } = await getSupabase()
    .from('records')
    .select('*')
    .order('trust_score', { ascending: false })
    .limit(limit);

  if (error) {
    console.error('Error getting top identities:', error);
    throw error;
  }

  return data as DbRecord[];
}

// ===========================================
// ORGANIZATION REGISTRATION
// ===========================================

/**
 * Create a new organization registration
 */
export async function createOrgRegistration(data: {
  id: string;
  namespace: string;
  organization_name: string;
  email: string;
  website: string;
  domain: string;
  description: string | null;
  tier: string;
  verification_code: string;
}) {
  const { data: result, error } = await getSupabase()
    .from('org_registrations')
    .insert({
      id: data.id,
      namespace: data.namespace,
      organization_name: data.organization_name,
      email: data.email,
      website: data.website,
      domain: data.domain,
      description: data.description,
      tier: data.tier,
      verification_code: data.verification_code,
      status: 'pending',
    })
    .select()
    .single();

  if (error) throw error;
  return result;
}

/**
 * Get organization registration by ID
 */
export async function getOrgRegistration(id: string) {
  const { data, error } = await getSupabase()
    .from('org_registrations')
    .select('*')
    .eq('id', id)
    .single();

  if (error && error.code !== 'PGRST116') throw error;
  return data;
}

/**
 * Get organization registration by namespace
 */
export async function getOrgRegistrationByNamespace(namespace: string) {
  const { data, error } = await getSupabase()
    .from('org_registrations')
    .select('*')
    .eq('namespace', namespace)
    .in('status', ['pending', 'verified'])
    .single();

  if (error && error.code !== 'PGRST116') throw error;
  return data;
}

/**
 * Get organization registration by domain
 */
export async function getOrgRegistrationByDomain(domain: string) {
  const { data, error } = await getSupabase()
    .from('org_registrations')
    .select('*')
    .eq('domain', domain)
    .in('status', ['pending', 'verified'])
    .single();

  if (error && error.code !== 'PGRST116') throw error;
  return data;
}

/**
 * Update organization registration status
 */
export async function updateOrgRegistrationStatus(
  id: string,
  status: 'verified' | 'rejected',
  rejectionReason?: string
) {
  const updateData: Record<string, any> = {
    status,
  };

  if (status === 'verified') {
    updateData.verified_at = new Date().toISOString();
  }

  if (status === 'rejected') {
    updateData.rejected_at = new Date().toISOString();
    updateData.rejection_reason = rejectionReason;
  }

  const { data, error } = await getSupabase()
    .from('org_registrations')
    .update(updateData)
    .eq('id', id)
    .select()
    .single();

  if (error) throw error;
  return data;
}

/**
 * Set public key for verified organization
 */
export async function setOrgPublicKey(id: string, publicKey: string) {
  const { data, error } = await getSupabase()
    .from('org_registrations')
    .update({ public_key: publicKey })
    .eq('id', id)
    .eq('status', 'verified')
    .select()
    .single();

  if (error) throw error;
  return data;
}

/**
 * Get all pending registrations (for admin)
 */
export async function getPendingOrgRegistrations() {
  const { data, error } = await getSupabase()
    .from('org_registrations')
    .select('*')
    .eq('status', 'pending')
    .order('created_at', { ascending: false });

  if (error) throw error;
  return data || [];
}

// ===========================================
// BROWSER SESSIONS
// ===========================================

export interface BrowserSessionInput {
  sessionToken: string;
  publicKey: string;
  handle?: string;
  browserInfo: string;
  deviceInfo?: any;
  createdAt: Date;
  expiresAt: Date;
}

export interface BrowserSession {
  id: number;
  sessionToken: string;
  publicKey: string;
  handle?: string;
  browserInfo: string;
  deviceInfo?: any;
  createdAt: Date;
  expiresAt: Date;
  lastUsedAt: Date;
  isActive: boolean;
  revokedAt?: Date;
}

/**
 * Create a new browser session
 */
export async function createBrowserSession(input: BrowserSessionInput): Promise<BrowserSession> {
  const { data, error } = await getSupabase()
    .from('browser_sessions')
    .insert({
      session_token: input.sessionToken,
      public_key: input.publicKey.toLowerCase(),
      handle: input.handle?.toLowerCase() || null,
      browser_info: input.browserInfo,
      device_info: input.deviceInfo || null,
      created_at: input.createdAt.toISOString(),
      expires_at: input.expiresAt.toISOString(),
      last_used_at: new Date().toISOString(),
      is_active: true,
    })
    .select()
    .single();

  if (error) {
    console.error('Error creating browser session:', error);
    throw error;
  }

  return mapBrowserSession(data);
}

/**
 * Get all active browser sessions for a user
 */
export async function getBrowserSessions(publicKey: string): Promise<BrowserSession[]> {
  const { data, error } = await getSupabase()
    .from('browser_sessions')
    .select('*')
    .eq('public_key', publicKey.toLowerCase())
    .eq('is_active', true)
    .order('last_used_at', { ascending: false });

  if (error) {
    console.error('Error fetching browser sessions:', error);
    throw error;
  }

  return (data || []).map(mapBrowserSession);
}

/**
 * Update session last used timestamp
 */
export async function updateBrowserSessionLastUsed(sessionToken: string): Promise<void> {
  const { error } = await getSupabase()
    .from('browser_sessions')
    .update({ last_used_at: new Date().toISOString() })
    .eq('session_token', sessionToken);

  if (error) {
    console.error('Error updating browser session:', error);
  }
}

/**
 * Revoke a browser session
 */
export async function revokeBrowserSession(sessionToken: string): Promise<boolean> {
  const { error } = await getSupabase()
    .from('browser_sessions')
    .update({
      is_active: false,
      revoked_at: new Date().toISOString(),
    })
    .eq('session_token', sessionToken);

  if (error) {
    console.error('Error revoking browser session:', error);
    return false;
  }

  return true;
}

/**
 * Revoke all browser sessions for a user
 */
export async function revokeAllBrowserSessions(publicKey: string): Promise<number> {
  const { data, error } = await getSupabase()
    .from('browser_sessions')
    .update({
      is_active: false,
      revoked_at: new Date().toISOString(),
    })
    .eq('public_key', publicKey.toLowerCase())
    .eq('is_active', true)
    .select();

  if (error) {
    console.error('Error revoking all browser sessions:', error);
    throw error;
  }

  return data?.length || 0;
}

/**
 * Clean up expired sessions (run periodically)
 */
export async function cleanupExpiredSessions(): Promise<number> {
  const { data, error } = await getSupabase()
    .from('browser_sessions')
    .update({
      is_active: false,
      revoked_at: new Date().toISOString(),
    })
    .lt('expires_at', new Date().toISOString())
    .eq('is_active', true)
    .select();

  if (error) {
    console.error('Error cleaning up sessions:', error);
    return 0;
  }

  return data?.length || 0;
}

/**
 * Map database row to BrowserSession type
 */
function mapBrowserSession(row: any): BrowserSession {
  return {
    id: row.id,
    sessionToken: row.session_token,
    publicKey: row.public_key,
    handle: row.handle || undefined,
    browserInfo: row.browser_info,
    deviceInfo: row.device_info || undefined,
    createdAt: new Date(row.created_at),
    expiresAt: new Date(row.expires_at),
    lastUsedAt: new Date(row.last_used_at),
    isActive: row.is_active,
    revokedAt: row.revoked_at ? new Date(row.revoked_at) : undefined,
  };
}

/**
 * Get alias by identity public key
 */
export async function getAliasByIdentity(publicKey: string): Promise<{ handle: string } | null> {
  const { data, error } = await getSupabase()
    .from('aliases')
    .select('handle')
    .eq('pk_root', publicKey.toLowerCase())
    .single();

  if (error && error.code !== 'PGRST116') {
    console.error('Error fetching alias:', error);
    return null;
  }

  return data;
}