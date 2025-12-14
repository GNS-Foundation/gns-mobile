import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../crypto/identity_keypair.dart';
import '../crypto/secure_storage.dart';
import '../chain/breadcrumb_engine.dart';
import '../chain/chain_storage.dart';
import 'gns_record.dart';
import 'gns_api_client.dart';
import '../profile/profile_module.dart';

class IdentityWallet {
  static final IdentityWallet _instance = IdentityWallet._internal();
  factory IdentityWallet() => _instance;
  IdentityWallet._internal();

  final _storage = SecureStorageService();
  final _breadcrumbEngine = BreadcrumbEngine();
  final _chainStorage = ChainStorage();
  final _apiClient = GnsApiClient();

  GnsKeypair? _keypair;
  GnsRecord? _localRecord;
  ProfileData _profileData = ProfileData();
  bool _initialized = false;
  bool _networkAvailable = false;

  bool get isInitialized => _initialized;
  bool get hasIdentity => _keypair != null;
  String? get publicKey => _keypair?.publicKeyHex;
  String? get gnsId => _keypair?.gnsId;
  GnsRecord? get localRecord => _localRecord;
  BreadcrumbEngine get breadcrumbEngine => _breadcrumbEngine;
  bool get networkAvailable => _networkAvailable;

  // ==================== COMMUNICATION SERVICE SUPPORT ====================
  
  /// Get Ed25519 private key bytes (for signatures)
  Uint8List? get privateKeyBytes => _keypair?.privateKey;
  
  /// Get Ed25519 public key bytes (for identity/verification)
  Uint8List? get publicKeyBytes => _keypair?.publicKey;
  
  /// Get X25519 encryption private key bytes (for decryption)
  /// ✅ DUAL-KEY: Separate X25519 key for encryption
  Uint8List? get encryptionPrivateKeyBytes => _keypair?.encryptionPrivateKey;
  
  /// Get X25519 encryption public key bytes (for others to encrypt to us)
  /// ✅ DUAL-KEY: Separate X25519 key for encryption
  Uint8List? get encryptionPublicKeyBytes => _keypair?.encryptionPublicKey;
  
  /// Get X25519 encryption public key as hex string (for sharing with others)
  String? get encryptionPublicKeyHex => _keypair?.encryptionPublicKeyHex;
  
  /// Get current claimed handle (async for storage access)
  Future<String?> getCurrentHandle() async {
    return await _storage.readClaimedHandle();
  }
  
  /// Sign data and return raw bytes (for WebSocket auth)
  Future<Uint8List?> signBytes(Uint8List data) async {
    if (_keypair == null) return null;
    return await _keypair!.sign(data);
  }

  Future<void> initialize() async {
    if (_initialized) return;

    debugPrint('Initializing Identity Wallet...');
    await _checkNetworkStatus();
    await _breadcrumbEngine.initialize();

    // ✅ DUAL-KEY: Load BOTH keys
    final ed25519Key = await _storage.readPrivateKey();
    final x25519Key = await _storage.readX25519PrivateKey();
    
    if (ed25519Key != null && ed25519Key.isNotEmpty && 
        x25519Key != null && x25519Key.isNotEmpty) {
      _keypair = await GnsKeypair.fromHex(
        ed25519PrivateKeyHex: ed25519Key,
        x25519PrivateKeyHex: x25519Key,
      );
      
      // 🔍 DIAGNOSTIC
      final pk = _keypair!.publicKeyHex;
      debugPrint('🔐 LOADED dual-key from keychain: $pk');
      debugPrint('🔐 Ed25519: ${pk.substring(0, 16)}...');
      debugPrint('🔐 X25519:  ${_keypair!.encryptionPublicKeyHex.substring(0, 16)}...');
    }

    await _chainStorage.initialize();
    await _loadOrCreateLocalRecord();
    
    // ✅ FIX: Sync identity to network on every app start
    // This ensures encryption_key is always available for messaging
    _publishInBackground();

    _initialized = true;
    debugPrint('Identity Wallet initialized: $gnsId');
    debugPrint('Network available: $_networkAvailable');
  }

  Future<void> _checkNetworkStatus() async {
    try {
      final health = await _apiClient.healthCheck();
      _networkAvailable = health['status'] == 'healthy';
      debugPrint('Network status: $_networkAvailable');
    } catch (e) {
      _networkAvailable = false;
      debugPrint('Network check failed: $e');
    }
  }

  Future<void> _loadOrCreateLocalRecord() async {
    if (_keypair == null) return;

    final handle = await _storage.readClaimedHandle();
    final stats = await _breadcrumbEngine.getStats();

    final builder = GnsRecordBuilder(_keypair!.publicKeyHex)
      ..withTrust(stats.trustScore, stats.breadcrumbCount)
      // ✅ DUAL-KEY: Add X25519 encryption key to record
      ..withEncryptionKey(_keypair!.encryptionPublicKeyHex);

    if (handle != null) builder.withHandle(handle);
    builder.addModule(ProfileModule.create(_profileData));

    final dataToSign = Uint8List.fromList(utf8.encode(builder.dataToSign));
    final signature = await _keypair!.signToHex(dataToSign);
    _localRecord = builder.build(signature);
  }

  Future<bool> checkIdentityExists() async {
    return await _storage.hasIdentity();
  }

  /// Creates identity AND reserves handle atomically (for welcome screen)
  Future<IdentityCreationResult> createIdentityWithHandle(String handle) async {
    final cleanHandle = handle.toLowerCase().replaceAll('@', '').trim();

    if (!_isValidHandle(cleanHandle)) {
      return IdentityCreationResult(
        success: false,
        error: 'Handle must be 3-20 characters, letters, numbers, underscore only',
      );
    }

    if (_isReservedWord(cleanHandle)) {
      return IdentityCreationResult(success: false, error: 'This handle is reserved');
    }

    try {
      // ✅ DUAL-KEY: Generate BOTH keys
      _keypair = await GnsKeypair.generate();
      
      // ✅ DUAL-KEY: Store BOTH keys separately
      await _storage.storePrivateKey(_keypair!.privateKeyHex);
      await _storage.writeX25519PrivateKey(_keypair!.encryptionPrivateKeyHex);
      await _storage.storePublicKey(_keypair!.publicKeyHex);
      await _storage.storeGnsId(_keypair!.gnsId);
      
      debugPrint('New dual-key identity created: ${_keypair!.gnsId}');
      debugPrint('  Ed25519: ${_keypair!.publicKeyHex.substring(0, 16)}...');
      debugPrint('  X25519:  ${_keypair!.encryptionPublicKeyHex.substring(0, 16)}...');

      await _storage.storeFirstBreadcrumbAt(DateTime.now());
      await _loadOrCreateLocalRecord();

      bool networkReserved = false;
      await _checkNetworkStatus();

      if (_networkAvailable) {
        try {
          final timestamp = DateTime.now().toUtc().toIso8601String();
          final message = 'reserve:$cleanHandle:$timestamp';
          final signature = await _keypair!.signToHex(Uint8List.fromList(utf8.encode(message)));

          final response = await _apiClient.reserveHandle(
            handle: cleanHandle,
            publicKey: _keypair!.publicKeyHex,
            signature: signature,
          );
          networkReserved = response['success'] == true;
          debugPrint('Network reservation: $networkReserved');
        } catch (e) {
          debugPrint('Network reservation failed: $e');
        }
      }

      await _storage.storeReservedHandle(cleanHandle, DateTime.now());
      _publishInBackground();

      return IdentityCreationResult(
        success: true,
        gnsId: _keypair!.gnsId,
        publicKey: _keypair!.publicKeyHex,
        handle: cleanHandle,
        networkReserved: networkReserved,
        message: networkReserved
            ? '@$cleanHandle reserved on GNS Network! Collect 100 breadcrumbs to claim.'
            : '@$cleanHandle reserved locally. Network sync pending.',
      );
    } catch (e) {
      debugPrint('Identity creation failed: $e');
      return IdentityCreationResult(success: false, error: 'Failed to create identity: $e');
    }
  }

  Future<void> createIdentity() async {
    if (_keypair != null) throw Exception('Identity already exists');

    // ✅ DUAL-KEY: Generate BOTH keys
    _keypair = await GnsKeypair.generate();
    
    // ✅ DUAL-KEY: Store BOTH keys separately
    await _storage.storePrivateKey(_keypair!.privateKeyHex);
    await _storage.writeX25519PrivateKey(_keypair!.encryptionPrivateKeyHex);
    await _storage.storePublicKey(_keypair!.publicKeyHex);
    await _storage.storeGnsId(_keypair!.gnsId);
    
    await _loadOrCreateLocalRecord();
    debugPrint('New dual-key identity created: ${_keypair!.gnsId}');
    _publishInBackground();
  }

  void _publishInBackground() {
    Future.microtask(() async {
      try {
        await publishToNetwork();
      } catch (e) {
        debugPrint('Background publish failed: $e');
      }
    });
  }

  Future<bool> publishToNetwork() async {
    if (_keypair == null || _localRecord == null) {
      debugPrint('📡 Cannot publish: keypair or localRecord is null');
      return false;
    }
    await _checkNetworkStatus();
    if (!_networkAvailable) {
      debugPrint('📡 Cannot publish: network unavailable');
      return false;
    }

    try {
      final recordJson = _localRecord!.toJson();
      
      // 🔍 DEBUG: Log what we're sending
      debugPrint('📡 Publishing record to network...');
      debugPrint('   Identity: ${_keypair!.publicKeyHex.substring(0, 16)}...');
      debugPrint('   Encryption Key: ${recordJson['encryption_key']?.toString().substring(0, 16) ?? 'NULL'}...');
      debugPrint('   Handle: ${recordJson['handle'] ?? 'none'}');
      debugPrint('   Signature: ${recordJson['signature']?.toString().substring(0, 16) ?? 'NULL'}...');
      debugPrint('   Signature length: ${recordJson['signature']?.toString().length ?? 0}');
      
      final response = await _apiClient.publishRecord(
        publicKey: _keypair!.publicKeyHex,
        record: recordJson,
      );
      
      if (response['success'] == true) {
        debugPrint('📡 ✅ Published to network successfully!');
        return true;
      } else {
        debugPrint('📡 ❌ Publish failed: ${response['error']} - ${response['message']}');
        return false;
      }
    } catch (e) {
      debugPrint('📡 ❌ Publish exception: $e');
      return false;
    }
  }

  Future<IdentityInfo> getIdentityInfo() async {
    final stats = await _breadcrumbEngine.getStats();
    final handle = await _storage.readClaimedHandle();
    final reservedHandle = await _storage.readReservedHandle();
    final firstBreadcrumbAt = await _storage.readFirstBreadcrumbAt();

    return IdentityInfo(
      publicKey: _keypair?.publicKeyHex,
      gnsId: _keypair?.gnsId,
      claimedHandle: handle,
      reservedHandle: reservedHandle,
      breadcrumbCount: stats.breadcrumbCount,
      trustScore: stats.trustScore,
      daysSinceCreation: stats.daysSinceStart,
      canClaimHandle: stats.canClaimHandle,
      chainValid: stats.chainValid,
      networkAvailable: _networkAvailable,
      firstBreadcrumbAt: firstBreadcrumbAt,
    );
  }

  ProfileData getProfile() => _profileData;

  Future<bool> updateProfile(ProfileData profile) async {
    try {
      _profileData = profile;
      await _loadOrCreateLocalRecord();
      _publishInBackground();
      return true;
    } catch (e) {
      debugPrint('Failed to update profile: $e');
      return false;
    }
  }

  Future<bool> updateProfileModule(ProfileData profile) async {
    try {
      _profileData = profile;
      await _loadOrCreateLocalRecord();
      _publishInBackground();
      return true;
    } catch (e) {
      debugPrint('Failed to update profile module: $e');
      return false;
    }
  }

  Future<HandleReservationResult> reserveHandle(String handle) async {
    final cleanHandle = handle.toLowerCase().replaceAll('@', '').trim();

    if (!_isValidHandle(cleanHandle)) {
      return HandleReservationResult(
        success: false,
        error: 'Handle must be 3-20 characters, letters, numbers, underscore only',
      );
    }

    if (_isReservedWord(cleanHandle)) {
      return HandleReservationResult(success: false, error: 'This handle is reserved');
    }

    bool networkReserved = false;
    await _checkNetworkStatus();

    if (_networkAvailable && _keypair != null) {
      try {
        final checkResponse = await _apiClient.checkHandle(cleanHandle);
        if (checkResponse['success'] == true) {
          final data = checkResponse['data'] as Map<String, dynamic>?;
          if (data?['available'] != true) {
            return HandleReservationResult(success: false, error: '@$cleanHandle is already taken');
          }
        }

        final timestamp = DateTime.now().toUtc().toIso8601String();
        final message = 'reserve:$cleanHandle:$timestamp';
        final signature = await _keypair!.signToHex(Uint8List.fromList(utf8.encode(message)));

        final response = await _apiClient.reserveHandle(
          handle: cleanHandle,
          publicKey: _keypair!.publicKeyHex,
          signature: signature,
        );
        networkReserved = response['success'] == true;
        debugPrint('Network reservation: $networkReserved');
      } catch (e) {
        debugPrint('Network reservation failed: $e');
      }
    }

    await _storage.storeReservedHandle(cleanHandle, DateTime.now());

    return HandleReservationResult(
      success: true,
      handle: cleanHandle,
      expiresAt: DateTime.now().add(const Duration(days: 30)),
      networkReserved: networkReserved,
      message: networkReserved
          ? '@$cleanHandle reserved on GNS Network! Collect 100 breadcrumbs to claim.'
          : '@$cleanHandle reserved locally. Network sync pending.',
    );
  }

  Future<HandleClaimResult> claimHandle() async {
    final reserved = await _storage.readReservedHandle();
    if (reserved == null) {
      return HandleClaimResult(success: false, error: 'No handle reserved');
    }

    final stats = await _breadcrumbEngine.getStats();
    if (!stats.canClaimHandle) {
      return HandleClaimResult(
        success: false,
        error: 'Requirements not met',
        requirements: HandleRequirements(
          breadcrumbsRequired: 100,
          breadcrumbsCurrent: stats.breadcrumbCount,
          trustRequired: 20,
          trustCurrent: stats.trustScore,
        ),
      );
    }

    // Check keypair
    if (_keypair == null) {
      return HandleClaimResult(success: false, error: 'No identity');
    }

    // ✅ PHASE 6: Actually claim on the network!
    await _checkNetworkStatus();
    
    bool networkClaimed = false;
    String? networkError;
    
    if (_networkAvailable) {
      try {
        // Get first breadcrumb timestamp
        final firstBreadcrumbAt = await _storage.readFirstBreadcrumbAt();
        
        // Build the claim with PoT proof
        final claim = {
          'identity': _keypair!.publicKeyHex,
          'proof': {
            'breadcrumb_count': stats.breadcrumbCount,
            'trust_score': stats.trustScore,
            'first_breadcrumb_at': firstBreadcrumbAt?.toUtc().toIso8601String() ?? 
                DateTime.now().toUtc().toIso8601String(),
          },
          'claimed_at': DateTime.now().toUtc().toIso8601String(),
        };
        
        // Sign the entire claim
        final claimJson = jsonEncode({
          'handle': reserved,
          ...claim,
        });
        final signature = await _keypair!.signToHex(
          Uint8List.fromList(utf8.encode(claimJson))
        );
        
        debugPrint('📝 Claiming handle @$reserved on network...');
        debugPrint('   Breadcrumbs: ${stats.breadcrumbCount}');
        debugPrint('   Trust Score: ${stats.trustScore}');
        
        // Call the server
        final response = await _apiClient.claimHandle(
          handle: reserved,
          claim: claim,
          signature: signature,
        );
        
        if (response['success'] == true) {
          networkClaimed = true;
          debugPrint('✅ Handle @$reserved claimed on network!');
        } else {
          networkError = response['error']?.toString() ?? 'Network claim failed';
          debugPrint('❌ Network claim failed: $networkError');
        }
      } catch (e) {
        networkError = e.toString();
        debugPrint('❌ Network claim error: $e');
      }
    } else {
      networkError = 'Network unavailable';
      debugPrint('⚠️ Network unavailable, storing claim locally');
    }

    // Store locally regardless (can sync later)
    await _storage.storeClaimedHandle(reserved);
    await _loadOrCreateLocalRecord();
    
    // Publish updated record to network
    _publishInBackground();

    // Return success with appropriate message
    if (networkClaimed) {
      return HandleClaimResult(
        success: true,
        handle: reserved,
        message: '🎉 @$reserved is now permanently yours on the GNS Network!',
      );
    } else {
      return HandleClaimResult(
        success: true,
        handle: reserved,
        message: '@$reserved claimed locally. Network sync: ${networkError ?? "pending"}',
      );
    }
  }

  bool _isValidHandle(String handle) => RegExp(r'^[a-z0-9_]{3,20}$').hasMatch(handle);
  bool _isReservedWord(String handle) {
    const reserved = ['admin', 'root', 'system', 'gns', 'layer', 'browser', 'support', 'help', 'official', 'verified'];
    return reserved.contains(handle);
  }

  Future<void> startBreadcrumbCollection({Duration? interval}) async {
    await _breadcrumbEngine.startCollection(interval: interval);
  }

  void stopBreadcrumbCollection() => _breadcrumbEngine.stopCollection();

  Future<BreadcrumbDropResult> dropBreadcrumb() async {
    final result = await _breadcrumbEngine.dropBreadcrumb(manual: true);
    await _loadOrCreateLocalRecord();
    return result;
  }

  Future<String?> sign(Uint8List data) async {
    if (_keypair == null) return null;
    return await _keypair!.signToHex(data);
  }

  Future<String?> signString(String message) async {
    if (_keypair == null) return null;
    return await _keypair!.signToHex(Uint8List.fromList(utf8.encode(message)));
  }

  Future<bool> verify(String publicKeyHex, Uint8List message, String signatureHex) async {
    return await GnsKeypair.verifyHex(
      publicKeyHex,
      message.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      signatureHex,
    );
  }

  Future<String> exportIdentity() async {
    // ✅ DUAL-KEY: Export BOTH keys
    final ed25519Key = await _storage.readPrivateKey();
    final x25519Key = await _storage.readX25519PrivateKey();
    final publicKey = await _storage.readPublicKey();
    final gnsId = await _storage.readGnsId();
    final handle = await _storage.readClaimedHandle();
    
    if (ed25519Key == null || x25519Key == null) {
      throw Exception('No identity to export');
    }
    
    final exportData = {
      'version': 3,  // v3 = dual-key
      'ed25519_private': ed25519Key,
      'x25519_private': x25519Key,
      'public_key': publicKey,
      'gns_id': gnsId,
      'claimed_handle': handle,
      'exported_at': DateTime.now().toIso8601String(),
    };
    
    return base64Encode(utf8.encode(jsonEncode(exportData)));
  }

  Future<void> importIdentity(String exportedData) async {
    final decoded = utf8.decode(base64Decode(exportedData));
    final data = jsonDecode(decoded) as Map<String, dynamic>;
    
    final version = data['version'] as int? ?? 1;
    
    if (version >= 3) {
      // ✅ DUAL-KEY: Import BOTH keys
      final ed25519Key = data['ed25519_private'] as String;
      final x25519Key = data['x25519_private'] as String;
      
      await _storage.storePrivateKey(ed25519Key);
      await _storage.writeX25519PrivateKey(x25519Key);
      
      _keypair = await GnsKeypair.fromHex(
        ed25519PrivateKeyHex: ed25519Key,
        x25519PrivateKeyHex: x25519Key,
      );
    } else {
      // Legacy: Single key only (Ed25519)
      final privateKey = data['private_key'] as String;
      
      // Generate NEW X25519 key for old exports
      final tempKeypair = await GnsKeypair.generate();
      
      await _storage.storePrivateKey(privateKey);
      await _storage.writeX25519PrivateKey(tempKeypair.encryptionPrivateKeyHex);
      
      _keypair = await GnsKeypair.fromHex(
        ed25519PrivateKeyHex: privateKey,
        x25519PrivateKeyHex: tempKeypair.encryptionPrivateKeyHex,
      );
      
      debugPrint('⚠️ Imported legacy identity - generated new X25519 key');
    }
    
    // Import metadata
    final publicKey = data['public_key'] as String?;
    final gnsId = data['gns_id'] as String?;
    final handle = data['claimed_handle'] as String?;
    
    if (publicKey != null) await _storage.storePublicKey(publicKey);
    if (gnsId != null) await _storage.storeGnsId(gnsId);
    if (handle != null) await _storage.storeClaimedHandle(handle);
    
    await _loadOrCreateLocalRecord();
    debugPrint('Identity imported: $gnsId');
    debugPrint('  Ed25519: ${_keypair!.publicKeyHex.substring(0, 16)}...');
    debugPrint('  X25519:  ${_keypair!.encryptionPublicKeyHex.substring(0, 16)}...');
  }

  Future<void> deleteIdentity() async {
    _breadcrumbEngine.dispose();
    await _storage.deleteAll();
    await _chainStorage.deleteAll();
    _keypair = null;
    _localRecord = null;
    _initialized = false;
    debugPrint('Identity deleted');
  }
}

// ==================== RESULT CLASSES ====================

class IdentityCreationResult {
  final bool success;
  final String? gnsId;
  final String? publicKey;
  final String? handle;
  final bool networkReserved;
  final String? message;
  final String? error;

  IdentityCreationResult({
    required this.success,
    this.gnsId,
    this.publicKey,
    this.handle,
    this.networkReserved = false,
    this.message,
    this.error,
  });
}

class IdentityInfo {
  final String? publicKey;
  final String? gnsId;
  final String? claimedHandle;
  final String? reservedHandle;
  final int breadcrumbCount;
  final double trustScore;
  final int daysSinceCreation;
  final bool canClaimHandle;
  final bool chainValid;
  final bool networkAvailable;
  final DateTime? firstBreadcrumbAt;

  IdentityInfo({
    this.publicKey,
    this.gnsId,
    this.claimedHandle,
    this.reservedHandle,
    required this.breadcrumbCount,
    required this.trustScore,
    required this.daysSinceCreation,
    required this.canClaimHandle,
    required this.chainValid,
    this.networkAvailable = false,
    this.firstBreadcrumbAt,
  });

  String get displayName {
    if (claimedHandle != null) return '@$claimedHandle';
    if (reservedHandle != null) return '@$reservedHandle (pending)';
    return gnsId ?? 'Unknown';
  }
}

class HandleReservationResult {
  final bool success;
  final String? handle;
  final DateTime? expiresAt;
  final bool networkReserved;
  final String? message;
  final String? error;

  HandleReservationResult({
    required this.success,
    this.handle,
    this.expiresAt,
    this.networkReserved = false,
    this.message,
    this.error,
  });
}

class HandleClaimResult {
  final bool success;
  final String? handle;
  final String? message;
  final String? error;
  final HandleRequirements? requirements;

  HandleClaimResult({required this.success, this.handle, this.message, this.error, this.requirements});
}

class HandleRequirements {
  final int breadcrumbsRequired;
  final int breadcrumbsCurrent;
  final double trustRequired;
  final double trustCurrent;

  HandleRequirements({
    required this.breadcrumbsRequired,
    required this.breadcrumbsCurrent,
    required this.trustRequired,
    required this.trustCurrent,
  });

  bool get breadcrumbsMet => breadcrumbsCurrent >= breadcrumbsRequired;
  bool get trustMet => trustCurrent >= trustRequired;
}
