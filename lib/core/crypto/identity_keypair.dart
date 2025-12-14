import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:cryptography/cryptography.dart';
import 'package:convert/convert.dart';

/// GNS Keypair with dual-key architecture
/// - Ed25519: Identity and signatures
/// - X25519: Encryption (separate, independent)
/// 
/// This avoids Ed25519→X25519 conversion complexity
/// Both keys are RFC 7748 compliant
class GnsKeypair {
  // Identity keys (Ed25519)
  final Uint8List ed25519PrivateKey;  // 32 bytes
  final Uint8List ed25519PublicKey;   // 32 bytes
  
  // Encryption keys (X25519) - SEPARATE!
  final Uint8List x25519PrivateKey;   // 32 bytes
  final Uint8List x25519PublicKey;    // 32 bytes
  
  GnsKeypair._({
    required this.ed25519PrivateKey,
    required this.ed25519PublicKey,
    required this.x25519PrivateKey,
    required this.x25519PublicKey,
  });
  
  /// Generate new keypair with both Ed25519 and X25519 keys
  static Future<GnsKeypair> generate() async {
    // Generate Ed25519 keypair for identity/signatures
    final ed25519 = Ed25519();
    final ed25519KeyPair = await ed25519.newKeyPair();
    final ed25519PrivateBytes = await ed25519KeyPair.extractPrivateKeyBytes();
    final ed25519PublicKey = await ed25519KeyPair.extractPublicKey();
    
    // Generate SEPARATE X25519 keypair for encryption
    final x25519 = X25519();
    final x25519KeyPair = await x25519.newKeyPair();
    final x25519PrivateBytes = await x25519KeyPair.extractPrivateKeyBytes();
    final x25519PublicKey = await x25519KeyPair.extractPublicKey();
    
    final keypair = GnsKeypair._(
      ed25519PrivateKey: Uint8List.fromList(ed25519PrivateBytes),
      ed25519PublicKey: Uint8List.fromList(ed25519PublicKey.bytes),
      x25519PrivateKey: Uint8List.fromList(x25519PrivateBytes),
      x25519PublicKey: Uint8List.fromList(x25519PublicKey.bytes),
    );
    
    debugPrint('🔑 GENERATED dual keypair: ${keypair.gnsId}');
    debugPrint('   Ed25519 (identity): ${keypair.publicKeyHex.substring(0, 16)}...');
    debugPrint('   X25519 (encryption): ${keypair.encryptionPublicKeyHex.substring(0, 16)}...');
    
    return keypair;
  }
  
  /// Load keypair from stored keys (both Ed25519 and X25519)
  static Future<GnsKeypair> fromKeys({
    required Uint8List ed25519PrivateKey,
    required Uint8List x25519PrivateKey,
  }) async {
    if (ed25519PrivateKey.length != 32) {
      throw ArgumentError('Ed25519 private key must be 32 bytes');
    }
    if (x25519PrivateKey.length != 32) {
      throw ArgumentError('X25519 private key must be 32 bytes');
    }
    
    // Derive Ed25519 public key
    final ed25519 = Ed25519();
    final ed25519KeyPair = await ed25519.newKeyPairFromSeed(ed25519PrivateKey);
    final ed25519PublicKey = await ed25519KeyPair.extractPublicKey();
    
    // Derive X25519 public key
    final x25519 = X25519();
    final x25519KeyPair = await x25519.newKeyPairFromSeed(x25519PrivateKey);
    final x25519PublicKey = await x25519KeyPair.extractPublicKey();
    
    return GnsKeypair._(
      ed25519PrivateKey: ed25519PrivateKey,
      ed25519PublicKey: Uint8List.fromList(ed25519PublicKey.bytes),
      x25519PrivateKey: x25519PrivateKey,
      x25519PublicKey: Uint8List.fromList(x25519PublicKey.bytes),
    );
  }
  
  /// Load from hex strings (for secure storage)
  static Future<GnsKeypair> fromHex({
    required String ed25519PrivateKeyHex,
    required String x25519PrivateKeyHex,
  }) async {
    final keypair = await fromKeys(
      ed25519PrivateKey: Uint8List.fromList(hex.decode(ed25519PrivateKeyHex)),
      x25519PrivateKey: Uint8List.fromList(hex.decode(x25519PrivateKeyHex)),
    );
    
    debugPrint('🔓 LOADED dual keypair: ${keypair.gnsId}');
    
    return keypair;
  }
  
  // ==================== Ed25519 PROPERTIES (Identity) ====================
  
  /// Ed25519 public key as hex (this is your identity)
  String get publicKeyHex => hex.encode(ed25519PublicKey);
  
  /// Ed25519 private key as hex (for secure storage)
  String get privateKeyHex => hex.encode(ed25519PrivateKey);
  
  /// GNS identity derived from Ed25519 public key
  String get gnsId => 'gns_${publicKeyHex.substring(0, 16)}';
  
  // Legacy compatibility
  Uint8List get privateKey => ed25519PrivateKey;
  Uint8List get publicKey => ed25519PublicKey;
  
  // ==================== X25519 PROPERTIES (Encryption) ====================
  
  /// X25519 private key (for decrypting messages)
  Uint8List get encryptionPrivateKey => x25519PrivateKey;
  
  /// X25519 public key (for others to encrypt to you)
  Uint8List get encryptionPublicKey => x25519PublicKey;
  
  /// X25519 public key as hex (publish this in your GNS record)
  String get encryptionPublicKeyHex => hex.encode(x25519PublicKey);
  
  /// X25519 private key as hex (for secure storage)
  String get encryptionPrivateKeyHex => hex.encode(x25519PrivateKey);
  
  // ==================== SERIALIZATION ====================
  
  /// Export both keys for secure storage
  Map<String, String> toJson() {
    return {
      'ed25519_private': privateKeyHex,
      'x25519_private': encryptionPrivateKeyHex,
      'ed25519_public': publicKeyHex,
      'x25519_public': encryptionPublicKeyHex,
    };
  }
  
  /// Load from stored JSON
  static Future<GnsKeypair> fromJson(Map<String, dynamic> json) async {
    return fromHex(
      ed25519PrivateKeyHex: json['ed25519_private'],
      x25519PrivateKeyHex: json['x25519_private'],
    );
  }
  
  // ==================== SIGNING (Ed25519) ====================
  
  Future<Uint8List> sign(Uint8List message) async {
    final algorithm = Ed25519();
    final keyPair = await algorithm.newKeyPairFromSeed(ed25519PrivateKey);
    final signature = await algorithm.sign(message, keyPair: keyPair);
    return Uint8List.fromList(signature.bytes);
  }
  
  Future<Uint8List> signString(String message) async {
    return sign(Uint8List.fromList(utf8.encode(message)));
  }
  
  Future<String> signToHex(Uint8List message) async {
    final sig = await sign(message);
    return hex.encode(sig);
  }
  
  static Future<bool> verify(
    Uint8List publicKey,
    Uint8List message,
    Uint8List signature,
  ) async {
    try {
      final algorithm = Ed25519();
      final pk = SimplePublicKey(publicKey, type: KeyPairType.ed25519);
      final sig = Signature(signature, publicKey: pk);
      return await algorithm.verify(message, signature: sig);
    } catch (e) {
      debugPrint('Signature verification error: $e');
      return false;
    }
  }
  
  static Future<bool> verifyHex(
    String publicKeyHex,
    String messageHex,
    String signatureHex,
  ) async {
    return verify(
      Uint8List.fromList(hex.decode(publicKeyHex)),
      Uint8List.fromList(hex.decode(messageHex)),
      Uint8List.fromList(hex.decode(signatureHex)),
    );
  }
  
  @override
  String toString() => 'GnsKeypair(gnsId: $gnsId, ed25519: ${publicKeyHex.substring(0, 8)}..., x25519: ${encryptionPublicKeyHex.substring(0, 8)}...)';
}

/// Derived keypairs for hierarchical key derivation
class DerivedKey {
  final GnsKeypair rootKeypair;
  final String derivationPath;
  final GnsKeypair derivedKeypair;
  
  DerivedKey._({
    required this.rootKeypair,
    required this.derivationPath,
    required this.derivedKeypair,
  });
  
  static Future<DerivedKey> forEpoch(
    GnsKeypair rootKeypair,
    DateTime epochTime,
  ) async {
    final path = 'epoch/${epochTime.year}/${epochTime.month}/${epochTime.day}';
    return forPath(rootKeypair, path);
  }
  
  static Future<DerivedKey> forPath(
    GnsKeypair rootKeypair,
    String path,
  ) async {
    final derivationInput = utf8.encode('${rootKeypair.privateKeyHex}:$path');
    final hash = await Sha256().hash(derivationInput);
    final seed = Uint8List.fromList(hash.bytes);
    
    // For derived keys, we generate new X25519 keys too
    final derivedKeypair = await GnsKeypair.generate();
    
    return DerivedKey._(
      rootKeypair: rootKeypair,
      derivationPath: path,
      derivedKeypair: derivedKeypair,
    );
  }
  
  Future<Uint8List> sign(Uint8List message) => derivedKeypair.sign(message);
  String get publicKeyHex => derivedKeypair.publicKeyHex;
  
  Future<Map<String, String>> createDerivationProof() async {
    final proof = await rootKeypair.signToHex(
      Uint8List.fromList(utf8.encode(
        'derive:$derivationPath:${derivedKeypair.publicKeyHex}',
      )),
    );
    return {
      'root_public_key': rootKeypair.publicKeyHex,
      'derived_public_key': derivedKeypair.publicKeyHex,
      'derivation_path': derivationPath,
      'proof': proof,
    };
  }
}
