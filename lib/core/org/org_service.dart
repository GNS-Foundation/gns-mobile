/// Organization Service - Unified org registration management
/// 
/// Handles the full org registration flow:
/// 1. Register → Creates pending registration
/// 2. Verify DNS → Checks TXT record and updates status
/// 3. Activate → Links admin public key to namespace
/// 
/// Location: lib/core/org/org_service.dart

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'org_storage.dart';

/// Result wrapper for org operations
class OrgResult<T> {
  final bool success;
  final T? data;
  final String? error;
  
  OrgResult.success(this.data) : success = true, error = null;
  OrgResult.failure(this.error) : success = false, data = null;
}

/// Organization service singleton
class OrgService extends ChangeNotifier {
  static OrgService? _instance;
  static OrgService get instance => _instance ??= OrgService._();
  OrgService._();
  
  final _storage = OrgStorage();
  static const _apiBase = 'https://gns-browser-production.up.railway.app';
  
  List<OrgRegistration> _registrations = [];
  bool _loading = false;
  
  /// All registrations
  List<OrgRegistration> get registrations => _registrations;
  
  /// Pending registrations (need DNS verification)
  List<OrgRegistration> get pendingRegistrations => 
    _registrations.where((r) => r.isPending).toList();
  
  /// Verified registrations (ready to activate)
  List<OrgRegistration> get verifiedRegistrations => 
    _registrations.where((r) => r.isVerified).toList();
  
  /// Active registrations (fully activated)
  List<OrgRegistration> get activeRegistrations => 
    _registrations.where((r) => r.isActive).toList();
  
  /// Has any registrations
  bool get hasRegistrations => _registrations.isNotEmpty;
  
  /// Is loading
  bool get isLoading => _loading;
  
  /// Initialize service and load saved registrations
  Future<void> initialize() async {
    await _storage.initialize();
    await _loadRegistrations();
  }
  
  Future<void> _loadRegistrations() async {
    _registrations = await _storage.getAllRegistrations();
    notifyListeners();
  }
  
  /// Check if a namespace is available
  Future<OrgResult<Map<String, dynamic>>> checkAvailability(String namespace) async {
    try {
      final clean = namespace.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      final response = await http.get(
        Uri.parse('$_apiBase/org/check/$clean'),
      ).timeout(const Duration(seconds: 10));
      
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        return OrgResult.success(data['data']);
      }
      return OrgResult.failure(data['error'] ?? 'Check failed');
    } catch (e) {
      return OrgResult.failure('Network error: $e');
    }
  }
  
  /// Register a new organization namespace
  Future<OrgResult<OrgRegistration>> register({
    required String namespace,
    required String organizationName,
    required String email,
    required String website,
    String? description,
    String tier = 'starter',
  }) async {
    _loading = true;
    notifyListeners();
    
    try {
      final clean = namespace.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      final domain = _extractDomain(website);
      
      final response = await http.post(
        Uri.parse('$_apiBase/org/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'namespace': clean,
          'organization_name': organizationName,
          'email': email,
          'website': website,
          'domain': domain,
          'description': description,
          'tier': tier,
        }),
      ).timeout(const Duration(seconds: 15));
      
      final data = jsonDecode(response.body);
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        final registration = OrgRegistration(
          id: data['data']?['registration_id'] ?? '',
          namespace: clean,
          organizationName: organizationName,
          domain: domain,
          email: email,
          description: description,
          tier: tier,
          verificationCode: data['data']?['verification_code'] ?? '',
          status: OrgStatus.pending,
          createdAt: DateTime.now(),
        );
        
        await _storage.saveRegistration(registration);
        await _loadRegistrations();
        
        _loading = false;
        notifyListeners();
        return OrgResult.success(registration);
      }
      
      _loading = false;
      notifyListeners();
      return OrgResult.failure(data['error'] ?? 'Registration failed');
    } catch (e) {
      _loading = false;
      notifyListeners();
      return OrgResult.failure('Network error: $e');
    }
  }
  
  /// Verify DNS for a pending registration
  Future<OrgResult<OrgRegistration>> verifyDns(String namespace) async {
    _loading = true;
    notifyListeners();
    
    try {
      final reg = await _storage.getByNamespace(namespace);
      if (reg == null) {
        _loading = false;
        notifyListeners();
        return OrgResult.failure('Registration not found locally');
      }
      
      final response = await http.post(
        Uri.parse('$_apiBase/org/verify'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'registration_id': reg.id,
          'domain': reg.domain,
          'verification_code': reg.verificationCode,
        }),
      ).timeout(const Duration(seconds: 30));
      
      final data = jsonDecode(response.body);
      
      if (response.statusCode == 200) {
        final innerData = data['data'] ?? data;
        if (innerData['verified'] == true) {
          // Update local status
          final updated = reg.copyWith(
            status: OrgStatus.verified,
            verifiedAt: DateTime.now(),
          );
          await _storage.saveRegistration(updated);
          await _loadRegistrations();
          
          _loading = false;
          notifyListeners();
          return OrgResult.success(updated);
        }
        
        // DNS not found yet
        _loading = false;
        notifyListeners();
        return OrgResult.failure(innerData['message'] ?? 'DNS record not found. Please wait for propagation.');
      }
      
      _loading = false;
      notifyListeners();
      return OrgResult.failure(data['error'] ?? 'Verification failed');
    } catch (e) {
      _loading = false;
      notifyListeners();
      return OrgResult.failure('Network error: $e');
    }
  }
  
  /// Activate a verified registration with admin public key
  Future<OrgResult<OrgRegistration>> activate(String namespace, String adminPk) async {
    _loading = true;
    notifyListeners();
    
    try {
      final reg = await _storage.getByNamespace(namespace);
      if (reg == null) {
        _loading = false;
        notifyListeners();
        return OrgResult.failure('Registration not found locally');
      }
      
      final response = await http.post(
        Uri.parse('$_apiBase/org/$namespace/activate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'admin_pk': adminPk,
          'email': reg.email,
        }),
      ).timeout(const Duration(seconds: 15));
      
      final data = jsonDecode(response.body);
      
      if (response.statusCode == 200 && data['success'] == true) {
        // Update local status
        final updated = reg.copyWith(
          status: OrgStatus.active,
          adminPk: adminPk,
        );
        await _storage.saveRegistration(updated);
        await _loadRegistrations();
        
        _loading = false;
        notifyListeners();
        return OrgResult.success(updated);
      }
      
      _loading = false;
      notifyListeners();
      return OrgResult.failure(data['error'] ?? 'Activation failed');
    } catch (e) {
      _loading = false;
      notifyListeners();
      return OrgResult.failure('Network error: $e');
    }
  }
  
  /// Sync local registrations with server status
  Future<void> syncWithServer() async {
    _loading = true;
    notifyListeners();
    
    for (final reg in _registrations) {
      try {
        // Check server status
        if (reg.isPending || reg.isVerified) {
          // Try to verify DNS
          final response = await http.post(
            Uri.parse('$_apiBase/org/verify'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'domain': reg.domain,
            }),
          ).timeout(const Duration(seconds: 10));
          
          final data = jsonDecode(response.body);
          if (data['data']?['verified'] == true) {
            await _storage.updateStatus(
              reg.namespace, 
              OrgStatus.verified,
              verifiedAt: DateTime.now(),
            );
          }
        }
        
        // Check if already activated on server
        final statusResponse = await http.get(
          Uri.parse('$_apiBase/org/${reg.namespace}'),
        ).timeout(const Duration(seconds: 10));
        
        if (statusResponse.statusCode == 200) {
          final statusData = jsonDecode(statusResponse.body);
          if (statusData['success'] == true && statusData['data'] != null) {
            // Namespace exists on server = it's active
            await _storage.updateStatus(reg.namespace, OrgStatus.active);
          }
        }
      } catch (e) {
        debugPrint('Error syncing ${reg.namespace}: $e');
      }
    }
    
    await _loadRegistrations();
    _loading = false;
    notifyListeners();
  }
  
  /// Get organization info from server
  Future<OrgResult<Map<String, dynamic>>> getOrgInfo(String namespace) async {
    try {
      final response = await http.get(
        Uri.parse('$_apiBase/org/$namespace'),
      ).timeout(const Duration(seconds: 10));
      
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        return OrgResult.success(data['data']);
      }
      return OrgResult.failure(data['error'] ?? 'Not found');
    } catch (e) {
      return OrgResult.failure('Network error: $e');
    }
  }
  
  /// Delete a local registration
  Future<void> deleteRegistration(String namespace) async {
    await _storage.deleteRegistration(namespace);
    await _loadRegistrations();
  }
  
  /// Extract domain from website URL
  String _extractDomain(String website) {
    String domain = website.toLowerCase().trim();
    domain = domain.replaceAll(RegExp(r'^https?://'), '');
    domain = domain.replaceAll(RegExp(r'^www\.'), '');
    domain = domain.split('/').first;
    return domain;
  }
}
