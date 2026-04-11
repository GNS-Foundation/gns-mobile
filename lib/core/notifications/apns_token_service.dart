/// APNs Token Service
/// Receives the device token from iOS via MethodChannel
/// and registers it with the GNS backend.
/// 
/// Location: lib/core/notifications/apns_token_service.dart

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../gns/identity_wallet.dart';

class ApnsTokenService {
  static const _channel = MethodChannel('com.gns.gcrumbs/push');
  static const _baseUrl = 'https://gns-browser-production.up.railway.app';

  static final ApnsTokenService _instance = ApnsTokenService._internal();
  factory ApnsTokenService() => _instance;
  ApnsTokenService._internal();

  String? _token;
  String? get token => _token;

  /// Call once from main() to start listening for the APNs token.
  void initialize() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onToken') {
        final token = call.arguments as String?;
        if (token != null && token.isNotEmpty) {
          debugPrint('📲 APNs token received: ${token.substring(0, 16)}...');
          _token = token;
          await _registerWithBackend(token);
        }
      }
    });
    debugPrint('📲 APNs token listener initialized');
  }

  Future<void> _registerWithBackend(String token) async {
    try {
      final wallet = IdentityWallet();
      final pk = wallet.publicKey;
      if (pk == null) return;

      final res = await http.post(
        Uri.parse('$_baseUrl/push/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'public_key': pk,
          'device_token': token,
          'platform': 'ios',
        }),
      );

      if (res.statusCode == 200 || res.statusCode == 201) {
        debugPrint('✅ APNs token registered with backend');
      } else {
        debugPrint('⚠️ APNs registration response: ${res.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ APNs token registration error: $e');
    }
  }
}
