/// Facet Validator - Globe Posts Phase 1
///
/// Validates facet IDs before creation, checking against:
/// 1. Protocol facets (special behavior required)
/// 2. Blocked facets (system reserved and trademarks)
/// 3. Licensed brands (authorized employees only)
/// 4. Format rules (length, characters, etc.)
///
/// Philosophy: HUMANS PREVAIL
/// - Clear feedback on why a facet can't be created
/// - Guide users toward valid alternatives
/// - Protect against impersonation while enabling expression
///
/// Location: lib/core/facets/facet_validator.dart

import 'package:flutter/foundation.dart';
import 'protocol_facets.dart';
import 'blocked_facets.dart';

/// Result type for facet validation
enum FacetValidationType {
  /// Facet ID is available for user-defined use
  available,
  
  /// Facet ID is a protocol facet (requires activation)
  protocol,
  
  /// Facet ID is blocked (system reserved)
  blockedSystem,
  
  /// Facet ID is blocked (trademark protection)
  blockedBrand,
  
  /// Facet ID is blocked (government/org)
  blockedGovernment,
  
  /// Facet ID is blocked (offensive)
  blockedOffensive,
  
  /// Facet ID is licensed (brand employee can request)
  licensed,
  
  /// Facet ID format is invalid
  invalidFormat,
}

/// Complete result of facet validation
class FacetValidationResult {
  /// The type of validation result
  final FacetValidationType type;
  
  /// Whether the facet can be created (available or protocol with eligibility)
  final bool canCreate;
  
  /// Human-readable message explaining the result
  final String message;
  
  /// For protocol facets: the config
  final ProtocolFacetConfig? protocolConfig;
  
  /// For blocked facets: the info
  final BlockedFacetInfo? blockedInfo;
  
  /// For invalid format: specific error
  final String? formatError;
  
  /// Suggested alternatives (if any)
  final List<String> suggestions;

  const FacetValidationResult({
    required this.type,
    required this.canCreate,
    required this.message,
    this.protocolConfig,
    this.blockedInfo,
    this.formatError,
    this.suggestions = const [],
  });

  /// Quick check if result is a success (can proceed)
  bool get isSuccess => type == FacetValidationType.available || 
                         type == FacetValidationType.protocol;

  /// Quick check if result is a block
  bool get isBlocked => type == FacetValidationType.blockedSystem ||
                        type == FacetValidationType.blockedBrand ||
                        type == FacetValidationType.blockedGovernment ||
                        type == FacetValidationType.blockedOffensive;

  @override
  String toString() => 'FacetValidationResult($type: $message)';

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'can_create': canCreate,
    'message': message,
    'protocol_config': protocolConfig?.toJson(),
    'blocked_info': blockedInfo?.toJson(),
    'format_error': formatError,
    'suggestions': suggestions,
  };
}

/// Validates facet IDs and returns detailed results
class FacetValidator {
  // ============================================================
  // FORMAT RULES
  // ============================================================
  
  /// Minimum length for facet ID
  static const int minLength = 2;
  
  /// Maximum length for facet ID
  static const int maxLength = 32;
  
  /// Valid characters regex (lowercase letters, numbers, underscore)
  static final RegExp validCharsRegex = RegExp(r'^[a-z][a-z0-9_]*$');
  
  /// Characters not allowed anywhere
  static const Set<String> invalidChars = {'@', '#', '/', '\\', ' ', '.', '-'};

  // ============================================================
  // MAIN VALIDATION
  // ============================================================

  /// Validate a facet ID and return detailed result
  /// 
  /// [facetId] - The facet ID to validate
  /// [hasHandle] - Whether user has claimed a @handle (for protocol facets)
  /// [breadcrumbCount] - User's breadcrumb count (for protocol eligibility)
  /// [trustScore] - User's trust score (for protocol eligibility)
  /// [authorizedBrands] - List of brand IDs user is authorized for (employee verification)
  static FacetValidationResult validate({
    required String facetId,
    bool hasHandle = false,
    int breadcrumbCount = 0,
    double trustScore = 0,
    List<String> authorizedBrands = const [],
  }) {
    final normalized = facetId.toLowerCase().trim();

    // 1. Check format first
    final formatResult = _validateFormat(normalized);
    if (formatResult != null) {
      return formatResult;
    }

    // 2. Check if it's a protocol facet
    if (ProtocolFacets.isProtocolFacet(normalized)) {
      return _validateProtocolFacet(
        normalized,
        hasHandle: hasHandle,
        breadcrumbCount: breadcrumbCount,
        trustScore: trustScore,
      );
    }

    // 3. Check if it's blocked
    if (BlockedFacets.isBlocked(normalized)) {
      return _validateBlockedFacet(
        normalized,
        authorizedBrands: authorizedBrands,
      );
    }

    // 4. Available for user-defined use!
    return FacetValidationResult(
      type: FacetValidationType.available,
      canCreate: true,
      message: 'Facet "$normalized" is available',
    );
  }

  // ============================================================
  // FORMAT VALIDATION
  // ============================================================

  static FacetValidationResult? _validateFormat(String id) {
    // Check empty
    if (id.isEmpty) {
      return const FacetValidationResult(
        type: FacetValidationType.invalidFormat,
        canCreate: false,
        message: 'Facet ID cannot be empty',
        formatError: 'empty',
      );
    }

    // Check minimum length
    if (id.length < minLength) {
      return FacetValidationResult(
        type: FacetValidationType.invalidFormat,
        canCreate: false,
        message: 'Facet ID must be at least $minLength characters',
        formatError: 'too_short',
      );
    }

    // Check maximum length
    if (id.length > maxLength) {
      return FacetValidationResult(
        type: FacetValidationType.invalidFormat,
        canCreate: false,
        message: 'Facet ID cannot exceed $maxLength characters',
        formatError: 'too_long',
      );
    }

    // Check valid characters
    if (!validCharsRegex.hasMatch(id)) {
      // Determine specific issue
      if (!RegExp(r'^[a-z]').hasMatch(id)) {
        return const FacetValidationResult(
          type: FacetValidationType.invalidFormat,
          canCreate: false,
          message: 'Facet ID must start with a letter',
          formatError: 'must_start_with_letter',
        );
      }

      // Check for specific invalid characters
      for (final char in invalidChars) {
        if (id.contains(char)) {
          return FacetValidationResult(
            type: FacetValidationType.invalidFormat,
            canCreate: false,
            message: 'Facet ID cannot contain "$char"',
            formatError: 'invalid_char_$char',
          );
        }
      }

      // Check for uppercase
      if (id != id.toLowerCase()) {
        return FacetValidationResult(
          type: FacetValidationType.invalidFormat,
          canCreate: false,
          message: 'Facet ID must be lowercase',
          formatError: 'must_be_lowercase',
          suggestions: [id.toLowerCase()],
        );
      }

      return const FacetValidationResult(
        type: FacetValidationType.invalidFormat,
        canCreate: false,
        message: 'Facet ID can only contain letters, numbers, and underscores',
        formatError: 'invalid_characters',
      );
    }

    return null; // Format is valid
  }

  // ============================================================
  // PROTOCOL FACET VALIDATION
  // ============================================================

  static FacetValidationResult _validateProtocolFacet(
    String id, {
    required bool hasHandle,
    required int breadcrumbCount,
    required double trustScore,
  }) {
    final config = ProtocolFacets.getConfig(id)!;
    
    // Check eligibility
    final eligibility = ProtocolFacets.checkEligibility(
      facetId: id,
      hasHandle: hasHandle,
      breadcrumbCount: breadcrumbCount,
      trustScore: trustScore,
    );

    if (eligibility.isEligible) {
      return FacetValidationResult(
        type: FacetValidationType.protocol,
        canCreate: true,
        message: '${config.icon} ${config.name} - ${config.description}',
        protocolConfig: config,
      );
    } else {
      return FacetValidationResult(
        type: FacetValidationType.protocol,
        canCreate: false,
        message: eligibility.reason ?? 'Not eligible for this protocol facet',
        protocolConfig: config,
      );
    }
  }

  // ============================================================
  // BLOCKED FACET VALIDATION
  // ============================================================

  static FacetValidationResult _validateBlockedFacet(
    String id, {
    required List<String> authorizedBrands,
  }) {
    final info = BlockedFacets.getInfo(id)!;

    // Check if user is authorized for this brand
    if (info.isLicensable && authorizedBrands.contains(id)) {
      return FacetValidationResult(
        type: FacetValidationType.licensed,
        canCreate: true,
        message: 'You are authorized to use $id@ (brand employee)',
        blockedInfo: info,
      );
    }

    // Determine the specific block type
    switch (info.category) {
      case BlockedCategory.system:
        return FacetValidationResult(
          type: FacetValidationType.blockedSystem,
          canCreate: false,
          message: 'Reserved for GNS system operations',
          blockedInfo: info,
          suggestions: _generateSuggestions(id, 'system'),
        );

      case BlockedCategory.brandTech:
      case BlockedCategory.brandFinance:
      case BlockedCategory.brandConsumer:
      case BlockedCategory.brandMedia:
      case BlockedCategory.brandCrypto:
        return FacetValidationResult(
          type: FacetValidationType.blockedBrand,
          canCreate: false,
          message: 'Trademark protection: "${id}" is a registered brand',
          blockedInfo: info,
          suggestions: _generateSuggestions(id, 'brand'),
        );

      case BlockedCategory.government:
        return FacetValidationResult(
          type: FacetValidationType.blockedGovernment,
          canCreate: false,
          message: 'Reserved: "${id}" is a government/organization identifier',
          blockedInfo: info,
          suggestions: _generateSuggestions(id, 'government'),
        );

      case BlockedCategory.offensive:
        return FacetValidationResult(
          type: FacetValidationType.blockedOffensive,
          canCreate: false,
          message: 'This facet ID is not allowed',
          blockedInfo: info,
        );

      case BlockedCategory.licensed:
        return FacetValidationResult(
          type: FacetValidationType.licensed,
          canCreate: false,
          message: '"$id" is licensed to a trademark owner. Contact them for authorization.',
          blockedInfo: info,
        );
    }
  }

  // ============================================================
  // SUGGESTIONS
  // ============================================================

  static List<String> _generateSuggestions(String id, String context) {
    final suggestions = <String>[];

    switch (context) {
      case 'system':
        // Suggest adding prefix/suffix
        suggestions.add('my_$id');
        suggestions.add('${id}_personal');
        break;

      case 'brand':
        // For brands, suggest alternatives
        suggestions.add('fan_of_$id');
        suggestions.add('${id}_enthusiast');
        suggestions.add('i_love_$id');
        break;

      case 'government':
        suggestions.add('${id}_watcher');
        suggestions.add('${id}_news');
        break;
    }

    // Filter out any suggestions that are also blocked
    return suggestions.where((s) => !BlockedFacets.isBlocked(s)).toList();
  }

  // ============================================================
  // BATCH VALIDATION
  // ============================================================

  /// Validate multiple facet IDs at once
  static Map<String, FacetValidationResult> validateBatch({
    required List<String> facetIds,
    bool hasHandle = false,
    int breadcrumbCount = 0,
    double trustScore = 0,
    List<String> authorizedBrands = const [],
  }) {
    return {
      for (final id in facetIds)
        id: validate(
          facetId: id,
          hasHandle: hasHandle,
          breadcrumbCount: breadcrumbCount,
          trustScore: trustScore,
          authorizedBrands: authorizedBrands,
        ),
    };
  }

  // ============================================================
  // QUICK CHECKS
  // ============================================================

  /// Quick check if a facet ID is available (no details)
  static bool isAvailable(String facetId) {
    final normalized = facetId.toLowerCase().trim();
    
    // Check format
    if (normalized.length < minLength || 
        normalized.length > maxLength ||
        !validCharsRegex.hasMatch(normalized)) {
      return false;
    }

    // Check protocol and blocked
    return !ProtocolFacets.isProtocolFacet(normalized) && 
           !BlockedFacets.isBlocked(normalized);
  }

  /// Check if a facet ID requires special handling
  static bool requiresSpecialHandling(String facetId) {
    final normalized = facetId.toLowerCase().trim();
    return ProtocolFacets.isProtocolFacet(normalized) || 
           BlockedFacets.isBlocked(normalized);
  }
}

/// Extension for UI-friendly validation results
extension FacetValidationResultUI on FacetValidationResult {
  /// Get appropriate icon for the result
  String get icon {
    switch (type) {
      case FacetValidationType.available:
        return '✅';
      case FacetValidationType.protocol:
        return canCreate ? protocolConfig?.icon ?? '🔵' : '⏳';
      case FacetValidationType.blockedSystem:
        return '⚙️';
      case FacetValidationType.blockedBrand:
        return '™️';
      case FacetValidationType.blockedGovernment:
        return '🏛️';
      case FacetValidationType.blockedOffensive:
        return '🚫';
      case FacetValidationType.licensed:
        return canCreate ? '✅' : '🔒';
      case FacetValidationType.invalidFormat:
        return '❌';
    }
  }

  /// Get color for UI (as hex string for flexibility)
  String get colorHex {
    switch (type) {
      case FacetValidationType.available:
        return '#10B981'; // Green
      case FacetValidationType.protocol:
        return canCreate ? '#3B82F6' : '#F59E0B'; // Blue or Amber
      case FacetValidationType.blockedSystem:
      case FacetValidationType.blockedGovernment:
        return '#6B7280'; // Gray
      case FacetValidationType.blockedBrand:
        return '#F59E0B'; // Amber
      case FacetValidationType.blockedOffensive:
        return '#EF4444'; // Red
      case FacetValidationType.licensed:
        return canCreate ? '#10B981' : '#8B5CF6'; // Green or Purple
      case FacetValidationType.invalidFormat:
        return '#EF4444'; // Red
    }
  }

  /// Get action text for button
  String? get actionText {
    switch (type) {
      case FacetValidationType.available:
        return 'Create Facet';
      case FacetValidationType.protocol:
        return canCreate ? 'Activate ${protocolConfig?.name}' : null;
      case FacetValidationType.licensed:
        return canCreate ? 'Activate Brand Facet' : 'Request Access';
      default:
        return null;
    }
  }
}
