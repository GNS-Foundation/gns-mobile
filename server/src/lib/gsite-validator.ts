// ============================================================
// GNS VALIDATION SERVICE
// ============================================================
// Location: server/src/lib/gsite-validator.ts
// Purpose: Validate gSites and themes against JSON schemas
// ============================================================

import Ajv, { ValidateFunction, ErrorObject } from 'ajv';
import addFormats from 'ajv-formats';

// Import schemas
import gsiteSchema from '../schemas/gsite.schema.json';
import themeSchema from '../schemas/theme.schema.json';

// ============================================================
// TYPES
// ============================================================

export interface ValidationResult {
  valid: boolean;
  errors: ValidationError[];
  warnings: ValidationWarning[];
}

export interface ValidationError {
  path: string;
  message: string;
  keyword: string;
  params?: Record<string, unknown>;
}

export interface ValidationWarning {
  path: string;
  message: string;
}

export type GSiteType = 
  | 'Person' 
  | 'Business' 
  | 'Store' 
  | 'Service' 
  | 'Publication' 
  | 'Community' 
  | 'Organization' 
  | 'Event' 
  | 'Product' 
  | 'Place';

// ============================================================
// VALIDATOR CLASS
// ============================================================

export class GSiteValidator {
  private ajv: Ajv;
  private gsiteValidate: ValidateFunction;
  private themeValidate: ValidateFunction;

  constructor() {
    // Initialize AJV with formats support
    this.ajv = new Ajv({
      allErrors: true,
      verbose: true,
      strict: false,
    });
    
    // Add format validators (date-time, uri, email, etc.)
    addFormats(this.ajv);

    // Compile schemas
    this.gsiteValidate = this.ajv.compile(gsiteSchema);
    this.themeValidate = this.ajv.compile(themeSchema);
  }

  // ----------------------------------------------------------
  // VALIDATE gSITE
  // ----------------------------------------------------------
  
  validateGSite(data: unknown): ValidationResult {
    const valid = this.gsiteValidate(data);
    
    if (valid) {
      const warnings = this.checkGSiteWarnings(data as Record<string, unknown>);
      return { valid: true, errors: [], warnings };
    }

    return {
      valid: false,
      errors: this.formatErrors(this.gsiteValidate.errors),
      warnings: [],
    };
  }

  // ----------------------------------------------------------
  // VALIDATE THEME
  // ----------------------------------------------------------
  
  validateTheme(data: unknown): ValidationResult {
    const valid = this.themeValidate(data);
    
    if (valid) {
      const warnings = this.checkThemeWarnings(data as Record<string, unknown>);
      return { valid: true, errors: [], warnings };
    }

    return {
      valid: false,
      errors: this.formatErrors(this.themeValidate.errors),
      warnings: [],
    };
  }

  // ----------------------------------------------------------
  // BUSINESS LOGIC WARNINGS
  // ----------------------------------------------------------
  
  private checkGSiteWarnings(data: Record<string, unknown>): ValidationWarning[] {
    const warnings: ValidationWarning[] = [];

    if (!data.tagline) {
      warnings.push({
        path: 'tagline',
        message: 'Consider adding a tagline for better discoverability',
      });
    }

    if (!data.avatar) {
      warnings.push({
        path: 'avatar',
        message: 'gSites with avatars get 3x more engagement',
      });
    }

    const type = data['@type'] as string;
    
    if (type === 'Business') {
      if (!data.hours) {
        warnings.push({
          path: 'hours',
          message: 'Adding business hours helps customers find you',
        });
      }
      if (!data.location) {
        warnings.push({
          path: 'location',
          message: 'Location is important for local discovery',
        });
      }
    }

    if (type === 'Store') {
      const products = data.products as unknown[] | undefined;
      if (!products || products.length === 0) {
        warnings.push({
          path: 'products',
          message: 'Store has no products listed',
        });
      }
    }

    if (type === 'Person') {
      if (!data.bio) {
        warnings.push({
          path: 'bio',
          message: 'A bio helps others understand who you are',
        });
      }
    }

    return warnings;
  }

  private checkThemeWarnings(data: Record<string, unknown>): ValidationWarning[] {
    const warnings: ValidationWarning[] = [];

    if (!data.preview) {
      warnings.push({
        path: 'preview',
        message: 'Themes without previews are less likely to be used',
      });
    }

    return warnings;
  }

  // ----------------------------------------------------------
  // FORMAT ERRORS
  // ----------------------------------------------------------
  
  private formatErrors(errors: ErrorObject[] | null | undefined): ValidationError[] {
    if (!errors) return [];

    return errors.map(err => ({
      path: err.instancePath || err.schemaPath,
      message: err.message || 'Validation failed',
      keyword: err.keyword,
      params: err.params,
    }));
  }
}

// ============================================================
// SINGLETON INSTANCE
// ============================================================

let validatorInstance: GSiteValidator | null = null;

export function getValidator(): GSiteValidator {
  if (!validatorInstance) {
    validatorInstance = new GSiteValidator();
  }
  return validatorInstance;
}

// ============================================================
// CONVENIENCE FUNCTIONS
// ============================================================

export function validateGSite(data: unknown): ValidationResult {
  return getValidator().validateGSite(data);
}

export function validateTheme(data: unknown): ValidationResult {
  return getValidator().validateTheme(data);
}

export function isValidGSite(data: unknown): boolean {
  return getValidator().validateGSite(data).valid;
}

export function isValidTheme(data: unknown): boolean {
  return getValidator().validateTheme(data).valid;
}
