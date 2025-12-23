// ============================================================
// GNS gSITE VALIDATOR - FIXED VERSION
// ============================================================
// Location: server/src/lib/gsite-validator.ts
// Purpose: Validates gSite JSON against schema
// FIX: Validates against specific @type, not oneOf all types
// ============================================================

import Ajv from 'ajv';
import addFormats from 'ajv-formats';
import gsiteSchema from '../schemas/gsite.schema.json';
import themeSchema from '../schemas/theme.schema.json';

// ============================================================
// TYPES
// ============================================================

export interface ValidationError {
  path: string;
  message: string;
  keyword?: string;
}

export interface ValidationWarning {
  path: string;
  message: string;
}

export interface ValidationResult {
  valid: boolean;
  errors: ValidationError[];
  warnings: ValidationWarning[];
}

// ============================================================
// VALIDATOR CLASS
// ============================================================

class GSiteValidator {
  private ajv: Ajv;
  private themeValidate: any;

  constructor() {
    this.ajv = new Ajv({ 
      allErrors: true, 
      strict: false,
      allowUnionTypes: true,
    });
    addFormats(this.ajv);
    
    // Pre-compile theme validator
    try {
      this.themeValidate = this.ajv.compile(themeSchema);
    } catch (e) {
      console.error('Failed to compile theme schema:', e);
    }
  }

  // ----------------------------------------------------------
  // MAIN VALIDATION METHOD
  // ----------------------------------------------------------

  validateGSite(data: any): ValidationResult {
    const errors: ValidationError[] = [];
    const warnings: ValidationWarning[] = [];

    // 1. Check required base fields first
    if (!data['@context']) {
      errors.push({ path: '@context', message: 'Missing required field @context' });
    }
    if (!data['@type']) {
      errors.push({ path: '@type', message: 'Missing required field @type' });
    }
    if (!data['@id']) {
      errors.push({ path: '@id', message: 'Missing required field @id' });
    }
    if (!data['name']) {
      errors.push({ path: 'name', message: 'Missing required field name' });
    }
    if (!data['signature']) {
      errors.push({ path: 'signature', message: 'Missing required field signature' });
    }

    // If base fields missing, return early
    if (errors.length > 0) {
      return { valid: false, errors, warnings };
    }

    // 2. Validate @context
    if (data['@context'] !== 'https://schema.gns.network/v1') {
      errors.push({ 
        path: '@context', 
        message: 'Invalid @context. Must be https://schema.gns.network/v1' 
      });
    }

    // 3. Validate @type is known
    const validTypes = [
      'Person', 'Business', 'Store', 'Service', 'Publication',
      'Community', 'Organization', 'Event', 'Product', 'Place'
    ];
    
    if (!validTypes.includes(data['@type'])) {
      errors.push({ 
        path: '@type', 
        message: `Invalid @type. Must be one of: ${validTypes.join(', ')}` 
      });
      return { valid: false, errors, warnings };
    }

    // 4. Validate @id format
    const id = data['@id'];
    if (!id.startsWith('@') && !id.endsWith('@')) {
      errors.push({ 
        path: '@id', 
        message: '@id must start with @ (handle) or end with @ (namespace)' 
      });
    }

    // 5. Validate signature format
    if (!data['signature'].startsWith('ed25519:')) {
      errors.push({ 
        path: 'signature', 
        message: 'Signature must start with ed25519:' 
      });
    }

    // 6. Type-specific validation
    const typeErrors = this.validateByType(data['@type'], data);
    errors.push(...typeErrors);

    // 7. Add business logic warnings
    warnings.push(...this.getWarnings(data['@type'], data));

    return {
      valid: errors.length === 0,
      errors,
      warnings,
    };
  }

  // ----------------------------------------------------------
  // TYPE-SPECIFIC VALIDATION
  // ----------------------------------------------------------

  private validateByType(type: string, data: any): ValidationError[] {
    const errors: ValidationError[] = [];

    switch (type) {
      case 'Person':
        // Person has no additional required fields beyond base
        // Optional: facets, skills, interests, status
        if (data.facets && !Array.isArray(data.facets)) {
          errors.push({ path: 'facets', message: 'facets must be an array' });
        }
        if (data.skills && !Array.isArray(data.skills)) {
          errors.push({ path: 'skills', message: 'skills must be an array' });
        }
        break;

      case 'Business':
        if (!data.category) {
          errors.push({ path: 'category', message: 'Business requires category field' });
        }
        break;

      case 'Store':
        if (!data.products || !Array.isArray(data.products)) {
          errors.push({ path: 'products', message: 'Store requires products array' });
        }
        break;

      case 'Service':
        if (!data.profession) {
          errors.push({ path: 'profession', message: 'Service requires profession field' });
        }
        if (!data.services || !Array.isArray(data.services)) {
          errors.push({ path: 'services', message: 'Service requires services array' });
        }
        break;

      case 'Publication':
        if (!data.publicationType) {
          errors.push({ path: 'publicationType', message: 'Publication requires publicationType field' });
        }
        break;

      case 'Community':
        if (!data.communityType) {
          errors.push({ path: 'communityType', message: 'Community requires communityType field' });
        }
        if (!data.membership) {
          errors.push({ path: 'membership', message: 'Community requires membership field' });
        }
        break;

      case 'Organization':
        if (!data.orgType) {
          errors.push({ path: 'orgType', message: 'Organization requires orgType field' });
        }
        break;

      case 'Event':
        if (!data.eventType) {
          errors.push({ path: 'eventType', message: 'Event requires eventType field' });
        }
        if (!data.startDate) {
          errors.push({ path: 'startDate', message: 'Event requires startDate field' });
        }
        if (!data.timezone) {
          errors.push({ path: 'timezone', message: 'Event requires timezone field' });
        }
        if (!data.organizer) {
          errors.push({ path: 'organizer', message: 'Event requires organizer field' });
        }
        break;

      case 'Product':
        if (!data.productName) {
          errors.push({ path: 'productName', message: 'Product requires productName field' });
        }
        if (!data.description) {
          errors.push({ path: 'description', message: 'Product requires description field' });
        }
        if (!data.images || !Array.isArray(data.images)) {
          errors.push({ path: 'images', message: 'Product requires images array' });
        }
        if (!data.category) {
          errors.push({ path: 'category', message: 'Product requires category field' });
        }
        break;

      case 'Place':
        if (!data.placeType) {
          errors.push({ path: 'placeType', message: 'Place requires placeType field' });
        }
        break;
    }

    // Validate trust if present
    if (data.trust) {
      if (typeof data.trust.score !== 'number' || data.trust.score < 0 || data.trust.score > 100) {
        errors.push({ path: 'trust.score', message: 'trust.score must be a number between 0 and 100' });
      }
      if (typeof data.trust.breadcrumbs !== 'number' || data.trust.breadcrumbs < 0) {
        errors.push({ path: 'trust.breadcrumbs', message: 'trust.breadcrumbs must be a non-negative number' });
      }
    }

    // Validate location if present
    if (data.location) {
      // H3 format check if provided
      if (data.location.h3 && !/^[0-9a-f]{15,16}$/i.test(data.location.h3)) {
        errors.push({ path: 'location.h3', message: 'Invalid H3 cell format' });
      }
    }

    // Validate links if present
    if (data.links && Array.isArray(data.links)) {
      data.links.forEach((link: any, index: number) => {
        if (!link.type) {
          errors.push({ path: `links[${index}].type`, message: 'Link requires type field' });
        }
        if (!link.url && !link.handle) {
          errors.push({ path: `links[${index}]`, message: 'Link requires either url or handle' });
        }
      });
    }

    return errors;
  }

  // ----------------------------------------------------------
  // BUSINESS LOGIC WARNINGS
  // ----------------------------------------------------------

  private getWarnings(type: string, data: any): ValidationWarning[] {
    const warnings: ValidationWarning[] = [];

    // Universal recommendations
    if (!data.tagline) {
      warnings.push({ path: 'tagline', message: 'Consider adding a tagline for better discoverability' });
    }
    if (!data.avatar) {
      warnings.push({ path: 'avatar', message: 'gSites with avatars get 3x more engagement' });
    }
    if (!data.bio) {
      warnings.push({ path: 'bio', message: 'A bio helps others understand who you are' });
    }

    // Type-specific recommendations
    switch (type) {
      case 'Business':
      case 'Store':
      case 'Service':
        if (!data.hours) {
          warnings.push({ path: 'hours', message: 'Adding business hours helps customers know when to visit' });
        }
        if (!data.location) {
          warnings.push({ path: 'location', message: 'Adding a location helps customers find you' });
        }
        break;

      case 'Store':
        if (!data.products || data.products.length === 0) {
          warnings.push({ path: 'products', message: 'Add products to showcase what you sell' });
        }
        break;

      case 'Person':
        if (!data.skills || data.skills.length === 0) {
          warnings.push({ path: 'skills', message: 'Adding skills helps others find you for collaboration' });
        }
        if (!data.facets || data.facets.length === 0) {
          warnings.push({ path: 'facets', message: 'Create facets to organize your different identities' });
        }
        break;

      case 'Event':
        if (!data.location) {
          warnings.push({ path: 'location', message: 'Add a location so attendees know where to go' });
        }
        break;
    }

    // Trust score warning
    if (!data.trust || data.trust.score < 50) {
      warnings.push({ path: 'trust', message: 'Collect more breadcrumbs to increase your trust score' });
    }

    return warnings;
  }

  // ----------------------------------------------------------
  // THEME VALIDATION
  // ----------------------------------------------------------

  validateTheme(data: any): ValidationResult {
    const errors: ValidationError[] = [];
    const warnings: ValidationWarning[] = [];

    // Basic required fields
    if (!data.name) {
      errors.push({ path: 'name', message: 'Theme requires name field' });
    }
    if (!data.version) {
      errors.push({ path: 'version', message: 'Theme requires version field' });
    }
    if (!data.entityTypes || !Array.isArray(data.entityTypes)) {
      errors.push({ path: 'entityTypes', message: 'Theme requires entityTypes array' });
    }
    if (!data.colors) {
      errors.push({ path: 'colors', message: 'Theme requires colors object' });
    }
    if (!data.typography) {
      errors.push({ path: 'typography', message: 'Theme requires typography object' });
    }

    // Use AJV for detailed validation if basic checks pass
    if (errors.length === 0 && this.themeValidate) {
      const valid = this.themeValidate(data);
      if (!valid && this.themeValidate.errors) {
        for (const err of this.themeValidate.errors) {
          errors.push({
            path: err.instancePath || err.schemaPath || '',
            message: err.message || 'Validation error',
            keyword: err.keyword,
          });
        }
      }
    }

    return { valid: errors.length === 0, errors, warnings };
  }
}

// ============================================================
// SINGLETON EXPORT
// ============================================================

const validator = new GSiteValidator();

export function validateGSite(data: any): ValidationResult {
  return validator.validateGSite(data);
}

export function validateTheme(data: any): ValidationResult {
  return validator.validateTheme(data);
}

export default validator;
