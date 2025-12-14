/// Secure Storage - Phase 3A Update
/// 
/// Platform-secure storage for cryptographic keys and identity data.
/// Updated to support profile data storage.
/// 
/// Location: lib/core/crypto/secure_storage.dart

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class SecureKeys {
  static const privateKey = 'gns_sk_root';
  static const publicKey = 'gns_pk_root';
  static const gnsId = 'gns_id';
  static const reservedHandle = 'gns_reserved_handle';
  static const claimedHandle = 'gns_claimed_handle';
  static const chainHead = 'gns_chain_head';
  static const epochCount = 'gns_epoch_count';
  static const breadcrumbCount = 'gns_breadcrumb_count';
  static const trustScore = 'gns_trust_score';
  static const firstBreadcrumbAt = 'gns_first_breadcrumb_at';
  static const lastBreadcrumbAt = 'gns_last_breadcrumb_at';
  static const profileData = 'gns_profile_data';  // NEW: Phase 3A
  static const avatarPath = 'gns_avatar_path';    // NEW: Phase 3B
}

class SecureStorageService {
  static final SecureStorageService _instance = SecureStorageService._internal();
  factory SecureStorageService() => _instance;
  SecureStorageService._internal();

  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      keyCipherAlgorithm: KeyCipherAlgorithm.RSA_ECB_OAEPwithSHA_256andMGF1Padding,
      storageCipherAlgorithm: StorageCipherAlgorithm.AES_GCM_NoPadding,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
      accountName: 'Globe Crumbs',
    ),
  );

  // ==================== IDENTITY KEYS ====================

  Future<void> storePrivateKey(String privateKeyHex) async {
    await _storage.write(key: SecureKeys.privateKey, value: privateKeyHex);
    debugPrint('Private key stored securely');
  }

  Future<String?> readPrivateKey() async {
    return await _storage.read(key: SecureKeys.privateKey);
  }

  Future<void> storePublicKey(String publicKeyHex) async {
    await _storage.write(key: SecureKeys.publicKey, value: publicKeyHex);
  }

  Future<String?> readPublicKey() async {
    return await _storage.read(key: SecureKeys.publicKey);
  }

  Future<void> storeGnsId(String gnsId) async {
    await _storage.write(key: SecureKeys.gnsId, value: gnsId);
  }

  Future<String?> readGnsId() async {
    return await _storage.read(key: SecureKeys.gnsId);
  }

  Future<bool> hasIdentity() async {
    final pk = await readPrivateKey();
    return pk != null && pk.isNotEmpty;
  }

  // ==================== X25519 ENCRYPTION KEYS ====================

  static const String _x25519PrivateKeyKey = 'x25519_private_key';

  Future<void> writeX25519PrivateKey(String key) async {
    await _storage.write(key: _x25519PrivateKeyKey, value: key);
  }

  Future<String?> readX25519PrivateKey() async {
    return await _storage.read(key: _x25519PrivateKeyKey);
  }

  Future<void> deleteX25519PrivateKey() async {
    await _storage.delete(key: _x25519PrivateKeyKey);
  }

  // ==================== HANDLE MANAGEMENT ====================

  Future<void> storeReservedHandle(String handle, DateTime reservedAt) async {
    await _storage.write(key: SecureKeys.reservedHandle, value: handle);
    await _storage.write(
      key: '${SecureKeys.reservedHandle}_at',
      value: reservedAt.toIso8601String(),
    );
  }

  Future<String?> readReservedHandle() async {
    return await _storage.read(key: SecureKeys.reservedHandle);
  }

  Future<void> storeClaimedHandle(String handle) async {
    await _storage.write(key: SecureKeys.claimedHandle, value: handle);
    await _storage.delete(key: SecureKeys.reservedHandle);
    await _storage.delete(key: '${SecureKeys.reservedHandle}_at');
  }

  Future<String?> readClaimedHandle() async {
    return await _storage.read(key: SecureKeys.claimedHandle);
  }

  // ==================== CHAIN STATE ====================

  Future<void> storeChainHead(String blockHash) async {
    await _storage.write(key: SecureKeys.chainHead, value: blockHash);
  }

  Future<String?> readChainHead() async {
    return await _storage.read(key: SecureKeys.chainHead);
  }

  Future<void> storeBreadcrumbCount(int count) async {
    await _storage.write(key: SecureKeys.breadcrumbCount, value: count.toString());
  }

  Future<int> readBreadcrumbCount() async {
    final str = await _storage.read(key: SecureKeys.breadcrumbCount);
    return str != null ? int.tryParse(str) ?? 0 : 0;
  }

  Future<int> incrementBreadcrumbCount() async {
    final current = await readBreadcrumbCount();
    final newCount = current + 1;
    await storeBreadcrumbCount(newCount);
    return newCount;
  }

  Future<void> storeTrustScore(double score) async {
    await _storage.write(key: SecureKeys.trustScore, value: score.toString());
  }

  Future<double> readTrustScore() async {
    final str = await _storage.read(key: SecureKeys.trustScore);
    return str != null ? double.tryParse(str) ?? 0.0 : 0.0;
  }

  Future<void> storeEpochCount(int count) async {
    await _storage.write(key: SecureKeys.epochCount, value: count.toString());
  }

  Future<int> readEpochCount() async {
    final str = await _storage.read(key: SecureKeys.epochCount);
    return str != null ? int.tryParse(str) ?? 0 : 0;
  }

  // ==================== TIMESTAMPS ====================

  Future<void> storeFirstBreadcrumbAt(DateTime time) async {
    await _storage.write(key: SecureKeys.firstBreadcrumbAt, value: time.toIso8601String());
  }

  Future<DateTime?> readFirstBreadcrumbAt() async {
    final str = await _storage.read(key: SecureKeys.firstBreadcrumbAt);
    return str != null ? DateTime.tryParse(str) : null;
  }

  Future<void> storeLastBreadcrumbAt(DateTime time) async {
    await _storage.write(key: SecureKeys.lastBreadcrumbAt, value: time.toIso8601String());
  }

  Future<DateTime?> readLastBreadcrumbAt() async {
    final str = await _storage.read(key: SecureKeys.lastBreadcrumbAt);
    return str != null ? DateTime.tryParse(str) : null;
  }

  // ==================== PROFILE DATA (Phase 3A) ====================

  /// Store profile data as JSON string
  Future<void> storeProfileData(String profileJson) async {
    await _storage.write(key: SecureKeys.profileData, value: profileJson);
    debugPrint('Profile data stored');
  }

  /// Read profile data JSON string
  Future<String?> readProfileData() async {
    return await _storage.read(key: SecureKeys.profileData);
  }

  /// Delete profile data
  Future<void> deleteProfileData() async {
    await _storage.delete(key: SecureKeys.profileData);
  }

  // ==================== IMPORT/EXPORT ====================

  Future<String> exportIdentity() async {
    final privateKey = await readPrivateKey();
    final publicKey = await readPublicKey();
    final gnsId = await readGnsId();
    final handle = await readClaimedHandle();
    final profileData = await readProfileData();

    if (privateKey == null) {
      throw Exception('No identity to export');
    }

    final exportData = {
      'version': 2,  // Updated version for Phase 3A
      'private_key': privateKey,
      'public_key': publicKey,
      'gns_id': gnsId,
      'claimed_handle': handle,
      'profile_data': profileData,
      'exported_at': DateTime.now().toIso8601String(),
    };

    return base64Encode(utf8.encode(jsonEncode(exportData)));
  }

  Future<void> importIdentity(String exportedData) async {
    try {
      final decoded = utf8.decode(base64Decode(exportedData));
      final data = jsonDecode(decoded) as Map<String, dynamic>;

      final privateKey = data['private_key'] as String;
      final publicKey = data['public_key'] as String?;
      final gnsId = data['gns_id'] as String?;
      final handle = data['claimed_handle'] as String?;
      final profileData = data['profile_data'] as String?;

      await storePrivateKey(privateKey);
      if (publicKey != null) await storePublicKey(publicKey);
      if (gnsId != null) await storeGnsId(gnsId);
      if (handle != null) await storeClaimedHandle(handle);
      if (profileData != null) await storeProfileData(profileData);

      debugPrint('Identity imported successfully');
    } catch (e) {
      debugPrint('Import failed: $e');
      rethrow;
    }
  }

  // ==================== AVATAR ====================

  Future<void> storeAvatarPath(String path) async {
    await _storage.write(key: SecureKeys.avatarPath, value: path);
    debugPrint('Avatar path stored');
  }

  Future<String?> readAvatarPath() async {
    return await _storage.read(key: SecureKeys.avatarPath);
  }

  Future<void> deleteAvatarPath() async {
    await _storage.delete(key: SecureKeys.avatarPath);
  }

  // ==================== CLEANUP ====================

  Future<void> deleteAll() async {
    await _storage.deleteAll();
    debugPrint('All secure storage deleted');
  }

  Future<void> deleteIdentity() async {
    await _storage.delete(key: SecureKeys.privateKey);
    await _storage.delete(key: SecureKeys.publicKey);
    await _storage.delete(key: SecureKeys.gnsId);
    await _storage.delete(key: SecureKeys.profileData);
    debugPrint('Identity deleted');
  }
}
