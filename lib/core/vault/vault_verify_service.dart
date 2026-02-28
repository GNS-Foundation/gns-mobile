/// Vault Verify Service — Check identity status via vault.gcrumbs.com
///
/// With Option B architecture, the Flutter app does NOT push data to the
/// Vault API. Instead, it continues syncing to gns-backend as before.
/// The Vault API reads from gns-backend automatically.
///
/// This service is for:
///   - Checking how the public Vault API sees our identity
///   - Displaying "Verified on GNS Vault" badge in the app
///   - Looking up other identities via the Vault API
///
/// Architecture:
///   Flutter → gns-backend (existing sync, unchanged)
///   vault.gcrumbs.com → gns-backend (proxy, reads from same source)
///   Flutter → vault.gcrumbs.com (this service, read-only status checks)
///
/// Location: lib/core/vault/vault_verify_service.dart

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import '../gns/identity_wallet.dart';

/// Badge tiers matching TrIP specification
enum BadgeTier {
  unverified,
  seedling,
  explorer,
  navigator,
  trailblazer,
}

extension BadgeTierExtension on BadgeTier {
  String get apiName => name;

  String get emoji {
    switch (this) {
      case BadgeTier.unverified: return '⬜';
      case BadgeTier.seedling: return '🌱';
      case BadgeTier.explorer: return '🧭';
      case BadgeTier.navigator: return '🗺️';
      case BadgeTier.trailblazer: return '🏔️';
    }
  }

  String get label {
    switch (this) {
      case BadgeTier.unverified: return 'Unverified';
      case BadgeTier.seedling: return 'Seedling';
      case BadgeTier.explorer: return 'Explorer';
      case BadgeTier.navigator: return 'Navigator';
      case BadgeTier.trailblazer: return 'Trailblazer';
    }
  }

  static BadgeTier fromString(String tier) {
    switch (tier) {
      case 'seedling': return BadgeTier.seedling;
      case 'explorer': return BadgeTier.explorer;
      case 'navigator': return BadgeTier.navigator;
      case 'trailblazer': return BadgeTier.trailblazer;
      default: return BadgeTier.unverified;
    }
  }
}

/// Result from the Vault verification endpoint
class VaultVerifyResult {
  final bool human;
  final double trustScore;
  final int breadcrumbs;
  final int identityAgeDays;
  final BadgeTier badgeTier;
  final bool meetsRequirements;
  final String verifiedAt;

  VaultVerifyResult({
    required this.human,
    required this.trustScore,
    required this.breadcrumbs,
    required this.identityAgeDays,
    required this.badgeTier,
    required this.meetsRequirements,
    required this.verifiedAt,
  });

  factory VaultVerifyResult.fromJson(Map<String, dynamic> json) => VaultVerifyResult(
    human: json['human'] as bool? ?? false,
    trustScore: (json['trust_score'] as num?)?.toDouble() ?? 0,
    breadcrumbs: json['breadcrumbs'] as int? ?? 0,
    identityAgeDays: json['identity_age_days'] as int? ?? 0,
    badgeTier: BadgeTierExtension.fromString(json['badge_tier'] as String? ?? 'unverified'),
    meetsRequirements: json['meets_requirements'] as bool? ?? false,
    verifiedAt: json['verified_at'] as String? ?? '',
  );

  /// Human-readable summary
  String get summary => '${badgeTier.emoji} ${badgeTier.label} '
      '(${trustScore.toStringAsFixed(0)}% trust, $breadcrumbs crumbs)';
}

/// Public identity info from the Vault API
class VaultIdentityInfo {
  final String publicKey;
  final String? handle;
  final String? displayName;
  final BadgeTier badgeTier;
  final double trustScore;
  final int breadcrumbs;
  final bool humanVerified;
  final String createdAt;

  VaultIdentityInfo({
    required this.publicKey,
    this.handle,
    this.displayName,
    required this.badgeTier,
    required this.trustScore,
    required this.breadcrumbs,
    required this.humanVerified,
    required this.createdAt,
  });

  factory VaultIdentityInfo.fromJson(Map<String, dynamic> json) => VaultIdentityInfo(
    publicKey: json['public_key'] as String? ?? '',
    handle: json['handle'] as String?,
    displayName: json['display_name'] as String?,
    badgeTier: BadgeTierExtension.fromString(json['badge_tier'] as String? ?? 'unverified'),
    trustScore: (json['trust_score'] as num?)?.toDouble() ?? 0,
    breadcrumbs: json['breadcrumbs'] as int? ?? 0,
    humanVerified: json['human_verified'] as bool? ?? false,
    createdAt: json['created_at'] as String? ?? '',
  );
}

class VaultVerifyService {
  static final VaultVerifyService _instance = VaultVerifyService._internal();
  factory VaultVerifyService() => _instance;
  VaultVerifyService._internal();

  /// Production Vault API URL
  static const String vaultApiUrl = 'https://vault.gcrumbs.com';

  /// Test API key (for verify endpoint)
  static const String _devApiKey = 'gns_test_key_development';

  final _wallet = IdentityWallet();

  late final Dio _dio = Dio(BaseOptions(
    baseUrl: vaultApiUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
    headers: {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    },
  ));

  // ==================== HEALTH ====================

  /// Check if the Vault API is reachable and connected to backend
  Future<Map<String, dynamic>?> healthCheck() async {
    try {
      final response = await _dio.get('/v1/health');
      if (response.statusCode == 200) {
        return response.data as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      debugPrint('🔐 Vault health check failed: $e');
      return null;
    }
  }

  /// Quick connectivity check
  Future<bool> isReachable() async {
    final health = await healthCheck();
    return health?['status'] == 'ok';
  }

  // ==================== VERIFY OWN IDENTITY ====================

  /// Check how the Vault API sees our identity.
  /// 
  /// Returns the trust score, badge tier, and human verification status
  /// as computed by the Vault API (which reads from gns-backend).
  /// 
  /// Useful for displaying "Verified on GNS Vault" badge.
  Future<VaultVerifyResult?> checkMyVerification() async {
    if (!_wallet.hasIdentity) return null;

    try {
      final publicKey = _wallet.publicKey ?? '';
      if (publicKey.isEmpty) return null;

      final response = await _dio.post(
        '/v1/verify',
        data: {'public_key': publicKey},
        options: Options(headers: {'X-API-Key': _devApiKey}),
      );

      if (response.statusCode == 200) {
        final result = VaultVerifyResult.fromJson(response.data);
        debugPrint('🔐 Vault verification: ${result.summary}');
        return result;
      }
      return null;
    } catch (e) {
      debugPrint('🔐 Vault verification check failed: $e');
      return null;
    }
  }

  // ==================== LOOKUP ====================

  /// Look up any identity's public info via the Vault API
  Future<VaultIdentityInfo?> lookupIdentity(String publicKey) async {
    try {
      final response = await _dio.get('/v1/identity/$publicKey');
      if (response.statusCode == 200) {
        return VaultIdentityInfo.fromJson(response.data);
      }
      return null;
    } catch (e) {
      debugPrint('🔐 Vault identity lookup failed: $e');
      return null;
    }
  }

  /// Verify any identity's human status
  Future<VaultVerifyResult?> verifyIdentity(String publicKey) async {
    try {
      final response = await _dio.post(
        '/v1/verify',
        data: {'public_key': publicKey},
        options: Options(headers: {'X-API-Key': _devApiKey}),
      );

      if (response.statusCode == 200) {
        return VaultVerifyResult.fromJson(response.data);
      }
      return null;
    } catch (e) {
      debugPrint('🔐 Vault verify failed: $e');
      return null;
    }
  }
}
