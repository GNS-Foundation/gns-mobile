/// Organization Storage - Persist org registrations locally
/// 
/// Stores pending and verified organization registrations so users
/// can resume verification after leaving the app.
/// 
/// Location: lib/core/org/org_storage.dart

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Organization registration status
enum OrgStatus {
  pending,    // DNS verification not yet complete
  verified,   // DNS verified, ready to activate
  active,     // Fully activated with admin_pk
  suspended,  // Suspended by admin
}

/// Local organization registration record
class OrgRegistration {
  final String id;
  final String namespace;
  final String organizationName;
  final String domain;
  final String email;
  final String? description;
  final String tier;
  final String verificationCode;
  final OrgStatus status;
  final DateTime createdAt;
  final DateTime? verifiedAt;
  final String? adminPk;

  OrgRegistration({
    required this.id,
    required this.namespace,
    required this.organizationName,
    required this.domain,
    required this.email,
    this.description,
    required this.tier,
    required this.verificationCode,
    required this.status,
    required this.createdAt,
    this.verifiedAt,
    this.adminPk,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'namespace': namespace,
    'organization_name': organizationName,
    'domain': domain,
    'email': email,
    'description': description,
    'tier': tier,
    'verification_code': verificationCode,
    'status': status.name,
    'created_at': createdAt.toIso8601String(),
    'verified_at': verifiedAt?.toIso8601String(),
    'admin_pk': adminPk,
  };

  factory OrgRegistration.fromJson(Map<String, dynamic> json) => OrgRegistration(
    id: json['id'] ?? json['registration_id'] ?? '',
    namespace: json['namespace'] ?? '',
    organizationName: json['organization_name'] ?? '',
    domain: json['domain'] ?? '',
    email: json['email'] ?? '',
    description: json['description'],
    tier: json['tier'] ?? 'starter',
    verificationCode: json['verification_code'] ?? '',
    status: OrgStatus.values.firstWhere(
      (s) => s.name == json['status'],
      orElse: () => OrgStatus.pending,
    ),
    createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
    verifiedAt: json['verified_at'] != null ? DateTime.tryParse(json['verified_at']) : null,
    adminPk: json['admin_pk'],
  );

  OrgRegistration copyWith({
    String? id,
    String? namespace,
    String? organizationName,
    String? domain,
    String? email,
    String? description,
    String? tier,
    String? verificationCode,
    OrgStatus? status,
    DateTime? createdAt,
    DateTime? verifiedAt,
    String? adminPk,
  }) => OrgRegistration(
    id: id ?? this.id,
    namespace: namespace ?? this.namespace,
    organizationName: organizationName ?? this.organizationName,
    domain: domain ?? this.domain,
    email: email ?? this.email,
    description: description ?? this.description,
    tier: tier ?? this.tier,
    verificationCode: verificationCode ?? this.verificationCode,
    status: status ?? this.status,
    createdAt: createdAt ?? this.createdAt,
    verifiedAt: verifiedAt ?? this.verifiedAt,
    adminPk: adminPk ?? this.adminPk,
  );

  /// DNS TXT record value
  String get txtRecordValue => 'gns-verify=$verificationCode';
  
  /// DNS TXT record host
  String get txtRecordHost => '_gns.$domain';
  
  /// Full namespace handle format
  String get namespaceHandle => '$namespace@';
  
  /// Is this registration complete?
  bool get isActive => status == OrgStatus.active;
  
  /// Is this registration pending DNS verification?
  bool get isPending => status == OrgStatus.pending;
  
  /// Is this registration verified but not yet activated?
  bool get isVerified => status == OrgStatus.verified;
}

/// Organization storage service
class OrgStorage {
  static const _storageKey = 'gns_org_registrations';
  
  SharedPreferences? _prefs;
  
  /// Initialize storage
  Future<void> initialize() async {
    _prefs ??= await SharedPreferences.getInstance();
  }
  
  /// Get all stored registrations
  Future<List<OrgRegistration>> getAllRegistrations() async {
    await initialize();
    final json = _prefs!.getString(_storageKey);
    if (json == null) return [];
    
    try {
      final list = jsonDecode(json) as List;
      return list.map((e) => OrgRegistration.fromJson(e)).toList();
    } catch (e) {
      return [];
    }
  }
  
  /// Get registration by namespace
  Future<OrgRegistration?> getByNamespace(String namespace) async {
    final all = await getAllRegistrations();
    try {
      return all.firstWhere((r) => r.namespace == namespace.toLowerCase());
    } catch (_) {
      return null;
    }
  }
  
  /// Get pending registrations
  Future<List<OrgRegistration>> getPendingRegistrations() async {
    final all = await getAllRegistrations();
    return all.where((r) => r.status == OrgStatus.pending).toList();
  }
  
  /// Get verified registrations (ready to activate)
  Future<List<OrgRegistration>> getVerifiedRegistrations() async {
    final all = await getAllRegistrations();
    return all.where((r) => r.status == OrgStatus.verified).toList();
  }
  
  /// Get active registrations
  Future<List<OrgRegistration>> getActiveRegistrations() async {
    final all = await getAllRegistrations();
    return all.where((r) => r.status == OrgStatus.active).toList();
  }
  
  /// Save a registration
  Future<void> saveRegistration(OrgRegistration registration) async {
    await initialize();
    final all = await getAllRegistrations();
    
    // Remove existing with same namespace
    all.removeWhere((r) => r.namespace == registration.namespace);
    
    // Add new
    all.add(registration);
    
    await _prefs!.setString(_storageKey, jsonEncode(all.map((e) => e.toJson()).toList()));
  }
  
  /// Update registration status
  Future<void> updateStatus(String namespace, OrgStatus status, {DateTime? verifiedAt, String? adminPk}) async {
    final reg = await getByNamespace(namespace);
    if (reg == null) return;
    
    await saveRegistration(reg.copyWith(
      status: status,
      verifiedAt: verifiedAt ?? reg.verifiedAt,
      adminPk: adminPk ?? reg.adminPk,
    ));
  }
  
  /// Delete a registration
  Future<void> deleteRegistration(String namespace) async {
    await initialize();
    final all = await getAllRegistrations();
    all.removeWhere((r) => r.namespace == namespace.toLowerCase());
    await _prefs!.setString(_storageKey, jsonEncode(all.map((e) => e.toJson()).toList()));
  }
  
  /// Clear all registrations
  Future<void> clearAll() async {
    await initialize();
    await _prefs!.remove(_storageKey);
  }
}
