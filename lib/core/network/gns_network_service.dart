/// GNS Network Service - Phase 2/3A
/// 
/// Handles all network communication with GNS relay nodes.
/// 
/// Location: lib/core/network/gns_network_service.dart

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import '../gns/gns_record.dart';
import '../gns/identity_wallet.dart';

class GnsNetworkService {
  static final GnsNetworkService _instance = GnsNetworkService._internal();
  factory GnsNetworkService() => _instance;
  GnsNetworkService._internal();

  // Your Railway deployment URL
  static const String baseUrl = 'https://gns-browser-production.up.railway.app';
  
  final Dio _dio = Dio(BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
    headers: {
      'Content-Type': 'application/json',
    },
  ));

  final _wallet = IdentityWallet();

  /// Sort map keys alphabetically for canonical JSON
  static Map<String, dynamic> _sortedMap(Map<String, dynamic> map) {
    final sorted = <String, dynamic>{};
    final keys = map.keys.toList()..sort();
    for (final key in keys) {
      final value = map[key];
      if (value is Map<String, dynamic>) {
        sorted[key] = _sortedMap(value);
      } else if (value is List) {
        sorted[key] = value.map((v) => v is Map<String, dynamic> ? _sortedMap(v) : v).toList();
      } else if (value is double && value == value.truncateToDouble()) {
        sorted[key] = value.toInt();  // 70.0 → 70 to match JavaScript
      } else {
        sorted[key] = value;
      }
    }
    return sorted;
  }

  // ==================== RECORDS API ====================

  /// Publish/update own GNS record to the network
  Future<bool> syncRecord() async {
    try {
      final record = _wallet.localRecord;
      if (record == null) {
        debugPrint('❌ SYNC: No local record to sync');
        return false;
      }

      // Build record_json with SORTED keys (must match what was signed!)
      // Numbers are normalized: 70.0 → 70 to match JavaScript JSON.stringify
      final trustScoreNormalized = record.trustScore == record.trustScore.truncateToDouble() 
          ? record.trustScore.toInt() 
          : record.trustScore;
          
      final recordJson = _sortedMap({
        'breadcrumb_count': record.breadcrumbCount,
        'created_at': record.createdAt.toUtc().toIso8601String(),
        'endpoints': record.endpoints.map((e) => _sortedMap(e.toJson())).toList(),
        'epoch_roots': record.epochRoots,
        'handle': record.handle,
        'identity': record.identity,
        'modules': record.modules.map((m) => _sortedMap(m.toJson())).toList(),
        'trust_score': trustScoreNormalized,
        'updated_at': record.updatedAt.toUtc().toIso8601String(),
        'version': record.version,
      });

      // Server expects: { record_json: {...}, signature: "..." }
      final requestData = {
        'record_json': recordJson,
        'signature': record.signature,
      };

      debugPrint('📤 SYNC: Sending record to network...');
      debugPrint('📤 SYNC: Identity: ${record.identity.substring(0, 16)}...');
      debugPrint('📤 SYNC: Handle: ${record.handle}');
      debugPrint('📤 SYNC: Modules: ${record.modules.length}');
      debugPrint('📤 SYNC: Full JSON:');
      debugPrint(jsonEncode(requestData));

      final response = await _dio.put(
        '/records/${record.identity}',
        data: requestData,
      );

      debugPrint('📥 SYNC: Response status: ${response.statusCode}');
      debugPrint('📥 SYNC: Response data: ${response.data}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint('✅ SYNC: Record synced to network');
        return true;
      }
      
      debugPrint('❌ SYNC: Failed with status ${response.statusCode}');
      return false;
    } on DioException catch (e) {
      debugPrint('❌ SYNC: DioException: ${e.type}');
      debugPrint('❌ SYNC: Message: ${e.message}');
      debugPrint('❌ SYNC: Status: ${e.response?.statusCode}');
      debugPrint('❌ SYNC: Response body: ${e.response?.data}');
      debugPrint('❌ SYNC: Request URL: ${e.requestOptions.uri}');
      debugPrint('❌ SYNC: Request data: ${e.requestOptions.data}');
      return false;
    } catch (e) {
      debugPrint('❌ SYNC: Error: $e');
      return false;
    }
  }

  /// Look up a GNS record by public key
  Future<GnsRecord?> lookupPublicKey(String publicKey) async {
    try {
      final response = await _dio.get('/records/$publicKey');

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        // Server returns { success: true, data: { pk_root, record_json, signature } }
        if (data['success'] == true && data['data'] != null) {
          final recordData = data['data'] as Map<String, dynamic>;
          final recordJson = recordData['record_json'] as Map<String, dynamic>;
          recordJson['signature'] = recordData['signature'];
          return GnsRecord.fromJson(recordJson);
        }
        return null;
      }
      
      return null;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        debugPrint('Record not found: $publicKey');
        return null;
      }
      debugPrint('Network error looking up record: ${e.message}');
      return null;
    } catch (e) {
      debugPrint('Error looking up record: $e');
      return null;
    }
  }

  /// Fetch a GNS record by public key (alias for lookupPublicKey)
  Future<GnsRecord?> fetchRecord(String publicKey) async {
    return lookupPublicKey(publicKey);
  }

  /// Resolve a handle to public key only (without fetching full record)
  Future<HandleResolveResult> resolveHandle(String handle) async {
    try {
      final cleanHandle = handle.replaceAll('@', '').toLowerCase().trim();
      debugPrint('🔍 Resolving handle: @$cleanHandle');
      
      final response = await _dio.get('/aliases/$cleanHandle');

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        if (data['success'] == true && data['data'] != null) {
          final aliasData = data['data'] as Map<String, dynamic>;
          final publicKey = aliasData['pk_root'] as String?;
          
          if (publicKey != null) {
            debugPrint('✅ Handle resolved: @$cleanHandle → ${publicKey.substring(0, 16)}...');
            return HandleResolveResult(
              success: true,
              handle: cleanHandle,
              publicKey: publicKey,
            );
          }
        }
      }
      
      return HandleResolveResult(success: false, error: 'Handle not found');
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return HandleResolveResult(success: false, error: 'Handle not found');
      }
      return HandleResolveResult(success: false, error: 'Network error');
    } catch (e) {
      return HandleResolveResult(success: false, error: e.toString());
    }
  }

  // ==================== ALIASES API ====================

  /// Look up public key by handle
  Future<GnsRecord?> lookupHandle(String handle) async {
    try {
      final cleanHandle = handle.replaceAll('@', '').toLowerCase().trim();
      debugPrint('🔍 Looking up handle: @$cleanHandle');
      
      final aliasResponse = await _dio.get('/aliases/$cleanHandle');

      if (aliasResponse.statusCode != 200 || aliasResponse.data == null) {
        debugPrint('Handle not found: $cleanHandle');
        return null;
      }

      final data = aliasResponse.data as Map<String, dynamic>;
      if (data['success'] != true || data['data'] == null) {
        debugPrint('Handle not found: $cleanHandle');
        return null;
      }
      
      final aliasData = data['data'] as Map<String, dynamic>;
      final publicKey = aliasData['pk_root'] as String?;
      
      if (publicKey == null) {
        debugPrint('No pk_root in alias response');
        return null;
      }

      debugPrint('✅ Handle resolved: @$cleanHandle → ${publicKey.substring(0, 16)}...');
      return await lookupPublicKey(publicKey);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        debugPrint('Handle not found: $handle');
        return null;
      }
      debugPrint('Network error looking up handle: ${e.message}');
      return null;
    } catch (e) {
      debugPrint('Error looking up handle: $e');
      return null;
    }
  }

  /// Check if a handle is available
  Future<bool> checkHandleAvailable(String handle) async {
    try {
      final cleanHandle = handle.replaceAll('@', '').toLowerCase().trim();
      final response = await _dio.get('/aliases', queryParameters: {'check': cleanHandle});

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        return data['available'] == true;
      }
      
      return false;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        // 404 might mean handle is available
        return true;
      }
      debugPrint('Network error checking handle: ${e.message}');
      return false;
    } catch (e) {
      debugPrint('Error checking handle: $e');
      return false;
    }
  }

  /// Reserve a handle (requires PoT proof)
  Future<HandleNetworkResult> reserveHandle(String handle) async {
    try {
      final cleanHandle = handle.replaceAll('@', '').toLowerCase().trim();
      final record = _wallet.localRecord;
      
      if (record == null) {
        return HandleNetworkResult(success: false, error: 'No identity');
      }

      // Build alias claim with PoT proof
      final info = await _wallet.getIdentityInfo();
      final claim = {
        'handle': cleanHandle,
        'identity': record.identity,
        'claimed_at': DateTime.now().toUtc().toIso8601String(),
        'proof': {
          'breadcrumb_count': info.breadcrumbCount,
          'trust_score': info.trustScore,
          'first_breadcrumb_at': info.firstBreadcrumbAt?.toIso8601String(),
        },
      };

      // Sign the claim
      final signature = await _wallet.signString(jsonEncode(claim));
      if (signature == null) {
        return HandleNetworkResult(success: false, error: 'Failed to sign claim');
      }
      claim['signature'] = signature;

      final response = await _dio.put(
        '/aliases/$cleanHandle',
        data: claim,
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return HandleNetworkResult(success: true, handle: cleanHandle);
      }
      
      final errorMsg = response.data?['error'] ?? 'Failed to reserve handle';
      return HandleNetworkResult(success: false, error: errorMsg);
    } on DioException catch (e) {
      final errorMsg = e.response?.data?['error'] ?? e.message ?? 'Network error';
      return HandleNetworkResult(success: false, error: errorMsg);
    } catch (e) {
      return HandleNetworkResult(success: false, error: e.toString());
    }
  }

  /// Claim a reserved handle (after meeting requirements)
  Future<HandleNetworkResult> claimHandle(String handle) async {
    // For now, reservation and claiming are the same operation
    // The server validates PoT requirements
    return reserveHandle(handle);
  }

  // ==================== EPOCHS API ====================

  /// Publish an epoch commitment
  Future<bool> publishEpoch(Map<String, dynamic> epochHeader) async {
    try {
      final publicKey = _wallet.publicKey;
      if (publicKey == null) return false;

      final epochIndex = epochHeader['epoch_index'];
      
      final response = await _dio.put(
        '/epochs/$publicKey/$epochIndex',
        data: epochHeader,
      );

      return response.statusCode == 200 || response.statusCode == 201;
    } on DioException catch (e) {
      debugPrint('Network error publishing epoch: ${e.message}');
      return false;
    } catch (e) {
      debugPrint('Error publishing epoch: $e');
      return false;
    }
  }

  /// Get epochs for an identity
  Future<List<Map<String, dynamic>>> getEpochs(String publicKey) async {
    try {
      final response = await _dio.get('/epochs/$publicKey');

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;
        if (data is List) {
          return data.cast<Map<String, dynamic>>();
        }
      }
      
      return [];
    } on DioException catch (e) {
      debugPrint('Network error getting epochs: ${e.message}');
      return [];
    } catch (e) {
      debugPrint('Error getting epochs: $e');
      return [];
    }
  }

  // ==================== SEARCH ====================

  /// Search identities by partial handle match
  /// Returns list of identity maps for live search
  Future<List<Map<String, dynamic>>> searchIdentities(String query) async {
    if (query.isEmpty) return [];
    
    try {
      final response = await _dio.get(
        '/web/search',
        queryParameters: {
          'q': query,
          'type': 'identity',
          'limit': '20',
        },
      );
      
      if (response.statusCode == 200) {
        final data = response.data;
        
        if (data['success'] == true && data['data'] != null) {
          final results = data['data']['results'] as List<dynamic>? ?? [];
          
          return results.map((r) {
            final identity = r['identity'] as Map<String, dynamic>?;
            if (identity == null) return <String, dynamic>{};
            
            return {
              'handle': identity['handle'],
              'displayName': identity['displayName'],
              'publicKey': identity['publicKey'],
              'avatarUrl': identity['avatarUrl'],
              'trustScore': identity['trustScore'],
              'breadcrumbCount': identity['breadcrumbCount'],
              'isVerified': identity['isVerified'],
            };
          }).where((m) => m.isNotEmpty).toList().cast<Map<String, dynamic>>();
        }
      }
      
      return [];
    } catch (e) {
      debugPrint('Search identities network error: $e');
      return [];
    }
  }

  // ==================== HEALTH CHECK ====================

  /// Check if the network is reachable
  Future<bool> isNetworkAvailable() async {
    try {
      final response = await _dio.get('/health');
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Get network status
  Future<NetworkStatus> getNetworkStatus() async {
    try {
      final response = await _dio.get('/health');
      
      if (response.statusCode == 200) {
        return NetworkStatus(
          isOnline: true,
          nodeUrl: baseUrl,
          latencyMs: 0, // Could measure actual latency
        );
      }
      
      return NetworkStatus(isOnline: false, nodeUrl: baseUrl);
    } catch (e) {
      return NetworkStatus(isOnline: false, nodeUrl: baseUrl, error: e.toString());
    }
  }
}

// ==================== RESULT CLASSES ====================

class HandleNetworkResult {
  final bool success;
  final String? handle;
  final String? error;

  HandleNetworkResult({required this.success, this.handle, this.error});
}

class HandleResolveResult {
  final bool success;
  final String? handle;
  final String? publicKey;
  final String? error;

  HandleResolveResult({
    required this.success,
    this.handle,
    this.publicKey,
    this.error,
  });
}

class NetworkStatus {
  final bool isOnline;
  final String nodeUrl;
  final int? latencyMs;
  final String? error;

  NetworkStatus({
    required this.isOnline,
    required this.nodeUrl,
    this.latencyMs,
    this.error,
  });
}
