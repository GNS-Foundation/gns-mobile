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
  GnsKeypair? get keypair => _keypair;

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

  Future<void> setNetworkAvailable(bool available) async {
    _networkAvailable = available;
  }

  Future<bool> publishRecord(GnsRecord record) async {
    if (_keypair == null) return false;
    try {
      final success = await _apiClient.publishRecord(record, _keypair!);
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
}
