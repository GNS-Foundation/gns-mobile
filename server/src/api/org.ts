// ===========================================
// GNS NODE - ORGANIZATION REGISTRATION API
// /org endpoints for namespace registration with DNS verification
// ===========================================
// Location: src/api/org.ts
//
// ENDPOINTS:
//   POST /org/register     - Submit registration, get verification code
//   POST /org/verify       - Check DNS TXT record
//   GET  /org/status/:id   - Check registration status
//
// REQUIRES: Run org_registration_migration.sql first
// ===========================================

import { Router, Request, Response } from 'express';
import * as dns from 'dns';
import { promisify } from 'util';
import { randomBytes } from 'crypto';
import * as db from '../lib/db';
import { ApiResponse } from '../types';

const router = Router();

// Promisify DNS lookup
const resolveTxt = promisify(dns.resolveTxt);

// ===========================================
// TYPES
// ===========================================

interface OrgRegistration {
  id: string;
  namespace: string;
  organization_name: string;
  email: string;
  website: string;
  domain: string;
  description: string | null;
  tier: string;
  verification_code: string;
  status: 'pending' | 'verified' | 'rejected';
  created_at: string;
  verified_at: string | null;
  public_key: string | null;
}

// ===========================================
// HELPERS
// ===========================================

/**
 * Generate a unique verification code
 */
function generateVerificationCode(): string {
  const bytes = randomBytes(12);
  return bytes.toString('hex');
}

/**
 * Validate namespace format
 */
function isValidNamespace(namespace: string): boolean {
  return /^[a-z0-9]{3,20}$/.test(namespace);
}

/**
 * Extract domain from URL
 */
function extractDomain(website: string): string {
  let domain = website.toLowerCase().trim();
  domain = domain.replace(/^https?:\/\//, '');
  domain = domain.replace(/^www\./, '');
  domain = domain.split('/')[0];
  return domain;
}

/**
 * Check DNS TXT records for verification code
 */
async function checkDnsTxt(domain: string, expectedCode: string): Promise<boolean> {
  try {
    console.log(`[DNS] Checking TXT records for ${domain}...`);
    
    // Try multiple record locations
    const domainsToCheck = [
      domain,
      `_gns.${domain}`,
      `gns-verify.${domain}`,
    ];
    
    for (const checkDomain of domainsToCheck) {
      try {
        const records = await resolveTxt(checkDomain);
        console.log(`[DNS] Found ${records.length} TXT records for ${checkDomain}`);
        
        // Records come as array of arrays (each record can have multiple strings)
        for (const record of records) {
          const recordText = record.join('');
          console.log(`[DNS] Record: ${recordText}`);
          
          // Check for exact match or gns-verify= prefix
          if (recordText === expectedCode || 
              recordText === `gns-verify=${expectedCode}` ||
              recordText.includes(expectedCode)) {
            console.log(`[DNS] ✓ Verification code found!`);
            return true;
          }
        }
      } catch (e) {
        // Domain check failed, try next
        console.log(`[DNS] No records at ${checkDomain}`);
      }
    }
    
    console.log(`[DNS] ✗ Verification code not found`);
    return false;
  } catch (error) {
    console.error('[DNS] Lookup error:', error);
    return false;
  }
}

// ===========================================
// POST /org/register
// Submit registration and get verification code
// ===========================================

router.post('/register', async (req: Request, res: Response) => {
  try {
    const { 
      namespace, 
      organization_name, 
      email, 
      website, 
      description, 
      tier 
    } = req.body;

    // Validate required fields
    if (!namespace || !organization_name || !email || !website) {
      return res.status(400).json({
        success: false,
        error: 'Missing required fields: namespace, organization_name, email, website',
      } as ApiResponse);
    }

    // Validate namespace format
    const cleanNamespace = namespace.toLowerCase().replace(/[^a-z0-9]/g, '');
    if (!isValidNamespace(cleanNamespace)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid namespace format. Use 3-20 lowercase letters and numbers.',
      } as ApiResponse);
    }

    // Extract domain
    const domain = extractDomain(website);
    if (!domain || !domain.includes('.')) {
      return res.status(400).json({
        success: false,
        error: 'Invalid website URL',
      } as ApiResponse);
    }

    // Check if namespace is already taken
    const existingAlias = await db.getAlias(cleanNamespace);
    if (existingAlias) {
      return res.status(409).json({
        success: false,
        error: 'This namespace is already registered',
      } as ApiResponse);
    }

    // Check for pending registration
    const existingRegistration = await db.getOrgRegistrationByNamespace(cleanNamespace);
    if (existingRegistration && existingRegistration.status === 'verified') {
      return res.status(409).json({
        success: false,
        error: 'This namespace is already registered',
      } as ApiResponse);
    }

    // Generate verification code
    const verificationCode = generateVerificationCode();
    const registrationId = `org_${Date.now()}_${randomBytes(4).toString('hex')}`;

    // Store registration
    const registration = await db.createOrgRegistration({
      id: registrationId,
      namespace: cleanNamespace,
      organization_name,
      email,
      website,
      domain,
      description: description || null,
      tier: tier || 'startup',
      verification_code: verificationCode,
    });

    console.log(`[Org] Registration created: ${cleanNamespace}@ for ${domain} (${registrationId})`);

    return res.status(201).json({
      success: true,
      data: {
        registration_id: registrationId,
        namespace: cleanNamespace,
        domain: domain,
        verification_code: verificationCode,
        txt_record: `gns-verify=${verificationCode}`,
        instructions: {
          step1: 'Log in to your domain registrar or DNS provider',
          step2: `Add a TXT record to ${domain}`,
          step3: `Set the value to: gns-verify=${verificationCode}`,
          step4: 'Wait for DNS propagation (usually 5-30 minutes)',
          step5: 'Click "Verify" to confirm ownership',
        },
      },
      message: 'Registration submitted. Please add the DNS TXT record to verify ownership.',
    } as ApiResponse);

  } catch (error: any) {
    console.error('POST /org/register error:', error);
    
    if (error?.code === '23505') {
      return res.status(409).json({
        success: false,
        error: 'This namespace or domain is already registered',
      } as ApiResponse);
    }
    
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
    } as ApiResponse);
  }
});

// ===========================================
// POST /org/verify
// Check DNS TXT record and complete registration
// ===========================================

router.post('/verify', async (req: Request, res: Response) => {
  try {
    const { registration_id, domain, verification_code } = req.body;

    if (!registration_id && !domain) {
      return res.status(400).json({
        success: false,
        error: 'Missing registration_id or domain',
      } as ApiResponse);
    }

    // Get registration
    let registration: OrgRegistration | null = null;
    
    if (registration_id) {
      registration = await db.getOrgRegistration(registration_id);
    } else if (domain) {
      registration = await db.getOrgRegistrationByDomain(domain);
    }

    if (!registration) {
      return res.status(404).json({
        success: false,
        error: 'Registration not found',
      } as ApiResponse);
    }

    if (registration.status === 'verified') {
      return res.json({
        success: true,
        data: {
          verified: true,
          namespace: registration.namespace,
          message: 'Already verified',
        },
      } as ApiResponse);
    }

    // Check DNS
    const isVerified = await checkDnsTxt(
      registration.domain, 
      registration.verification_code
    );

    if (!isVerified) {
      return res.status(400).json({
        success: false,
        verified: false,
        error: 'DNS TXT record not found. Please ensure you added the correct record and wait for DNS propagation.',
        expected: {
          domain: registration.domain,
          record_type: 'TXT',
          value: `gns-verify=${registration.verification_code}`,
        },
      } as ApiResponse);
    }

    // Update registration status
    await db.updateOrgRegistrationStatus(registration.id, 'verified');

    // Create the namespace alias
    // Note: We'll need the organization's public key to complete this
    // For now, mark as verified and they can claim it in the app
    
    console.log(`[Org] ✓ Verified: ${registration.namespace}@ for ${registration.domain}`);

    return res.json({
      success: true,
      data: {
        verified: true,
        namespace: `${registration.namespace}@`,
        domain: registration.domain,
        message: 'Domain ownership verified! Your namespace is now reserved.',
      },
    } as ApiResponse);

  } catch (error) {
    console.error('POST /org/verify error:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
    } as ApiResponse);
  }
});

// ===========================================
// GET /org/status/:id
// Check registration status
// ===========================================

router.get('/status/:id', async (req: Request, res: Response) => {
  try {
    const { id } = req.params;

    const registration = await db.getOrgRegistration(id);

    if (!registration) {
      return res.status(404).json({
        success: false,
        error: 'Registration not found',
      } as ApiResponse);
    }

    return res.json({
      success: true,
      data: {
        registration_id: registration.id,
        namespace: registration.namespace,
        organization_name: registration.organization_name,
        domain: registration.domain,
        status: registration.status,
        verification_code: registration.status === 'pending' 
          ? registration.verification_code 
          : undefined,
        created_at: registration.created_at,
        verified_at: registration.verified_at,
      },
    } as ApiResponse);

  } catch (error) {
    console.error('GET /org/status/:id error:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
    } as ApiResponse);
  }
});

// ===========================================
// GET /org/check/:namespace
// Quick check if namespace is available
// ===========================================

router.get('/check/:namespace', async (req: Request, res: Response) => {
  try {
    const namespace = req.params.namespace?.toLowerCase().replace(/[^a-z0-9]/g, '');

    if (!namespace || namespace.length < 3) {
      return res.status(400).json({
        success: false,
        error: 'Invalid namespace',
      } as ApiResponse);
    }

    // Check existing alias
    const existingAlias = await db.getAlias(namespace);
    if (existingAlias) {
      return res.json({
        success: true,
        data: {
          namespace: namespace,
          available: false,
          reason: 'Already registered',
        },
      } as ApiResponse);
    }

    // Check pending registrations
    const pendingRegistration = await db.getOrgRegistrationByNamespace(namespace);
    if (pendingRegistration) {
      return res.json({
        success: true,
        data: {
          namespace: namespace,
          available: false,
          reason: pendingRegistration.status === 'verified' 
            ? 'Already registered' 
            : 'Registration pending',
        },
      } as ApiResponse);
    }

    return res.json({
      success: true,
      data: {
        namespace: namespace,
        available: true,
      },
    } as ApiResponse);

  } catch (error) {
    console.error('GET /org/check/:namespace error:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
    } as ApiResponse);
  }
});

export default router;
