// Discovery Service - Phase 3B.1
//
// Resolves GNS identities by @handle or public key with caching.
//
// Location: lib/core/discovery/discovery_service.dart

import 'package:flutter/foundation.dart';
import '../network/gns_network_service.dart';
import '../profile/identity_view_data.dart';
import '../profile/profile_module.dart';
import '../gns/gns_record.dart';
import '../contacts/contact_storage.dart';

/// Result of a discovery search
class DiscoveryResult {
  final bool success;
  final IdentityViewData? identity;
  final String? error;
  final DiscoverySource source;

  DiscoveryResult({
    required this.success,
    this.identity,
    this.error,
    this.source = DiscoverySource.network,
  });

  factory DiscoveryResult.found(IdentityViewData identity, {DiscoverySource source = DiscoverySource.network}) {
    return DiscoveryResult(success: true, identity: identity, source: source);
  }

  factory DiscoveryResult.notFound(String error) {
    return DiscoveryResult(success: false, error: error);
  }

  factory DiscoveryResult.error(String error) {
    return DiscoveryResult(success: false, error: error);
  }
}

enum DiscoverySource {
  cache,
  network,
  contact,
}

/// Service for discovering GNS identities
class DiscoveryService {
  static final DiscoveryService _instance = DiscoveryService._internal();
  factory DiscoveryService() => _instance;
  DiscoveryService._internal();

  final _network = GnsNetworkService();
  final _contactStorage = ContactStorage();
  
  // In-memory cache: publicKey -> (IdentityViewData, expiry)
  final Map<String, _CacheEntry> _cache = {};
  
  // Cache durations
  static const Duration _successCacheDuration = Duration(minutes: 5);
  static const Duration _notFoundCacheDuration = Duration(minutes: 1);

  /// Search for identity by query (auto-detects handle vs pubkey)
  Future<DiscoveryResult> search(String query) async {
    final trimmed = query.trim();
    
    if (trimmed.isEmpty) {
      return DiscoveryResult.error('Search query is empty');
    }

    // Remove @ prefix if present
    final cleanQuery = trimmed.startsWith('@') ? trimmed.substring(1) : trimmed;

    // Detect if it's a public key (64 hex chars) or handle
    if (_isPublicKey(cleanQuery)) {
      return searchByPublicKey(cleanQuery);
    } else {
      return searchByHandle(cleanQuery);
    }
  }

  /// Search for identity by handle (without @)
  Future<DiscoveryResult> searchByHandle(String handle) async {
    final cleanHandle = handle.toLowerCase().replaceAll('@', '').trim();
    
    if (cleanHandle.isEmpty) {
      return DiscoveryResult.error('Handle is empty');
    }

    if (!_isValidHandle(cleanHandle)) {
      return DiscoveryResult.error('Invalid handle format');
    }

    debugPrint('🔍 DISCOVERY: Searching for handle: @$cleanHandle');

    try {
      // Resolve handle to public key via /aliases endpoint
      final aliasResult = await _network.resolveHandle(cleanHandle);
      
      if (!aliasResult.success || aliasResult.publicKey == null) {
        debugPrint('❌ DISCOVERY: Handle not found: @$cleanHandle');
        return DiscoveryResult.notFound('Handle @$cleanHandle not found');
      }

      debugPrint('✅ DISCOVERY: Handle resolved to: ${aliasResult.publicKey!.substring(0, 16)}...');

      // Now fetch the full record
      return searchByPublicKey(aliasResult.publicKey!);
    } catch (e) {
      debugPrint('❌ DISCOVERY: Search error: $e');
      return DiscoveryResult.error('Search failed: $e');
    }
  }

  /// Search for identity by full public key
  Future<DiscoveryResult> searchByPublicKey(String publicKey) async {
    final cleanKey = publicKey.toLowerCase().trim();
    
    if (!_isPublicKey(cleanKey)) {
      return DiscoveryResult.error('Invalid public key format');
    }

    debugPrint('🔍 DISCOVERY: Searching for pubkey: ${cleanKey.substring(0, 16)}...');

    // Check cache first
    final cached = _getFromCache(cleanKey);
    if (cached != null) {
      debugPrint('📦 DISCOVERY: Found in cache');
      return DiscoveryResult.found(cached, source: DiscoverySource.cache);
    }

    // Check if it's a contact
    final isContact = await _contactStorage.isContact(cleanKey);

    try {
      // Fetch from network
      final record = await _network.fetchRecord(cleanKey);
      
      if (record == null) {
        debugPrint('❌ DISCOVERY: Record not found');
        return DiscoveryResult.notFound('Identity not found');
      }

      // Build IdentityViewData from record
      final identity = IdentityViewData.fromRecord(
        record,
        isContact: isContact,
      );
      
      // Cache it
      _addToCache(cleanKey, identity);

      debugPrint('✅ DISCOVERY: Found: ${identity.displayLabel}');
      return DiscoveryResult.found(identity, source: DiscoverySource.network);
    } catch (e) {
      debugPrint('❌ DISCOVERY: Fetch error: $e');
      return DiscoveryResult.error('Failed to fetch identity: $e');
    }
  }

  /// Get cached identity without network call
  IdentityViewData? getCached(String publicKey) {
    return _getFromCache(publicKey.toLowerCase());
  }

  /// Clear all cached identities
  void clearCache() {
    _cache.clear();
    debugPrint('🗑️ DISCOVERY: Cache cleared');
  }

  /// Clear specific cached identity
  void clearCachedIdentity(String publicKey) {
    _cache.remove(publicKey.toLowerCase());
  }

  // ==================== PRIVATE HELPERS ====================

  bool _isPublicKey(String value) {
    // Public key is 64 hex characters
    if (value.length != 64) return false;
    return RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(value);
  }

  bool _isValidHandle(String handle) {
    // Handle: 3-20 chars, lowercase letters, numbers, underscore
    return RegExp(r'^[a-z0-9_]{3,20}$').hasMatch(handle);
  }

  IdentityViewData? _getFromCache(String publicKey) {
    final entry = _cache[publicKey];
    if (entry == null) return null;
    
    // Check if expired
    if (DateTime.now().isAfter(entry.expiry)) {
      _cache.remove(publicKey);
      return null;
    }
    
    return entry.identity;
  }

  void _addToCache(String publicKey, IdentityViewData identity) {
    _cache[publicKey] = _CacheEntry(
      identity: identity,
      expiry: DateTime.now().add(_successCacheDuration),
    );
  }
}

class _CacheEntry {
  final IdentityViewData identity;
  final DateTime expiry;

  _CacheEntry({required this.identity, required this.expiry});
}
