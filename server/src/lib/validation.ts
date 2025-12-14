// ===========================================
// GNS NODE - VALIDATION SCHEMAS
// Using Zod for runtime validation
// ===========================================

import { z } from 'zod';
import { GNS_CONSTANTS, RESERVED_HANDLES } from '../types';

// ===========================================
// Base Schemas
// ===========================================

export const pkRootSchema = z
  .string()
  .length(GNS_CONSTANTS.PK_LENGTH)
  .regex(/^[0-9a-f]+$/i, 'Invalid public key format');

export const signatureSchema = z
  .string()
  .length(GNS_CONSTANTS.SIGNATURE_LENGTH)
  .regex(/^[0-9a-f]+$/i, 'Invalid signature format');

export const handleSchema = z
  .string()
  .min(GNS_CONSTANTS.HANDLE_MIN_LENGTH)
  .max(GNS_CONSTANTS.HANDLE_MAX_LENGTH)
  .regex(GNS_CONSTANTS.HANDLE_REGEX, 'Handle must be 3-20 chars, lowercase letters, numbers, underscore only')
  .refine(
    (val) => !RESERVED_HANDLES.includes(val.toLowerCase() as any),
    'This handle is reserved'
  );

// ===========================================
// GNS Module Schema
// ===========================================

export const gnsModuleSchema = z.object({
  id: z.string().min(1),
  schema: z.string().min(1),
  name: z.string().optional(),
  description: z.string().optional(),
  data_url: z.string().url().optional(),
  is_public: z.boolean().default(true),
  config: z.record(z.unknown()).optional(),
});

// ===========================================
// GNS Endpoint Schema
// ===========================================

export const gnsEndpointSchema = z.object({
  type: z.enum(['direct', 'relay', 'onion']),
  protocol: z.enum(['quic', 'wss', 'https']),
  address: z.string().min(1),
  port: z.number().int().positive().optional(),
  priority: z.number().int().default(0),
  is_active: z.boolean().default(true),
});

// ===========================================
// GNS Record Schema
// ===========================================

export const gnsRecordSchema = z.object({
  version: z.number().int().positive().default(1),
  identity: pkRootSchema,
  handle: handleSchema.optional().nullable(),
  
  // 🟢 FIX: ADD THE ENCRYPTION KEY FIELD
  encryption_key: z.string().length(GNS_CONSTANTS.PK_LENGTH).optional().nullable(),
  
  modules: z.array(gnsModuleSchema).default([]),
  endpoints: z.array(gnsEndpointSchema).default([]),
  epoch_roots: z.array(z.string()).default([]),
  trust_score: z.number().min(0).max(100),
  breadcrumb_count: z.number().int().nonnegative(),
  created_at: z.string().datetime(),
  updated_at: z.string().datetime(),
}).passthrough();

// ===========================================
// Signed Record Request
// ===========================================

export const signedRecordSchema = z.object({
  pk_root: pkRootSchema,
  record_json: gnsRecordSchema,
  signature: signatureSchema,
}).refine(
  (data) => data.pk_root.toLowerCase() === data.record_json.identity.toLowerCase(),
  'pk_root must match record identity'
);

// ===========================================
// PoT Proof Schema
// ===========================================

export const potProofSchema = z.object({
  breadcrumb_count: z
    .number()
    .int()
    .min(GNS_CONSTANTS.MIN_BREADCRUMBS_FOR_HANDLE, 
      `Must have at least ${GNS_CONSTANTS.MIN_BREADCRUMBS_FOR_HANDLE} breadcrumbs`),
  trust_score: z
    .number()
    .min(GNS_CONSTANTS.MIN_TRUST_SCORE_FOR_HANDLE,
      `Trust score must be at least ${GNS_CONSTANTS.MIN_TRUST_SCORE_FOR_HANDLE}`),
  first_breadcrumb_at: z.string().datetime(),
  latest_epoch_root: z.string().optional(),
});

// ===========================================
// Alias Claim Schema
// ===========================================

export const aliasClaimSchema = z.object({
  handle: handleSchema,
  identity: pkRootSchema,
  proof: potProofSchema,
  signature: signatureSchema,
}).refine(
  (data) => data.identity.length === GNS_CONSTANTS.PK_LENGTH,
  'Invalid identity format'
);

// ===========================================
// Epoch Header Schema
// ===========================================

export const epochHeaderSchema = z.object({
  identity: pkRootSchema,
  epoch_index: z.number().int().nonnegative(),
  start_time: z.string().datetime(),
  end_time: z.string().datetime(),
  merkle_root: z.string().length(64),
  block_count: z.number().int().positive(),
  prev_epoch_hash: z.string().length(64).optional().nullable(),
  signature: signatureSchema,
  epoch_hash: z.string().length(64),
});

export const signedEpochSchema = z.object({
  pk_root: pkRootSchema,
  epoch: epochHeaderSchema,
  signature: signatureSchema,
}).refine(
  (data) => data.pk_root.toLowerCase() === data.epoch.identity.toLowerCase(),
  'pk_root must match epoch identity'
);

// ===========================================
// Message Schema
// ===========================================

export const messageSchema = z.object({
  from_pk: pkRootSchema,
  to_pk: pkRootSchema,
  payload: z.string().min(1).max(100000), // Max 100KB payload
  signature: signatureSchema,
});

// ===========================================
// Auth Schemas
// ===========================================

export const authRequestSchema = z.object({
  pk: pkRootSchema,
  nonce: z.string().length(64),
  timestamp: z.string().datetime(),
  signature: signatureSchema,
});

// ===========================================
// Query Schemas
// ===========================================

export const paginationSchema = z.object({
  page: z.coerce.number().int().positive().default(1),
  limit: z.coerce.number().int().min(1).max(100).default(50),
});

export const sinceSchema = z.object({
  since: z.string().datetime().optional(),
  limit: z.coerce.number().int().min(1).max(1000).default(100),
});

// ===========================================
// Type Exports
// ===========================================

export type SignedRecordInput = z.infer<typeof signedRecordSchema>;
export type AliasClaimInput = z.infer<typeof aliasClaimSchema>;
export type SignedEpochInput = z.infer<typeof signedEpochSchema>;
export type MessageInput = z.infer<typeof messageSchema>;
export type AuthRequestInput = z.infer<typeof authRequestSchema>;
export type PaginationInput = z.infer<typeof paginationSchema>;
export type SinceInput = z.infer<typeof sinceSchema>;
