/// NFC Protocol Test Suite - Sprint 1 Validation
/// 
/// Tests:
/// 1. ChaCha20-Poly1305 encryption/decryption
/// 2. NDEF message format creation and parsing
/// 3. Ed25519 signature creation and verification
/// 4. Payment token signing and verification
/// 5. Replay attack prevention
/// 
/// Run: dart test nfc_protocol_test.dart

import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:gns_browser/core/nfc/nfc_protocol.dart';

void main() async {
  print('═══════════════════════════════════════════════════════════════');
  print('   GNS NFC Protocol - Sprint 1 Test Suite');
  print('═══════════════════════════════════════════════════════════════\n');

  int passed = 0;
  int failed = 0;

  // Initialize crypto service
  final crypto = NfcCryptoService();

  // ═══════════════════════════════════════════════════════════════════════
  // TEST 1: ChaCha20-Poly1305 Encryption/Decryption
  // ═══════════════════════════════════════════════════════════════════════
  print('📦 TEST 1: ChaCha20-Poly1305 Encryption');
  print('─────────────────────────────────────────────────────────────────');
  
  try {
    // Generate session key
    final sessionKey = crypto.generateNonce();
    final extendedKey = Uint8List(32);
    extendedKey.setRange(0, 16, sessionKey);
    extendedKey.setRange(16, 32, sessionKey);  // Repeat for 32 bytes
    
    // Test data
    final plaintext = utf8.encode('GNS Payment: €25.00 to @coffee_shop');
    final plaintextBytes = Uint8List.fromList(plaintext);
    
    // Encrypt
    final encrypted = await crypto.encryptPayload(
      plaintext: plaintextBytes,
      sessionKey: extendedKey,
    );
    
    print('   Original:  ${utf8.decode(plaintextBytes)}');
    print('   Nonce:     ${base64Encode(encrypted.nonce)} (${encrypted.nonce.length} bytes)');
    print('   Encrypted: ${base64Encode(encrypted.ciphertext).substring(0, 40)}...');
    
    // Decrypt
    final decrypted = await crypto.decryptPayload(
      ciphertext: encrypted.ciphertext,
      nonce: encrypted.nonce,
      sessionKey: extendedKey,
    );
    
    final decryptedText = utf8.decode(decrypted);
    print('   Decrypted: $decryptedText');
    
    if (decryptedText == 'GNS Payment: €25.00 to @coffee_shop') {
      print('   ✅ PASSED: Encryption/decryption round-trip successful\n');
      passed++;
    } else {
      print('   ❌ FAILED: Decrypted text mismatch\n');
      failed++;
    }
  } catch (e) {
    print('   ❌ FAILED: $e\n');
    failed++;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // TEST 2: Ed25519 Signature Creation & Verification
  // ═══════════════════════════════════════════════════════════════════════
  print('🔐 TEST 2: Ed25519 Signatures');
  print('─────────────────────────────────────────────────────────────────');
  
  try {
    // Generate key pair
    final ed = Ed25519();
    final keyPair = await ed.newKeyPair();
    final privateKey = await keyPair.extractPrivateKeyBytes();
    final publicKey = (await keyPair.extractPublicKey()).bytes;
    
    print('   Private:   ${_bytesToHex(Uint8List.fromList(privateKey)).substring(0, 32)}...');
    print('   Public:    ${_bytesToHex(Uint8List.fromList(publicKey))}');
    
    // Sign data
    final paymentData = utf8.encode('payment:abc123:2500:EUR:1705484400000');
    final signature = await crypto.signPaymentData(
      data: Uint8List.fromList(paymentData),
      privateKey: Uint8List.fromList(privateKey),
    );
    
    print('   Signature: ${base64Encode(signature).substring(0, 44)}...');
    print('   Sig size:  ${signature.length} bytes');
    
    // Verify valid signature
    final isValid = await crypto.verifyPaymentSignature(
      data: Uint8List.fromList(paymentData),
      signature: signature,
      publicKey: Uint8List.fromList(publicKey),
    );
    
    print('   Valid sig: $isValid');
    
    // Verify tampered signature fails
    final tamperedSig = Uint8List.fromList(signature);
    tamperedSig[0] ^= 0xFF;  // Flip bits
    
    final isInvalid = await crypto.verifyPaymentSignature(
      data: Uint8List.fromList(paymentData),
      signature: tamperedSig,
      publicKey: Uint8List.fromList(publicKey),
    );
    
    print('   Tampered:  $isInvalid (should be false)');
    
    if (isValid && !isInvalid) {
      print('   ✅ PASSED: Signature verification works correctly\n');
      passed++;
    } else {
      print('   ❌ FAILED: Signature verification incorrect\n');
      failed++;
    }
  } catch (e) {
    print('   ❌ FAILED: $e\n');
    failed++;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // TEST 3: NFC Payment Token Creation & Serialization
  // ═══════════════════════════════════════════════════════════════════════
  print('💳 TEST 3: NFC Payment Token');
  print('─────────────────────────────────────────────────────────────────');
  
  try {
    // Generate merchant keys
    final ed = Ed25519();
    final merchantKeyPair = await ed.newKeyPair();
    final merchantPrivate = await merchantKeyPair.extractPrivateKeyBytes();
    final merchantPublic = (await merchantKeyPair.extractPublicKey()).bytes;
    
    // Create payment token
    final token = await crypto.createPaymentToken(
      merchantPrivateKey: Uint8List.fromList(merchantPrivate),
      merchantPublicKey: Uint8List.fromList(merchantPublic),
      amountMinorUnits: 2500,  // €25.00
      currency: 'EUR',
      h3Cell: '891f8a2820fffff',  // Sample H3 cell
      requireGeoAuth: true,
    );
    
    print('   Amount:    ${token.amountDisplay}');
    print('   Currency:  ${token.currency}');
    print('   H3 Cell:   ${token.h3Cell}');
    print('   Geo-Auth:  ${token.requiresGeoAuth}');
    print('   Timestamp: ${DateTime.fromMillisecondsSinceEpoch(token.timestamp)}');
    print('   Nonce:     ${base64Encode(token.nonce)}');
    
    // Serialize to bytes
    final tokenBytes = token.toBytes();
    print('   Size:      ${tokenBytes.length} bytes');
    print('   Hex:       ${_bytesToHex(tokenBytes).substring(0, 60)}...');
    
    // Deserialize
    final parsed = NfcPaymentToken.fromBytes(tokenBytes);
    
    print('   Parsed €:  ${parsed.amountDisplay}');
    print('   Parsed H3: ${parsed.h3Cell}');
    
    // Verify round-trip
    final roundTrip = parsed.amountMinorUnits == token.amountMinorUnits &&
                      parsed.currency == token.currency &&
                      parsed.h3Cell == token.h3Cell &&
                      parsed.requiresGeoAuth == token.requiresGeoAuth;
    
    if (roundTrip) {
      print('   ✅ PASSED: Token serialization/deserialization works\n');
      passed++;
    } else {
      print('   ❌ FAILED: Token round-trip mismatch\n');
      failed++;
    }
  } catch (e) {
    print('   ❌ FAILED: $e\n');
    failed++;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // TEST 4: Replay Attack Prevention
  // ═══════════════════════════════════════════════════════════════════════
  print('🛡️ TEST 4: Replay Attack Prevention');
  print('─────────────────────────────────────────────────────────────────');
  
  try {
    final tracker = NonceTracker();
    final now = DateTime.now().millisecondsSinceEpoch;
    
    // Generate test nonce
    final nonce1 = crypto.generateNonce();
    final nonce2 = crypto.generateNonce();
    
    print('   Nonce 1:   ${base64Encode(nonce1).substring(0, 22)}');
    print('   Nonce 2:   ${base64Encode(nonce2).substring(0, 22)}');
    
    // First use should succeed
    final first = tracker.validateAndRegister(nonce1, now);
    print('   First use: $first (should be true)');
    
    // Replay attempt should fail
    final replay = tracker.validateAndRegister(nonce1, now);
    print('   Replay:    $replay (should be false)');
    
    // Different nonce should succeed
    final different = tracker.validateAndRegister(nonce2, now);
    print('   Different: $different (should be true)');
    
    // Old timestamp should fail
    final oldTime = now - (6 * 60 * 1000);  // 6 minutes ago
    final oldNonce = crypto.generateNonce();
    final tooOld = tracker.validateAndRegister(oldNonce, oldTime);
    print('   Too old:   $tooOld (should be false)');
    
    // Future timestamp (slight tolerance)
    final futureTime = now + (10 * 1000);  // 10 seconds future
    final futureNonce = crypto.generateNonce();
    final slightFuture = tracker.validateAndRegister(futureNonce, futureTime);
    print('   Near future: $slightFuture (should be true)');
    
    // Far future should fail
    final farFuture = now + (60 * 1000);  // 1 minute future
    final farNonce = crypto.generateNonce();
    final tooFuture = tracker.validateAndRegister(farNonce, farFuture);
    print('   Far future:  $tooFuture (should be false)');
    
    print('   Stats:     ${tracker.stats}');
    
    if (first && !replay && different && !tooOld && slightFuture && !tooFuture) {
      print('   ✅ PASSED: Replay attack prevention working correctly\n');
      passed++;
    } else {
      print('   ❌ FAILED: Replay protection incorrect\n');
      failed++;
    }
  } catch (e) {
    print('   ❌ FAILED: $e\n');
    failed++;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // TEST 5: Payment Token Verification Flow
  // ═══════════════════════════════════════════════════════════════════════
  print('✓ TEST 5: Payment Token Verification Flow');
  print('─────────────────────────────────────────────────────────────────');
  
  try {
    final tracker = NonceTracker();
    
    // Generate merchant keys
    final ed = Ed25519();
    final merchantKeyPair = await ed.newKeyPair();
    final merchantPrivate = await merchantKeyPair.extractPrivateKeyBytes();
    final merchantPublic = (await merchantKeyPair.extractPublicKey()).bytes;
    
    // Create valid token
    final token = await crypto.createPaymentToken(
      merchantPrivateKey: Uint8List.fromList(merchantPrivate),
      merchantPublicKey: Uint8List.fromList(merchantPublic),
      amountMinorUnits: 1000,
      currency: 'EUR',
      h3Cell: '891f8a2820fffff',
      requireGeoAuth: true,
    );
    
    print('   Token created: ${token.amountDisplay}');
    
    // Verify valid token
    final result = await crypto.verifyPaymentToken(
      token,
      nonceTracker: tracker,
      expectedH3Cell: '891f8a2820fffff',
    );
    
    print('   Verification: ${result.isValid}');
    print('   Error:        ${result.error ?? 'none'}');
    
    // Replay should fail
    final replayResult = await crypto.verifyPaymentToken(
      token,
      nonceTracker: tracker,
      expectedH3Cell: '891f8a2820fffff',
    );
    
    print('   Replay check: ${replayResult.isValid} (should be false)');
    print('   Replay error: ${replayResult.error ?? 'none'}');
    
    // Wrong H3 cell should fail (with strict matching)
    final newTracker = NonceTracker();
    final token2 = await crypto.createPaymentToken(
      merchantPrivateKey: Uint8List.fromList(merchantPrivate),
      merchantPublicKey: Uint8List.fromList(merchantPublic),
      amountMinorUnits: 1000,
      currency: 'EUR',
      h3Cell: '891f8a2820fffff',
      requireGeoAuth: true,
    );
    
    final wrongLocation = await crypto.verifyPaymentToken(
      token2,
      nonceTracker: newTracker,
      expectedH3Cell: '892f8a2820fffff',  // Different cell
    );
    
    print('   Wrong cell:   ${wrongLocation.isValid} (should be false)');
    
    if (result.isValid && !replayResult.isValid && !wrongLocation.isValid) {
      print('   ✅ PASSED: Token verification flow correct\n');
      passed++;
    } else {
      print('   ❌ FAILED: Verification flow incorrect\n');
      failed++;
    }
  } catch (e) {
    print('   ❌ FAILED: $e\n');
    failed++;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // TEST 6: NDEF Message Building
  // ═══════════════════════════════════════════════════════════════════════
  print('📱 TEST 6: NDEF Message Building');
  print('─────────────────────────────────────────────────────────────────');
  
  try {
    // Generate merchant keys
    final ed = Ed25519();
    final merchantKeyPair = await ed.newKeyPair();
    final merchantPrivate = await merchantKeyPair.extractPrivateKeyBytes();
    final merchantPublic = (await merchantKeyPair.extractPublicKey()).bytes;
    
    // Create token
    final token = await crypto.createPaymentToken(
      merchantPrivateKey: Uint8List.fromList(merchantPrivate),
      merchantPublicKey: Uint8List.fromList(merchantPublic),
      amountMinorUnits: 5000,
      currency: 'EUR',
      h3Cell: '891f8a2820fffff',
    );
    
    // Build NDEF message
    final builder = NdefMessageBuilder();
    builder.addPaymentToken(token);
    builder.addTextRecord('GNS Payment: €50.00');
    builder.addUriRecord('https://gns.id/pay/abc123');
    
    final message = builder.build();
    final messageBytes = message.toBytes();
    
    print('   Records:     ${message.records.length}');
    print('   Total size:  ${messageBytes.length} bytes');
    print('   Hex preview: ${_bytesToHex(messageBytes).substring(0, 80)}...');
    
    // Extract payment token from message
    final extractedToken = message.findPaymentToken();
    
    if (extractedToken != null) {
      print('   Extracted:   ${extractedToken.amountDisplay}');
      print('   Match:       ${extractedToken.amountMinorUnits == token.amountMinorUnits}');
      
      if (extractedToken.amountMinorUnits == token.amountMinorUnits) {
        print('   ✅ PASSED: NDEF message building and parsing works\n');
        passed++;
      } else {
        print('   ❌ FAILED: Extracted token mismatch\n');
        failed++;
      }
    } else {
      print('   ❌ FAILED: Could not extract token\n');
      failed++;
    }
  } catch (e) {
    print('   ❌ FAILED: $e\n');
    failed++;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // TEST 7: Challenge-Response Authentication
  // ═══════════════════════════════════════════════════════════════════════
  print('🔄 TEST 7: Challenge-Response Authentication');
  print('─────────────────────────────────────────────────────────────────');
  
  try {
    final tracker = NonceTracker();
    
    // Generate keys for merchant and user
    final ed = Ed25519();
    
    final merchantKeyPair = await ed.newKeyPair();
    final merchantPublic = (await merchantKeyPair.extractPublicKey()).bytes;
    
    final userKeyPair = await ed.newKeyPair();
    final userPrivate = await userKeyPair.extractPrivateKeyBytes();
    final userPublic = (await userKeyPair.extractPublicKey()).bytes;
    
    // Merchant creates challenge
    final challenge = crypto.createChallenge(
      merchantPublicKey: Uint8List.fromList(merchantPublic),
      amountMinorUnits: 1500,
      currency: 'EUR',
      h3Cell: '891f8a2820fffff',
      memo: 'Coffee order #42',
    );
    
    print('   Challenge:');
    print('     Amount: €${(challenge.amountMinorUnits / 100).toStringAsFixed(2)}');
    print('     Nonce:  ${base64Encode(challenge.nonce).substring(0, 22)}');
    print('     H3:     ${challenge.h3Cell}');
    print('     Memo:   ${challenge.memo}');
    
    // User signs response
    final response = await crypto.signChallengeResponse(
      challenge: challenge,
      userPrivateKey: Uint8List.fromList(userPrivate),
      userPublicKey: Uint8List.fromList(userPublic),
      userH3Cell: '891f8a2820fffff',  // Same cell (within range)
    );
    
    print('   Response:');
    print('     User PK: ${_bytesToHex(response.userPublicKey).substring(0, 32)}...');
    print('     User H3: ${response.userH3Cell}');
    print('     Sig:     ${base64Encode(response.signature).substring(0, 32)}...');
    
    // Merchant verifies response
    final verified = await crypto.verifyChallengeResponse(
      challenge: challenge,
      response: response,
      nonceTracker: tracker,
    );
    
    print('   Verified:  $verified');
    
    // Replay should fail
    final replayVerified = await crypto.verifyChallengeResponse(
      challenge: challenge,
      response: response,
      nonceTracker: tracker,
    );
    
    print('   Replay:    $replayVerified (should be false)');
    
    if (verified && !replayVerified) {
      print('   ✅ PASSED: Challenge-response authentication works\n');
      passed++;
    } else {
      print('   ❌ FAILED: Challenge-response verification incorrect\n');
      failed++;
    }
  } catch (e) {
    print('   ❌ FAILED: $e\n');
    failed++;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // TEST 8: Session Key Derivation
  // ═══════════════════════════════════════════════════════════════════════
  print('🔑 TEST 8: Session Key Derivation (X25519 + HKDF)');
  print('─────────────────────────────────────────────────────────────────');
  
  try {
    final x25519 = X25519();
    
    // Generate two key pairs (Alice and Bob)
    final aliceKeyPair = await x25519.newKeyPair();
    final alicePrivate = await aliceKeyPair.extractPrivateKeyBytes();
    final alicePublic = (await aliceKeyPair.extractPublicKey()).bytes;
    
    final bobKeyPair = await x25519.newKeyPair();
    final bobPrivate = await bobKeyPair.extractPrivateKeyBytes();
    final bobPublic = (await bobKeyPair.extractPublicKey()).bytes;
    
    print('   Alice PK: ${_bytesToHex(Uint8List.fromList(alicePublic)).substring(0, 32)}...');
    print('   Bob PK:   ${_bytesToHex(Uint8List.fromList(bobPublic)).substring(0, 32)}...');
    
    // Common salt (could be challenge nonce)
    final salt = crypto.generateNonce();
    print('   Salt:     ${base64Encode(salt)}');
    
    // Derive session key from Alice's perspective
    final aliceSessionKey = await crypto.deriveSessionKey(
      myPrivateKey: Uint8List.fromList(alicePrivate),
      theirPublicKey: Uint8List.fromList(bobPublic),
      salt: salt,
    );
    
    // Derive session key from Bob's perspective
    final bobSessionKey = await crypto.deriveSessionKey(
      myPrivateKey: Uint8List.fromList(bobPrivate),
      theirPublicKey: Uint8List.fromList(alicePublic),
      salt: salt,
    );
    
    print('   Alice key: ${_bytesToHex(aliceSessionKey)}');
    print('   Bob key:   ${_bytesToHex(bobSessionKey)}');
    
    // Keys should match
    final keysMatch = _bytesEqual(aliceSessionKey, bobSessionKey);
    print('   Match:     $keysMatch');
    
    // Verify encryption/decryption with shared key
    final testMessage = utf8.encode('Secret payment data');
    final encrypted = await crypto.encryptPayload(
      plaintext: Uint8List.fromList(testMessage),
      sessionKey: aliceSessionKey,
    );
    
    final decrypted = await crypto.decryptPayload(
      ciphertext: encrypted.ciphertext,
      nonce: encrypted.nonce,
      sessionKey: bobSessionKey,
    );
    
    final decryptedText = utf8.decode(decrypted);
    print('   Encrypted: ${base64Encode(encrypted.ciphertext).substring(0, 32)}...');
    print('   Decrypted: $decryptedText');
    
    if (keysMatch && decryptedText == 'Secret payment data') {
      print('   ✅ PASSED: Session key derivation and encryption works\n');
      passed++;
    } else {
      print('   ❌ FAILED: Session key derivation incorrect\n');
      failed++;
    }
  } catch (e) {
    print('   ❌ FAILED: $e\n');
    failed++;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // SUMMARY
  // ═══════════════════════════════════════════════════════════════════════
  print('═══════════════════════════════════════════════════════════════');
  print('   SPRINT 1 TEST RESULTS');
  print('═══════════════════════════════════════════════════════════════');
  print('   Passed: $passed');
  print('   Failed: $failed');
  print('   Total:  ${passed + failed}');
  print('');
  
  if (failed == 0) {
    print('   🎉 ALL TESTS PASSED! Sprint 1 NFC Protocol ready.');
  } else {
    print('   ⚠️  Some tests failed. Review implementation.');
  }
  print('═══════════════════════════════════════════════════════════════\n');
}

// Helper functions
String _bytesToHex(Uint8List bytes) {
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
