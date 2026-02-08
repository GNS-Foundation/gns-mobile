// ===========================================
// GNS BROWSER - CALLKIT + PUSHKIT SERVICE
//
// Handles:
// - PushKit VoIP token registration
// - CallKit native call UI
// - Background call wake-up
// ===========================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:uuid/uuid.dart';
import 'package:dio/dio.dart';

class CallKitService {
  static final CallKitService _instance = CallKitService._internal();
  factory CallKitService() => _instance;
  CallKitService._internal();

  // Callbacks
  Function(Map<String, dynamic>)? onCallAccepted;
  Function(Map<String, dynamic>)? onCallDeclined;
  Function(Map<String, dynamic>)? onCallEnded;

  // State
  String? _currentCallId;
  String? _voipToken;
  bool _initialized = false;

  String? get voipToken => _voipToken;
  String? get currentCallId => _currentCallId;

  // ===========================================
  // INITIALIZATION
  // ===========================================

  Future<void> initialize() async {
    if (_initialized) return;
    if (!Platform.isIOS) {
      // Android uses Firebase FCM — handled separately
      _initialized = true;
      return;
    }

    // Listen for VoIP token from PushKit
    FlutterCallkitIncoming.onEvent.listen(_handleCallKitEvent);

    // Get VoIP token
    await _requestVoipToken();

    _initialized = true;
    debugPrint('✅ CallKit service initialized');
  }

  // ===========================================
  // PUSHKIT VoIP TOKEN
  // ===========================================

  Future<void> _requestVoipToken() async {
    try {
      // flutter_callkit_incoming handles PushKit registration automatically
      // The token comes via the event listener
      _voipToken = await FlutterCallkitIncoming.getDevicePushTokenVoIP();
      debugPrint('📲 VoIP token: ${_voipToken?.substring(0, 20)}...');
    } catch (e) {
      debugPrint('⚠️ Failed to get VoIP token: $e');
    }
  }

  /// Register push token with GNS server
  Future<void> registerWithServer({
    required String serverUrl,
    required String publicKey,
    required String deviceId,
    String? appVersion,
  }) async {
    if (_voipToken == null) {
      debugPrint('⚠️ No VoIP token to register');
      return;
    }

    try {
      final dio = Dio();
      await dio.post(
        '$serverUrl/push/register',
        data: {
          'publicKey': publicKey,
          'voipToken': _voipToken,
          'platform': Platform.isIOS ? 'ios' : 'android',
          'deviceId': deviceId,
          'appVersion': appVersion,
          'sandbox': kDebugMode,  // Debug builds use sandbox APNs
        },
      );
      debugPrint('✅ Push token registered with server');
    } catch (e) {
      debugPrint('❌ Failed to register push token: $e');
    }
  }

  // ===========================================
  // SHOW INCOMING CALL (Native CallKit UI)
  // ===========================================

  /// Display the native iOS call screen.
  /// Called when receiving either:
  /// 1. A WebSocket 'incoming_call' signal (app in foreground)
  /// 2. A VoIP push notification (app in background/killed)
  Future<void> showIncomingCall({
    required String callId,
    required String callerPublicKey,
    String? callerHandle,
    String? callerName,
    String callType = 'voice',
  }) async {
    _currentCallId = callId;

    final displayName = callerName
        ?? (callerHandle != null ? '@$callerHandle' : null)
        ?? '${callerPublicKey.substring(0, 12)}...';

    final params = CallKitParams(
      id: callId,
      nameCaller: displayName,
      appName: 'GNS Browser',
      handle: callerHandle ?? callerPublicKey.substring(0, 16),
      type: callType == 'video' ? 1 : 0,  // 0 = voice, 1 = video
      duration: 45000,  // Ring for 45 seconds
      textAccept: 'Accept',
      textDecline: 'Decline',
      // iOS-specific
      ios: IOSParams(
        iconName: 'CallKitIcon',  // Add to Assets.xcassets
        handleType: 'generic',
        supportsVideo: true,
        maximumCallGroups: 1,
        maximumCallsPerCallGroup: 1,
        audioSessionMode: 'default',
        audioSessionActive: true,
        audioSessionPreferredSampleRate: 44100.0,
        audioSessionPreferredIOBufferDuration: 0.005,
        supportsDTMF: false,
        supportsHolding: false,
        supportsGrouping: false,
        supportsUngrouping: false,
        ringtonePath: 'system_ringtone_default',
      ),
      // Android-specific (for future)
      android: AndroidParams(
        isCustomNotification: true,
        isShowLogo: true,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#1a1a2e',
        actionColor: '#4CAF50',
        incomingCallNotificationChannelName: 'GNS Incoming Calls',
      ),
      extra: {
        'callerPublicKey': callerPublicKey,
        'callerHandle': callerHandle ?? '',
        'callType': callType,
      },
    );

    await FlutterCallkitIncoming.showCallkitIncoming(params);
    debugPrint('📞 Showing incoming call from $displayName');
  }

  // ===========================================
  // OUTGOING CALL
  // ===========================================

  Future<String> startOutgoingCall({
    required String calleePublicKey,
    String? calleeName,
    String callType = 'voice',
  }) async {
    final callId = const Uuid().v4();
    _currentCallId = callId;

    final params = CallKitParams(
      id: callId,
      nameCaller: calleeName ?? '${calleePublicKey.substring(0, 12)}...',
      handle: calleePublicKey.substring(0, 16),
      type: callType == 'video' ? 1 : 0,
      extra: {
        'calleePublicKey': calleePublicKey,
        'callType': callType,
      },
    );

    await FlutterCallkitIncoming.startCall(params);
    return callId;
  }

  // ===========================================
  // CALL ACTIONS
  // ===========================================

  Future<void> endCall([String? callId]) async {
    final id = callId ?? _currentCallId;
    if (id != null) {
      await FlutterCallkitIncoming.endCall(id);
    }
    _currentCallId = null;
  }

  Future<void> endAllCalls() async {
    await FlutterCallkitIncoming.endAllCalls();
    _currentCallId = null;
  }

  Future<void> setCallConnected(String callId) async {
    // Tells CallKit the call is connected (stops "connecting..." text)
    await FlutterCallkitIncoming.setCallConnected(callId);
  }

  // ===========================================
  // EVENT HANDLING
  // ===========================================

  void _handleCallKitEvent(CallEvent? event) {
    if (event == null) return;

    debugPrint('📞 CallKit event: ${event.event}');

    switch (event.event) {
      case Event.actionCallIncoming:
        // Call is being displayed to user
        debugPrint('   Incoming call displayed');
        break;

      case Event.actionCallAccept:
        // User tapped Accept ✅
        debugPrint('   Call accepted!');
        final data = event.body as Map<String, dynamic>? ?? {};
        final extra = data['extra'] as Map<String, dynamic>? ?? {};
        _currentCallId = data['id'] as String?;
        onCallAccepted?.call({
          'callId': data['id'],
          'callerPublicKey': extra['callerPublicKey'],
          'callerHandle': extra['callerHandle'],
          'callType': extra['callType'] ?? 'voice',
        });
        break;

      case Event.actionCallDecline:
        // User tapped Decline ❌
        debugPrint('   Call declined');
        final data = event.body as Map<String, dynamic>? ?? {};
        final extra = data['extra'] as Map<String, dynamic>? ?? {};
        onCallDeclined?.call({
          'callId': data['id'],
          'callerPublicKey': extra['callerPublicKey'],
        });
        _currentCallId = null;
        break;

      case Event.actionCallEnded:
        // Call ended (either party)
        debugPrint('   Call ended');
        final data = event.body as Map<String, dynamic>? ?? {};
        onCallEnded?.call({
          'callId': data['id'],
        });
        _currentCallId = null;
        break;

      case Event.actionCallTimeout:
        // Ring timed out — no answer
        debugPrint('   Call timed out');
        final data = event.body as Map<String, dynamic>? ?? {};
        onCallDeclined?.call({
          'callId': data['id'],
          'reason': 'timeout',
        });
        _currentCallId = null;
        break;

      case Event.actionDidUpdateDevicePushTokenVoip:
        // PushKit token updated
        final token = event.body?['deviceTokenVoIP'] as String?;
        if (token != null) {
          _voipToken = token;
          debugPrint('📲 VoIP token updated: ${token.substring(0, 20)}...');
        }
        break;

      default:
        debugPrint('   Unhandled: ${event.event}');
    }
  }

  // ===========================================
  // HANDLE VoIP PUSH (called from AppDelegate)
  // ===========================================

  /// Process incoming VoIP push payload.
  /// This is called when the app is woken by a PushKit VoIP notification.
  Future<void> handleVoipPush(Map<String, dynamic> payload) async {
    final gns = payload['gns'] as Map<String, dynamic>?;
    if (gns == null) return;

    final type = gns['type'] as String?;
    if (type != 'incoming_call') return;

    await showIncomingCall(
      callId: gns['callId'] as String,
      callerPublicKey: gns['callerPk'] as String,
      callerHandle: gns['callerHandle'] as String?,
      callerName: gns['callerName'] as String?,
      callType: gns['callType'] as String? ?? 'voice',
    );
  }

  void dispose() {
    _initialized = false;
    _currentCallId = null;
  }
}
