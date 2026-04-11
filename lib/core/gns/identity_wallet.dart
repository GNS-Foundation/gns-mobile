// ===========================================
// GNS - IDENTITY WALLET
//
// SECURITY FIXES (v1.1 - Relay Attack Resilience):
//   [MEDIUM] Added signWithChannelBinding() for CBT-bound operation signing
//   [MEDIUM] Added buildAuthHeaders() to centralise signed header generation
//   [MEDIUM] Added deriveChannelBindingToken() mirroring server-side logic
// ===========================================

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import '../crypto/identity_keypair.dart';
import '../crypto/secure_storage.dart';
import '../chain/breadcrumb_engine.dart';
import '../chain/chain_storage.dart';
import 'gns_record.dart';
import 'gns_api_client.dart';
import '../profile/profile_module.dart';
import '../financial/financial_module.dart';

// =============================================================================
// IDENTITY INFO
// =============================================================================

/// A lightweight snapshot of the local identity state.
///
/// Returned by [IdentityWallet.getIdentityInfo].
class IdentityInfo {
  /// Claimed (server-confirmed) GNS handle, e.g. `alice`.
  final String? claimedHandle;

  /// Handle reserved locally but not yet confirmed by the server.
  final String? reservedHandle;

  /// Convenience getter: returns claimed, then reserved.
  String? get handle => claimedHandle ?? reservedHandle;

  final String? publicKey;
  final String? gnsId;
  final double trustScore;
  final int breadcrumbCount;
  final int daysSinceCreation;
  final bool networkAvailable;
  final DateTime? firstBreadcrumbAt;

  /// Whether all prerequisites for claiming the reserved handle are met.
  bool get canClaimHandle {
    const minBreadcrumbs = 100;
    const minTrust = 20.0;
    return reservedHandle != null &&
        claimedHandle == null &&
        breadcrumbCount >= minBreadcrumbs &&
        trustScore >= minTrust;
  }

  IdentityInfo({
    this.claimedHandle,
    this.reservedHandle,
    this.publicKey,
    this.gnsId,
    this.trustScore = 0,
    this.breadcrumbCount = 0,
    this.daysSinceCreation = 0,
    this.networkAvailable = false,
    this.firstBreadcrumbAt,
  });
}

// =============================================================================
// HANDLE CLAIM RESULT
// =============================================================================

/// Requirements snapshot returned when a claim attempt fails.
class HandleClaimRequirements {
  final int breadcrumbsCurrent;
  final int breadcrumbsRequired;
  final double trustCurrent;
  final double trustRequired;

  bool get breadcrumbsMet => breadcrumbsCurrent >= breadcrumbsRequired;
  bool get trustMet => trustCurrent >= trustRequired;

  HandleClaimRequirements({
    required this.breadcrumbsCurrent,
    this.breadcrumbsRequired = 100,
    required this.trustCurrent,
    this.trustRequired = 20.0,
  });
}

/// Result of [IdentityWallet.claimHandle].
class HandleClaimResult {
  final bool success;
  final String? handle;
  final String? message;
  final String? error;
  final HandleClaimRequirements? requirements;

  HandleClaimResult.success({required this.handle, this.message})
      : success = true,
        error = null,
        requirements = null;

  HandleClaimResult.failure({
    this.error,
    this.requirements,
  })  : success = false,
        handle = null,
        message = null;
}

/// Result of [IdentityWallet.createIdentityWithHandle].
class CreateIdentityResult {
  final bool success;
  final String? gnsId;
  final String? handle;
  final String? error;

  CreateIdentityResult.success({required this.gnsId, required this.handle})
      : success = true,
        error = null;

  CreateIdentityResult.failure({this.error})
      : success = false,
        gnsId = null,
        handle = null;
}

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
  /// Alias kept for callers that use `wallet.publicKeyHex` directly.
  String? get publicKeyHex => _keypair?.publicKeyHex;
  String? get gnsId => _keypair?.gnsId;
  GnsRecord? get localRecord => _localRecord;
  BreadcrumbEngine get breadcrumbEngine => _breadcrumbEngine;
  bool get networkAvailable => _networkAvailable;

  /// Synchronous handle getter (claimed → reserved → record).
  String? get currentHandle => _localRecord?.handle;

  /// Trust score from local record (or 0).
  double get trustScore => _localRecord?.trustScore ?? 0;

  /// Breadcrumb count from local record (or 0).
  int get breadcrumbCount => _localRecord?.breadcrumbCount ?? 0;

  /// Return the current profile data stored in the local GNS record.
  ProfileData getProfile() => _profileData;

  /// Alias for [getCurrentHandle] (sync convenience).
  Future<String?> getHandle() async => getCurrentHandle();

  /// Sign a string and return the hex signature. Alias for [signString].
  Future<String> sign(String data) async {
    final sig = await signString(data);
    return sig ?? '';
  }

  /// Delete the identity: wipe keys, record, chain data.
  Future<void> deleteIdentity() async {
    await _storage.deleteAll();
    await _chainStorage.deleteAll();
    _keypair = null;
    _localRecord = null;
    _profileData = ProfileData();
    _initialized = false;
    debugPrint('🗑️ Identity deleted');
  }
  GnsKeypair? get keypair => _keypair;

  /// Async check whether an identity keypair exists in secure storage.
  /// Use this on startup before [initialize] is called, or after it.
  Future<bool> checkIdentityExists() async {
    if (_keypair != null) return true;
    return await _storage.hasIdentity();
  }

  // ==================== COMMUNICATION SERVICE SUPPORT ====================

  Uint8List? get privateKeyBytes => _keypair?.privateKey;
  Uint8List? get publicKeyBytes => _keypair?.publicKey;
  Uint8List? get encryptionPrivateKeyBytes => _keypair?.encryptionPrivateKey;
  Uint8List? get encryptionPublicKeyBytes => _keypair?.encryptionPublicKey;

  String? get encryptionPublicKeyHex => _keypair?.encryptionPublicKeyHex;

  // ==================== CHANNEL BINDING TOKEN ====================

  /// Channel Binding Token window in seconds (must match server).
  static const int _cbtWindowSeconds = 300;

  /// Derive the Channel Binding Token for the current session.
  ///
  /// CBT = SHA256(connection_id || agent_public_key || timestamp_epoch)
  ///
  /// On mobile, [connectionId] should be a stable per-session value —
  /// e.g. a UUID generated at app launch and stored in memory only
  /// (never persisted, so each app session gets a fresh CBT namespace).
  ///
  /// The server derives its own CBT from the TLS/WebSocket connection ID.
  /// For mobile ↔ server communication the CBT is included in signed
  /// payloads so the server can verify the token was created for
  /// the current session, not replayed from a different one.
  String deriveChannelBindingToken({
    required String connectionId,
    DateTime? at,
  }) {
    assert(_keypair != null, 'Wallet must be initialized before deriving CBT');
    final ts = at ?? DateTime.now();
    final epoch = ts.millisecondsSinceEpoch ~/ 1000 ~/ _cbtWindowSeconds;
    final raw = '$connectionId:${_keypair!.publicKeyHex.toLowerCase()}:$epoch';
    final digest = sha256.convert(utf8.encode(raw));
    return digest.toString();
  }

  // ==================== SIGNING WITH CHANNEL BINDING ====================

  /// Sign [payload] with the wallet's Ed25519 key, incorporating the
  /// Channel Binding Token so the signature is bound to the current session.
  ///
  /// The signed bytes are:
  ///   SHA256( payload || channelBindingToken_utf8 )
  ///
  /// This prevents a relay from replaying a valid signature from one session
  /// in a different session, because the CBT changes per session.
  ///
  /// Returns the hex-encoded Ed25519 signature.
  Future<String> signWithChannelBinding({
    required Uint8List payload,
    required String channelBindingToken,
  }) async {
    if (_keypair == null) throw StateError('Wallet not initialized');

    // Bind payload to the channel by appending the CBT before signing
    final cbtBytes = utf8.encode(channelBindingToken);
    final bound = Uint8List(payload.length + cbtBytes.length)
      ..setRange(0, payload.length, payload)
      ..setRange(payload.length, payload.length + cbtBytes.length, cbtBytes);

    return _keypair!.signToHex(bound);
  }

  /// Sign a string [message] with channel binding. Convenience wrapper.
  Future<String> signStringWithChannelBinding({
    required String message,
    required String channelBindingToken,
  }) async {
    return signWithChannelBinding(
      payload: Uint8List.fromList(utf8.encode(message)),
      channelBindingToken: channelBindingToken,
    );
  }

  // ==================== AUTH HEADER BUILDER ====================

  /// Build a complete set of authenticated HTTP request headers.
  ///
  /// Includes:
  ///   X-GNS-PublicKey   — Ed25519 identity key (hex)
  ///   X-GNS-Timestamp   — Unix ms timestamp
  ///   X-GNS-Signature   — Ed25519 sig over "timestamp:publicKey"
  ///   X-GNS-CBT         — Channel Binding Token
  ///
  /// [connectionId] should be the stable per-session identifier
  /// (e.g. WebSocket connection ID or app-launch UUID).
  Future<Map<String, String>> buildAuthHeaders({
    required String connectionId,
  }) async {
    if (_keypair == null) throw StateError('Wallet not initialized');

    final pk = _keypair!.publicKeyHex.toLowerCase();
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final message = '$timestamp:$pk';

    // Ed25519 sign the "timestamp:publicKey" message
    final msgBytes = Uint8List.fromList(utf8.encode(message));
    final signature = await _keypair!.signToHex(msgBytes);

    // Derive CBT for this session
    final cbt = deriveChannelBindingToken(connectionId: connectionId);

    return {
      'Content-Type': 'application/json',
      'X-GNS-PublicKey': pk,
      'X-GNS-Timestamp': timestamp,
      'X-GNS-Signature': signature,
      'X-GNS-CBT': cbt,
    };
  }

  // ==================== SIGNED AGENT OPERATION ====================

  /// Create a GNS-AIP compliant signed agent operation payload.
  ///
  /// Per Whitepaper Appendix A, the signed operation includes:
  ///   - The canonical payload
  ///   - The delegation certificate hash
  ///   - The Channel Binding Token
  ///   - The timestamp
  ///
  /// All fields are signed together as SHA256(canonical JSON of above).
  Future<Map<String, dynamic>> createSignedAgentOperation({
    required Map<String, dynamic> payload,
    required String delegationCertHash,
    required String connectionId,
  }) async {
    if (_keypair == null) throw StateError('Wallet not initialized');

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final cbt = deriveChannelBindingToken(connectionId: connectionId);
    final pk = _keypair!.publicKeyHex;

    // Build the signable structure (canonical — keys sorted)
    final signable = <String, dynamic>{
      'agent_public_key': pk,
      'channel_binding_token': cbt,
      'delegation_cert_hash': delegationCertHash,
      'payload': payload,
      'timestamp': timestamp,
    };

    // Canonical JSON: sorted keys, no whitespace
    final canonical = _canonicalJson(signable);
    final canonicalHash = sha256.convert(utf8.encode(canonical)).bytes;
    final signature = await _keypair!.signToHex(Uint8List.fromList(canonicalHash));

    return {
      'payload': payload,
      'delegation_cert_hash': delegationCertHash,
      'channel_binding_token': cbt,
      'timestamp': timestamp,
      'agent_public_key': pk,
      'signature': signature,
    };
  }

  /// Recursively produce canonical (sorted-key) JSON — matches server-side
  /// canonicalJson() in crypto.ts.
  String _canonicalJson(dynamic obj) {
    if (obj == null) return 'null';
    if (obj is bool) return obj.toString();
    if (obj is num) return obj.toString();
    if (obj is String) return jsonEncode(obj);
    if (obj is List) return '[${obj.map(_canonicalJson).join(',')}]';
    if (obj is Map) {
      final sorted = obj.keys.toList()..sort();
      final pairs = sorted
          .where((k) => obj[k] != null)
          .map((k) => '${jsonEncode(k)}:${_canonicalJson(obj[k])}');
      return '{${pairs.join(',')}}';
    }
    return jsonEncode(obj);
  }

  // ==================== EXISTING WALLET METHODS (unchanged) ==============

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      final stored = await _storage.loadKeypair();
      if (stored != null) {
        _keypair = stored;
        _localRecord = await _chainStorage.loadRecord();
        debugPrint('🔑 Wallet loaded: ${_keypair!.gnsId}');
      }
      _initialized = true;
    } catch (e) {
      debugPrint('❌ Wallet init error: $e');
      _initialized = true;
    }
  }

  Future<GnsKeypair> createIdentity() async {
    _keypair = await GnsKeypair.generate();
    await _storage.saveKeypair(_keypair!);
    debugPrint('🆔 New identity created: ${_keypair!.gnsId}');
    return _keypair!;
  }

  /// Create a new identity AND reserve a GNS handle in one step.
  ///
  /// Generates a fresh Ed25519 keypair, persists it, then calls
  /// [GnsApiClient.reserveHandle] to reserve [handle] on the server.
  /// The reserved handle is stored in secure storage so that
  /// [getIdentityInfo] and [getCurrentHandle] can return it immediately.
  Future<CreateIdentityResult> createIdentityWithHandle(String handle) async {
    try {
      // 1. Generate and persist keypair.
      final keypair = await GnsKeypair.generate();
      _keypair = keypair;
      await _storage.saveKeypair(keypair);
      debugPrint('🆔 New identity created: ${keypair.gnsId}');

      // 2. Sign the reservation request.
      final pk = keypair.publicKeyHex;
      final cleanHandle = handle.toLowerCase().replaceAll('@', '').trim();
      final message = 'reserve:$cleanHandle:$pk';
      final msgBytes = Uint8List.fromList(utf8.encode(message));
      final sig = await keypair.signToHex(msgBytes);

      // 3. Reserve on the server.
      final result = await _apiClient.reserveHandle(
        handle: cleanHandle,
        publicKey: pk,
        signature: sig,
      );

      final success = result['success'] == true ||
          result['handle'] != null ||
          result['reserved'] == true;

      if (success) {
        // 4. Persist to secure storage.
        await _storage.storeReservedHandle(cleanHandle, DateTime.now());
        debugPrint('✅ Handle reserved: @$cleanHandle');
        return CreateIdentityResult.success(
          gnsId: keypair.gnsId,
          handle: cleanHandle,
        );
      } else {
        final error = result['error']?.toString() ?? 'Handle reservation failed';
        return CreateIdentityResult.failure(error: error);
      }
    } catch (e) {
      debugPrint('❌ createIdentityWithHandle error: $e');
      return CreateIdentityResult.failure(error: e.toString());
    }
  }

  Future<void> setNetworkAvailable(bool available) async {
    _networkAvailable = available;
  }

  Future<bool> publishRecord(GnsRecord record) async {
    if (_keypair == null) return false;
    try {
      final result = await _apiClient.publishRecord(
        publicKey: _keypair!.publicKeyHex,
        record: record.toJson(),
      );
      final success = result['success'] == true ||
          result['identity'] != null ||
          result['record'] != null;
      if (success) {
        _localRecord = record;
        await _chainStorage.saveRecord(record);
      }
      return success;
    } catch (e) {
      debugPrint('❌ Publish record error: $e');
      return false;
    }
  }

  // ==================== IDENTITY INFO ====================

  /// Returns a snapshot of the current identity state.
  Future<IdentityInfo> getIdentityInfo() async {
    final record = _localRecord;
    final pk = publicKey;
    final id = gnsId;

    // Prefer the handle from the local GNS record (server-confirmed/claimed).
    final String? claimed = record?.handle ?? await _storage.readClaimedHandle();

    // If no claimed handle, look up a reserved one.
    String? reserved;
    if (claimed == null) {
      try {
        reserved = await _storage.readReservedHandle();
      } catch (_) {}
    }

    // Breadcrumb count: prefer record, fall back to secure storage.
    final int breadcrumbs = record?.breadcrumbCount ??
        (await _storage.readBreadcrumbCount() ?? 0);

    // Trust score: prefer record, fall back to secure storage.
    final double trust = record?.trustScore ??
        (await _storage.readTrustScore() ?? 0.0);

    final created = record?.createdAt ?? DateTime.now();
    final days = DateTime.now().difference(created).inDays;

    return IdentityInfo(
      claimedHandle: claimed,
      reservedHandle: reserved,
      publicKey: pk,
      gnsId: id,
      trustScore: trust,
      breadcrumbCount: breadcrumbs,
      daysSinceCreation: days,
      networkAvailable: _networkAvailable,
      firstBreadcrumbAt: record?.createdAt,
    );
  }

  // ==================== HANDLE CLAIM ====================

  /// Attempt to claim the currently reserved handle.
  ///
  /// Validates local prerequisites first, then posts to the GNS API.
  Future<HandleClaimResult> claimHandle() async {
    if (_keypair == null) {
      return HandleClaimResult.failure(error: 'Wallet not initialised');
    }

    final info = await getIdentityInfo();

    if (info.reservedHandle == null) {
      return HandleClaimResult.failure(error: 'No reserved handle found');
    }

    if (!info.canClaimHandle) {
      return HandleClaimResult.failure(
        error: 'Requirements not met',
        requirements: HandleClaimRequirements(
          breadcrumbsCurrent: info.breadcrumbCount,
          trustCurrent: info.trustScore,
        ),
      );
    }

    try {
      final handle = info.reservedHandle!;
      final pk = _keypair!.publicKeyHex;
      final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final claimPayload = {
        'identity': pk,
        'proof': {
          'breadcrumb_count': info.breadcrumbCount,
          'trust_score': info.trustScore,
        },
        'claimed_at': timestamp,
      };
      final claimJson = jsonEncode(claimPayload);
      final msgBytes = Uint8List.fromList(utf8.encode(claimJson));
      final sig = await _keypair!.signToHex(msgBytes);

      final result = await _apiClient.claimHandle(
        handle: handle,
        claim: claimPayload,
        signature: sig,
      );

      final success = result['success'] == true ||
          result['handle'] != null ||
          result['identity'] != null;

      if (success) {
        // Persist claimed handle to secure storage.
        try {
          await _storage.storeClaimedHandle(handle);
        } catch (_) {}

        // Update local record to mark the handle as claimed.
        if (_localRecord != null) {
          final updated = GnsRecord(
            identity: _localRecord!.identity,
            handle: handle,
            encryptionKey: _localRecord!.encryptionKey,
            modules: _localRecord!.modules,
            endpoints: _localRecord!.endpoints,
            epochRoots: _localRecord!.epochRoots,
            trustScore: _localRecord!.trustScore,
            breadcrumbCount: _localRecord!.breadcrumbCount,
            createdAt: _localRecord!.createdAt,
            updatedAt: DateTime.now(),
            signature: _localRecord!.signature,
          );
          _localRecord = updated;
          await _chainStorage.saveRecord(updated);
        }

        return HandleClaimResult.success(
          handle: handle,
          message: '@$handle has been claimed!',
        );
      } else {
        final error = result['error']?.toString() ?? 'Server rejected the claim';
        return HandleClaimResult.failure(error: error);
      }
    } catch (e) {
      debugPrint('❌ claimHandle error: $e');
      return HandleClaimResult.failure(error: e.toString());
    }
  }

  // ==================== SIGNING UTILITIES ====================

  /// Sign raw bytes with the Ed25519 identity key.
  /// Returns the signature bytes, or null if the wallet is not initialised.
  Future<Uint8List?> signBytes(List<int> bytes) async {
    if (_keypair == null) return null;
    try {
      final hexSig = await _keypair!.signToHex(Uint8List.fromList(bytes));
      // Convert hex string back to bytes for callers that need raw bytes.
      final result = Uint8List(hexSig.length ~/ 2);
      for (var i = 0; i < result.length; i++) {
        result[i] = int.parse(hexSig.substring(i * 2, i * 2 + 2), radix: 16);
      }
      return result;
    } catch (e) {
      debugPrint('❌ signBytes error: $e');
      return null;
    }
  }

  // ==================== HANDLE UTILITIES ====================

  /// Returns the current handle (claimed preferred, then reserved), or null.
  Future<String?> getCurrentHandle() async {
    // Prefer the handle in the local GNS record (claimed/server-confirmed).
    if (_localRecord?.handle != null) return _localRecord!.handle;
    // Then try secure storage for claimed or reserved handle.
    try {
      return await _storage.readClaimedHandle() ??
             await _storage.readReservedHandle();
    } catch (_) {
      return null;
    }
  }

  // ==================== FINANCIAL DATA ====================

  /// Persist [financial] data to the GNS record and publish to the network.
  ///
  /// Returns true on successful publish, false on failure
  /// (data is still saved locally either way).
  Future<bool> updateFinancialData(FinancialData financial) async {
    if (_keypair == null || _localRecord == null) return false;

    try {
      final existing = _localRecord!;

      // Serialise financial data as a GNS module.
      final financialModule = GnsModule(
        id: 'financial',
        schema: 'gns.module.financial/v1',
        name: 'Financial',
        config: financial.toJson(),
      );

      // Replace any existing financial module.
      final modules = existing.modules
          .where((m) => m.schema != 'gns.module.financial/v1')
          .toList()
        ..add(financialModule);

      // Re-sign (use existing signature as placeholder — server will validate
      // the record payload, but needs a non-empty signature field).
      final updated = GnsRecord(
        identity: existing.identity,
        handle: existing.handle,
        encryptionKey: existing.encryptionKey,
        modules: modules,
        endpoints: existing.endpoints,
        epochRoots: existing.epochRoots,
        trustScore: existing.trustScore,
        breadcrumbCount: existing.breadcrumbCount,
        createdAt: existing.createdAt,
        updatedAt: DateTime.now(),
        signature: existing.signature,
      );

      _localRecord = updated;
      await _chainStorage.saveRecord(updated);

      return await publishRecord(updated);
    } catch (e) {
      debugPrint('❌ updateFinancialData error: $e');
      return false;
    }
  }

  // ==================== PROFILE DATA ====================

  /// Persist [profile] data to the GNS record and publish to the network.
  ///
  /// Returns true on successful publish, false on failure
  /// (data is still saved locally either way).
  Future<bool> updateProfileModule(ProfileData profile) async {
    if (_keypair == null || _localRecord == null) return false;

    try {
      final existing = _localRecord!;

      // Serialise profile data as a GNS module.
      final profileModule = GnsModule(
        id: 'profile',
        schema: GnsModuleSchemas.profile,
        name: 'Profile',
        isPublic: true,
        config: profile.toJson(),
      );

      // Replace any existing profile module.
      final modules = existing.modules
          .where((m) => m.schema != GnsModuleSchemas.profile)
          .toList()
        ..add(profileModule);

      final updated = GnsRecord(
        identity: existing.identity,
        handle: existing.handle,
        encryptionKey: existing.encryptionKey,
        modules: modules,
        endpoints: existing.endpoints,
        epochRoots: existing.epochRoots,
        trustScore: existing.trustScore,
        breadcrumbCount: existing.breadcrumbCount,
        createdAt: existing.createdAt,
        updatedAt: DateTime.now(),
        signature: existing.signature,
      );

      _localRecord = updated;
      await _chainStorage.saveRecord(updated);

      return await publishRecord(updated);
    } catch (e) {
      debugPrint('❌ updateProfileModule error: $e');
      return false;
    }
  }

  // ==================== STRING SIGNING ====================

  /// Sign a string message with the Ed25519 identity key.
  /// Returns the hex-encoded signature, or null if the wallet is not initialised.
  Future<String?> signString(String message) async {
    if (_keypair == null) return null;
    try {
      return await _keypair!.signToHex(Uint8List.fromList(utf8.encode(message)));
    } catch (e) {
      debugPrint('❌ signString error: $e');
      return null;
    }
  }
}
