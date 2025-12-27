/// Browser Pairing Service - QR Auth for Panthera Browser
/// 
/// Handles scanning QR codes from browser and approving sessions.
/// 
/// Location: lib/core/auth/browser_pairing_service.dart

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import '../gns/identity_wallet.dart';

/// QR code data from browser
class BrowserAuthRequest {
  final String type;
  final int version;
  final String sessionId;
  final String challenge;
  final String browserInfo;
  final int expiresAt;

  BrowserAuthRequest({
    required this.type,
    required this.version,
    required this.sessionId,
    required this.challenge,
    required this.browserInfo,
    required this.expiresAt,
  });

  factory BrowserAuthRequest.fromJson(Map<String, dynamic> json) {
    return BrowserAuthRequest(
      type: json['type'] as String,
      version: json['version'] as int? ?? 1,
      sessionId: json['sessionId'] as String,
      challenge: json['challenge'] as String,
      browserInfo: json['browserInfo'] as String? ?? 'Unknown Browser',
      expiresAt: json['expiresAt'] as int,
    );
  }

  factory BrowserAuthRequest.fromQRData(String qrData) {
    try {
      final json = jsonDecode(qrData) as Map<String, dynamic>;
      return BrowserAuthRequest.fromJson(json);
    } catch (e) {
      throw FormatException('Invalid QR code data: $e');
    }
  }

  bool get isExpired => DateTime.now().millisecondsSinceEpoch > expiresAt;
  
  bool get isValid => type == 'gns_browser_auth' && !isExpired;

  Duration get timeRemaining {
    final remaining = expiresAt - DateTime.now().millisecondsSinceEpoch;
    return Duration(milliseconds: remaining > 0 ? remaining : 0);
  }
}

/// Result of approval/rejection
class BrowserAuthResult {
  final bool success;
  final String? error;
  final String? sessionId;

  BrowserAuthResult.success(this.sessionId) : success = true, error = null;
  BrowserAuthResult.failure(this.error) : success = false, sessionId = null;
}

/// Browser Pairing Service
class BrowserPairingService {
  static const String _baseUrl = 'https://gns-browser-production.up.railway.app';
  
  final IdentityWallet _wallet;
  final Dio _dio;

  BrowserPairingService({required IdentityWallet wallet})
      : _wallet = wallet,
        _dio = Dio(BaseOptions(
          baseUrl: _baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ));

  /// Parse QR code data
  BrowserAuthRequest? parseQRCode(String qrData) {
    try {
      final request = BrowserAuthRequest.fromQRData(qrData);
      
      if (!request.isValid) {
        debugPrint('❌ Invalid or expired QR code');
        return null;
      }
      
      debugPrint('✅ Valid browser auth QR: ${request.sessionId.substring(0, 8)}...');
      debugPrint('   Browser: ${request.browserInfo}');
      debugPrint('   Expires in: ${request.timeRemaining.inSeconds}s');
      
      return request;
    } catch (e) {
      debugPrint('❌ Failed to parse QR code: $e');
      return null;
    }
  }


  /// Approve browser session
  /// Signs the challenge with the user's Ed25519 private key
  /// ✅ UPDATED: Now includes X25519 encryption private key for browser decryption
  Future<BrowserAuthResult> approveSession(BrowserAuthRequest request) async {
    try {
      if (!request.isValid) {
        return BrowserAuthResult.failure('Session expired');
      }

      if (_wallet.publicKey == null || _wallet.privateKeyBytes == null) {
        return BrowserAuthResult.failure('Wallet not initialized');
      }

      debugPrint('🔐 Signing browser approval...');

      // Get current handle
      final handle = await _wallet.getCurrentHandle();

      // Build the data to sign (must match backend exactly)
      // canonicalJson sorts keys alphabetically
      final signedData = {
        'action': 'approve',
        'challenge': request.challenge,
        'publicKey': _wallet.publicKey!.toLowerCase(),
        'sessionId': request.sessionId,
      };

      // Canonical JSON (alphabetically sorted keys)
      final canonicalString = _canonicalJson(signedData);
      debugPrint('   Signing: ${canonicalString.substring(0, 50)}...');

      // Sign with Ed25519
      final signature = await _wallet.signBytes(utf8.encode(canonicalString));
      
      if (signature == null) {
        return BrowserAuthResult.failure('Failed to sign');
      }

      final signatureHex = _bytesToHex(signature);
      debugPrint('   ✅ Signature: ${signatureHex.substring(0, 24)}...');

      // ✅ NEW: Get X25519 encryption keys
      final encryptionPublicKey = _wallet.encryptionPublicKeyHex;
      final encryptionPrivateKey = _wallet.encryptionPrivateKeyBytes;
      
      if (encryptionPublicKey == null || encryptionPrivateKey == null) {
        return BrowserAuthResult.failure('Encryption keys not available');
      }
      
      final encryptionPrivateKeyHex = _bytesToHex(encryptionPrivateKey);
      
      debugPrint('   🔑 Including X25519 keys for browser decryption');
      debugPrint('   X25519 Public:  ${encryptionPublicKey.substring(0, 16)}...');
      debugPrint('   X25519 Private: ${encryptionPrivateKeyHex.substring(0, 16)}...');

      // Send approval to backend with encryption keys
      final response = await _dio.post(
        '/auth/sessions/approve',
        data: {
          'sessionId': request.sessionId,
          'publicKey': _wallet.publicKey,
          'handle': handle,  // ✅ Include handle
          'signature': signatureHex,
          // ✅ NEW: Include X25519 keys for browser E2E encryption
          'encryptionKey': encryptionPublicKey,
          'encryptionPrivateKey': encryptionPrivateKeyHex,  // ✅ For browser decryption
          'deviceInfo': {
            'platform': defaultTargetPlatform.name,
            'approvedAt': DateTime.now().toIso8601String(),
          },
        },
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        debugPrint('✅ Browser session approved with encryption keys!');
        return BrowserAuthResult.success(request.sessionId);
      } else {
        final error = response.data['error'] ?? 'Approval failed';
        debugPrint('❌ Approval failed: $error');
        return BrowserAuthResult.failure(error);
      }
    } catch (e) {
      debugPrint('❌ Approval error: $e');
      if (e is DioException) {
        final message = e.response?.data?['error'] ?? e.message;
        return BrowserAuthResult.failure(message);
      }
      return BrowserAuthResult.failure(e.toString());
    }
  }

  /// Reject browser session
  Future<BrowserAuthResult> rejectSession(BrowserAuthRequest request) async {
    try {
      debugPrint('❌ Rejecting browser session...');

      // Build signed rejection
      final signedData = {
        'action': 'reject',
        'challenge': request.challenge,
        'publicKey': _wallet.publicKey!.toLowerCase(),
        'sessionId': request.sessionId,
      };

      final canonicalString = _canonicalJson(signedData);
      final signature = await _wallet.signBytes(utf8.encode(canonicalString));
      final signatureHex = signature != null ? _bytesToHex(signature) : '';

      await _dio.post(
        '/auth/sessions/reject',
        data: {
          'sessionId': request.sessionId,
          'publicKey': _wallet.publicKey,
          'signature': signatureHex,
        },
      );

      debugPrint('✅ Browser session rejected');
      return BrowserAuthResult.success(request.sessionId);
    } catch (e) {
      debugPrint('❌ Reject error: $e');
      return BrowserAuthResult.failure(e.toString());
    }
  }

  /// Get list of active browser sessions
  Future<List<Map<String, dynamic>>> getActiveSessions() async {
    try {
      final response = await _dio.get(
        '/auth/sessions',
        options: Options(headers: {
          'X-GNS-PublicKey': _wallet.publicKey,
        }),
      );

      if (response.data['success'] == true) {
        return List<Map<String, dynamic>>.from(response.data['data'] ?? []);
      }

      return [];
    } catch (e) {
      debugPrint('Error fetching sessions: $e');
      return [];
    }
  }

  /// Revoke all browser sessions
  Future<bool> revokeAllSessions() async {
    try {
      final response = await _dio.post(
        '/auth/sessions/revoke-all',
        options: Options(headers: {
          'X-GNS-PublicKey': _wallet.publicKey,
        }),
      );

      return response.data['success'] == true;
    } catch (e) {
      debugPrint('Error revoking sessions: $e');
      return false;
    }
  }

  /// Canonical JSON (keys sorted alphabetically)
  String _canonicalJson(Map<String, dynamic> obj) {
    final sortedKeys = obj.keys.toList()..sort();
    final pairs = sortedKeys.map((k) {
      final v = obj[k];
      final value = v is String ? '"$v"' : v.toString();
      return '"$k":$value';
    });
    return '{${pairs.join(',')}}';
  }

  /// Convert bytes to hex string
  String _bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
