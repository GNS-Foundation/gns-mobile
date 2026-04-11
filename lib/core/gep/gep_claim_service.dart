/// GEP Claim Service
///
/// Handles all GEP claim operations: create, fetch, verify DNS.
/// Uses GnsApiClient for HTTP calls to the GNS backend.
///
/// Location: lib/core/gep/gep_claim_service.dart

import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../gns/gns_api_client.dart';
import '../gns/identity_wallet.dart';
import '../chain/chain_storage.dart';
import '../privacy/h3_quantizer.dart';
import 'gep_address.dart';

/// Claim tier levels
enum ClaimTier { visitor, resident, sovereign }

extension ClaimTierExt on ClaimTier {
  String get value {
    switch (this) {
      case ClaimTier.visitor: return 'visitor';
      case ClaimTier.resident: return 'resident';
      case ClaimTier.sovereign: return 'sovereign';
    }
  }

  String get label {
    switch (this) {
      case ClaimTier.visitor: return 'Visitor';
      case ClaimTier.resident: return 'Resident';
      case ClaimTier.sovereign: return 'Sovereign';
    }
  }

  String get emoji {
    switch (this) {
      case ClaimTier.visitor: return '👤';
      case ClaimTier.resident: return '🏠';
      case ClaimTier.sovereign: return '👑';
    }
  }

  int get minBreadcrumbs {
    switch (this) {
      case ClaimTier.visitor: return 1;
      case ClaimTier.resident: return 50;
      case ClaimTier.sovereign: return 50;
    }
  }

  int get minDays {
    switch (this) {
      case ClaimTier.visitor: return 1;
      case ClaimTier.resident: return 30;
      case ClaimTier.sovereign: return 30;
    }
  }
}

/// A GEP claim as returned by the API
class GepClaim {
  final String? id;
  final String gea;
  final String cellIndex;
  final int resolution;
  final String claimTier;
  final String claimantPk;
  final String? claimantHandle;
  final int breadcrumbsInCell;
  final int uniqueDays;
  final String? domain;
  final bool txtVerified;
  final String title;
  final String? description;
  final String? contentUrl;
  final String status;
  final DateTime? createdAt;

  GepClaim({
    this.id,
    required this.gea,
    required this.cellIndex,
    required this.resolution,
    required this.claimTier,
    required this.claimantPk,
    this.claimantHandle,
    required this.breadcrumbsInCell,
    required this.uniqueDays,
    this.domain,
    this.txtVerified = false,
    required this.title,
    this.description,
    this.contentUrl,
    this.status = 'active',
    this.createdAt,
  });

  factory GepClaim.fromJson(Map<String, dynamic> json) {
    return GepClaim(
      id: json['id'] as String?,
      gea: json['gea'] as String,
      cellIndex: json['cell_index'] as String,
      resolution: json['resolution'] as int,
      claimTier: json['claim_tier'] as String,
      claimantPk: json['claimant_pk'] as String,
      claimantHandle: json['claimant_handle'] as String?,
      breadcrumbsInCell: json['breadcrumbs_in_cell'] as int? ?? 0,
      uniqueDays: json['unique_days'] as int? ?? 0,
      domain: json['domain'] as String?,
      txtVerified: json['txt_verified'] as bool? ?? false,
      title: json['title'] as String,
      description: json['description'] as String?,
      contentUrl: json['content_url'] as String?,
      status: json['status'] as String? ?? 'active',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
    );
  }

  bool get isSovereign => claimTier == 'sovereign';
  bool get isResident => claimTier == 'resident';
  bool get isVisitor => claimTier == 'visitor';
  bool get isDnsVerified => txtVerified && domain != null;
}

/// Claims response from the API
class GepClaimsResponse {
  final String gea;
  final int total;
  final GepClaim? sovereign;
  final GepClaim? resident;
  final List<GepClaim> visitors;

  GepClaimsResponse({
    required this.gea,
    required this.total,
    this.sovereign,
    this.resident,
    required this.visitors,
  });

  factory GepClaimsResponse.fromJson(Map<String, dynamic> json) {
    return GepClaimsResponse(
      gea: json['gea'] as String,
      total: json['total'] as int? ?? 0,
      sovereign: json['sovereign'] != null
          ? GepClaim.fromJson(json['sovereign'] as Map<String, dynamic>)
          : null,
      resident: json['resident'] != null
          ? GepClaim.fromJson(json['resident'] as Map<String, dynamic>)
          : null,
      visitors: (json['visitors'] as List<dynamic>? ?? [])
          .map((v) => GepClaim.fromJson(v as Map<String, dynamic>))
          .toList(),
    );
  }

  bool get hasClaims => total > 0;
  bool get hasSovereign => sovereign != null;
}

/// Service for GEP claim operations
class GepClaimService {
  static final GepClaimService _instance = GepClaimService._internal();
  factory GepClaimService() => _instance;
  GepClaimService._internal();

  final _api = GnsApiClient();

  /// Get the user's eligible claim tier based on breadcrumbs at a location
  Future<ClaimTierEligibility> checkEligibility({
    required double lat,
    required double lon,
    int resolution = 7,
  }) async {
    final quantizer = H3Quantizer();
    final cellHex = quantizer.latLonToH3Hex(lat, lon, resolution: resolution);

    // Count breadcrumbs in this cell from local chain
    final chainStorage = ChainStorage();
    final allBlocks = await chainStorage.getAllBlocks();
    
    int breadcrumbsInCell = 0;
    final uniqueDaysSet = <String>{};
    
    for (final block in allBlocks) {
      if (block.locationCell == cellHex) {
        breadcrumbsInCell++;
        uniqueDaysSet.add(
          '${block.timestamp.year}-${block.timestamp.month}-${block.timestamp.day}'
        );
      }
    }

    final uniqueDays = uniqueDaysSet.length;

    // Determine highest eligible tier
    ClaimTier highestTier = ClaimTier.visitor;
    if (breadcrumbsInCell >= ClaimTier.resident.minBreadcrumbs &&
        uniqueDays >= ClaimTier.resident.minDays) {
      highestTier = ClaimTier.resident;
    }

    return ClaimTierEligibility(
      cellIndex: cellHex,
      breadcrumbsInCell: breadcrumbsInCell,
      uniqueDays: uniqueDays,
      highestTier: highestTier,
      canVisitor: breadcrumbsInCell >= ClaimTier.visitor.minBreadcrumbs,
      canResident: breadcrumbsInCell >= ClaimTier.resident.minBreadcrumbs &&
          uniqueDays >= ClaimTier.resident.minDays,
    );
  }

  /// Submit a claim
  Future<GepClaim> submitClaim({
    required double lat,
    required double lon,
    int resolution = 7,
    required ClaimTier tier,
    required String claimantPk,
    required int breadcrumbsInCell,
    required int uniqueDays,
    required String title,
    String? description,
    String? contentUrl,
    String? domain,
    String? delegationCert,
    required String signature,
  }) async {
    try {
      final response = await _api.dio.post('/gep/claims', data: {
        'lat': lat,
        'lon': lon,
        'resolution': resolution,
        'claim_tier': tier.value,
        'claimant_pk': claimantPk,
        'breadcrumbs_in_cell': breadcrumbsInCell,
        'unique_days': uniqueDays,
        'title': title,
        'description': description,
        'content_url': contentUrl,
        'domain': domain,
        'delegation_cert': delegationCert,
        'signature': signature,
      });

      if (response.data['success'] == true) {
        return GepClaim.fromJson(response.data['data'] as Map<String, dynamic>);
      } else {
        throw Exception(response.data['error'] ?? 'Failed to submit claim');
      }
    } catch (e) {
      debugPrint('GEP claim submission error: $e');
      rethrow;
    }
  }

  /// Fetch claims for a GEA
  Future<GepClaimsResponse> getClaims(String gea) async {
    try {
      final response = await _api.dio.get('/gep/claims/$gea');
      if (response.data['success'] == true) {
        return GepClaimsResponse.fromJson(
            response.data['data'] as Map<String, dynamic>);
      }
      return GepClaimsResponse(gea: gea, total: 0, visitors: []);
    } catch (e) {
      debugPrint('GEP claims fetch error: $e');
      return GepClaimsResponse(gea: gea, total: 0, visitors: []);
    }
  }

  /// Fetch claims by public key
  Future<List<GepClaim>> getMyClaims(String publicKey) async {
    try {
      final response = await _api.dio.get('/gep/claims/by-pk/$publicKey');
      if (response.data['success'] == true) {
        final claims = response.data['data']['claims'] as List<dynamic>;
        return claims
            .map((c) => GepClaim.fromJson(c as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (e) {
      debugPrint('GEP my claims fetch error: $e');
      return [];
    }
  }

  /// Update claim content
  Future<GepClaim> updateContent({
    required String claimId,
    required String claimantPk,
    String? title,
    String? description,
    String? contentUrl,
    required String signature,
  }) async {
    final response = await _api.dio.put('/gep/claims/$claimId/content', data: {
      'claimant_pk': claimantPk,
      'title': title,
      'description': description,
      'content_url': contentUrl,
      'signature': signature,
    });

    if (response.data['success'] == true) {
      return GepClaim.fromJson(response.data['data'] as Map<String, dynamic>);
    }
    throw Exception(response.data['error'] ?? 'Failed to update claim');
  }

  /// Verify DNS TXT record for sovereign claim
  Future<DnsVerifyResult> verifyDns({
    required String domain,
    required String gea,
    required String claimantPk,
  }) async {
    try {
      final response = await _api.dio.post('/gep/claims/verify-dns', data: {
        'domain': domain,
        'gea': gea,
        'claimant_pk': claimantPk,
      });

      if (response.data['success'] == true) {
        final data = response.data['data'] as Map<String, dynamic>;
        return DnsVerifyResult(
          verified: data['verified'] as bool? ?? false,
          domain: domain,
          message: data['message'] as String? ?? data['reason'] as String? ?? '',
        );
      }
      return DnsVerifyResult(verified: false, domain: domain, message: 'Request failed');
    } catch (e) {
      return DnsVerifyResult(verified: false, domain: domain, message: '$e');
    }
  }

  /// Get the Physical Web URL for a location
  String getPhysicalWebUrl(double lat, double lon, {int resolution = 7}) {
    return '${_api.nodeUrl}/gep/web/lookup?lat=$lat&lon=$lon&resolution=$resolution';
  }
}

/// Eligibility check result
class ClaimTierEligibility {
  final String cellIndex;
  final int breadcrumbsInCell;
  final int uniqueDays;
  final ClaimTier highestTier;
  final bool canVisitor;
  final bool canResident;

  ClaimTierEligibility({
    required this.cellIndex,
    required this.breadcrumbsInCell,
    required this.uniqueDays,
    required this.highestTier,
    required this.canVisitor,
    required this.canResident,
  });

  bool get canClaim => canVisitor;
  
  String get eligibilityLabel {
    if (canResident) return 'Eligible for Resident claim (${breadcrumbsInCell} crumbs, $uniqueDays days)';
    if (canVisitor) return 'Eligible for Visitor claim ($breadcrumbsInCell crumbs)';
    return 'Drop breadcrumbs here to claim this place';
  }
}

/// DNS verification result
class DnsVerifyResult {
  final bool verified;
  final String domain;
  final String message;

  DnsVerifyResult({
    required this.verified,
    required this.domain,
    required this.message,
  });
}
