/// GNS Channel Service
///
/// Manages the persistent WebSocket connection from mobile → relay AFTER
/// a browser pairing session is approved.
///
/// This is the real-time bridge that makes the password manager work:
///
///   Chrome Extension
///       ↓ credential_request  (device=browser)
///   Railway Relay  ───────────────────────
///       ↓ forwarded to device=mobile
///   GnsChannelService  ← YOU ARE HERE
///       ↓ emits CredentialRequest on stream
///   CredentialApprovalSheet → user taps Approve
///       ↓ credential_response  (device=mobile)
///   Railway Relay  ───────────────────────
///       ↓ forwarded to device=browser
///   Chrome Extension autofills the form
///
/// Location: lib/core/vault/gns_channel_service.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as ws_status;

// ─────────────────────────────────────────────────────────────────────────────
// MODELS
// ─────────────────────────────────────────────────────────────────────────────

/// Incoming credential request from Chrome extension
class CredentialRequest {
  final String requestId;
  final String domain;
  final String? usernameHint;   // Optional pre-filled username from browser
  final String? pageTitle;      // Tab title for display
  final DateTime receivedAt;

  CredentialRequest({
    required this.requestId,
    required this.domain,
    this.usernameHint,
    this.pageTitle,
    required this.receivedAt,
  });

  factory CredentialRequest.fromJson(Map<String, dynamic> j) =>
    CredentialRequest(
      requestId:    j['requestId'] as String,
      domain:       j['domain'] as String,
      usernameHint: j['hint'] as String?,
      pageTitle:    j['pageTitle'] as String?,
      receivedAt:   DateTime.fromMillisecondsSinceEpoch(
                      (j['timestamp'] as int?) ?? DateTime.now().millisecondsSinceEpoch),
    );
}

/// State of the persistent mobile channel
enum ChannelConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
}

// ─────────────────────────────────────────────────────────────────────────────
// SERVICE
// ─────────────────────────────────────────────────────────────────────────────

class GnsChannelService {
  static final GnsChannelService _instance = GnsChannelService._internal();
  factory GnsChannelService() => _instance;
  GnsChannelService._internal();

  static const _baseWsUrl   = 'wss://gns-browser-production.up.railway.app/ws';
  static const _reconnectDelay = Duration(seconds: 5);
  static const _maxReconnects  = 10;

  // ── State ──────────────────────────────────────────────────────────────────
  WebSocketChannel? _channel;
  StreamSubscription? _channelSub;

  String? _publicKey;
  String? _sessionToken;

  ChannelConnectionState _state = ChannelConnectionState.disconnected;
  int _reconnectCount = 0;
  bool _shouldReconnect = true;

  // ── Streams ────────────────────────────────────────────────────────────────
  final _credentialRequestController =
      StreamController<CredentialRequest>.broadcast();
  final _stateController =
      StreamController<ChannelConnectionState>.broadcast();

  /// Listen here for incoming credential requests from Chrome extension.
  Stream<CredentialRequest> get credentialRequests =>
      _credentialRequestController.stream;

  /// Connection state changes.
  Stream<ChannelConnectionState> get stateStream => _stateController.stream;

  ChannelConnectionState get state => _state;
  bool get isConnected => _state == ChannelConnectionState.connected;

  // ── Connect / Disconnect ───────────────────────────────────────────────────

  /// Call this after a browser pairing session is approved.
  /// [sessionToken] comes from BrowserAuthResult.sessionId (stored by app).
  Future<void> connect({
    required String publicKey,
    required String sessionToken,
  }) async {
    _publicKey    = publicKey;
    _sessionToken = sessionToken;
    _shouldReconnect = true;
    _reconnectCount  = 0;
    await _doConnect();
  }

  Future<void> _doConnect() async {
    _setState(ChannelConnectionState.connecting);
    debugPrint('[CHANNEL] Connecting as device=mobile...');

    try {
      final uri = Uri.parse(
        '$_baseWsUrl'
        '?pk=$_publicKey'
        '&device=mobile'
        '&session=$_sessionToken',
      );

      _channel = WebSocketChannel.connect(uri);
      await _channel!.ready;

      _setState(ChannelConnectionState.connected);
      _reconnectCount = 0;
      debugPrint('[CHANNEL] Connected — listening for credential requests');

      _channelSub = _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
        cancelOnError: false,
      );

      // Send heartbeat every 25s to stay alive through idle timeouts
      _startHeartbeat();

    } catch (e) {
      debugPrint('[CHANNEL] Connect failed: $e');
      _setState(ChannelConnectionState.disconnected);
      _scheduleReconnect();
    }
  }

  void disconnect() {
    _shouldReconnect = false;
    _heartbeatTimer?.cancel();
    _channelSub?.cancel();
    _channel?.sink.close(ws_status.normalClosure);
    _channel = null;
    _setState(ChannelConnectionState.disconnected);
    debugPrint('[CHANNEL] Disconnected');
  }

  // ── Outgoing messages ──────────────────────────────────────────────────────

  /// Send a credential response back to the Chrome extension.
  void sendCredentialResponse({
    required String requestId,
    required String domain,
    String? username,
    String? password,
    bool denied = false,
  }) {
    if (!isConnected) {
      debugPrint('[CHANNEL] Cannot send response — not connected');
      return;
    }

    final message = {
      'type':      'credential_response',
      'requestId': requestId,
      'domain':    domain,
      'denied':    denied,
      if (!denied && username != null) 'username': username,
      if (!denied && password != null) 'password': password,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    _channel!.sink.add(jsonEncode(message));
    debugPrint('[CHANNEL] Sent credential_response for $domain '
        '(${denied ? "DENIED" : "APPROVED"})');
  }

  /// Send a generic ping to keep the connection alive.
  void sendPing() {
    if (isConnected) {
      _channel?.sink.add(jsonEncode({'type': 'ping'}));
    }
  }

  // ── Message handling ───────────────────────────────────────────────────────

  void _onMessage(dynamic data) {
    try {
      final msg = jsonDecode(data as String) as Map<String, dynamic>;
      final type = msg['type'] as String?;

      debugPrint('[CHANNEL] Received: $type');

      switch (type) {
        case 'welcome':
          debugPrint('[CHANNEL] Welcome from relay — '
              'browsers: ${msg['connectedDevices']?['browsers'] ?? 0}');
          break;

        case 'credential_request':
          // Chrome extension is asking for credentials for a domain
          final request = CredentialRequest.fromJson(msg);
          debugPrint('[CHANNEL] Credential request: ${request.domain} '
              '(reqId: ${request.requestId.substring(0, 8)}...)');
          _credentialRequestController.add(request);
          break;

        case 'pong':
          // Heartbeat ack — ignore
          break;

        case 'connection_status':
          final browsers = msg['data']?['browsers'] ?? 0;
          debugPrint('[CHANNEL] Connection status — browsers online: $browsers');
          break;

        default:
          debugPrint('[CHANNEL] Unknown message type: $type');
      }
    } catch (e) {
      debugPrint('[CHANNEL] _onMessage parse error: $e');
    }
  }

  void _onError(Object error) {
    debugPrint('[CHANNEL] WebSocket error: $error');
    _scheduleReconnect();
  }

  void _onDone() {
    debugPrint('[CHANNEL] WebSocket closed');
    _heartbeatTimer?.cancel();
    if (_shouldReconnect) {
      _setState(ChannelConnectionState.reconnecting);
      _scheduleReconnect();
    } else {
      _setState(ChannelConnectionState.disconnected);
    }
  }

  // ── Reconnect ──────────────────────────────────────────────────────────────

  void _scheduleReconnect() {
    if (!_shouldReconnect) return;
    if (_reconnectCount >= _maxReconnects) {
      debugPrint('[CHANNEL] Max reconnect attempts reached — giving up');
      _setState(ChannelConnectionState.disconnected);
      return;
    }

    _reconnectCount++;
    final delay = Duration(
      seconds: _reconnectDelay.inSeconds * _reconnectCount,
    );
    debugPrint('[CHANNEL] Reconnecting in ${delay.inSeconds}s '
        '(attempt $_reconnectCount/$_maxReconnects)');

    Future.delayed(delay, () {
      if (_shouldReconnect) _doConnect();
    });
  }

  // ── Heartbeat ──────────────────────────────────────────────────────────────

  Timer? _heartbeatTimer;

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      sendPing();
    });
  }

  // ── State ──────────────────────────────────────────────────────────────────

  void _setState(ChannelConnectionState s) {
    _state = s;
    _stateController.add(s);
  }

  // ── Dispose ────────────────────────────────────────────────────────────────

  void dispose() {
    disconnect();
    _credentialRequestController.close();
    _stateController.close();
  }
}
