/// GNS Vault Service
///
/// Encrypted password vault tied to the user's GNS identity.
/// Credentials are encrypted with a key derived from the wallet's
/// Ed25519 private key — only YOUR key can decrypt YOUR vault.
///
/// Location: lib/core/vault/gns_vault_service.dart

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';
import 'package:cryptography/cryptography.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MODELS
// ─────────────────────────────────────────────────────────────────────────────

/// A single saved credential entry
class VaultCredential {
  final String id;
  final String domain;       // e.g. "github.com"
  final String username;
  final String password;     // stored encrypted; returned decrypted
  final String? notes;
  final String? faviconUrl;
  final DateTime createdAt;
  final DateTime updatedAt;

  VaultCredential({
    required this.id,
    required this.domain,
    required this.username,
    required this.password,
    this.notes,
    this.faviconUrl,
    required this.createdAt,
    required this.updatedAt,
  });

  VaultCredential copyWith({
    String? domain,
    String? username,
    String? password,
    String? notes,
    String? faviconUrl,
  }) => VaultCredential(
    id: id,
    domain: domain ?? this.domain,
    username: username ?? this.username,
    password: password ?? this.password,
    notes: notes ?? this.notes,
    faviconUrl: faviconUrl ?? this.faviconUrl,
    createdAt: createdAt,
    updatedAt: DateTime.now(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'domain': domain,
    'username': username,
    'password': password,
    if (notes != null) 'notes': notes,
    if (faviconUrl != null) 'favicon_url': faviconUrl,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  factory VaultCredential.fromJson(Map<String, dynamic> j) => VaultCredential(
    id: j['id'] as String,
    domain: j['domain'] as String,
    username: j['username'] as String,
    password: j['password'] as String,
    notes: j['notes'] as String?,
    faviconUrl: j['favicon_url'] as String?,
    createdAt: DateTime.parse(j['created_at'] as String),
    updatedAt: DateTime.parse(j['updated_at'] as String),
  );
}

/// Result of a vault operation
class VaultResult {
  final bool success;
  final String? error;
  final VaultCredential? credential;
  final List<VaultCredential>? credentials;

  VaultResult.ok({this.credential, this.credentials})
      : success = true, error = null;
  VaultResult.err(this.error)
      : success = false, credential = null, credentials = null;
}

// ─────────────────────────────────────────────────────────────────────────────
// SERVICE
// ─────────────────────────────────────────────────────────────────────────────

/// GNS Vault Service
///
/// All credentials are encrypted with AES-256-GCM using a key derived
/// from the wallet's Ed25519 private key via HKDF-SHA256.
/// The vault blob is stored in flutter_secure_storage (iOS Keychain /
/// Android Keystore) — never written to disk unencrypted.
class GnsVaultService {
  static final GnsVaultService _instance = GnsVaultService._internal();
  factory GnsVaultService() => _instance;
  GnsVaultService._internal();

  static const _storageKey  = 'gns_vault_v1';
  static const _hkdfInfo    = 'GNS-Vault-v1';

  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );
  final _uuid = const Uuid();

  // Derived vault key (in memory only, never persisted)
  List<int>? _vaultKey;
  bool _initialized = false;

  bool get isInitialized => _initialized;

  // ── Initialise ─────────────────────────────────────────────────────────────

  /// Call once after IdentityWallet is ready.
  /// [privateKeyBytes] = wallet.privateKeyBytes (Ed25519 seed, 32 bytes)
  Future<void> initialize(Uint8List privateKeyBytes) async {
    if (_initialized) return;

    // Derive a 256-bit vault key from the Ed25519 private key using HKDF
    final hkdf = Hkdf(
      hmac: Hmac(Sha256()),
      outputLength: 32,
    );
    final derived = await hkdf.deriveKey(
      secretKey: SecretKey(privateKeyBytes),
      nonce: List<int>.filled(32, 0), // static salt is fine — key is already secret
      info: utf8.encode(_hkdfInfo),
    );
    _vaultKey = await derived.extractBytes();
    _initialized = true;
    debugPrint('[VAULT] Initialized — vault key derived from GNS identity');
  }

  // ── CRUD ───────────────────────────────────────────────────────────────────

  /// Add a new credential. Returns the saved entry.
  Future<VaultResult> addCredential({
    required String domain,
    required String username,
    required String password,
    String? notes,
    String? faviconUrl,
  }) async {
    try {
      final cred = VaultCredential(
        id: _uuid.v4(),
        domain: _normaliseDomain(domain),
        username: username,
        password: password,
        notes: notes,
        faviconUrl: faviconUrl,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final all = await _loadAll();
      all.add(cred);
      await _saveAll(all);

      debugPrint('[VAULT] Added credential for ${cred.domain}');
      return VaultResult.ok(credential: cred);
    } catch (e) {
      debugPrint('[VAULT] addCredential error: $e');
      return VaultResult.err(e.toString());
    }
  }

  /// Get all credentials matching a domain (exact + subdomain aware).
  Future<List<VaultCredential>> getForDomain(String rawDomain) async {
    final domain = _normaliseDomain(rawDomain);
    final all = await _loadAll();
    return all.where((c) =>
      c.domain == domain ||
      domain.endsWith('.${c.domain}') ||
      c.domain.endsWith('.$domain')
    ).toList();
  }

  /// Get all credentials (for vault management screen).
  Future<List<VaultCredential>> getAll() => _loadAll();

  /// Update an existing credential.
  Future<VaultResult> updateCredential(VaultCredential updated) async {
    try {
      final all = await _loadAll();
      final idx = all.indexWhere((c) => c.id == updated.id);
      if (idx < 0) return VaultResult.err('Credential not found');
      all[idx] = updated.copyWith();  // updates updatedAt
      await _saveAll(all);
      return VaultResult.ok(credential: all[idx]);
    } catch (e) {
      return VaultResult.err(e.toString());
    }
  }

  /// Delete a credential by id.
  Future<bool> deleteCredential(String id) async {
    try {
      final all = await _loadAll();
      all.removeWhere((c) => c.id == id);
      await _saveAll(all);
      return true;
    } catch (e) {
      debugPrint('[VAULT] deleteCredential error: $e');
      return false;
    }
  }

  /// Total number of saved credentials.
  Future<int> get count async => (await _loadAll()).length;

  // ── Encryption helpers ─────────────────────────────────────────────────────

  /// Load all credentials from secure storage (decrypted).
  Future<List<VaultCredential>> _loadAll() async {
    _assertInit();
    final raw = await _storage.read(key: _storageKey);
    if (raw == null || raw.isEmpty) return [];

    try {
      final decrypted = await _decrypt(raw);
      final list = jsonDecode(decrypted) as List;
      return list.map((j) => VaultCredential.fromJson(j as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('[VAULT] _loadAll decrypt error: $e');
      return [];
    }
  }

  /// Save all credentials to secure storage (encrypted).
  Future<void> _saveAll(List<VaultCredential> credentials) async {
    _assertInit();
    final json = jsonEncode(credentials.map((c) => c.toJson()).toList());
    final encrypted = await _encrypt(json);
    await _storage.write(key: _storageKey, value: encrypted);
  }

  /// Encrypt plaintext using AES-256-GCM with the derived vault key.
  /// Returns base64(nonce + ciphertext + mac).
  Future<String> _encrypt(String plaintext) async {
    final algorithm = AesGcm.with256bits();
    final secretKey = SecretKey(_vaultKey!);
    final nonce = algorithm.newNonce();
    final sealed = await algorithm.encrypt(
      utf8.encode(plaintext),
      secretKey: secretKey,
      nonce: nonce,
    );
    // Pack: 12-byte nonce + ciphertext + 16-byte MAC
    final packed = Uint8List.fromList([
      ...nonce,
      ...sealed.cipherText,
      ...sealed.mac.bytes,
    ]);
    return base64.encode(packed);
  }

  /// Decrypt base64(nonce + ciphertext + mac) back to plaintext.
  Future<String> _decrypt(String encoded) async {
    final algorithm = AesGcm.with256bits();
    final secretKey = SecretKey(_vaultKey!);
    final packed = base64.decode(encoded);

    const nonceLen = 12;
    const macLen   = 16;
    final nonce      = packed.sublist(0, nonceLen);
    final mac        = packed.sublist(packed.length - macLen);
    final cipherText = packed.sublist(nonceLen, packed.length - macLen);

    final box = SecretBox(cipherText, nonce: nonce, mac: Mac(mac));
    final plainBytes = await algorithm.decrypt(box, secretKey: secretKey);
    return utf8.decode(plainBytes);
  }

  void _assertInit() {
    if (!_initialized || _vaultKey == null) {
      throw StateError('[VAULT] Not initialized — call initialize() first');
    }
  }

  // ── Utility ────────────────────────────────────────────────────────────────

  /// Strip scheme, www, trailing slash from a domain string.
  String _normaliseDomain(String raw) {
    var d = raw.trim().toLowerCase();
    d = d.replaceAll(RegExp(r'^https?://'), '');
    d = d.replaceAll(RegExp(r'^www\.'), '');
    d = d.split('/').first;   // strip path
    d = d.split(':').first;   // strip port
    return d;
  }

  /// Wipe the vault (used on identity deletion).
  Future<void> deleteVault() async {
    await _storage.delete(key: _storageKey);
    _vaultKey = null;
    _initialized = false;
    debugPrint('[VAULT] Vault deleted');
  }
}
