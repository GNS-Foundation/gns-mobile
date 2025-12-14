// lib/core/gns/gns_api_client.dart
// GNS API Client - HTTP client for GNS Network nodes

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class GnsApiClient {
  static final GnsApiClient _instance = GnsApiClient._internal();
  factory GnsApiClient() => _instance;
  GnsApiClient._internal() {
    _initDio();
  }

  // Default GNS Node URL - Railway deployment
  static const String defaultNodeUrl = 'https://gns-browser-production.up.railway.app';
  
  late Dio _dio;
  String _nodeUrl = defaultNodeUrl;
  
  String get nodeUrl => _nodeUrl;
  
  void _initDio() {
    _dio = Dio(BaseOptions(
      baseUrl: _nodeUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ));
    
    // Add logging interceptor in debug mode
    if (kDebugMode) {
      _dio.interceptors.add(LogInterceptor(
        requestBody: true,
        responseBody: true,
        logPrint: (obj) => debugPrint(obj.toString()),
      ));
    }
  }
  
  /// Change the node URL
  void setNodeUrl(String url) {
    _nodeUrl = url;
    _dio.options.baseUrl = url;
    debugPrint('GnsApiClient: Node URL set to $url');
  }
  
  // ==================== HEALTH ====================
  
  /// Check node health
  Future<Map<String, dynamic>> healthCheck() async {
    try {
      final response = await _dio.get('/health');
      return response.data as Map<String, dynamic>;
    } catch (e) {
      debugPrint('Health check failed: $e');
      return {'status': 'error', 'error': e.toString()};
    }
  }
  
  /// Get node info
  Future<Map<String, dynamic>> getNodeInfo() async {
    try {
      final response = await _dio.get('/');
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      debugPrint('Get node info failed: $e');
      return {'error': e.toString()};
    }
  }
  
  // ==================== RECORDS ====================
  
  /// Publish or update a GNS record (signature is inside the record)
  Future<Map<String, dynamic>> publishRecord({
    required String publicKey,
    required Map<String, dynamic> record,
  }) async {
    try {
      // Extract signature and remove from record_json
      final signature = record['signature'];
      final recordWithoutSignature = Map<String, dynamic>.from(record);
      recordWithoutSignature.remove('signature');
      
      final response = await _dio.put(
        '/records/$publicKey',
        data: {
          'record_json': recordWithoutSignature,
          'signature': signature,
        },
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      debugPrint('Publish record failed: ${e.response?.data}');
      if (e.response != null) {
        return e.response!.data as Map<String, dynamic>;
      }
      return {'success': false, 'error': e.message};
    }
  }
  
  /// Get a GNS record by public key
  Future<Map<String, dynamic>> getRecord(String publicKey) async {
    try {
      final response = await _dio.get('/records/$publicKey');
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return {'success': false, 'error': 'Not found'};
      }
      return {'success': false, 'error': e.message};
    }
  }
  
  /// Delete a GNS record
  Future<Map<String, dynamic>> deleteRecord({
    required String publicKey,
    required String signature,
  }) async {
    try {
      final response = await _dio.delete(
        '/records/$publicKey',
        data: {'signature': signature},
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      return {'success': false, 'error': e.message};
    }
  }
  
  // ==================== ALIASES ====================
  
  /// Check if a handle is available
  Future<Map<String, dynamic>> checkHandle(String handle) async {
    try {
      final cleanHandle = handle.toLowerCase().replaceAll('@', '').trim();
      final response = await _dio.get('/aliases', queryParameters: {
        'check': cleanHandle,
      });
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      return {'success': false, 'error': e.message};
    }
  }
  
  /// Resolve a handle to public key
  Future<Map<String, dynamic>> resolveHandle(String handle) async {
    try {
      final cleanHandle = handle.toLowerCase().replaceAll('@', '').trim();
      final response = await _dio.get('/aliases/$cleanHandle');
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return {'success': false, 'error': 'Handle not found'};
      }
      return {'success': false, 'error': e.message};
    }
  }
  
  /// Reserve a handle (before claiming with PoT)
  Future<Map<String, dynamic>> reserveHandle({
    required String handle,
    required String publicKey,
    required String signature,
  }) async {
    try {
      final cleanHandle = handle.toLowerCase().replaceAll('@', '').trim();
      
      final requestBody = {
        'identity': publicKey,
        'signature': signature,
      };
      
      debugPrint('=== ALIAS RESERVE REQUEST ===');
      debugPrint('URL: POST /aliases/$cleanHandle/reserve');
      debugPrint('Body: $requestBody');
      
      final response = await _dio.post(
        '/aliases/$cleanHandle/reserve',
        data: requestBody,
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      debugPrint('Reserve handle failed: ${e.response?.data}');
      if (e.response != null && e.response!.data is Map) {
        return e.response!.data as Map<String, dynamic>;
      }
      return {'success': false, 'error': e.message};
    }
  }
  
  /// Claim a handle (requires PoT proof - 100 breadcrumbs)
  Future<Map<String, dynamic>> claimHandle({
    required String handle,
    required Map<String, dynamic> claim,
    required String signature,
  }) async {
    try {
      final cleanHandle = handle.toLowerCase().replaceAll('@', '').trim();
      
      final requestBody = {
        'handle': cleanHandle,
        'identity': claim['identity'],
        'proof': claim['proof'],
        'claimed_at': claim['claimed_at'],
        'signature': signature,
      };
      
      debugPrint('=== ALIAS CLAIM REQUEST ===');
      debugPrint('URL: PUT /aliases/$cleanHandle');
      debugPrint('Body: $requestBody');
      
      final response = await _dio.put(
        '/aliases/$cleanHandle',
        data: requestBody,
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      debugPrint('Claim handle failed: ${e.response?.data}');
      if (e.response != null) {
        return e.response!.data as Map<String, dynamic>;
      }
      return {'success': false, 'error': e.message};
    }
  }
  
  // ==================== EPOCHS ====================
  
  /// Publish an epoch header
  Future<Map<String, dynamic>> publishEpoch({
    required String publicKey,
    required int epochIndex,
    required Map<String, dynamic> epoch,
    required String signature,
  }) async {
    try {
      final response = await _dio.put(
        '/epochs/$publicKey/$epochIndex',
        data: {
          'epoch': epoch,
          'signature': signature,
        },
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      debugPrint('Publish epoch failed: ${e.response?.data}');
      if (e.response != null) {
        return e.response!.data as Map<String, dynamic>;
      }
      return {'success': false, 'error': e.message};
    }
  }
  
  /// Get all epochs for an identity
  Future<Map<String, dynamic>> getEpochs(String publicKey) async {
    try {
      final response = await _dio.get('/epochs/$publicKey');
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      return {'success': false, 'error': e.message};
    }
  }
  
  /// Get a specific epoch
  Future<Map<String, dynamic>> getEpoch(String publicKey, int epochIndex) async {
    try {
      final response = await _dio.get('/epochs/$publicKey/$epochIndex');
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return {'success': false, 'error': 'Epoch not found'};
      }
      return {'success': false, 'error': e.message};
    }
  }
  
  // ==================== MESSAGES ====================
  
  /// Send an encrypted message
  Future<Map<String, dynamic>> sendMessage({
    required String toPublicKey,
    required String fromPublicKey,
    required String encryptedPayload,
    String? messageType,
  }) async {
    try {
      final response = await _dio.post(
        '/messages/$toPublicKey',
        data: {
          'from_pk': fromPublicKey,
          'payload': encryptedPayload,
          if (messageType != null) 'type': messageType,
        },
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      return {'success': false, 'error': e.message};
    }
  }
  
  /// Get inbox messages (requires auth)
  Future<Map<String, dynamic>> getInbox({
    required String publicKey,
    required String signature,
    required String timestamp,
  }) async {
    try {
      final response = await _dio.get(
        '/messages/inbox',
        options: Options(headers: {
          'X-GNS-PK': publicKey,
          'X-GNS-Sig': signature,
          'X-GNS-Timestamp': timestamp,
        }),
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      return {'success': false, 'error': e.message};
    }
  }
  
  /// Acknowledge/delete a message
  Future<Map<String, dynamic>> deleteMessage({
    required String messageId,
    required String publicKey,
    required String signature,
  }) async {
    try {
      final response = await _dio.delete(
        '/messages/$messageId',
        options: Options(headers: {
          'X-GNS-PK': publicKey,
          'X-GNS-Sig': signature,
        }),
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      return {'success': false, 'error': e.message};
    }
  }
  
  // ==================== AUTH ====================
  
  /// Get auth challenge
  Future<Map<String, dynamic>> getAuthChallenge(String publicKey) async {
    try {
      final response = await _dio.get('/auth/challenge', queryParameters: {
        'pk': publicKey,
      });
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      return {'success': false, 'error': e.message};
    }
  }
}
