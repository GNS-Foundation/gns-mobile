/// GNS NFC Protocol - Secure Tap-to-Pay Implementation
/// 
/// Sprint 1: Core NFC cryptographic protocol for contactless payments
/// 
/// Features:
/// - NDEF message format for GNS payment tokens
/// - ChaCha20-Poly1305 authenticated encryption
/// - Ed25519 signature creation and verification
/// - Replay attack prevention with nonce tracking
/// - Secure session establishment
/// 
/// Location: lib/core/nfc/nfc_protocol.dart

import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:crypto/crypto.dart' as crypto;

// =============================================================================
// CONSTANTS & CONFIGURATION
// =============================================================================

/// NFC Protocol version for forward compatibility
const int kNfcProtocolVersion = 1;

/// NDEF record type for GNS payments
const String kNdefTypeGnsPayment = 'application/vnd.gns.payment';

/// NDEF record type for GNS auth challenge
const String kNdefTypeGnsChallenge = 'application/vnd.gns.challenge';

/// NDEF record type for GNS auth response
const String kNdefTypeGnsResponse = 'application/vnd.gns.response';

/// Maximum age for a valid nonce (prevents replay attacks)
const Duration kNonceMaxAge = Duration(minutes: 5);

/// Maximum future timestamp tolerance (clock skew)
const Duration kTimestampFutureTolerance = Duration(seconds: 30);

/// Nonce length in bytes
const int kNonceLength = 16;

/// Session key length
const int kSessionKeyLength = 32;

/// MAC length for ChaCha20-Poly1305
const int kMacLength = 16;

// =============================================================================
// DATA STRUCTURES
// =============================================================================

/// NFC Payment Token - transmitted via NDEF
/// 
/// Structure:
/// ```
/// +------------------+
/// | version (1 byte) |
/// +------------------+
/// | flags (1 byte)   |
/// +------------------+
/// | timestamp (8)    |
/// +------------------+
/// | nonce (16)       |
/// +------------------+
/// | merchant_pk (32) |
/// +------------------+
/// | amount (8 bytes) |
/// +------------------+
/// | currency (3)     |
/// +------------------+
/// | h3_cell (15)     |
/// +------------------+
/// | enc_payload (var)|
/// +------------------+
/// | signature (64)   |
/// +------------------+
/// ```
class NfcPaymentToken {
  /// Protocol version
  final int version;
  
  /// Flags: bit 0 = requires geo-auth, bit 1 = encrypted, bit 2 = has memo
  final int flags;
  
  /// Unix timestamp in milliseconds
  final int timestamp;
  
  /// Random nonce (16 bytes)
  final Uint8List nonce;
  
  /// Merchant's Ed25519 public key (32 bytes)
  final Uint8List merchantPublicKey;
  
  /// Amount in minor units (e.g., cents)
  final int amountMinorUnits;
  
  /// ISO 4217 currency code (3 chars)
  final String currency;
  
  /// H3 cell index (resolution 8, 15 chars)
  final String h3Cell;
  
  /// Encrypted payload (if flags.bit1 set)
  final Uint8List? encryptedPayload;
  
  /// Ed25519 signature over all preceding fields
  final Uint8List signature;

  NfcPaymentToken({
    this.version = kNfcProtocolVersion,
    required this.flags,
    required this.timestamp,
    required this.nonce,
    required this.merchantPublicKey,
    required this.amountMinorUnits,
    required this.currency,
    required this.h3Cell,
    this.encryptedPayload,
    required this.signature,
  });

  /// Check if geo-auth is required
  bool get requiresGeoAuth => (flags & 0x01) != 0;
  
  /// Check if payload is encrypted
  bool get isEncrypted => (flags & 0x02) != 0;
  
  /// Check if memo is present
  bool get hasMemo => (flags & 0x04) != 0;

  /// Format amount for display
  String get amountDisplay {
    final major = amountMinorUnits ~/ 100;
    final minor = amountMinorUnits % 100;
    final symbol = _currencySymbols[currency] ?? currency;
    return '$symbol$major.${minor.toString().padLeft(2, '0')}';
  }

  static const _currencySymbols = {
    'EUR': '€',
    'USD': '\$',
    'GBP': '£',
  };

  /// Serialize to bytes for NFC transmission
  Uint8List toBytes() {
    final buffer = BytesBuilder();
    
    // Header
    buffer.addByte(version);
    buffer.addByte(flags);
    
    // Timestamp (8 bytes, big endian)
    buffer.add(_int64ToBytes(timestamp));
    
    // Nonce (16 bytes)
    buffer.add(nonce);
    
    // Merchant public key (32 bytes)
    buffer.add(merchantPublicKey);
    
    // Amount (8 bytes, big endian)
    buffer.add(_int64ToBytes(amountMinorUnits));
    
    // Currency (3 bytes, ASCII)
    final currencyBytes = utf8.encode(currency.padRight(3).substring(0, 3));
    buffer.add(currencyBytes);
    
    // H3 cell (15 bytes, ASCII padded)
    final h3Bytes = utf8.encode(h3Cell.padRight(15).substring(0, 15));
    buffer.add(h3Bytes);
    
    // Encrypted payload (if present)
    if (encryptedPayload != null && encryptedPayload!.isNotEmpty) {
      // Length prefix (2 bytes)
      buffer.addByte((encryptedPayload!.length >> 8) & 0xFF);
      buffer.addByte(encryptedPayload!.length & 0xFF);
      buffer.add(encryptedPayload!);
    }
    
    // Signature (64 bytes)
    buffer.add(signature);
    
    return buffer.toBytes();
  }

  /// Deserialize from bytes
  factory NfcPaymentToken.fromBytes(Uint8List bytes) {
    if (bytes.length < 146) {  // Minimum size without encrypted payload
      throw FormatException('Invalid NFC token: too short (${bytes.length} bytes)');
    }
    
    int offset = 0;
    
    // Header
    final version = bytes[offset++];
    final flags = bytes[offset++];
    
    // Timestamp
    final timestamp = _bytesToInt64(bytes.sublist(offset, offset + 8));
    offset += 8;
    
    // Nonce
    final nonce = bytes.sublist(offset, offset + 16);
    offset += 16;
    
    // Merchant public key
    final merchantPk = bytes.sublist(offset, offset + 32);
    offset += 32;
    
    // Amount
    final amount = _bytesToInt64(bytes.sublist(offset, offset + 8));
    offset += 8;
    
    // Currency
    final currency = utf8.decode(bytes.sublist(offset, offset + 3)).trim();
    offset += 3;
    
    // H3 cell
    final h3Cell = utf8.decode(bytes.sublist(offset, offset + 15)).trim();
    offset += 15;
    
    // Encrypted payload (if present based on remaining size)
    Uint8List? encPayload;
    final hasEncrypted = (flags & 0x02) != 0;
    if (hasEncrypted && offset + 2 < bytes.length - 64) {
      final encLength = (bytes[offset] << 8) | bytes[offset + 1];
      offset += 2;
      if (offset + encLength <= bytes.length - 64) {
        encPayload = bytes.sublist(offset, offset + encLength);
        offset += encLength;
      }
    }
    
    // Signature (last 64 bytes)
    final signature = bytes.sublist(bytes.length - 64);
    
    return NfcPaymentToken(
      version: version,
      flags: flags,
      timestamp: timestamp,
      nonce: Uint8List.fromList(nonce),
      merchantPublicKey: Uint8List.fromList(merchantPk),
      amountMinorUnits: amount,
      currency: currency,
      h3Cell: h3Cell,
      encryptedPayload: encPayload,
      signature: Uint8List.fromList(signature),
    );
  }

  /// Get bytes to sign (everything except signature)
  Uint8List get signableBytes {
    final full = toBytes();
    return full.sublist(0, full.length - 64);
  }
}

/// Challenge from merchant terminal
class NfcChallenge {
  final int timestamp;
  final Uint8List nonce;
  final Uint8List merchantPublicKey;
  final int amountMinorUnits;
  final String currency;
  final String h3Cell;
  final String? memo;

  NfcChallenge({
    required this.timestamp,
    required this.nonce,
    required this.merchantPublicKey,
    required this.amountMinorUnits,
    required this.currency,
    required this.h3Cell,
    this.memo,
  });

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp,
    'nonce': base64Encode(nonce),
    'merchant_pk': base64Encode(merchantPublicKey),
    'amount': amountMinorUnits,
    'currency': currency,
    'h3_cell': h3Cell,
    if (memo != null) 'memo': memo,
  };

  factory NfcChallenge.fromJson(Map<String, dynamic> json) {
    return NfcChallenge(
      timestamp: json['timestamp'] as int,
      nonce: base64Decode(json['nonce'] as String),
      merchantPublicKey: base64Decode(json['merchant_pk'] as String),
      amountMinorUnits: json['amount'] as int,
      currency: json['currency'] as String,
      h3Cell: json['h3_cell'] as String,
      memo: json['memo'] as String?,
    );
  }
}

/// Response from user device
class NfcResponse {
  final Uint8List challengeNonce;  // Echo back challenge nonce
  final Uint8List userPublicKey;
  final String userH3Cell;
  final Uint8List signature;
  final Uint8List? encryptedBreadcrumb;

  NfcResponse({
    required this.challengeNonce,
    required this.userPublicKey,
    required this.userH3Cell,
    required this.signature,
    this.encryptedBreadcrumb,
  });

  Map<String, dynamic> toJson() => {
    'challenge_nonce': base64Encode(challengeNonce),
    'user_pk': base64Encode(userPublicKey),
    'user_h3': userH3Cell,
    'signature': base64Encode(signature),
    if (encryptedBreadcrumb != null) 'breadcrumb': base64Encode(encryptedBreadcrumb!),
  };

  factory NfcResponse.fromJson(Map<String, dynamic> json) {
    return NfcResponse(
      challengeNonce: base64Decode(json['challenge_nonce'] as String),
      userPublicKey: base64Decode(json['user_pk'] as String),
      userH3Cell: json['user_h3'] as String,
      signature: base64Decode(json['signature'] as String),
      encryptedBreadcrumb: json['breadcrumb'] != null 
          ? base64Decode(json['breadcrumb'] as String) 
          : null,
    );
  }
}

// =============================================================================
// REPLAY ATTACK PREVENTION
// =============================================================================

/// Nonce tracker to prevent replay attacks
/// 
/// Uses a sliding window approach:
/// 1. Track seen nonces with their timestamps
/// 2. Reject any nonce seen within the window
/// 3. Automatically prune old nonces
class NonceTracker {
  final Map<String, int> _seenNonces = {};
  final Duration _maxAge;
  int _lastPrune = 0;

  NonceTracker({Duration? maxAge}) : _maxAge = maxAge ?? kNonceMaxAge;

  /// Check if nonce is valid (not seen before and not too old)
  /// Returns true if nonce is valid and registers it
  bool validateAndRegister(Uint8List nonce, int timestamp) {
    final now = DateTime.now().millisecondsSinceEpoch;
    
    // Prune old nonces periodically
    if (now - _lastPrune > _maxAge.inMilliseconds ~/ 2) {
      _pruneOldNonces(now);
    }
    
    // Check timestamp validity
    if (!_isTimestampValid(timestamp, now)) {
      return false;
    }
    
    // Check if nonce was already seen
    final nonceKey = base64Encode(nonce);
    if (_seenNonces.containsKey(nonceKey)) {
      return false;  // Replay attack detected!
    }
    
    // Register the nonce
    _seenNonces[nonceKey] = timestamp;
    return true;
  }

  /// Check if a nonce has been seen (without registering)
  bool hasSeenNonce(Uint8List nonce) {
    return _seenNonces.containsKey(base64Encode(nonce));
  }

  /// Validate timestamp is within acceptable range
  bool _isTimestampValid(int timestamp, int now) {
    // Not too old
    if (now - timestamp > _maxAge.inMilliseconds) {
      return false;
    }
    // Not too far in future (allow some clock skew)
    if (timestamp - now > kTimestampFutureTolerance.inMilliseconds) {
      return false;
    }
    return true;
  }

  /// Remove expired nonces from tracking
  void _pruneOldNonces(int now) {
    final cutoff = now - _maxAge.inMilliseconds;
    _seenNonces.removeWhere((_, timestamp) => timestamp < cutoff);
    _lastPrune = now;
  }

  /// Get statistics
  Map<String, dynamic> get stats => {
    'tracked_nonces': _seenNonces.length,
    'max_age_ms': _maxAge.inMilliseconds,
  };

  /// Clear all tracked nonces
  void clear() {
    _seenNonces.clear();
    _lastPrune = 0;
  }
}

// =============================================================================
// NFC CRYPTO SERVICE
// =============================================================================

/// NFC-specific crypto operations
/// 
/// Provides high-level crypto functions for NFC payments:
/// - Session key derivation
/// - Payment token signing/verification
/// - Payload encryption/decryption
/// - Challenge-response authentication
class NfcCryptoService {
  static const String _hkdfInfo = 'gns-nfc-v1';
  static final _random = Random.secure();
  
  // Cached algorithm instances
  final _chacha = Chacha20.poly1305Aead();
  final _ed25519 = Ed25519();
  final _x25519 = X25519();

  /// Generate cryptographically secure nonce
  Uint8List generateNonce() {
    return Uint8List.fromList(
      List.generate(kNonceLength, (_) => _random.nextInt(256)),
    );
  }

  /// Generate session key from ECDH key exchange
  Future<Uint8List> deriveSessionKey({
    required Uint8List myPrivateKey,
    required Uint8List theirPublicKey,
    required Uint8List salt,
  }) async {
    // Perform X25519 key exchange
    final myKeyPair = await _x25519.newKeyPairFromSeed(myPrivateKey);
    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: myKeyPair,
      remotePublicKey: SimplePublicKey(
        theirPublicKey,
        type: KeyPairType.x25519,
      ),
    );
    final sharedBytes = await sharedSecret.extractBytes();

    // Derive session key using HKDF
    final hkdf = Hkdf(hmac: Hmac(Sha256()), outputLength: kSessionKeyLength);
    final derivedKey = await hkdf.deriveKey(
      secretKey: SecretKey(sharedBytes),
      nonce: salt,
      info: utf8.encode(_hkdfInfo),
    );
    
    return Uint8List.fromList(await derivedKey.extractBytes());
  }

  /// Sign payment data with Ed25519
  Future<Uint8List> signPaymentData({
    required Uint8List data,
    required Uint8List privateKey,
  }) async {
    if (privateKey.length != 32) {
      throw ArgumentError('Ed25519 private key must be 32 bytes');
    }
    
    // Hash the data first (consistent with GNS envelope signing)
    final hash = crypto.sha256.convert(data).bytes;
    
    // Sign the hash
    final keyPair = await _ed25519.newKeyPairFromSeed(privateKey);
    final signature = await _ed25519.sign(
      Uint8List.fromList(hash),
      keyPair: keyPair,
    );
    
    return Uint8List.fromList(signature.bytes);
  }

  /// Verify payment signature
  Future<bool> verifyPaymentSignature({
    required Uint8List data,
    required Uint8List signature,
    required Uint8List publicKey,
  }) async {
    if (publicKey.length != 32) {
      throw ArgumentError('Ed25519 public key must be 32 bytes');
    }
    if (signature.length != 64) {
      throw ArgumentError('Ed25519 signature must be 64 bytes');
    }
    
    try {
      // Hash the data
      final hash = crypto.sha256.convert(data).bytes;
      
      // Verify signature
      final isValid = await _ed25519.verify(
        Uint8List.fromList(hash),
        signature: Signature(
          signature,
          publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
        ),
      );
      
      return isValid;
    } catch (e) {
      return false;
    }
  }

  /// Encrypt payload with ChaCha20-Poly1305
  Future<EncryptedPayload> encryptPayload({
    required Uint8List plaintext,
    required Uint8List sessionKey,
    Uint8List? nonce,
  }) async {
    final actualNonce = nonce ?? generateNonce().sublist(0, 12);  // 12 bytes for ChaCha
    
    final secretBox = await _chacha.encrypt(
      plaintext,
      secretKey: SecretKey(sessionKey),
      nonce: actualNonce,
    );
    
    // Combine ciphertext + MAC
    final encrypted = Uint8List.fromList([
      ...secretBox.cipherText,
      ...secretBox.mac.bytes,
    ]);
    
    return EncryptedPayload(
      ciphertext: encrypted,
      nonce: actualNonce,
    );
  }

  /// Decrypt payload with ChaCha20-Poly1305
  Future<Uint8List> decryptPayload({
    required Uint8List ciphertext,
    required Uint8List nonce,
    required Uint8List sessionKey,
  }) async {
    if (ciphertext.length < kMacLength) {
      throw ArgumentError('Ciphertext too short');
    }
    
    final actualCiphertext = ciphertext.sublist(0, ciphertext.length - kMacLength);
    final mac = Mac(ciphertext.sublist(ciphertext.length - kMacLength));
    
    final decrypted = await _chacha.decrypt(
      SecretBox(actualCiphertext, nonce: nonce, mac: mac),
      secretKey: SecretKey(sessionKey),
    );
    
    return Uint8List.fromList(decrypted);
  }

  /// Create signed NFC payment token
  Future<NfcPaymentToken> createPaymentToken({
    required Uint8List merchantPrivateKey,
    required Uint8List merchantPublicKey,
    required int amountMinorUnits,
    required String currency,
    required String h3Cell,
    bool requireGeoAuth = true,
    Uint8List? additionalPayload,
    Uint8List? encryptionKey,
  }) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final nonce = generateNonce();
    
    // Calculate flags
    int flags = 0;
    if (requireGeoAuth) flags |= 0x01;
    
    // Encrypt additional payload if provided
    Uint8List? encPayload;
    if (additionalPayload != null && encryptionKey != null) {
      flags |= 0x02;
      final encrypted = await encryptPayload(
        plaintext: additionalPayload,
        sessionKey: encryptionKey,
      );
      encPayload = Uint8List.fromList([
        ...encrypted.nonce,
        ...encrypted.ciphertext,
      ]);
    }
    
    // Build signable data (without signature)
    final tempToken = NfcPaymentToken(
      flags: flags,
      timestamp: timestamp,
      nonce: nonce,
      merchantPublicKey: merchantPublicKey,
      amountMinorUnits: amountMinorUnits,
      currency: currency,
      h3Cell: h3Cell,
      encryptedPayload: encPayload,
      signature: Uint8List(64),  // Placeholder
    );
    
    // Sign the token data
    final signableData = tempToken.signableBytes;
    final signature = await signPaymentData(
      data: signableData,
      privateKey: merchantPrivateKey,
    );
    
    return NfcPaymentToken(
      flags: flags,
      timestamp: timestamp,
      nonce: nonce,
      merchantPublicKey: merchantPublicKey,
      amountMinorUnits: amountMinorUnits,
      currency: currency,
      h3Cell: h3Cell,
      encryptedPayload: encPayload,
      signature: signature,
    );
  }

  /// Verify NFC payment token
  Future<TokenVerificationResult> verifyPaymentToken(
    NfcPaymentToken token, {
    required NonceTracker nonceTracker,
    String? expectedH3Cell,
    int? maxDistanceResolution,
  }) async {
    // 1. Verify signature
    final signableData = token.signableBytes;
    final signatureValid = await verifyPaymentSignature(
      data: signableData,
      signature: token.signature,
      publicKey: token.merchantPublicKey,
    );
    if (!signatureValid) {
      return TokenVerificationResult.failure('Invalid signature');
    }
    
    // 2. Check replay protection
    if (!nonceTracker.validateAndRegister(token.nonce, token.timestamp)) {
      return TokenVerificationResult.failure('Replay attack detected or invalid timestamp');
    }
    
    // 3. Verify geo-location (if required and provided)
    if (token.requiresGeoAuth && expectedH3Cell != null) {
      if (!_verifyH3Proximity(token.h3Cell, expectedH3Cell, maxDistanceResolution ?? 8)) {
        return TokenVerificationResult.failure('Location mismatch');
      }
    }
    
    return TokenVerificationResult.success();
  }

  /// Verify H3 cell proximity
  bool _verifyH3Proximity(String merchantCell, String userCell, int resolution) {
    // For exact match at resolution 8
    if (merchantCell == userCell) return true;
    
    // Check parent cells for proximity (less strict matching)
    // Truncate to lower resolution for area matching
    final merchantPrefix = merchantCell.substring(0, min(resolution + 1, merchantCell.length));
    final userPrefix = userCell.substring(0, min(resolution + 1, userCell.length));
    
    return merchantPrefix == userPrefix;
  }

  /// Create challenge for NFC interaction
  NfcChallenge createChallenge({
    required Uint8List merchantPublicKey,
    required int amountMinorUnits,
    required String currency,
    required String h3Cell,
    String? memo,
  }) {
    return NfcChallenge(
      timestamp: DateTime.now().millisecondsSinceEpoch,
      nonce: generateNonce(),
      merchantPublicKey: merchantPublicKey,
      amountMinorUnits: amountMinorUnits,
      currency: currency,
      h3Cell: h3Cell,
      memo: memo,
    );
  }

  /// Sign challenge response
  Future<NfcResponse> signChallengeResponse({
    required NfcChallenge challenge,
    required Uint8List userPrivateKey,
    required Uint8List userPublicKey,
    required String userH3Cell,
    Uint8List? breadcrumbData,
    Uint8List? encryptionKey,
  }) async {
    // Build response data to sign
    final responseData = BytesBuilder();
    responseData.add(challenge.nonce);
    responseData.add(userPublicKey);
    responseData.add(utf8.encode(userH3Cell.padRight(15)));
    responseData.add(_int64ToBytes(challenge.timestamp));
    
    // Sign response
    final signature = await signPaymentData(
      data: responseData.toBytes(),
      privateKey: userPrivateKey,
    );
    
    // Encrypt breadcrumb if provided
    Uint8List? encBreadcrumb;
    if (breadcrumbData != null && encryptionKey != null) {
      final encrypted = await encryptPayload(
        plaintext: breadcrumbData,
        sessionKey: encryptionKey,
      );
      encBreadcrumb = Uint8List.fromList([
        ...encrypted.nonce,
        ...encrypted.ciphertext,
      ]);
    }
    
    return NfcResponse(
      challengeNonce: Uint8List.fromList(challenge.nonce),
      userPublicKey: userPublicKey,
      userH3Cell: userH3Cell,
      signature: signature,
      encryptedBreadcrumb: encBreadcrumb,
    );
  }

  /// Verify challenge response
  Future<bool> verifyChallengeResponse({
    required NfcChallenge challenge,
    required NfcResponse response,
    required NonceTracker nonceTracker,
  }) async {
    // Verify nonce matches
    if (!_bytesEqual(challenge.nonce, response.challengeNonce)) {
      return false;
    }
    
    // Check replay
    if (!nonceTracker.validateAndRegister(challenge.nonce, challenge.timestamp)) {
      return false;
    }
    
    // Rebuild response data
    final responseData = BytesBuilder();
    responseData.add(challenge.nonce);
    responseData.add(response.userPublicKey);
    responseData.add(utf8.encode(response.userH3Cell.padRight(15)));
    responseData.add(_int64ToBytes(challenge.timestamp));
    
    // Verify signature
    return verifyPaymentSignature(
      data: responseData.toBytes(),
      signature: response.signature,
      publicKey: response.userPublicKey,
    );
  }
}

/// Encrypted payload container
class EncryptedPayload {
  final Uint8List ciphertext;
  final Uint8List nonce;

  EncryptedPayload({
    required this.ciphertext,
    required this.nonce,
  });
}

/// Token verification result
class TokenVerificationResult {
  final bool isValid;
  final String? error;
  final Map<String, dynamic>? metadata;

  TokenVerificationResult._({
    required this.isValid,
    this.error,
    this.metadata,
  });

  factory TokenVerificationResult.success({Map<String, dynamic>? metadata}) {
    return TokenVerificationResult._(isValid: true, metadata: metadata);
  }

  factory TokenVerificationResult.failure(String error) {
    return TokenVerificationResult._(isValid: false, error: error);
  }
}

// =============================================================================
// NDEF MESSAGE BUILDER
// =============================================================================

/// Builder for NFC Data Exchange Format (NDEF) messages
class NdefMessageBuilder {
  final List<NdefRecord> _records = [];

  /// Add a GNS payment record
  void addPaymentToken(NfcPaymentToken token) {
    _records.add(NdefRecord(
      typeNameFormat: NdefTypeNameFormat.media,
      type: utf8.encode(kNdefTypeGnsPayment),
      payload: token.toBytes(),
    ));
  }

  /// Add a GNS challenge record
  void addChallenge(NfcChallenge challenge) {
    _records.add(NdefRecord(
      typeNameFormat: NdefTypeNameFormat.media,
      type: utf8.encode(kNdefTypeGnsChallenge),
      payload: utf8.encode(jsonEncode(challenge.toJson())),
    ));
  }

  /// Add a GNS response record
  void addResponse(NfcResponse response) {
    _records.add(NdefRecord(
      typeNameFormat: NdefTypeNameFormat.media,
      type: utf8.encode(kNdefTypeGnsResponse),
      payload: utf8.encode(jsonEncode(response.toJson())),
    ));
  }

  /// Add a text record (for fallback display)
  void addTextRecord(String text, {String languageCode = 'en'}) {
    final langBytes = utf8.encode(languageCode);
    final textBytes = utf8.encode(text);
    
    final payload = Uint8List(1 + langBytes.length + textBytes.length);
    payload[0] = langBytes.length;  // Status byte (language code length)
    payload.setRange(1, 1 + langBytes.length, langBytes);
    payload.setRange(1 + langBytes.length, payload.length, textBytes);
    
    _records.add(NdefRecord(
      typeNameFormat: NdefTypeNameFormat.wellKnown,
      type: Uint8List.fromList([0x54]),  // 'T' for text
      payload: payload,
    ));
  }

  /// Add a URI record
  void addUriRecord(String uri) {
    // Determine prefix code
    int prefixCode = 0;
    String actualUri = uri;
    
    for (final entry in _uriPrefixes.entries) {
      if (uri.startsWith(entry.value)) {
        prefixCode = entry.key;
        actualUri = uri.substring(entry.value.length);
        break;
      }
    }
    
    final uriBytes = utf8.encode(actualUri);
    final payload = Uint8List(1 + uriBytes.length);
    payload[0] = prefixCode;
    payload.setRange(1, payload.length, uriBytes);
    
    _records.add(NdefRecord(
      typeNameFormat: NdefTypeNameFormat.wellKnown,
      type: Uint8List.fromList([0x55]),  // 'U' for URI
      payload: payload,
    ));
  }

  static const _uriPrefixes = {
    0x00: '',
    0x01: 'http://www.',
    0x02: 'https://www.',
    0x03: 'http://',
    0x04: 'https://',
  };

  /// Build the complete NDEF message
  NdefMessage build() {
    return NdefMessage(records: List.unmodifiable(_records));
  }

  /// Clear all records
  void clear() {
    _records.clear();
  }
}

/// NDEF type name format
enum NdefTypeNameFormat {
  empty,
  wellKnown,
  media,
  absoluteUri,
  external,
  unknown,
  unchanged,
}

/// Single NDEF record
class NdefRecord {
  final NdefTypeNameFormat typeNameFormat;
  final Uint8List type;
  final Uint8List payload;
  final Uint8List? id;

  NdefRecord({
    required this.typeNameFormat,
    required this.type,
    required this.payload,
    this.id,
  });

  /// Serialize to bytes
  Uint8List toBytes({bool isFirst = false, bool isLast = false}) {
    final buffer = BytesBuilder();
    
    // Flags byte
    int flags = typeNameFormat.index & 0x07;
    if (isFirst) flags |= 0x80;  // MB (Message Begin)
    if (isLast) flags |= 0x40;   // ME (Message End)
    if (payload.length <= 255) flags |= 0x10;  // SR (Short Record)
    if (id != null && id!.isNotEmpty) flags |= 0x08;  // IL (ID Length present)
    buffer.addByte(flags);
    
    // Type length
    buffer.addByte(type.length);
    
    // Payload length (1 or 4 bytes based on SR flag)
    if (payload.length <= 255) {
      buffer.addByte(payload.length);
    } else {
      buffer.add(_int32ToBytes(payload.length));
    }
    
    // ID length (if present)
    if (id != null && id!.isNotEmpty) {
      buffer.addByte(id!.length);
    }
    
    // Type
    buffer.add(type);
    
    // ID (if present)
    if (id != null && id!.isNotEmpty) {
      buffer.add(id!);
    }
    
    // Payload
    buffer.add(payload);
    
    return buffer.toBytes();
  }

  /// Parse GNS-specific records
  static dynamic parseGnsRecord(NdefRecord record) {
    final typeStr = utf8.decode(record.type);
    
    switch (typeStr) {
      case kNdefTypeGnsPayment:
        return NfcPaymentToken.fromBytes(record.payload);
      case kNdefTypeGnsChallenge:
        return NfcChallenge.fromJson(
          jsonDecode(utf8.decode(record.payload)) as Map<String, dynamic>,
        );
      case kNdefTypeGnsResponse:
        return NfcResponse.fromJson(
          jsonDecode(utf8.decode(record.payload)) as Map<String, dynamic>,
        );
      default:
        return null;
    }
  }
}

/// Complete NDEF message
class NdefMessage {
  final List<NdefRecord> records;

  NdefMessage({required this.records});

  /// Serialize to bytes
  Uint8List toBytes() {
    if (records.isEmpty) return Uint8List(0);
    
    final buffer = BytesBuilder();
    for (var i = 0; i < records.length; i++) {
      buffer.add(records[i].toBytes(
        isFirst: i == 0,
        isLast: i == records.length - 1,
      ));
    }
    return buffer.toBytes();
  }

  /// Find first GNS payment token in message
  NfcPaymentToken? findPaymentToken() {
    for (final record in records) {
      if (record.typeNameFormat == NdefTypeNameFormat.media) {
        final typeStr = utf8.decode(record.type);
        if (typeStr == kNdefTypeGnsPayment) {
          return NfcPaymentToken.fromBytes(record.payload);
        }
      }
    }
    return null;
  }
}

// =============================================================================
// HELPER FUNCTIONS
// =============================================================================

Uint8List _int64ToBytes(int value) {
  final bytes = Uint8List(8);
  for (var i = 7; i >= 0; i--) {
    bytes[i] = value & 0xFF;
    value >>= 8;
  }
  return bytes;
}

int _bytesToInt64(List<int> bytes) {
  int value = 0;
  for (var i = 0; i < 8; i++) {
    value = (value << 8) | bytes[i];
  }
  return value;
}

Uint8List _int32ToBytes(int value) {
  final bytes = Uint8List(4);
  for (var i = 3; i >= 0; i--) {
    bytes[i] = value & 0xFF;
    value >>= 8;
  }
  return bytes;
}

bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
