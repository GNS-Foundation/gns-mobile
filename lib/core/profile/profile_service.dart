// Profile Service - Phase 4c
//
// Central service coordinating all profile-related operations:
// - Profile management (read/update)
// - Identity lookup (by handle or public key)
// - Contact management
// - QR code generation/parsing
// - Profile Facets (Phase 4c)
//
// Location: lib/core/profile/profile_service.dart

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:convert/convert.dart';

import '../gns/identity_wallet.dart';
import '../gns/gns_record.dart';
import '../crypto/identity_keypair.dart';
import '../crypto/secure_storage.dart';
import '../contacts/contact_entry.dart';
import '../contacts/contact_storage.dart';
import '../network/gns_network_service.dart';
import 'profile_module.dart';
import 'identity_view_data.dart';
import 'profile_facet.dart';
import 'facet_storage.dart';

class ProfileService {
  static final ProfileService _instance = ProfileService._internal();
  factory ProfileService() => _instance;
  ProfileService._internal();

  final _wallet = IdentityWallet();
  final _network = GnsNetworkService();
  final _contacts = ContactStorage();
  final _secureStorage = SecureStorageService();
  final _facetStorage = FacetStorage();

  bool _initialized = false;

  /// Initialize the service
  Future<void> initialize() async {
    if (_initialized) return;

    await _contacts.initialize();
    await _facetStorage.initialize();
    _initialized = true;
    debugPrint('ProfileService initialized');
  }

  Future<void> _ensureInitialized() async {
    if (!_initialized) await initialize();
  }

  // ==================== OWN PROFILE ====================

  /// Get own identity view data
  Future<IdentityViewData?> getMyIdentity() async {
    await _ensureInitialized();

    if (!_wallet.hasIdentity) return null;

    final info = await _wallet.getIdentityInfo();
    final record = _wallet.localRecord;
    final profile = record != null ? ProfileModule.fromRecord(record) : null;

    // Get last breadcrumb location if available
    final lastBreadcrumbAt = await _secureStorage.readLastBreadcrumbAt();

    return IdentityViewData(
      publicKey: info.publicKey ?? '',
      handle: info.claimedHandle ?? info.reservedHandle,
      displayName: profile?.displayName,
      bio: profile?.bio,
      avatarUrl: profile?.avatarUrl,
      links: profile?.links ?? [],
      trustScore: info.trustScore,
      breadcrumbCount: info.breadcrumbCount,
      daysSinceCreation: info.daysSinceCreation,
      createdAt: DateTime.now().subtract(Duration(days: info.daysSinceCreation)),
      lastSeen: lastBreadcrumbAt,
      isOwnIdentity: true,
      isContact: false,
      chainValid: info.chainValid,
    );
  }

  /// Get own profile data
  Future<ProfileData?> getMyProfile() async {
    if (!_wallet.hasIdentity) return null;
    final record = _wallet.localRecord;
    if (record == null) return null;
    return ProfileModule.fromRecord(record);
  }

  /// Update own profile
  Future<ProfileUpdateResult> updateProfile(ProfileData profile) async {
    await _ensureInitialized();

    if (!_wallet.hasIdentity) {
      return ProfileUpdateResult(success: false, error: 'No identity');
    }

    try {
      // Update local record with new profile module
      final success = await _wallet.updateProfileModule(profile);
      
      if (!success) {
        return ProfileUpdateResult(success: false, error: 'Failed to update local record');
      }

      // Try to sync to network (don't fail if network is unavailable)
      bool syncedToNetwork = false;
      try {
        syncedToNetwork = await _network.syncRecord();
      } catch (e) {
        debugPrint('Network sync failed (non-fatal): $e');
      }

      return ProfileUpdateResult(
        success: true,
        message: syncedToNetwork ? 'Profile updated' : 'Profile saved locally',
        syncedToNetwork: syncedToNetwork,
      );
    } catch (e) {
      debugPrint('Profile update error: $e');
      return ProfileUpdateResult(success: false, error: e.toString());
    }
  }

  // ==================== FACETS (Phase 4c) ====================

  /// Get all facets for current identity
  Future<List<ProfileFacet>> getFacets() async {
    await _ensureInitialized();
    return _facetStorage.getAllFacets();
  }

  /// Get a specific facet
  Future<ProfileFacet?> getFacet(String id) async {
    await _ensureInitialized();
    return _facetStorage.getFacet(id);
  }

  /// Get the default facet
  Future<ProfileFacet?> getDefaultFacet() async {
    await _ensureInitialized();
    return _facetStorage.getDefaultFacet();
  }

  /// Save a facet
  Future<void> saveFacet(ProfileFacet facet) async {
    await _ensureInitialized();
    await _facetStorage.saveFacet(facet);
  }

  /// Delete a facet
  Future<void> deleteFacet(String id) async {
    await _ensureInitialized();
    await _facetStorage.deleteFacet(id);
  }

  /// Set the default facet
  Future<void> setDefaultFacet(String id) async {
    await _ensureInitialized();
    await _facetStorage.setDefaultFacet(id);
  }

  /// Migrate existing ProfileData to default facet
  Future<void> migrateProfileToFacets() async {
    await _ensureInitialized();
    final profile = await getMyProfile();
    await _facetStorage.migrateFromProfileData(profile);
  }

  /// Get facet collection
  Future<FacetCollection> getFacetCollection() async {
    await _ensureInitialized();
    return _facetStorage.getFacetCollection();
  }

  // ==================== IDENTITY LOOKUP ====================

  /// Look up identity by handle
  Future<IdentityLookupResult> lookupByHandle(String handle) async {
    await _ensureInitialized();

    final cleanHandle = handle.replaceAll('@', '').toLowerCase().trim();
    
    if (cleanHandle.isEmpty) {
      return IdentityLookupResult(success: false, error: 'Empty handle');
    }

    try {
      // Check if it's our own handle
      final myInfo = await _wallet.getIdentityInfo();
      if (myInfo.claimedHandle == cleanHandle || myInfo.reservedHandle == cleanHandle) {
        final myIdentity = await getMyIdentity();
        if (myIdentity != null) {
          return IdentityLookupResult(success: true, identity: myIdentity);
        }
      }

      // Check local contacts first
      final localContact = await _contacts.getContactByHandle(cleanHandle);
      
      // Lookup on network
      GnsRecord? record;
      try {
        record = await _network.lookupHandle(cleanHandle);
      } catch (e) {
        debugPrint('Network lookup failed: $e');
      }
      
      if (record == null) {
        return IdentityLookupResult(success: false, error: 'Handle not found');
      }

      final identity = IdentityViewData.fromRecord(
        record,
        isContact: localContact != null,
      );

      // Add to search history
      await _contacts.addSearchHistory(SearchHistoryEntry(
        query: '@$cleanHandle',
        resultPublicKey: record.identity,
        resultHandle: cleanHandle,
      ));

      return IdentityLookupResult(success: true, identity: identity);
    } catch (e) {
      debugPrint('Handle lookup error: $e');
      return IdentityLookupResult(success: false, error: 'Lookup failed: $e');
    }
  }

  /// Look up identity by public key
  Future<IdentityLookupResult> lookupByPublicKey(String publicKey) async {
    await _ensureInitialized();

    final cleanKey = publicKey.trim().toLowerCase();
    
    if (cleanKey.length < 16) {
      return IdentityLookupResult(success: false, error: 'Invalid public key');
    }

    try {
      // Check if it's our own key
      final myInfo = await _wallet.getIdentityInfo();
      if (myInfo.publicKey?.toLowerCase() == cleanKey) {
        final myIdentity = await getMyIdentity();
        if (myIdentity != null) {
          return IdentityLookupResult(success: true, identity: myIdentity);
        }
      }

      // Check local contacts first
      final localContact = await _contacts.getContact(cleanKey);

      // Lookup on network
      GnsRecord? record;
      try {
        record = await _network.lookupPublicKey(cleanKey);
      } catch (e) {
        debugPrint('Network lookup failed: $e');
      }
      
      if (record == null) {
        return IdentityLookupResult(success: false, error: 'Identity not found');
      }

      final identity = IdentityViewData.fromRecord(
        record,
        isContact: localContact != null,
      );

      // Add to search history
      await _contacts.addSearchHistory(SearchHistoryEntry(
        query: cleanKey.substring(0, 16),
        resultPublicKey: record.identity,
        resultHandle: record.handle,
      ));

      return IdentityLookupResult(success: true, identity: identity);
    } catch (e) {
      debugPrint('Public key lookup error: $e');
      return IdentityLookupResult(success: false, error: 'Lookup failed: $e');
    }
  }

  /// Search by handle or public key (auto-detect)
  Future<IdentityLookupResult> search(String query) async {
    final trimmed = query.trim();
    
    if (trimmed.isEmpty) {
      return IdentityLookupResult(success: false, error: 'Empty query');
    }

    if (trimmed.startsWith('@')) {
      return lookupByHandle(trimmed);
    }

    // If it looks like a hex string, try as public key
    if (RegExp(r'^[0-9a-fA-F]{16,}$').hasMatch(trimmed)) {
      return lookupByPublicKey(trimmed);
    }

    // Otherwise try as handle
    return lookupByHandle(trimmed);
  }

  // ==================== CONTACTS ====================

  /// Get all contacts
  Future<List<ContactEntry>> getContacts() async {
    await _ensureInitialized();
    return _contacts.getAllContacts();
  }

  /// Get favorite contacts
  Future<List<ContactEntry>> getFavorites() async {
    await _ensureInitialized();
    return _contacts.getFavorites();
  }

  /// Get recent contacts
  Future<List<ContactEntry>> getRecentContacts({int limit = 10}) async {
    await _ensureInitialized();
    return _contacts.getRecentContacts(limit: limit);
  }

  /// Add a contact from identity data
  Future<bool> addContact(IdentityViewData identity, {String? nickname}) async {
    await _ensureInitialized();

    try {
      final contact = ContactEntry(
        publicKey: identity.publicKey,
        handle: identity.handle,
        displayName: identity.displayName,
        avatarUrl: identity.avatarUrl,
        trustScore: identity.trustScore,
        nickname: nickname,
      );

      await _contacts.addContact(contact);
      debugPrint('Contact added: ${contact.displayTitle}');
      return true;
    } catch (e) {
      debugPrint('Add contact error: $e');
      return false;
    }
  }

  /// Remove contact
  Future<void> removeContact(String publicKey) async {
    await _ensureInitialized();
    await _contacts.deleteContact(publicKey);
  }

  /// Check if identity is a contact
  Future<bool> isContact(String publicKey) async {
    await _ensureInitialized();
    return _contacts.hasContact(publicKey);
  }

  /// Update contact nickname
  Future<void> updateContactNickname(String publicKey, String nickname) async {
    await _ensureInitialized();
    final contact = await _contacts.getContact(publicKey);
    if (contact != null) {
      await _contacts.updateContact(contact.copyWith(nickname: nickname));
    }
  }

  /// Update contact notes
  Future<void> updateContactNotes(String publicKey, String notes) async {
    await _ensureInitialized();
    final contact = await _contacts.getContact(publicKey);
    if (contact != null) {
      await _contacts.updateContact(contact.copyWith(notes: notes));
    }
  }

  /// Toggle contact favorite
  Future<void> toggleFavorite(String publicKey) async {
    await _ensureInitialized();
    await _contacts.toggleFavorite(publicKey);
  }

  /// Sync contact from network (refresh cached data)
  Future<bool> syncContact(String publicKey) async {
    await _ensureInitialized();

    try {
      final record = await _network.lookupPublicKey(publicKey);
      if (record == null) return false;

      final contact = await _contacts.getContact(publicKey);
      if (contact == null) return false;

      final profile = ProfileModule.fromRecord(record);

      await _contacts.updateContact(contact.copyWith(
        handle: record.handle,
        displayName: profile?.displayName,
        avatarUrl: profile?.avatarUrl,
        trustScore: record.trustScore,
        lastSynced: DateTime.now(),
      ));

      return true;
    } catch (e) {
      debugPrint('Sync contact error: $e');
      return false;
    }
  }

  // ==================== SEARCH HISTORY ====================

  /// Get recent searches
  Future<List<SearchHistoryEntry>> getRecentSearches({int limit = 10}) async {
    await _ensureInitialized();
    return _contacts.getRecentSearches(limit: limit);
  }

  /// Clear search history
  Future<void> clearSearchHistory() async {
    await _ensureInitialized();
    await _contacts.clearSearchHistory();
  }

  // ==================== QR CODES ====================

  /// Generate QR payload for own identity
  Future<String?> generateQrPayload() async {
    if (!_wallet.hasIdentity) return null;

    try {
      final info = await _wallet.getIdentityInfo();
      final profile = await getMyProfile();

      final payload = {
        'version': 1,
        'type': 'identity',
        'public_key': info.publicKey,
        if (info.claimedHandle != null) 'handle': info.claimedHandle,
        if (profile?.displayName != null) 'display_name': profile!.displayName,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      };

      // Sign the payload
      final dataToSign = jsonEncode(payload);
      final signature = await _wallet.signString(dataToSign);
      
      if (signature == null) return null;

      payload['signature'] = signature;

      // Encode as base64
      final jsonStr = jsonEncode(payload);
      final base64Payload = base64Encode(utf8.encode(jsonStr));

      return 'gns://identity/$base64Payload';
    } catch (e) {
      debugPrint('QR generation error: $e');
      return null;
    }
  }

  /// Generate QR payload with specific facet (Phase 4c)
  Future<String?> generateQrPayloadWithFacet({String? facetId}) async {
    if (!_wallet.hasIdentity) return null;

    try {
      final info = await _wallet.getIdentityInfo();
      
      // Get facet data
      ProfileFacet? facet;
      if (facetId != null) {
        facet = await getFacet(facetId);
      } else {
        facet = await getDefaultFacet();
      }

      final payload = <String, dynamic>{
        'type': 'gns-identity',
        'version': 1,
        'pk': info.publicKey,
        if (info.claimedHandle != null) 'handle': info.claimedHandle,
        if (facet != null && facet.id != 'default') 'facet': facet.id,
        if (facet?.displayName != null) 'display_name': facet!.displayName,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      };

      return jsonEncode(payload);
    } catch (e) {
      debugPrint('QR generation error: $e');
      return null;
    }
  }

  /// Parse QR payload and return identity data
  Future<QrParseResult> parseQrPayload(String qrData) async {
    try {
      // Try to parse as JSON first (new facet format)
      Map<String, dynamic>? payload;
      
      if (qrData.startsWith('{')) {
        payload = jsonDecode(qrData) as Map<String, dynamic>;
      } else if (qrData.startsWith('gns://identity/')) {
        final base64Payload = qrData.substring('gns://identity/'.length);
        final jsonStr = utf8.decode(base64Decode(base64Payload));
        payload = jsonDecode(jsonStr) as Map<String, dynamic>;
      } else if (qrData.startsWith('gns://')) {
        return QrParseResult(success: false, error: 'Unknown GNS QR type');
      } else {
        // Try as raw base64
        try {
          final jsonStr = utf8.decode(base64Decode(qrData));
          payload = jsonDecode(jsonStr) as Map<String, dynamic>;
        } catch (_) {
          return QrParseResult(success: false, error: 'Invalid QR format');
        }
      }

      // Support both old and new payload formats
      final publicKey = payload['pk'] as String? ?? payload['public_key'] as String?;
      if (publicKey == null || publicKey.length < 32) {
        return QrParseResult(success: false, error: 'Invalid public key in QR');
      }

      // Extract facet ID (Phase 4c)
      final facetId = payload['facet'] as String?;
      final handle = payload['handle'] as String?;
      final displayName = payload['display_name'] as String?;

      // Check timestamp if present (reject if older than 24 hours)
      final timestampStr = payload['timestamp'] as String?;
      if (timestampStr != null) {
        final timestamp = DateTime.parse(timestampStr);
        if (DateTime.now().difference(timestamp).inHours > 24) {
          return QrParseResult(success: false, error: 'QR code expired');
        }
      }

      // Verify signature if present
      final signature = payload['signature'] as String?;
      if (signature != null) {
        final dataWithoutSig = Map<String, dynamic>.from(payload);
        dataWithoutSig.remove('signature');
        
        final isValid = await GnsKeypair.verifyHex(
          publicKey,
          hex.encode(utf8.encode(jsonEncode(dataWithoutSig))),
          signature,
        );

        if (!isValid) {
          return QrParseResult(success: false, error: 'Invalid signature');
        }
      }

      // Look up full identity from network
      final lookupResult = await lookupByPublicKey(publicKey);
      
      if (lookupResult.success && lookupResult.identity != null) {
        return QrParseResult(
          success: true,
          identity: lookupResult.identity,
          qrHandle: handle,
          qrDisplayName: displayName,
          facetId: facetId,
        );
      }

      // If not found on network, return basic info from QR
      final basicIdentity = IdentityViewData(
        publicKey: publicKey,
        handle: handle,
        displayName: displayName,
        trustScore: 0,
        breadcrumbCount: 0,
        daysSinceCreation: 0,
        createdAt: DateTime.now(),
      );

      return QrParseResult(
        success: true,
        identity: basicIdentity,
        notFoundOnNetwork: true,
        facetId: facetId,
      );
    } catch (e) {
      debugPrint('QR parse error: $e');
      return QrParseResult(success: false, error: 'Failed to parse QR: $e');
    }
  }

  // ==================== UTILITY ====================

  /// Get contact count
  Future<int> getContactCount() async {
    await _ensureInitialized();
    return _contacts.getContactCount();
  }
}

// ==================== RESULT CLASSES ====================

class ProfileUpdateResult {
  final bool success;
  final String? message;
  final String? error;
  final bool syncedToNetwork;

  ProfileUpdateResult({
    required this.success,
    this.message,
    this.error,
    this.syncedToNetwork = false,
  });
}

class IdentityLookupResult {
  final bool success;
  final IdentityViewData? identity;
  final String? error;

  IdentityLookupResult({
    required this.success,
    this.identity,
    this.error,
  });
}

class QrParseResult {
  final bool success;
  final IdentityViewData? identity;
  final String? error;
  final String? qrHandle;
  final String? qrDisplayName;
  final bool notFoundOnNetwork;
  final String? facetId;  // Phase 4c

  QrParseResult({
    required this.success,
    this.identity,
    this.error,
    this.qrHandle,
    this.qrDisplayName,
    this.notFoundOnNetwork = false,
    this.facetId,
  });
}
