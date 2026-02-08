/// Communication Crypto Service - DUAL-KEY ARCHITECTURE
/// 
/// Handles encryption, decryption, signing, and verification for GNS envelopes.
/// 
/// ✅ UPDATED: Now expects X25519 keys directly (no Ed25519→X25519 conversion)
/// - Encryption: Uses recipient's X25519 public key directly
/// - Decryption: Uses own X25519 private key directly
/// - Signing: Uses Ed25519 private key (separate)
/// - Verification: Uses Ed25519 public key (separate)
/// 
/// Location: lib/core/comm/comm_crypto_service.dart

import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:cryptography/cryptography.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'gns_envelope.dart';

/// Result of encryption operation
class EncryptResult {
  final bool success;
  final String encryptedPayload;
  final String ephemeralPublicKey;
  final String nonce;
  final int payloadSize;
  final Map<String, String>? recipientKeys;
  final String? error;

  EncryptResult.success({
    required this.encryptedPayload,
    required this.ephemeralPublicKey,
    required this.nonce,
    required this.payloadSize,
    this.recipientKeys,
  }) : success = true, error = null;

  EncryptResult.failure(this.error)
      : success = false,
        encryptedPayload = '',
        ephemeralPublicKey = '',
        nonce = '',
        payloadSize = 0,
        recipientKeys = null;
}

/// Result of decryption operation
class DecryptResult {
  final bool success;
  final Uint8List? payload;
  final String? error;

  DecryptResult.success(this.payload) : success = true, error = null;
  DecryptResult.failure(this.error) : success = false, payload = null;
}

/// Communication crypto service
class CommCryptoService {
  static const String _hkdfInfo = 'gns-envelope-v1';
  static const int _nonceLength = 12;
  static const int _macLength = 16;

  // ==========================================================================
  // PUBLIC API METHODS (used by communication_service.dart)
  // ==========================================================================

  /// Encrypt for single recipient (used by communication_service.dart)
  /// 
  /// ✅ DUAL-KEY: recipientPublicKey is X25519 (32 bytes)
  Future<EncryptResult> encryptForRecipient({
    required Uint8List payload,
    required Uint8List recipientPublicKey,  // ✅ X25519 public key
  }) async {
    if (recipientPublicKey.length != 32) {
      return EncryptResult.failure(
        'Invalid recipient X25519 public key length: ${recipientPublicKey.length} (expected 32)'
      );
    }
    return _encryptSingleRecipient(payload, recipientPublicKey);
  }

  /// Encrypt for multiple recipients (used by communication_service.dart)
  /// 
  /// ✅ DUAL-KEY: All recipient keys are X25519 (32 bytes each)
  Future<EncryptResult> encryptForMultipleRecipients({
    required Uint8List payload,
    required List<Uint8List> recipientPublicKeys,  // ✅ X25519 public keys
  }) async {
    // Validate all keys are 32 bytes
    for (var key in recipientPublicKeys) {
      if (key.length != 32) {
        return EncryptResult.failure(
          'Invalid recipient X25519 public key length: ${key.length} (expected 32)'
        );
      }
    }
    return _encryptMultiRecipient(payload, recipientPublicKeys);
  }

  /// Encrypt payload for recipient(s) - generic method
  /// 
  /// ✅ DUAL-KEY: All recipient keys are X25519
  Future<EncryptResult> encrypt({
    required Uint8List payload,
    required List<Uint8List> recipientPublicKeys,  // ✅ X25519 public keys
  }) async {
    try {
      if (recipientPublicKeys.isEmpty) {
        return EncryptResult.failure('No recipients specified');
      }

      if (recipientPublicKeys.length == 1) {
        return encryptForRecipient(
          payload: payload,
          recipientPublicKey: recipientPublicKeys.first,
        );
      } else {
        return encryptForMultipleRecipients(
          payload: payload,
          recipientPublicKeys: recipientPublicKeys,
        );
      }
    } catch (e) {
      debugPrint('Encryption error: $e');
      return EncryptResult.failure(e.toString());
    }
  }

  /// Decrypt envelope (used by communication_service.dart)
  /// 
  /// ✅ DUAL-KEY:
  /// - recipientPrivateKey: X25519 private key (32 bytes) - for decryption
  /// - recipientPublicKey: X25519 public key (32 bytes) - for multi-recipient lookup
  Future<DecryptResult> decrypt({
    required GnsEnvelope envelope,
    required Uint8List recipientPrivateKey,  // ✅ X25519 private key
    required Uint8List recipientPublicKey,   // ✅ X25519 public key
  }) async {
    try {
      // Validate key lengths
      if (recipientPrivateKey.length != 32) {
        return DecryptResult.failure(
          'Invalid X25519 private key length: ${recipientPrivateKey.length} (expected 32)'
        );
      }
      if (recipientPublicKey.length != 32) {
        return DecryptResult.failure(
          'Invalid X25519 public key length: ${recipientPublicKey.length} (expected 32)'
        );
      }
      
      if (envelope.recipientKeys != null) {
        return _decryptMultiRecipient(
          envelope,
          recipientPrivateKey,
          recipientPublicKey,
        );
      } else {
        return _decryptSingleRecipient(
          envelope,
          recipientPrivateKey,
          recipientPublicKey, 
        );
      }
    } catch (e) {
      debugPrint('Decryption error: $e');
      return DecryptResult.failure(e.toString());
    }
  }

  // ==========================================================================
  // SIGNATURE OPERATIONS (Ed25519 keys, NOT X25519!)
  // ==========================================================================

  /// Sign envelope with Ed25519 private key
  /// 
  /// ✅ DUAL-KEY: privateKey is Ed25519 (32 bytes seed)
  /// 
  /// Process:
  /// 1. Get canonical JSON from envelope
  /// 2. Hash canonical JSON with SHA256
  /// 3. Sign the hash with Ed25519
  /// 4. Return signature as base64
  Future<String> signEnvelope({
    required GnsEnvelope envelope,
    required Uint8List privateKey,  // ✅ Ed25519 private key (32 bytes seed)
  }) async {
    try {
      if (privateKey.length != 32) {
        throw ArgumentError('Ed25519 private key must be 32 bytes (seed)');
      }
      
      // 1. Get canonical JSON (sorted keys, compact)
      final canonical = envelope.canonicalJson;
      debugPrint('🔏 Signing envelope: ${envelope.id}');
      if (kDebugMode) {
        debugPrint('   Canonical: ${canonical.substring(0, min(100, canonical.length))}...');
      }
      
      // 2. Convert to UTF-8 bytes
      final canonicalBytes = utf8.encode(canonical);
      
      // 3. Hash with SHA256 (CRITICAL - must match server)
      final hash = crypto.sha256.convert(canonicalBytes).bytes;
      if (kDebugMode) {
        final hashHex = hash.take(16).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
        debugPrint('   Hash (first 16 bytes): $hashHex...');
      }
      
      // 4. Sign the hash with Ed25519
      final algorithm = Ed25519();
      final keyPair = await algorithm.newKeyPairFromSeed(privateKey);
      
      final signature = await algorithm.sign(
        Uint8List.fromList(hash),  // Sign HASH, not canonical
        keyPair: keyPair,
      );
      
      // 5. Return as base64
      final signatureBase64 = base64Encode(signature.bytes);
      if (kDebugMode) {
        debugPrint('   Signature: ${signatureBase64.substring(0, min(32, signatureBase64.length))}...');
      }
      
      return signatureBase64;
    } catch (e) {
      debugPrint('   ❌ Signing error: $e');
      rethrow;
    }
  }

  /// Verify envelope signature with Ed25519 public key
  /// 
  /// ✅ DUAL-KEY: senderPublicKey is Ed25519 (32 bytes)
  /// ✅ FIXED: Now handles both HEX (from backend) and BASE64 (from Flutter) signatures
  /// 
  /// Process:
  /// 1. Get canonical JSON from envelope
  /// 2. Hash canonical JSON with SHA256
  /// 3. Verify signature against the hash using Ed25519
  Future<bool> verifyEnvelope({
    required GnsEnvelope envelope,
    required Uint8List senderPublicKey,  // ✅ Ed25519 public key (32 bytes)
  }) async {
    try {
      if (senderPublicKey.length != 32) {
        debugPrint('   ❌ Invalid Ed25519 public key length: ${senderPublicKey.length}');
        return false;
      }
      
      // 1. Get canonical JSON (sorted keys, compact)
      final canonical = envelope.canonicalJson;
      debugPrint('🔍 Verifying envelope: ${envelope.id}');
      if (kDebugMode) {
        debugPrint('   From: ${envelope.fromPublicKey.substring(0, 16)}...');
        debugPrint('   Canonical: ${canonical.substring(0, min(100, canonical.length))}...');
      }
      
      // 2. Convert to UTF-8 bytes
      final canonicalBytes = utf8.encode(canonical);
      
      // 3. Hash with SHA256 (CRITICAL - must match signing)
      final hash = crypto.sha256.convert(canonicalBytes).bytes;
      if (kDebugMode) {
        final hashHex = hash.take(16).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
        debugPrint('   Hash (first 16 bytes): $hashHex...');
      }
      
      // 4. Parse signature - handle both HEX and BASE64 formats
      // ✅ FIX: Backend (email gateway, echo bot) sends HEX (128 chars for 64 bytes)
      //         Flutter clients send BASE64 (88 chars for 64 bytes)
      Uint8List signatureBytes;
      if (envelope.signature.length == 128 && _isHexString(envelope.signature)) {
        // HEX format (from email gateway and echo bot)
        signatureBytes = _hexToBytes(envelope.signature);
        debugPrint('   Signature format: HEX (${envelope.signature.length} chars → ${signatureBytes.length} bytes)');
      } else {
        // BASE64 format (from Flutter clients)
        signatureBytes = base64Decode(envelope.signature);
        debugPrint('   Signature format: BASE64 (${envelope.signature.length} chars → ${signatureBytes.length} bytes)');
      }
      
      if (signatureBytes.length != 64) {
        debugPrint('   ❌ Invalid signature length: ${signatureBytes.length} bytes (expected 64)');
        return false;
      }
      
      // 5. Verify with Ed25519
      final algorithm = Ed25519();
      final publicKey = SimplePublicKey(senderPublicKey, type: KeyPairType.ed25519);
      final signature = Signature(signatureBytes, publicKey: publicKey);
      
      final isValid = await algorithm.verify(
        Uint8List.fromList(hash),  // Verify HASH, not canonical
        signature: signature,
      );
      
      if (isValid) {
        debugPrint('   ✅ Signature VALID');
      } else {
        debugPrint('   ❌ Signature INVALID');
      }
      
      return isValid;
    } catch (e) {
      debugPrint('   ❌ Verification error: $e');
      return false;
    }
  }

  /// Check if a string is valid hexadecimal
  bool _isHexString(String s) {
    final hexRegex = RegExp(r'^[0-9a-fA-F]+$');
    return hexRegex.hasMatch(s);
  }

  // ==========================================================================
  // ENCRYPTION IMPLEMENTATION (X25519 keys)
  // ==========================================================================

  /// Single-recipient encryption with ephemeral key
  /// 
  /// ✅ DUAL-KEY: recipientPublicKey is X25519 (32 bytes)
  Future<EncryptResult> _encryptSingleRecipient(
    Uint8List payload,
    Uint8List recipientPublicKey,  // ✅ X25519 public key
  ) async {
    try {
      debugPrint('🔐 Encrypting for recipient (X25519)');
      
      // Generate ephemeral X25519 keypair
      final x25519 = X25519();
      final ephemeralKeyPair = await x25519.newKeyPair();
      final ephemeralPublic = await ephemeralKeyPair.extractPublicKey();

      // Derive shared secret with recipient's X25519 public key
      final sharedSecret = await x25519.sharedSecretKey(
        keyPair: ephemeralKeyPair,
        remotePublicKey: SimplePublicKey(
          recipientPublicKey,  // ✅ Already X25519
          type: KeyPairType.x25519,
        ),
      );
      final sharedBytes = await sharedSecret.extractBytes();

    final infoBytes = Uint8List.fromList([
      ...utf8.encode('$_hkdfInfo:'),
      ...ephemeralPublic.bytes,
      ...recipientPublicKey,
    ]);
    
    final algorithm = Hkdf(
      hmac: Hmac(Sha256()),
      outputLength: 32,
    );
    final derivedKey = await algorithm.deriveKey(
      secretKey: SecretKey(sharedBytes),
      nonce: [],
      info: infoBytes,
    );
      final keyBytes = await derivedKey.extractBytes();

      // Generate nonce
      final nonce = _generateNonce();

      // Encrypt with ChaCha20-Poly1305
      final cipher = Chacha20.poly1305Aead();
      final secretBox = await cipher.encrypt(
        payload,
        secretKey: SecretKey(keyBytes),
        nonce: nonce,
      );

      // Combine ciphertext + MAC
      final encrypted = Uint8List.fromList([
        ...secretBox.cipherText,
        ...secretBox.mac.bytes,
      ]);

      debugPrint('   ✅ Encrypted ${payload.length} bytes');

      return EncryptResult.success(
        encryptedPayload: base64Encode(encrypted),
        ephemeralPublicKey: base64Encode(ephemeralPublic.bytes),
        nonce: base64Encode(nonce),
        payloadSize: payload.length,
      );
    } catch (e) {
      debugPrint('   ❌ Single-recipient encryption error: $e');
      return EncryptResult.failure(e.toString());
    }
  }

  /// Multi-recipient encryption (hybrid)
  /// 
  /// ✅ DUAL-KEY: All recipient keys are X25519 (32 bytes)
  Future<EncryptResult> _encryptMultiRecipient(
    Uint8List payload,
    List<Uint8List> recipientPublicKeys,  // ✅ X25519 public keys
  ) async {
    try {
      debugPrint('🔐 Encrypting for ${recipientPublicKeys.length} recipients (X25519)');
      
      // Generate random symmetric key
      final symmetricKey = _generateSymmetricKey();

      // Encrypt payload with symmetric key
      final nonce = _generateNonce();
      final cipher = Chacha20.poly1305Aead();
      final secretBox = await cipher.encrypt(
        payload,
        secretKey: SecretKey(symmetricKey),
        nonce: nonce,
      );

      // Combine ciphertext + MAC
      final encrypted = Uint8List.fromList([
        ...secretBox.cipherText,
        ...secretBox.mac.bytes,
      ]);

      // Encrypt symmetric key for each recipient
      final recipientKeys = <String, String>{};
      for (var recipientPk in recipientPublicKeys) {
        final encryptedKey = await _encryptSymmetricKeyForRecipient(
          symmetricKey,
          recipientPk,  // ✅ X25519 public key
        );
        final recipientHex = _bytesToHex(recipientPk);
        recipientKeys[recipientHex] = encryptedKey;
      }

      debugPrint('   ✅ Encrypted ${payload.length} bytes for ${recipientPublicKeys.length} recipients');

      return EncryptResult.success(
        encryptedPayload: base64Encode(encrypted),
        ephemeralPublicKey: '',  // Not used in multi-recipient
        nonce: base64Encode(nonce),
        payloadSize: payload.length,
        recipientKeys: recipientKeys,
      );
    } catch (e) {
      debugPrint('   ❌ Multi-recipient encryption error: $e');
      return EncryptResult.failure(e.toString());
    }
  }

  // ==========================================================================
  // DECRYPTION IMPLEMENTATION (X25519 keys)
  // ==========================================================================

  /// Single-recipient decryption
  /// 
  /// ✅ DUAL-KEY: recipientPrivateKey is X25519 (32 bytes)
  Future<DecryptResult> _decryptSingleRecipient(
    GnsEnvelope envelope,
    Uint8List recipientPrivateKey,  // ✅ X25519 private key (32 bytes)
    Uint8List recipientPublicKey,   
  ) async {
    try {
      debugPrint('🔓 Decrypting message (X25519)');
      
      // Parse envelope data
      final encryptedBytes = base64Decode(envelope.encryptedPayload);
      
      // ✅ FIX: Handle ephemeralPublicKey in both HEX and BASE64 formats
      Uint8List ephemeralPublicBytes;
      if (envelope.ephemeralPublicKey.length == 64 && _isHexString(envelope.ephemeralPublicKey)) {
        // HEX format (from backend)
        ephemeralPublicBytes = _hexToBytes(envelope.ephemeralPublicKey);
      } else {
        // BASE64 format (from Flutter)
        ephemeralPublicBytes = base64Decode(envelope.ephemeralPublicKey);
      }
      
      final nonceBytes = base64Decode(envelope.nonce);
      
      final ciphertext = encryptedBytes.sublist(0, encryptedBytes.length - _macLength);
      final mac = Mac(encryptedBytes.sublist(encryptedBytes.length - _macLength));

      // ✅ DUAL-KEY: recipientPrivateKey is ALREADY X25519 (32 bytes)
      // NO CONVERSION NEEDED - use SimpleKeyPairData directly!
      final x25519 = X25519();
      final myKeyPair = SimpleKeyPairData(
        recipientPrivateKey,
        publicKey: SimplePublicKey(recipientPublicKey, type: KeyPairType.x25519),
        type: KeyPairType.x25519,
      );
      
      // Derive shared secret
      final sharedSecret = await x25519.sharedSecretKey(
        keyPair: myKeyPair,
        remotePublicKey: SimplePublicKey(
          ephemeralPublicBytes,
          type: KeyPairType.x25519,
        ),
      );
      final sharedBytes = await sharedSecret.extractBytes();

      // DEBUG: Log keys for troubleshooting
      final myPublicKey = await myKeyPair.extractPublicKey();
      debugPrint('   🔑 My X25519 public: ${_bytesToHex(Uint8List.fromList(myPublicKey.bytes)).substring(0, 16)}...');
      debugPrint('   🔑 Ephemeral public: ${_bytesToHex(ephemeralPublicBytes).substring(0, 16)}...');
      debugPrint('   🔑 Shared secret: ${_bytesToHex(Uint8List.fromList(sharedBytes)).substring(0, 16)}...');

      // Derive decryption key with HKDF
      // ✅ CRITICAL: Info MUST include ephemeral + recipient (YOUR) public keys!
      // Format: "gns-envelope-v1:" + ephemeralPub (32 bytes) + recipientPub (32 bytes)
      final infoBytes = Uint8List.fromList([
        ...utf8.encode('$_hkdfInfo:'),
        ...ephemeralPublicBytes,
        ...recipientPublicKey,  // YOUR X25519 public key
      ]);
      
      final algorithm = Hkdf(
        hmac: Hmac(Sha256()),
        outputLength: 32,
      );
      final derivedKey = await algorithm.deriveKey(
        secretKey: SecretKey(sharedBytes),
        nonce: [],
        info: infoBytes,
      );
      final keyBytes = await derivedKey.extractBytes();

      // Decrypt
      final cipher = Chacha20.poly1305Aead();
      final decrypted = await cipher.decrypt(
        SecretBox(ciphertext, nonce: nonceBytes, mac: mac),
        secretKey: SecretKey(keyBytes),
      );

      debugPrint('   ✅ Decrypted ${decrypted.length} bytes');

      return DecryptResult.success(Uint8List.fromList(decrypted));
    } catch (e) {
      debugPrint('   ❌ Single-recipient decryption error: $e');
      return DecryptResult.failure(e.toString());
    }
  }

  /// Multi-recipient decryption
  /// 
  /// ✅ DUAL-KEY:
  /// - recipientPrivateKey: X25519 private key (32 bytes)
  /// - recipientPublicKey: X25519 public key (32 bytes) - for lookup
  Future<DecryptResult> _decryptMultiRecipient(
    GnsEnvelope envelope,
    Uint8List recipientPrivateKey,  // ✅ X25519 private key
    Uint8List recipientPublicKey,   // ✅ X25519 public key
  ) async {
    try {
      debugPrint('🔓 Decrypting multi-recipient message (X25519)');
      
      // Look up encrypted symmetric key using X25519 public key
      final recipientKeyHex = _bytesToHex(recipientPublicKey);
      final encryptedSymmetricKey = envelope.recipientKeys![recipientKeyHex];
      
      if (encryptedSymmetricKey == null) {
        return DecryptResult.failure('No encrypted key for this recipient');
      }

      // Decrypt symmetric key using X25519 private key
      final symmetricKey = await _decryptSymmetricKeyForRecipient(
        encryptedSymmetricKey,
        recipientPrivateKey,  // ✅ X25519 private key
      );

      // Decrypt payload with symmetric key
      final encryptedBytes = base64Decode(envelope.encryptedPayload);
      final nonceBytes = base64Decode(envelope.nonce);
      
      final ciphertext = encryptedBytes.sublist(0, encryptedBytes.length - _macLength);
      final mac = Mac(encryptedBytes.sublist(encryptedBytes.length - _macLength));

      final cipher = Chacha20.poly1305Aead();
      final decrypted = await cipher.decrypt(
        SecretBox(ciphertext, nonce: nonceBytes, mac: mac),
        secretKey: SecretKey(symmetricKey),
      );

      debugPrint('   ✅ Decrypted ${decrypted.length} bytes');

      return DecryptResult.success(Uint8List.fromList(decrypted));
    } catch (e) {
      debugPrint('   ❌ Multi-recipient decryption error: $e');
      return DecryptResult.failure(e.toString());
    }
  }

  // ==========================================================================
  // HELPER FUNCTIONS
  // ==========================================================================

  Uint8List _generateNonce() {
    final random = Random.secure();
    return Uint8List.fromList(
      List.generate(_nonceLength, (_) => random.nextInt(256)),
    );
  }

  Uint8List _generateSymmetricKey() {
    final random = Random.secure();
    return Uint8List.fromList(
      List.generate(32, (_) => random.nextInt(256)),
    );
  }

  /// Encrypt symmetric key for recipient using X25519
  Future<String> _encryptSymmetricKeyForRecipient(
    Uint8List symmetricKey,
    Uint8List recipientPublicKey,  // ✅ X25519 public key
  ) async {
    final x25519 = X25519();
    final ephemeralKeyPair = await x25519.newKeyPair();
    final ephemeralPublic = await ephemeralKeyPair.extractPublicKey();

    final sharedSecret = await x25519.sharedSecretKey(
      keyPair: ephemeralKeyPair,
      remotePublicKey: SimplePublicKey(
        recipientPublicKey,  // ✅ Already X25519
        type: KeyPairType.x25519,
      ),
    );
    final sharedBytes = await sharedSecret.extractBytes();

    final nonce = _generateNonce();
    final cipher = Chacha20.poly1305Aead();
    final secretBox = await cipher.encrypt(
      symmetricKey,
      secretKey: SecretKey(sharedBytes),
      nonce: nonce,
    );

    final encrypted = Uint8List.fromList([
      ...secretBox.cipherText,
      ...secretBox.mac.bytes,
    ]);

    return jsonEncode({
      'ephemeral_public_key': base64Encode(ephemeralPublic.bytes),
      'nonce': base64Encode(nonce),
      'encrypted_key': base64Encode(encrypted),
    });
  }

  /// Decrypt symmetric key for recipient using X25519
  Future<Uint8List> _decryptSymmetricKeyForRecipient(
    String encryptedData,
    Uint8List recipientPrivateKey,  // ✅ X25519 private key
  ) async {
    final data = jsonDecode(encryptedData);
    final ephemeralPublicBytes = base64Decode(data['ephemeral_public_key']);
    final nonceBytes = base64Decode(data['nonce']);
    final encryptedKeyBytes = base64Decode(data['encrypted_key']);

    final ciphertext = encryptedKeyBytes.sublist(0, encryptedKeyBytes.length - _macLength);
    final mac = Mac(encryptedKeyBytes.sublist(encryptedKeyBytes.length - _macLength));

    // ✅ DUAL-KEY: recipientPrivateKey is ALREADY X25519
    final x25519 = X25519();
    final myKeyPair = await x25519.newKeyPairFromSeed(recipientPrivateKey);
    
    final sharedSecret = await x25519.sharedSecretKey(
      keyPair: myKeyPair,
      remotePublicKey: SimplePublicKey(
        ephemeralPublicBytes,
        type: KeyPairType.x25519,
      ),
    );
    final sharedBytes = await sharedSecret.extractBytes();

    final cipher = Chacha20.poly1305Aead();
    final decrypted = await cipher.decrypt(
      SecretBox(ciphertext, nonce: nonceBytes, mac: mac),
      secretKey: SecretKey(sharedBytes),
    );

    return Uint8List.fromList(decrypted);
  }

  String _bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Uint8List _hexToBytes(String hex) {
    final result = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < hex.length; i += 2) {
      result[i ~/ 2] = int.parse(hex.substring(i, i + 2), radix: 16);
    }
    return result;
  }
}
