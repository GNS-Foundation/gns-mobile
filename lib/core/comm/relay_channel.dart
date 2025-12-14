/// Relay Channel - HTTP/WebSocket Transport
/// 
/// Transport layer for your Railway GNS server.
/// 
/// Location: lib/core/comm/relay_channel.dart
/// 
/// MATCHES YOUR SERVER STRUCTURE:
/// - HTTP: /messages (not /api/v1/messages)
/// - WebSocket: /ws (not /api/v1/ws)

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'gns_envelope.dart';

/// Channel connection state
enum ChannelState {
  disconnected,
  connecting,
  connected,
  reconnecting,
  error,
}

/// Result of channel operations
class ChannelResult {
  final bool success;
  final String? error;
  final Map<String, dynamic>? data;

  ChannelResult.success([this.data]) : success = true, error = null;
  ChannelResult.failure(this.error) : success = false, data = null;
}

/// Abstract transport channel interface
abstract class CommunicationChannel {
  String get channelId;
  String get channelName;
  ChannelState get state;
  Stream<ChannelState> get stateStream;
  Stream<GnsEnvelope> get incomingEnvelopes;
  Future<bool> canReach(String publicKey);
  Future<ChannelResult> send(GnsEnvelope envelope);
  Future<ChannelResult> connect();
  Future<void> disconnect();
  Future<void> dispose();
}

/// Relay server channel configuration
class RelayChannelConfig {
  final String baseUrl;      // Base URL without path
  final Duration connectTimeout;
  final Duration receiveTimeout;
  final Duration reconnectDelay;
  final int maxReconnectAttempts;
  final Duration heartbeatInterval;

  const RelayChannelConfig({
    required this.baseUrl,
    this.connectTimeout = const Duration(seconds: 10),
    this.receiveTimeout = const Duration(seconds: 30),
    this.reconnectDelay = const Duration(seconds: 5),
    this.maxReconnectAttempts = 5,
    this.heartbeatInterval = const Duration(seconds: 30),
  });
  
  /// HTTP URL for messages API
  String get httpUrl => '$baseUrl/messages';
  
  /// WebSocket URL
  String get wsUrl {
    final uri = Uri.parse(baseUrl);
    final wsScheme = uri.scheme == 'https' ? 'wss' : 'ws';
    return '$wsScheme://${uri.host}${uri.port != 80 && uri.port != 443 ? ':${uri.port}' : ''}/ws';
  }
  
  /// =====================================================
  /// PRODUCTION - Your Railway deployment
  /// =====================================================
  factory RelayChannelConfig.production() => const RelayChannelConfig(
    baseUrl: 'https://gns-browser-production.up.railway.app',
  );
  
  /// =====================================================
  /// LOCAL DEVELOPMENT
  /// =====================================================
  factory RelayChannelConfig.local() => const RelayChannelConfig(
    baseUrl: 'http://localhost:3000',
  );
  
  /// Default uses production
  factory RelayChannelConfig.defaultConfig() => RelayChannelConfig.production();
}

/// Authentication provider for relay requests
typedef AuthProvider = Future<RelayAuth> Function();

/// Authentication data for relay
class RelayAuth {
  final String publicKey;
  final int timestamp;
  final String signature;

  RelayAuth({
    required this.publicKey,
    required this.timestamp,
    required this.signature,
  });
  
  Map<String, String> get headers => {
    'X-GNS-PublicKey': publicKey,
    'X-GNS-Timestamp': timestamp.toString(),
    'X-GNS-Signature': signature,
  };
}

/// Relay server transport channel
class RelayChannel implements CommunicationChannel {
  @override
  final String channelId = 'relay';
  
  @override
  final String channelName = 'GNS Relay';
  
  final RelayChannelConfig config;
  final AuthProvider authProvider;
  
  late final Dio _dio;
  WebSocketChannel? _wsChannel;
  
  // ✅ Expose dio for direct HTTP access (needed for fetching records)
  Dio get dio => _dio;
  
  ChannelState _state = ChannelState.disconnected;
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  
  final _stateController = StreamController<ChannelState>.broadcast();
  final _envelopeController = StreamController<GnsEnvelope>.broadcast();

  RelayChannel({
    required this.config,
    required this.authProvider,
  }) {
    _dio = Dio(BaseOptions(
      baseUrl: config.httpUrl,
      connectTimeout: config.connectTimeout,
      receiveTimeout: config.receiveTimeout,
      headers: {'Content-Type': 'application/json'},
    ));
    
    if (kDebugMode) {
      _dio.interceptors.add(LogInterceptor(
        requestBody: true,
        responseBody: true,
        logPrint: (obj) => debugPrint(obj.toString()),
      ));
    }
  }
  
  /// Create with default production config
  factory RelayChannel.production({required AuthProvider authProvider}) {
    return RelayChannel(
      config: RelayChannelConfig.production(),
      authProvider: authProvider,
    );
  }

  @override
  ChannelState get state => _state;
  
  @override
  Stream<ChannelState> get stateStream => _stateController.stream;
  
  @override
  Stream<GnsEnvelope> get incomingEnvelopes => _envelopeController.stream;

  void _setState(ChannelState newState) {
    if (_state != newState) {
      _state = newState;
      _stateController.add(newState);
      debugPrint('RelayChannel state: $newState');
    }
  }

  @override
  Future<bool> canReach(String publicKey) async {
    try {
      // baseUrl is already ".../messages"
      final response = await _dio.get('/presence/$publicKey');
      final data = response.data as Map<String, dynamic>?;

      final status = data?['data']?['status'] as String?;
      // The relay treats "online" and "away" as reachable
      return status == 'online' || status == 'away';
    } catch (e) {
      debugPrint('⚠️ canReach error for $publicKey: $e');
      if (e is DioException) {
        debugPrint('⚠️ canReach response: ${e.response?.data}');
      }
      // Be optimistic if presence check fails
      return true;
    }
  }

  @override
  Future<ChannelResult> connect() async {
    if (_state == ChannelState.connecting) {
      return ChannelResult.failure('Already connecting');
    }
    
    _setState(ChannelState.connecting);
    
    try {
      final auth = await authProvider();
      
      final wsUrl = '${config.wsUrl}'
          '?pubkey=${auth.publicKey}'
          '&timestamp=${auth.timestamp}'
          '&sig=${Uri.encodeComponent(auth.signature)}';
      
      debugPrint('Connecting WebSocket to: ${config.wsUrl}');
      
      _wsChannel = WebSocketChannel.connect(Uri.parse(wsUrl));
      
      _wsChannel!.stream.listen(
        _handleWebSocketMessage,
        onError: _handleWebSocketError,
        onDone: _handleWebSocketDone,
      );
      
      _reconnectAttempts = 0;
      _setState(ChannelState.connected);
      _startHeartbeat();
      
      // Update presence
      await _updatePresence('online');
      
      return ChannelResult.success();
    } catch (e) {
      debugPrint('WebSocket connection failed: $e');
      _setState(ChannelState.error);
      _scheduleReconnect();
      return ChannelResult.failure('Connection failed: $e');
    }
  }

  @override
  Future<void> disconnect() async {
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    
    await _updatePresence('offline');
    
    await _wsChannel?.sink.close();
    _wsChannel = null;
    _setState(ChannelState.disconnected);
  }

  @override
  Future<ChannelResult> send(GnsEnvelope envelope) async {
    // Try WebSocket first
    if (_state == ChannelState.connected && _wsChannel != null) {
      try {
        _wsChannel!.sink.add(jsonEncode({
          'type': 'message',
          'envelope': envelope.toJson(),
        }));
        return ChannelResult.success();
      } catch (e) {
        debugPrint('WebSocket send failed, falling back to HTTP: $e');
      }
    }
    
    // Fall back to HTTP
    try {
      final auth = await authProvider();
      
      await _dio.post(
        '',  // POST to /messages
        data: {
          'envelope': envelope.toJson(),
          'recipients': envelope.allVisibleRecipients,
        },
        options: Options(headers: auth.headers),
      );
      
      return ChannelResult.success();
    } catch (e) {
      debugPrint('HTTP send failed: $e');
      return ChannelResult.failure('Send failed: $e');
    }
  }

  /// Fetch pending messages
  Future<List<GnsEnvelope>> fetchPending({int? since, int limit = 100}) async {
    try {
      final auth = await authProvider();
      
      final response = await _dio.get(
        '',  // GET /messages
        queryParameters: {
          if (since != null) 'since': since,
          'limit': limit,
        },
        options: Options(headers: auth.headers),
      );
      
      final messages = response.data['messages'] as List? ?? [];
      return messages
          .map((m) => GnsEnvelope.fromJson(m as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Error fetching pending messages: $e');
      return [];
    }
  }

  /// Acknowledge messages (POST /messages/ack)
  /// ✅ FIXED: Use full URL to avoid race condition with baseUrl changes
  Future<void> acknowledgeMessages(List<String> messageIds) async {
    if (messageIds.isEmpty) {
      return;
    }

    try {
      final auth = await authProvider();

      // Ensure we're sending an array of strings
      final payload = <String, dynamic>{
        'messageIds': messageIds.map((id) => id.toString()).toList(),
      };

      // ✅ FIX: Use full URL to avoid race condition with baseUrl changes
      final url = '${config.baseUrl}/messages/ack';
      debugPrint('🔍 ACK → POST $url');
      debugPrint('🔍 ACK body: ${jsonEncode(payload)}');

      final response = await _dio.post(
        url,  // ✅ Full URL, not relative
        data: payload,
        options: Options(headers: auth.headers),
      );

      debugPrint('✅ ACK OK: ${response.statusCode}');

    } catch (e) {
      debugPrint('❌ ACK ERROR: $e');
      if (e is DioException) {
        debugPrint('❌ ACK response.status: ${e.response?.statusCode}');
        debugPrint('❌ ACK response.data: ${e.response?.data}');
      }
    }
  }

  /// Mark messages as read (POST /messages/read)
  /// ✅ FIXED: Use full URL to avoid race condition
  Future<void> markMessagesRead(List<String> messageIds) async {
    if (messageIds.isEmpty) return;

    try {
      final auth = await authProvider();
      final payload = <String, dynamic>{
        'messageIds': messageIds.map((id) => id.toString()).toList(),
      };

      // ✅ FIX: Use full URL
      final url = '${config.baseUrl}/messages/read';
      debugPrint('🔍 READ → POST $url');
      debugPrint('🔍 READ body: ${jsonEncode(payload)}');

      final response = await _dio.post(
        url,  // ✅ Full URL
        data: payload,
        options: Options(headers: auth.headers),
      );

      debugPrint('✅ READ OK: ${response.statusCode}');
    } catch (e) {
      debugPrint('❌ READ ERROR: $e');
      if (e is DioException) {
        debugPrint('❌ READ response.status: ${e.response?.statusCode}');
        debugPrint('❌ READ response.data: ${e.response?.data}');
      }
    }
  }

  /// Send typing indicator
  Future<void> sendTyping({
    required String threadId,
    required bool isTyping,
  }) async {
    if (_state == ChannelState.connected && _wsChannel != null) {
      try {
        _wsChannel!.sink.add(jsonEncode({
          'type': 'typing',
          'threadId': threadId,
          'isTyping': isTyping,
        }));
        return;
      } catch (e) {
        debugPrint('WebSocket typing failed, using HTTP: $e');
      }
    }
    
    // Fall back to HTTP - use full URL
    try {
      final auth = await authProvider();
      final url = '${config.baseUrl}/messages/typing';
      await _dio.post(
        url,
        data: {'threadId': threadId, 'isTyping': isTyping},
        options: Options(headers: auth.headers),
      );
    } catch (e) {
      debugPrint('Error sending typing indicator: $e');
    }
  }

  /// Resolve a @handle to its public key
  /// ✅ FIXED: Use full URL instead of mutating baseUrl
  Future<String?> resolveHandle(String handle) async {
    try {
      final cleanHandle = handle.toLowerCase().replaceAll('@', '').trim();
      
      // ✅ FIX: Use full URL instead of changing baseUrl
      final url = '${config.baseUrl}/handles/$cleanHandle';
      final response = await _dio.get(url);
      
      if (response.statusCode == 200 && response.data['success'] == true) {
        return response.data['data']['public_key'] as String? ??
               response.data['data']['pk_root'] as String?;
      }
      
      return null;
    } catch (e) {
      debugPrint('Error resolving handle: $e');
      return null;
    }
  }

  /// Resolve handle and return full info (including encryption key)
  /// ✅ FIXED: Use full URL instead of mutating baseUrl
  Future<Map<String, dynamic>?> resolveHandleInfo(String handle) async {
    try {
      final cleanHandle = handle.toLowerCase().replaceAll('@', '').trim();
      
      // ✅ FIX: Use full URL
      final url = '${config.baseUrl}/handles/$cleanHandle';
      final response = await _dio.get(url);
      
      if (response.statusCode == 200 && response.data['success'] == true) {
        final handleData = response.data['data'] as Map<String, dynamic>;
        return {
          'public_key': handleData['public_key'] ?? handleData['pk_root'],
          'encryption_key': handleData['encryption_key'],
          'handle': handleData['handle'] ?? '@$cleanHandle',
          'is_system': handleData['is_system'] ?? false,
          'type': handleData['type'],
        };
      }
      
      return null;
    } catch (e) {
      debugPrint('Error resolving handle info: $e');
      return null;
    }
  }

  /// Get identity info (including encryption key) by public key
  /// ✅ FIXED: Use full URL instead of mutating baseUrl
  Future<Map<String, dynamic>?> getIdentity(String publicKey) async {
    try {
      // ✅ FIX: Use full URL
      final url = '${config.baseUrl}/identities/$publicKey';
      final response = await _dio.get(url);
      
      if (response.statusCode == 200 && response.data['success'] == true) {
        final identityData = response.data['data'] as Map<String, dynamic>;
        return {
          'public_key': identityData['public_key'] ?? identityData['pk_root'],
          'encryption_key': identityData['encryption_key'],
          'handle': identityData['handle'],
          'display_name': identityData['display_name'],
          'avatar_url': identityData['avatar_url'],
        };
      }
      
      return null;
    } catch (e) {
      debugPrint('Error fetching identity: $e');
      return null;
    }
  }

  /// Update presence status
  /// ✅ FIXED: Use full URL
  Future<void> _updatePresence(String status) async {
    try {
      final auth = await authProvider();
      final url = '${config.baseUrl}/messages/presence';
      await _dio.post(
        url,
        data: {'status': status},
        options: Options(headers: auth.headers),
      );
    } catch (e) {
      debugPrint('Error updating presence: $e');
    }
  }

  void _handleWebSocketMessage(dynamic data) {
    try {
      final json = jsonDecode(data as String) as Map<String, dynamic>;
      final type = json['type'] as String;
      
      switch (type) {
        case 'message':
          final envelope = GnsEnvelope.fromJson(
            json['envelope'] as Map<String, dynamic>,
          );
          _envelopeController.add(envelope);
          break;
          
        case 'connected':
          debugPrint('WebSocket confirmed connected');
          break;
          
        case 'pong':
          break;
          
        case 'error':
          debugPrint('Relay error: ${json['message']}');
          break;
      }
    } catch (e) {
      debugPrint('Error handling WebSocket message: $e');
    }
  }

  void _handleWebSocketError(dynamic error) {
    debugPrint('WebSocket error: $error');
    _setState(ChannelState.error);
    _scheduleReconnect();
  }

  void _handleWebSocketDone() {
    debugPrint('WebSocket closed');
    if (_state != ChannelState.disconnected) {
      _setState(ChannelState.disconnected);
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_reconnectAttempts >= config.maxReconnectAttempts) {
      debugPrint('Max reconnect attempts reached');
      _setState(ChannelState.error);
      return;
    }
    
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(config.reconnectDelay, () {
      _reconnectAttempts++;
      debugPrint('Reconnect attempt $_reconnectAttempts/${config.maxReconnectAttempts}');
      _setState(ChannelState.reconnecting);
      connect();
    });
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(config.heartbeatInterval, (_) {
      if (_state == ChannelState.connected && _wsChannel != null) {
        _wsChannel!.sink.add(jsonEncode({'type': 'ping'}));
      }
    });
  }

  @override
  Future<void> dispose() async {
    await disconnect();
    await _stateController.close();
    await _envelopeController.close();
  }
}

/// Multi-channel manager
class ChannelManager {
  final List<CommunicationChannel> _channels = [];
  final Map<String, CommunicationChannel> _channelMap = {};
  
  void addChannel(CommunicationChannel channel) {
    _channels.add(channel);
    _channelMap[channel.channelId] = channel;
  }
  
  void removeChannel(String channelId) {
    final channel = _channelMap.remove(channelId);
    if (channel != null) {
      _channels.remove(channel);
    }
  }
  
  CommunicationChannel? getChannel(String channelId) => _channelMap[channelId];
  
  List<CommunicationChannel> get connectedChannels {
    return _channels.where((c) => c.state == ChannelState.connected).toList();
  }
  
  Future<ChannelResult> send(GnsEnvelope envelope) async {
    for (final channel in connectedChannels) {
      final result = await channel.send(envelope);
      if (result.success) return result;
    }
    
    if (_channels.isNotEmpty) {
      final channel = _channels.first;
      await channel.connect();
      return channel.send(envelope);
    }
    
    return ChannelResult.failure('No channels available');
  }
  
  Future<void> connectAll() async {
    await Future.wait(_channels.map((c) => c.connect()));
  }
  
  Future<void> disconnectAll() async {
    await Future.wait(_channels.map((c) => c.disconnect()));
  }
  
  Future<void> dispose() async {
    await Future.wait(_channels.map((c) => c.dispose()));
    _channels.clear();
    _channelMap.clear();
  }
}
