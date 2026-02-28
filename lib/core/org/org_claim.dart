/// GNS Organization Claims Service
/// 
/// Manages organization-level verified claims:
/// - Social media accounts (Twitter, LinkedIn, Instagram, YouTube, etc.)
/// - Legal entity identifiers (LEI, VAT, EUID, DUNS, etc.)
/// - Developer platforms (GitHub Org, npm, Docker Hub, etc.)
/// - Commerce/directory listings (Google Business, Yelp, App Store, etc.)
/// - Auto-generated GLUE URIs
/// 
/// Location: lib/core/org/org_claim.dart

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

// =============================================================
// MODELS
// =============================================================

/// A single organization claim (social, legal, developer, etc.)
class OrgClaim {
  final String id;
  final String namespace;
  final String category;
  final String claimType;
  final String claimValue;
  final String? displayLabel;
  final String status;
  final String? verificationMethod;
  final Map<String, dynamic> verificationProof;
  final String? externalUrl;
  final Map<String, dynamic> enrichedData;
  final String claimedByPk;
  final DateTime? verifiedAt;
  final DateTime? expiresAt;
  final bool isPublic;
  final int displayOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  OrgClaim({
    required this.id,
    required this.namespace,
    required this.category,
    required this.claimType,
    required this.claimValue,
    this.displayLabel,
    required this.status,
    this.verificationMethod,
    this.verificationProof = const {},
    this.externalUrl,
    this.enrichedData = const {},
    required this.claimedByPk,
    this.verifiedAt,
    this.expiresAt,
    this.isPublic = true,
    this.displayOrder = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  factory OrgClaim.fromJson(Map<String, dynamic> json) => OrgClaim(
    id: json['id'] as String,
    namespace: json['namespace'] as String,
    category: json['category'] as String,
    claimType: json['claim_type'] as String,
    claimValue: json['claim_value'] as String,
    displayLabel: json['display_label'] as String?,
    status: json['status'] as String,
    verificationMethod: json['verification_method'] as String?,
    verificationProof: (json['verification_proof'] as Map<String, dynamic>?) ?? {},
    externalUrl: json['external_url'] as String?,
    enrichedData: (json['enriched_data'] as Map<String, dynamic>?) ?? {},
    claimedByPk: json['claimed_by_pk'] as String,
    verifiedAt: json['verified_at'] != null ? DateTime.parse(json['verified_at']) : null,
    expiresAt: json['expires_at'] != null ? DateTime.parse(json['expires_at']) : null,
    isPublic: json['is_public'] as bool? ?? true,
    displayOrder: json['display_order'] as int? ?? 0,
    createdAt: DateTime.parse(json['created_at'] as String),
    updatedAt: DateTime.parse(json['updated_at'] as String),
  );

  bool get isVerified => status == 'verified';
  bool get isPending => status == 'pending';
  bool get isFailed => status == 'failed';
  bool get isExpired => expiresAt != null && expiresAt!.isBefore(DateTime.now());

  /// Get icon for this claim type
  String get icon {
    switch (claimType) {
      case 'twitter': return '🐦';
      case 'linkedin_company': return '💼';
      case 'instagram': return '📸';
      case 'youtube': return '🎬';
      case 'tiktok': return '🎵';
      case 'facebook': return '👥';
      case 'discord': return '🎮';
      case 'telegram': return '✈️';
      case 'mastodon': return '🐘';
      case 'bluesky': return '🦋';
      case 'lei': return '🏦';
      case 'vat_id': return '🧾';
      case 'euid': return '🇪🇺';
      case 'duns': return '📊';
      case 'chamber_of_commerce': return '🏛️';
      case 'rea': return '🇮🇹';
      case 'github_org': return '🐙';
      case 'npm_org': return '📦';
      case 'docker_hub': return '🐳';
      case 'pypi': return '🐍';
      case 'crates_io': return '🦀';
      case 'app_store': return '🍎';
      case 'play_store': return '▶️';
      case 'stripe': return '💳';
      case 'shopify': return '🛍️';
      case 'google_business': return '📍';
      case 'yelp': return '⭐';
      case 'tripadvisor': return '🦉';
      case 'glue_gns': return '🆔';
      default: return '🔗';
    }
  }

  /// Display-friendly type name
  String get typeName {
    switch (claimType) {
      case 'twitter': return 'Twitter / X';
      case 'linkedin_company': return 'LinkedIn';
      case 'instagram': return 'Instagram';
      case 'youtube': return 'YouTube';
      case 'tiktok': return 'TikTok';
      case 'facebook': return 'Facebook';
      case 'discord': return 'Discord';
      case 'telegram': return 'Telegram';
      case 'mastodon': return 'Mastodon';
      case 'bluesky': return 'Bluesky';
      case 'lei': return 'LEI';
      case 'vat_id': return 'VAT / Tax ID';
      case 'euid': return 'EUID (EU)';
      case 'duns': return 'D-U-N-S';
      case 'chamber_of_commerce': return 'Chamber of Commerce';
      case 'rea': return 'REA (Italy)';
      case 'github_org': return 'GitHub Org';
      case 'npm_org': return 'npm Org';
      case 'docker_hub': return 'Docker Hub';
      case 'pypi': return 'PyPI';
      case 'crates_io': return 'Crates.io';
      case 'app_store': return 'App Store';
      case 'play_store': return 'Play Store';
      case 'stripe': return 'Stripe';
      case 'shopify': return 'Shopify';
      case 'google_business': return 'Google Business';
      case 'yelp': return 'Yelp';
      case 'tripadvisor': return 'TripAdvisor';
      case 'glue_gns': return 'GLUE URI';
      default: return claimType;
    }
  }

  /// Status badge color (as hex int)
  int get statusColor {
    switch (status) {
      case 'verified': return 0xFF10B981;  // Green
      case 'pending': return 0xFFFBBF24;   // Yellow
      case 'verifying': return 0xFF3B82F6; // Blue
      case 'failed': return 0xFFEF4444;    // Red
      case 'expired': return 0xFF9CA3AF;   // Gray
      case 'revoked': return 0xFF6B7280;   // Dark gray
      default: return 0xFF9CA3AF;
    }
  }
}

/// Claim type definition (from org_claim_types table)
class OrgClaimType {
  final String claimType;
  final String category;
  final String displayName;
  final String? icon;
  final List<String> verificationMethods;
  final String? urlTemplate;
  final String? description;

  OrgClaimType({
    required this.claimType,
    required this.category,
    required this.displayName,
    this.icon,
    required this.verificationMethods,
    this.urlTemplate,
    this.description,
  });

  factory OrgClaimType.fromJson(Map<String, dynamic> json) => OrgClaimType(
    claimType: json['claim_type'] as String,
    category: json['category'] as String,
    displayName: json['display_name'] as String,
    icon: json['icon'] as String?,
    verificationMethods: List<String>.from(json['verification_methods'] ?? []),
    urlTemplate: json['url_template'] as String?,
    description: json['description'] as String?,
  );
}

/// Verification instructions returned when creating a claim
class VerificationInstructions {
  final String method;
  final String instructions;
  final Map<String, String>? dns;
  final String? requiredText;
  final String? alternative;
  final String? metaTag;

  VerificationInstructions({
    required this.method,
    required this.instructions,
    this.dns,
    this.requiredText,
    this.alternative,
    this.metaTag,
  });

  factory VerificationInstructions.fromJson(Map<String, dynamic> json) => VerificationInstructions(
    method: json['method'] as String,
    instructions: json['instructions'] as String,
    dns: json['dns'] != null ? Map<String, String>.from(json['dns']) : null,
    requiredText: json['required_text'] as String?,
    alternative: json['alternative'] as String?,
    metaTag: json['meta_tag'] as String?,
  );
}

/// GLEIF LEI lookup result
class LEIResult {
  final bool found;
  final String? lei;
  final String? legalName;
  final String? jurisdiction;
  final String? status;
  final String? registrationStatus;
  final String? glueUri;
  final String? error;
  final Map<String, dynamic> raw;

  LEIResult({
    required this.found,
    this.lei,
    this.legalName,
    this.jurisdiction,
    this.status,
    this.registrationStatus,
    this.glueUri,
    this.error,
    this.raw = const {},
  });

  factory LEIResult.fromJson(Map<String, dynamic> json) => LEIResult(
    found: json['found'] as bool? ?? false,
    lei: json['lei'] as String?,
    legalName: json['legal_name'] as String?,
    jurisdiction: json['jurisdiction'] as String?,
    status: json['status'] as String?,
    registrationStatus: json['registration_status'] as String?,
    glueUri: json['glue_uri'] as String?,
    error: json['error'] as String?,
    raw: json,
  );
}

// =============================================================
// SERVICE
// =============================================================

class OrgClaimsService {
  static const _apiBase = 'https://gns-browser-production.up.railway.app';
  
  final String namespace;
  final String adminPk;

  OrgClaimsService({
    required this.namespace,
    required this.adminPk,
  });

  // ---- Claim Types ----

  /// Fetch all supported claim types, grouped by category
  Future<Map<String, List<OrgClaimType>>> getClaimTypes() async {
    try {
      final response = await http.get(
        Uri.parse('$_apiBase/org/claim-types'),
      ).timeout(const Duration(seconds: 10));
      
      final data = jsonDecode(response.body);
      if (data['success'] != true) throw Exception(data['error']);
      
      final grouped = <String, List<OrgClaimType>>{};
      final categories = data['data'] as Map<String, dynamic>;
      
      for (final entry in categories.entries) {
        grouped[entry.key] = (entry.value as List)
            .map((ct) => OrgClaimType.fromJson(ct as Map<String, dynamic>))
            .toList();
      }
      
      return grouped;
    } catch (e) {
      debugPrint('[OrgClaims] Failed to fetch claim types: $e');
      return {};
    }
  }

  // ---- List Claims ----

  /// List all claims for this namespace
  Future<List<OrgClaim>> listClaims({String? category, String? status}) async {
    try {
      var url = '$_apiBase/org/$namespace/claims';
      final params = <String>[];
      if (category != null) params.add('category=$category');
      if (status != null) params.add('status=$status');
      if (params.isNotEmpty) url += '?${params.join('&')}';
      
      final response = await http.get(
        Uri.parse(url),
        headers: {'x-admin-pk': adminPk},
      ).timeout(const Duration(seconds: 10));
      
      final data = jsonDecode(response.body);
      if (data['success'] != true) throw Exception(data['error']);
      
      final claims = (data['data']['claims'] as List)
          .map((c) => OrgClaim.fromJson(c as Map<String, dynamic>))
          .toList();
      
      return claims;
    } catch (e) {
      debugPrint('[OrgClaims] Failed to list claims: $e');
      return [];
    }
  }

  /// Get public claims summary
  Future<Map<String, dynamic>> getPublicSummary() async {
    try {
      final response = await http.get(
        Uri.parse('$_apiBase/org/$namespace/claims/summary'),
      ).timeout(const Duration(seconds: 10));
      
      final data = jsonDecode(response.body);
      if (data['success'] != true) throw Exception(data['error']);
      return data['data'] as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[OrgClaims] Failed to get summary: $e');
      return {};
    }
  }

  // ---- Submit Claim ----

  /// Submit a new claim
  Future<({OrgClaim? claim, VerificationInstructions? verification, String? error})> submitClaim({
    required String claimType,
    required String claimValue,
    String? displayLabel,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_apiBase/org/$namespace/claims'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'claim_type': claimType,
          'claim_value': claimValue.trim(),
          'admin_pk': adminPk,
          'display_label': displayLabel,
        }),
      ).timeout(const Duration(seconds: 30));
      
      final data = jsonDecode(response.body);
      
      if (data['success'] != true) {
        return (claim: null, verification: null, error: data['error'] as String?);
      }
      
      final claim = OrgClaim.fromJson(data['data']['claim'] as Map<String, dynamic>);
      VerificationInstructions? verification;
      if (data['data']['verification'] != null) {
        verification = VerificationInstructions.fromJson(
          data['data']['verification'] as Map<String, dynamic>,
        );
      }
      
      return (claim: claim, verification: verification, error: null);
    } catch (e) {
      debugPrint('[OrgClaims] Submit failed: $e');
      return (claim: null, verification: null, error: e.toString());
    }
  }

  // ---- Verify Claim ----

  /// Trigger verification for a pending claim
  Future<({bool verified, String? message, Map<String, dynamic>? enriched})> verifyClaim(String claimId) async {
    try {
      final response = await http.post(
        Uri.parse('$_apiBase/org/$namespace/claims/$claimId/verify'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'admin_pk': adminPk}),
      ).timeout(const Duration(seconds: 30));
      
      final data = jsonDecode(response.body);
      if (data['success'] != true) throw Exception(data['error']);
      
      return (
        verified: data['data']['verified'] as bool? ?? false,
        message: data['data']['message'] as String?,
        enriched: data['data']['enriched'] as Map<String, dynamic>?,
      );
    } catch (e) {
      debugPrint('[OrgClaims] Verify failed: $e');
      return (verified: false, message: e.toString(), enriched: null);
    }
  }

  // ---- Revoke Claim ----

  /// Revoke/delete a claim
  Future<bool> revokeClaim(String claimId) async {
    try {
      final response = await http.delete(
        Uri.parse('$_apiBase/org/$namespace/claims/$claimId'),
        headers: {
          'Content-Type': 'application/json',
          'x-admin-pk': adminPk,
        },
      ).timeout(const Duration(seconds: 10));
      
      final data = jsonDecode(response.body);
      return data['success'] == true;
    } catch (e) {
      debugPrint('[OrgClaims] Revoke failed: $e');
      return false;
    }
  }

  // ---- LEI Lookup ----

  /// Look up an LEI by number
  Future<LEIResult> lookupLEI(String lei) async {
    try {
      final response = await http.post(
        Uri.parse('$_apiBase/org/$namespace/claims/lei/lookup'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'lei': lei, 'admin_pk': adminPk}),
      ).timeout(const Duration(seconds: 15));
      
      final data = jsonDecode(response.body);
      if (data['success'] != true) throw Exception(data['error']);
      return LEIResult.fromJson(data['data'] as Map<String, dynamic>);
    } catch (e) {
      return LEIResult(found: false, error: e.toString());
    }
  }

  /// Search LEI by company name
  Future<List<LEIResult>> searchLEI(String companyName, {String? jurisdiction}) async {
    try {
      final response = await http.post(
        Uri.parse('$_apiBase/org/$namespace/claims/lei/lookup'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'company_name': companyName,
          'jurisdiction': jurisdiction,
          'admin_pk': adminPk,
        }),
      ).timeout(const Duration(seconds: 15));
      
      final data = jsonDecode(response.body);
      if (data['success'] != true) return [];
      
      return (data['data']['results'] as List)
          .map((r) => LEIResult.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return [];
    }
  }

  // ---- VAT Validation ----

  /// Validate a VAT number via EU VIES
  Future<({bool valid, String? name, String? address})> validateVAT(String vatId) async {
    try {
      final response = await http.post(
        Uri.parse('$_apiBase/org/$namespace/claims/vat/validate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'vat_id': vatId, 'admin_pk': adminPk}),
      ).timeout(const Duration(seconds: 15));
      
      final data = jsonDecode(response.body);
      if (data['success'] != true) return (valid: false, name: null, address: null);
      
      return (
        valid: data['data']['valid'] as bool? ?? false,
        name: data['data']['name'] as String?,
        address: data['data']['address'] as String?,
      );
    } catch (e) {
      return (valid: false, name: null, address: null);
    }
  }
}

// =============================================================
// CATEGORY HELPERS
// =============================================================

/// All claim categories with display info
const orgClaimCategories = {
  'social': (name: 'Social Media', icon: '📱', description: 'Verify your social media presence'),
  'legal': (name: 'Legal Entity', icon: '⚖️', description: 'Link legal identifiers (LEI, VAT, EUID)'),
  'developer': (name: 'Developer', icon: '💻', description: 'Verify developer platform accounts'),
  'commerce': (name: 'Commerce', icon: '🛒', description: 'Link marketplace and payment accounts'),
  'directory': (name: 'Directories', icon: '📍', description: 'Verify business directory listings'),
  'glue': (name: 'GLUE URI', icon: '🆔', description: 'Auto-generated IETF GLUE identifier'),
};

/// Quick-access claim types for the "Add Claim" picker
const popularClaimTypes = [
  'twitter', 'linkedin_company', 'instagram', 'github_org',
  'lei', 'vat_id', 'youtube', 'google_business',
];
