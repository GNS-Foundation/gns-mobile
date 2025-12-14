// GNS Record - Phase 3A Update
//
// Identity manifest structure (replaces DNS records).
// FIXED: Canonical JSON encoding for signing AND sending.
//
// Location: lib/core/gns/gns_record.dart

import 'dart:convert';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';

// =============================================================================
// CANONICAL JSON UTILITIES (shared between GnsRecord and GnsRecordBuilder)
// =============================================================================

/// Normalize number to match JavaScript JSON.stringify behavior
/// Converts 70.0 to 70 (int) but keeps 70.5 as 70.5 (double)
dynamic canonicalNumber(num value) {
  if (value is double && value == value.truncateToDouble()) {
    return value.toInt();
  }
  return value;
}

/// Recursively sort map keys and normalize values for canonical JSON
dynamic canonicalValue(dynamic value) {
  if (value is Map<String, dynamic>) {
    final sorted = <String, dynamic>{};
    final keys = value.keys.toList()..sort();
    for (final key in keys) {
      sorted[key] = canonicalValue(value[key]);
    }
    return sorted;
  } else if (value is List) {
    return value.map(canonicalValue).toList();
  } else if (value is double && value == value.truncateToDouble()) {
    return value.toInt();
  }
  return value;
}

/// Encode to canonical JSON (sorted keys, normalized numbers)
/// This MUST match the server's canonicalJson() function
String canonicalJsonEncode(Map<String, dynamic> data) {
  return jsonEncode(canonicalValue(data));
}

// =============================================================================
// GNS RECORD
// =============================================================================

class GnsRecord {
  final String identity;
  final String? handle;
  final String? encryptionKey; 
  final List<GnsModule> modules;
  final List<GnsEndpoint> endpoints;
  final List<String> epochRoots;
  final double trustScore;
  final int breadcrumbCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String signature;
  final int version;

  GnsRecord({
    required this.identity,
    this.handle,
    this.encryptionKey, 
    required this.modules,
    required this.endpoints,
    required this.epochRoots,
    required this.trustScore,
    required this.breadcrumbCount,
    required this.createdAt,
    required this.updatedAt,
    required this.signature,
    this.version = 1,
  });

  /// Get the canonical data structure (what was signed)
  /// Keys are sorted alphabetically, numbers normalized
  Map<String, dynamic> get canonicalData {
    return canonicalValue({
      'breadcrumb_count': breadcrumbCount,
      'created_at': createdAt.toUtc().toIso8601String(),
      'encryption_key': encryptionKey,
      'endpoints': endpoints.map((e) => e.toJson()).toList(),
      'epoch_roots': epochRoots,
      'handle': handle,
      'identity': identity,
      'modules': modules.map((m) => m.toJson()).toList(),
      'trust_score': trustScore,
      'updated_at': updatedAt.toUtc().toIso8601String(),
      'version': version,
    }) as Map<String, dynamic>;
  }

  /// Data to sign (canonical JSON string)
  String get dataToSign => canonicalJsonEncode(canonicalData);

  String computeHash() {
    final digest = SHA256Digest();
    final bytes = digest.process(Uint8List.fromList(utf8.encode(dataToSign)));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  String get gnsId => 'gns_${identity.substring(0, 16)}';
  String get displayName => handle != null ? '@$handle' : gnsId;

  /// Convert to JSON for API - includes signature separately
  /// The record_json part uses canonical format (sorted keys, normalized numbers)
  Map<String, dynamic> toJson() {
    // Return canonical data + signature
    final data = canonicalData;
    data['signature'] = signature;
    return data;
  }

  /// Get record_json without signature (for API)
  Map<String, dynamic> toRecordJson() => canonicalData;

  factory GnsRecord.fromJson(Map<String, dynamic> json) {
    return GnsRecord(
      version: json['version'] as int? ?? 1,
      identity: json['identity'] as String,
      handle: json['handle'] as String?,
      encryptionKey: json['encryption_key'] as String?,
      modules: (json['modules'] as List).map((m) => GnsModule.fromJson(m as Map<String, dynamic>)).toList(),
      endpoints: (json['endpoints'] as List).map((e) => GnsEndpoint.fromJson(e as Map<String, dynamic>)).toList(),
      epochRoots: List<String>.from(json['epoch_roots'] as List),
      trustScore: (json['trust_score'] as num).toDouble(),
      breadcrumbCount: json['breadcrumb_count'] as int,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      signature: json['signature'] as String,
    );
  }
}

// =============================================================================
// GNS MODULE
// =============================================================================

class GnsModule {
  final String id;
  final String schema;
  final String? name;
  final String? description;
  final String? dataUrl;
  final bool isPublic;
  final Map<String, dynamic>? config;

  GnsModule({
    required this.id,
    required this.schema,
    this.name,
    this.description,
    this.dataUrl,
    this.isPublic = true,
    this.config,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'schema': schema,
    if (name != null) 'name': name,
    if (description != null) 'description': description,
    if (dataUrl != null) 'data_url': dataUrl,
    'is_public': isPublic,
    if (config != null) 'config': config,
  };

  factory GnsModule.fromJson(Map<String, dynamic> json) {
    return GnsModule(
      id: json['id'] as String,
      schema: json['schema'] as String,
      name: json['name'] as String?,
      description: json['description'] as String?,
      dataUrl: json['data_url'] as String?,
      isPublic: json['is_public'] as bool? ?? true,
      config: json['config'] as Map<String, dynamic>?,
    );
  }
}

abstract class GnsModuleSchemas {
  static const profile = 'gns.module.profile/v1';
  static const feed = 'gns.module.feed/v1';
  static const map = 'gns.module.map/v1';
  static const store = 'gns.module.store/v1';
  static const chat = 'gns.module.chat/v1';
  static const api = 'gns.module.api/v1';
}

// =============================================================================
// GNS ENDPOINT
// =============================================================================

class GnsEndpoint {
  final String type;
  final String protocol;
  final String address;
  final int? port;
  final int priority;
  final bool isActive;

  GnsEndpoint({
    required this.type,
    required this.protocol,
    required this.address,
    this.port,
    this.priority = 0,
    this.isActive = true,
  });

  Map<String, dynamic> toJson() => {
    'type': type,
    'protocol': protocol,
    'address': address,
    if (port != null) 'port': port,
    'priority': priority,
    'is_active': isActive,
  };

  factory GnsEndpoint.fromJson(Map<String, dynamic> json) {
    return GnsEndpoint(
      type: json['type'] as String,
      protocol: json['protocol'] as String,
      address: json['address'] as String,
      port: json['port'] as int?,
      priority: json['priority'] as int? ?? 0,
      isActive: json['is_active'] as bool? ?? true,
    );
  }
}

// =============================================================================
// GNS RECORD BUILDER
// =============================================================================

class GnsRecordBuilder {
  final String identity;
  String? handle;
  String? encryptionKey;
  List<GnsModule> modules = [];
  List<GnsEndpoint> endpoints = [];
  List<String> epochRoots = [];
  double trustScore = 0;
  int breadcrumbCount = 0;
  DateTime? createdAt;
  DateTime? _updatedAt;

  GnsRecordBuilder(this.identity);

  GnsRecordBuilder withHandle(String h) { handle = h; return this; }
  GnsRecordBuilder withEncryptionKey(String key) { encryptionKey = key; return this; }
  GnsRecordBuilder addModule(GnsModule m) { modules.add(m); return this; }
  GnsRecordBuilder addEndpoint(GnsEndpoint e) { endpoints.add(e); return this; }
  GnsRecordBuilder addEpochRoot(String root) { epochRoots.add(root); return this; }
  GnsRecordBuilder withTrust(double score, int breadcrumbs) { trustScore = score; breadcrumbCount = breadcrumbs; return this; }
  GnsRecordBuilder createdOn(DateTime dt) { createdAt = dt; return this; }

  /// Get the updatedAt timestamp (creates one if not set)
  DateTime get updatedAt {
    _updatedAt ??= DateTime.now();
    return _updatedAt!;
  }

  GnsRecord build(String signature) {
    return GnsRecord(
      identity: identity,
      handle: handle,
      encryptionKey: encryptionKey, 
      modules: modules,
      endpoints: endpoints,
      epochRoots: epochRoots,
      trustScore: trustScore,
      breadcrumbCount: breadcrumbCount,
      createdAt: createdAt ?? updatedAt,
      updatedAt: updatedAt,
      signature: signature,
    );
  }

  /// Get canonical data structure (matches GnsRecord.canonicalData)
  Map<String, dynamic> get canonicalData {
    return canonicalValue({
      'breadcrumb_count': breadcrumbCount,
      'created_at': (createdAt ?? updatedAt).toUtc().toIso8601String(),
      'encryption_key': encryptionKey,
      'endpoints': endpoints.map((e) => e.toJson()).toList(),
      'epoch_roots': epochRoots,
      'handle': handle,
      'identity': identity,
      'modules': modules.map((m) => m.toJson()).toList(),
      'trust_score': trustScore,
      'updated_at': updatedAt.toUtc().toIso8601String(),
      'version': 1,
    }) as Map<String, dynamic>;
  }

  /// Data to sign (canonical JSON string)
  /// Uses shared canonicalJsonEncode for consistency
  String get dataToSign => canonicalJsonEncode(canonicalData);
}
