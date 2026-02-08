/// GNS Call Service — Voice & Video Calls via WebRTC
///
/// Complete call lifecycle manager:
/// - Outgoing: startCall() → ringing → connected → endCall()
/// - Incoming: handleCallOffer() → acceptCall() → connected → endCall()
/// - WebRTC peer connection with STUN/TURN
/// - Signaling via existing GNS WebSocket relay
///
/// Dependencies:
///   flutter_webrtc: ^0.12.0
///   uuid: (existing)
///   http: (existing)
///
/// Location: lib/core/calls/call_service.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'dart:io';
import '../../services/callkit_service.dart';

// ===========================================
// CALL ENUMS & DATA CLASSES
// ===========================================

/// Call lifecycle states
enum CallState {
  idle,
  initiating,        // Creating offer, gathering ICE
  ringing,           // Outgoing: waiting for answer
  incomingRinging,   // Incoming: received offer
  connecting,        // WebRTC ICE negotiation
  connected,         // Media flowing
  ending,
  ended,
  failed,
}

enum CallType { voice, video }
enum CallDirection { outgoing, incoming }

enum CallEndReason {
  normal,
  rejected,
  busy,
  timeout,
  failed,
  cancelled,
}

/// Snapshot of current call state (immutable, safe to emit on streams)
class CallInfo {
  final String callId;
  final CallState state;
  final CallType type;
  final CallDirection direction;
  final String remotePublicKey;
  final String? remoteHandle;
  final DateTime startedAt;
  final DateTime? connectedAt;
  final Duration duration;
  final bool isAudioMuted;
  final bool isVideoEnabled;
  final bool isSpeakerOn;
  final CallEndReason? endReason;

  const CallInfo({
    required this.callId,
    required this.state,
    required this.type,
    required this.direction,
    required this.remotePublicKey,
    this.remoteHandle,
    required this.startedAt,
    this.connectedAt,
    this.duration = Duration.zero,
    this.isAudioMuted = false,
    this.isVideoEnabled = true,
    this.isSpeakerOn = false,
    this.endReason,
  });

  bool get isActive => state == CallState.connected;
  bool get isRinging =>
      state == CallState.ringing || state == CallState.incomingRinging;
  bool get isEnded =>
      state == CallState.ended || state == CallState.failed;

  String get durationFormatted {
    final m = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (duration.inHours > 0) {
      return '${duration.inHours}:$m:$s';
    }
    return '$m:$s';
  }

  String get stateLabel {
    switch (state) {
      case CallState.idle: return '';
      case CallState.initiating: return 'Connecting...';
      case CallState.ringing: return 'Ringing...';
      case CallState.incomingRinging: return 'Incoming call';
      case CallState.connecting: return 'Connecting...';
      case CallState.connected: return durationFormatted;
      case CallState.ending: return 'Ending...';
      case CallState.ended: return 'Call ended';
      case CallState.failed: return 'Call failed';
    }
  }
}

/// ICE server configuration from backend
class _IceConfig {
  final List<Map<String, dynamic>> iceServers;
  final int ttl;
  final DateTime fetchedAt;

  _IceConfig({
    required this.iceServers,
    required this.ttl,
    required this.fetchedAt,
  });

  bool get isExpired =>
      DateTime.now().difference(fetchedAt).inSeconds > (ttl ~/ 2);

  Map<String, dynamic> toWebRTC() => {
    'iceServers': iceServers,
    'sdpSemantics': 'unified-plan',
  };
}

// ===========================================
// CALL SERVICE SINGLETON
// ===========================================

/// Callback type for sending WebSocket messages
typedef SendRawFn = void Function(String jsonMessage);

/// Callback type for resolving public key to handle
typedef ResolveHandleFn = Future<String?> Function(String publicKey);

class CallService extends ChangeNotifier {
  // Singleton
  static final CallService _instance = CallService._internal();
  factory CallService() => _instance;
  CallService._internal();

  static const _uuid = Uuid();

  // ------- Configuration -------
  String _baseUrl = 'https://gns-browser-production.up.railway.app';
  String? _myPublicKey;
  String? _myHandle;
  SendRawFn? _sendRaw;          // WebSocket send function
  ResolveHandleFn? _resolveHandle;

  // ------- WebRTC -------
  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  // ------- Call state -------
  CallState _state = CallState.idle;
  String? _callId;
  CallType _callType = CallType.voice;
  CallDirection _direction = CallDirection.outgoing;
  String? _remotePublicKey;
  String? _remoteHandle;
  DateTime? _startedAt;
  DateTime? _connectedAt;
  Duration _duration = Duration.zero;
  CallEndReason? _endReason;

  // ------- Controls -------
  bool _audioMuted = false;
  bool _videoEnabled = true;
  bool _speakerOn = false;

  // ------- Buffering -------
  final List<RTCIceCandidate> _pendingCandidates = [];
  String? _pendingSdp;
  String? _pendingSdpType;

  // ------- Timers -------
  Timer? _ringTimer;
  Timer? _durationTimer;
  Timer? _ringtoneTimer;
  static const _ringTimeout = Duration(seconds: 30);

  // ------- Ringtones -------


  // ------- ICE config cache -------
  _IceConfig? _iceConfig;

  // ------- Streams -------
  final _stateController = StreamController<CallInfo>.broadcast();
  final _remoteStreamController = StreamController<MediaStream?>.broadcast();

  // ------- Renderers (initialize in UI) -------
  RTCVideoRenderer? localRenderer;
  RTCVideoRenderer? remoteRenderer;

  // =======================================
  // PUBLIC API
  // =======================================

  Stream<CallInfo> get callStream => _stateController.stream;
  Stream<MediaStream?> get remoteVideoStream => _remoteStreamController.stream;

  CallState get state => _state;
  CallInfo get currentCall => _buildCallInfo();
  bool get hasActiveCall =>
      _state != CallState.idle &&
      _state != CallState.ended &&
      _state != CallState.failed;

  MediaStream? get localStream => _localStream;
  MediaStream? get remoteStream => _remoteStream;

  /// Initialize the service with dependencies
  Future<void> initialize({
    required String publicKey,
    String? handle,
    required SendRawFn sendRaw,
    String? baseUrl,
    ResolveHandleFn? resolveHandle,
  }) async {
    _myPublicKey = publicKey;
    _myHandle = handle;
    _sendRaw = sendRaw;
    _resolveHandle = resolveHandle;
    if (baseUrl != null) _baseUrl = baseUrl;

    localRenderer = RTCVideoRenderer();
    remoteRenderer = RTCVideoRenderer();
    await localRenderer!.initialize();
    await remoteRenderer!.initialize();

    debugPrint('📞 CallService initialized (pk: ${publicKey.substring(0, 8)}...)');
    
    // Initialize CallKit integration
    await _initializeCallKit();
  }

  Future<void> _initializeCallKit() async {
    final callKit = CallKitService();
    await callKit.initialize();

    // Register VoIP token
    final deviceId = await _getDeviceId();
    final packageInfo = await PackageInfo.fromPlatform();
    
    if (_myPublicKey != null && deviceId != null) {
      await callKit.registerWithServer(
        serverUrl: _baseUrl,
        publicKey: _myPublicKey!,
        deviceId: deviceId,
        appVersion: packageInfo.version,
      );
    }

    // Callbacks
    callKit.onCallAccepted = (data) {
      debugPrint('📞 CallKit: Accepted call ${data['callId']}');
      final callId = data['callId'] as String;
      final callerPk = data['callerPublicKey'] as String;
      // If we are not already in a call, handle it as incoming answer?
      // Actually, if we accepted an INCOMING call, we need to answer it.
      // But CallKit UI usually appears for incoming calls.
      // If the user taps accept on CallKit UI:
      // We should trigger answer logic.
      if (_state == CallState.incomingRinging && _callId == callId) {
        acceptCall(); // This will answer
      } else {
        // App was likely in background/killed. We need to set state and answer.
        // TODO: Handle app wake from background specifically if needed
        // For now, assume state is synced via WebSocket or push payload
      }
    };

    callKit.onCallDeclined = (data) {
      debugPrint('📞 CallKit: Declined call ${data['callId']}');
      final callId = data['callId'] as String;
      final callerPk = data['callerPublicKey'] as String?;
      
      // Send rejection
      if (callerPk != null) {
         _sendRaw?.call(jsonEncode({
          'type': 'call_reject',
          'callId': callId,
          'targetPublicKey': callerPk,
        }));
      }
      
      endCall(reason: CallEndReason.rejected);
    };

    callKit.onCallEnded = (data) {
      debugPrint('📞 CallKit: Ended call ${data['callId']}');
      endCall(reason: CallEndReason.normal);
    };
  }

  Future<String?> _getDeviceId() async {
    final deviceInfo = DeviceInfoPlugin();
    if (Platform.isIOS) {
      final iosInfo = await deviceInfo.iosInfo;
      return iosInfo.identifierForVendor;
    } else if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      return androidInfo.id;
    }
    return null;
  }

  /// Update the WebSocket send function (after reconnect)
  void setSendRaw(SendRawFn fn) => _sendRaw = fn;

  // =======================================
  // OUTGOING CALL
  // =======================================

  /// Start a voice or video call to a remote user
  Future<CallInfo?> startCall({
    required String remotePublicKey,
    String? remoteHandle,
    CallType type = CallType.voice,
  }) async {
    if (hasActiveCall) {
      debugPrint('📞 Cannot start call: already active');
      return null;
    }

    _callId = _uuid.v4();
    _callType = type;
    _direction = CallDirection.outgoing;
    _remotePublicKey = remotePublicKey;
    _remoteHandle = remoteHandle;
    _startedAt = DateTime.now();
    _connectedAt = null;
    _duration = Duration.zero;
    _endReason = null;
    _audioMuted = false;
    _videoEnabled = type == CallType.video;
    _speakerOn = type == CallType.video;

    _setState(CallState.initiating);

    try {
      // 1. Fetch ICE config (STUN/TURN)
      await _ensureIceConfig();

      // 2. Capture local media
      _localStream = await _getUserMedia();
      localRenderer?.srcObject = _localStream;

      // 3. Create peer connection
      await _createPeerConnection();

      // 4. Add local tracks
      for (final track in _localStream!.getTracks()) {
        await _pc!.addTrack(track, _localStream!);
      }

      // 5. Create SDP offer
      final offer = await _pc!.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': type == CallType.video,
      });
      await _pc!.setLocalDescription(offer);

      // 6. Send offer to callee
      _sendSignal('call_offer', {
        'callId': _callId,
        'callType': type.name,
        'sdp': offer.sdp,
        'sdpType': offer.type,
        'fromHandle': _myHandle,
        'fromPublicKey': _myPublicKey,
      });

      _setState(CallState.ringing);

      // 7. Ring timeout
      _ringTimer = Timer(_ringTimeout, () {
        if (_state == CallState.ringing) {
          debugPrint('📞 Ring timeout');
          endCall(reason: CallEndReason.timeout);
        }
      });

      return _buildCallInfo();
    } catch (e) {
      debugPrint('📞 startCall error: $e');
      _setState(CallState.failed);
      await _cleanup();
      return null;
    }
  }

  // =======================================
  // INCOMING CALL
  // =======================================

  /// Handle an incoming call offer from WebSocket
  Future<void> handleCallOffer(Map<String, dynamic> signal) async {
    final callId = signal['callId'] as String?;
    final fromPk = signal['fromPublicKey'] as String?;
    final fromHandle = signal['fromHandle'] as String?;
    final sdp = signal['sdp'] as String?;
    final sdpType = signal['sdpType'] as String? ?? 'offer';
    final callTypeStr = signal['callType'] as String? ?? 'voice';

    if (callId == null || fromPk == null || sdp == null) {
      debugPrint('📞 Invalid call_offer: missing fields');
      return;
    }

    // Already in a call → busy
    if (hasActiveCall) {
      _sendSignal('call_busy', {'callId': callId}, targetPk: fromPk);
      return;
    }

    _callId = callId;
    _callType = callTypeStr == 'video' ? CallType.video : CallType.voice;
    _direction = CallDirection.incoming;
    _remotePublicKey = fromPk;
    _remoteHandle = fromHandle;
    _startedAt = DateTime.now();
    _connectedAt = null;
    _duration = Duration.zero;
    _endReason = null;
    _audioMuted = false;
    _videoEnabled = _callType == CallType.video;
    _speakerOn = _callType == CallType.video;

    // Buffer offer SDP
    _pendingSdp = sdp;
    _pendingSdpType = sdpType;
    _pendingCandidates.clear();

    _setState(CallState.incomingRinging);

    // Notify caller we're ringing
    _sendSignal('call_ringing', {'callId': callId});

    // Ring timeout
    _ringTimer = Timer(_ringTimeout, () {
      if (_state == CallState.incomingRinging) {
        debugPrint('📞 Incoming ring timeout');
        endCall(reason: CallEndReason.timeout);
      }
    });
  }

  /// Accept the incoming call (user tapped Accept)
  Future<void> acceptCall() async {
    if (_state != CallState.incomingRinging || _pendingSdp == null) {
      debugPrint('📞 Cannot accept: wrong state or no pending SDP');
      return;
    }

    _ringTimer?.cancel();
    _setState(CallState.connecting);

    try {
      await _ensureIceConfig();

      _localStream = await _getUserMedia();
      localRenderer?.srcObject = _localStream;

      await _createPeerConnection();

      for (final track in _localStream!.getTracks()) {
        await _pc!.addTrack(track, _localStream!);
      }

      // Set the caller's offer as remote description
      await _pc!.setRemoteDescription(
        RTCSessionDescription(_pendingSdp!, _pendingSdpType!),
      );

      // Apply buffered ICE candidates
      for (final c in _pendingCandidates) {
        await _pc!.addCandidate(c);
      }
      _pendingCandidates.clear();

      // Create and send answer
      final answer = await _pc!.createAnswer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': _callType == CallType.video,
      });
      await _pc!.setLocalDescription(answer);

      _sendSignal('call_answer', {
        'callId': _callId,
        'sdp': answer.sdp,
        'sdpType': answer.type,
      });

      _pendingSdp = null;
      _pendingSdpType = null;
    } catch (e) {
      debugPrint('📞 acceptCall error: $e');
      _setState(CallState.failed);
      await _cleanup();
    }
  }

  /// Reject the incoming call
  void rejectCall() {
    if (_state != CallState.incomingRinging) return;
    _sendSignal('call_reject', {'callId': _callId});
    _endReason = CallEndReason.rejected;
    _setState(CallState.ended);
    _cleanup();
  }

  // =======================================
  // SIGNAL ROUTER
  // =======================================

  /// Route an incoming WebSocket call signal to the right handler
  void handleCallSignal(String type, Map<String, dynamic> data) {
    // Extract payload — signals may nest data under 'payload' key
    final payload = data['payload'] as Map<String, dynamic>? ?? data;
    final callId = payload['callId'] as String? ?? data['callId'] as String?;

    // Ignore signals for a different call
    if (_callId != null && callId != null && callId != _callId) {
      debugPrint('📞 Ignoring signal for different call: $callId');
      return;
    }

    switch (type) {
      case 'call_offer':
        handleCallOffer(payload);
      case 'call_answer':
        _onAnswer(payload);
      case 'call_ice':
        _onIceCandidate(payload);
      case 'call_hangup':
        _onRemoteHangup();
      case 'call_busy':
        _onBusy();
      case 'call_reject':
        _onReject();
      case 'call_ringing':
        _onRinging();
      default:
        debugPrint('📞 Unknown call signal: $type');
    }
  }

  // ---- Signal handlers ----

  Future<void> _onAnswer(Map<String, dynamic> s) async {
    if (_state != CallState.ringing) return;
    _ringTimer?.cancel();
    _setState(CallState.connecting);

    try {
      await _pc!.setRemoteDescription(
        RTCSessionDescription(
          s['sdp'] as String,
          s['sdpType'] as String? ?? 'answer',
        ),
      );
      for (final c in _pendingCandidates) {
        await _pc!.addCandidate(c);
      }
      _pendingCandidates.clear();
    } catch (e) {
      debugPrint('📞 _onAnswer error: $e');
      _setState(CallState.failed);
      await _cleanup();
    }
  }

  Future<void> _onIceCandidate(Map<String, dynamic> s) async {
    final cMap = s['candidate'] as Map<String, dynamic>?;
    if (cMap == null) return;

    final candidate = RTCIceCandidate(
      cMap['candidate'] as String?,
      cMap['sdpMid'] as String?,
      cMap['sdpMLineIndex'] as int?,
    );

    if (_pc == null) {
      _pendingCandidates.add(candidate);
      return;
    }

    try {
      final remoteDesc = await _pc!.getRemoteDescription();
      if (remoteDesc == null) {
        _pendingCandidates.add(candidate);
        return;
      }
      await _pc!.addCandidate(candidate);
    } catch (e) {
      debugPrint('📞 ICE candidate error: $e');
      _pendingCandidates.add(candidate);
    }
  }

  void _onRemoteHangup() {
    debugPrint('📞 Remote hung up');
    _endReason = CallEndReason.normal;
    _setState(CallState.ended);
    _cleanup();
  }

  void _onBusy() {
    debugPrint('📞 Remote is busy');
    _ringTimer?.cancel();
    _endReason = CallEndReason.busy;
    _setState(CallState.ended);
    _cleanup();
  }

  void _onReject() {
    debugPrint('📞 Remote rejected');
    _ringTimer?.cancel();
    _endReason = CallEndReason.rejected;
    _setState(CallState.ended);
    _cleanup();
  }

  void _onRinging() {
    debugPrint('📞 Remote device ringing');
    // UI can play ringback tone
  }

  // =======================================
  // CALL CONTROLS
  // =======================================

  /// End the current call
  Future<void> endCall({CallEndReason reason = CallEndReason.normal}) async {
    if (!hasActiveCall) return;
    _ringTimer?.cancel();
    _durationTimer?.cancel();
    _endReason = reason;

    _sendSignal('call_hangup', {
      'callId': _callId,
      'reason': reason.name,
    });

    _setState(CallState.ended);
    await _cleanup();
  }

  /// Toggle microphone mute
  void toggleMute() {
    _audioMuted = !_audioMuted;
    _localStream?.getAudioTracks().forEach((t) => t.enabled = !_audioMuted);
    _emit();
  }

  /// Toggle camera on/off
  void toggleVideo() {
    _videoEnabled = !_videoEnabled;
    _localStream?.getVideoTracks().forEach((t) => t.enabled = _videoEnabled);
    _emit();
  }

  /// Toggle speaker/earpiece
  void toggleSpeaker() {
    _speakerOn = !_speakerOn;
    Helper.setSpeakerphoneOn(_speakerOn);
    _emit();
  }

  /// Switch front/back camera
  Future<void> switchCamera() async {
    final vt = _localStream?.getVideoTracks().firstOrNull;
    if (vt != null) await Helper.switchCamera(vt);
  }

  // =======================================
  // WEBRTC PEER CONNECTION
  // =======================================

  Future<void> _createPeerConnection() async {
    final config = _iceConfig?.toWebRTC() ?? {
      'iceServers': [
        {'urls': ['stun:stun.l.google.com:19302']},
      ],
      'sdpSemantics': 'unified-plan',
    };

    _pc = await createPeerConnection(config);

    // Trickle ICE → send candidates to remote
    _pc!.onIceCandidate = (RTCIceCandidate c) {
      _sendSignal('call_ice', {
        'callId': _callId,
        'candidate': {
          'candidate': c.candidate,
          'sdpMid': c.sdpMid,
          'sdpMLineIndex': c.sdpMLineIndex,
        },
      });
    };

    // Connection state tracking
    _pc!.onConnectionState = (RTCPeerConnectionState s) {
      debugPrint('📞 PeerConnection: $s');
      switch (s) {
        case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          _connectedAt = DateTime.now();
          _setState(CallState.connected);
          _startDurationTimer();
        case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          _endReason = CallEndReason.failed;
          _setState(CallState.failed);
          _cleanup();
        case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
          if (_state != CallState.ended && _state != CallState.failed) {
            _endReason = CallEndReason.normal;
            _setState(CallState.ended);
            _cleanup();
          }
        default:
          break;
      }
    };

    // Remote track received
    _pc!.onTrack = (RTCTrackEvent event) {
      debugPrint('📞 Remote track: ${event.track.kind}');
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams[0];
        remoteRenderer?.srcObject = _remoteStream;
        _remoteStreamController.add(_remoteStream);
      }
    };

    // Legacy callback (some platforms)
    _pc!.onAddStream = (MediaStream stream) {
      _remoteStream = stream;
      remoteRenderer?.srcObject = stream;
      _remoteStreamController.add(stream);
    };
  }

  // =======================================
  // MEDIA
  // =======================================

  Future<MediaStream> _getUserMedia() async {
    return await navigator.mediaDevices.getUserMedia({
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': _callType == CallType.video
          ? {
              'facingMode': 'user',
              'width': {'ideal': 1280},
              'height': {'ideal': 720},
              'frameRate': {'ideal': 30},
            }
          : false,
    });
  }

  // =======================================
  // ICE CONFIG
  // =======================================

  Future<void> _ensureIceConfig() async {
    if (_iceConfig != null && !_iceConfig!.isExpired) return;

    try {
      final headers = <String, String>{
        'Content-Type': 'application/json',
      };
      if (_myPublicKey != null) {
        headers['X-GNS-PublicKey'] = _myPublicKey!;
      }

      final res = await http.post(
        Uri.parse('$_baseUrl/calls/turn-credentials'),
        headers: headers,
      );

      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        if (json['success'] == true) {
          final data = json['data'];
          _iceConfig = _IceConfig(
            iceServers: List<Map<String, dynamic>>.from(
              (data['iceServers'] as List).map((e) => Map<String, dynamic>.from(e)),
            ),
            ttl: data['ttl'] as int,
            fetchedAt: DateTime.now(),
          );
          debugPrint('📞 ICE config: ${_iceConfig!.iceServers.length} server groups');
          return;
        }
      }
      throw Exception('HTTP ${res.statusCode}');
    } catch (e) {
      debugPrint('📞 TURN credential fetch failed, STUN only: $e');
      _iceConfig = _IceConfig(
        iceServers: [
          {'urls': ['stun:stun.l.google.com:19302', 'stun:stun1.l.google.com:19302']},
        ],
        ttl: 86400,
        fetchedAt: DateTime.now(),
      );
    }
  }

  // =======================================
  // SIGNALING
  // =======================================

  void _sendSignal(String type, Map<String, dynamic> payload, {String? targetPk}) {
    final target = targetPk ?? _remotePublicKey;
    if (target == null || _sendRaw == null) return;

    _sendRaw!(jsonEncode({
      'type': type,
      'targetPublicKey': target,
      'callId': payload['callId'] ?? _callId,
      'payload': payload,
    }));
  }

  // =======================================
  // STATE
  // =======================================

  void _setState(CallState s) {
    if (_state == s) return;
    debugPrint('📞 ${_state.name} → ${s.name}');
    _state = s;

    // Ringtone control
    switch (s) {
      case CallState.ringing:
        _playRingback();           // Caller hears ringback
      case CallState.incomingRinging:
        _playIncomingRing();       // Receiver hears ring
      case CallState.connected:
      case CallState.ended:
      case CallState.failed:
        _stopAllRingtones();       // Stop all on connect/end
      default:
        break;
    }

    _emit();
  }

  void _emit() {
    final info = _buildCallInfo();
    _stateController.add(info);
    notifyListeners();
  }

  CallInfo _buildCallInfo() => CallInfo(
    callId: _callId ?? '',
    state: _state,
    type: _callType,
    direction: _direction,
    remotePublicKey: _remotePublicKey ?? '',
    remoteHandle: _remoteHandle,
    startedAt: _startedAt ?? DateTime.now(),
    connectedAt: _connectedAt,
    duration: _duration,
    isAudioMuted: _audioMuted,
    isVideoEnabled: _videoEnabled,
    isSpeakerOn: _speakerOn,
    endReason: _endReason,
  );

  void _startDurationTimer() {
    _duration = Duration.zero;
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _duration += const Duration(seconds: 1);
      _emit();
    });
  }



  Future<void> _playIncomingRing() async {
    final player = FlutterRingtonePlayer();
    player.play(android: AndroidSounds.ringtone, ios: IosSounds.electronic, volume: 1.0);
    _ringtoneTimer?.cancel();
    _ringtoneTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      player.play(android: AndroidSounds.ringtone, ios: IosSounds.electronic, volume: 1.0);
    });
  }

  Future<void> _playRingback() async {
    final player = FlutterRingtonePlayer();
    player.play(android: AndroidSounds.ringtone, ios: IosSounds.electronic, volume: 0.5);
    _ringtoneTimer?.cancel();
    _ringtoneTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      player.play(android: AndroidSounds.ringtone, ios: IosSounds.electronic, volume: 0.5);
    });
  }

  Future<void> _stopAllRingtones() async {
    _ringtoneTimer?.cancel();
    _ringtoneTimer = null;
    FlutterRingtonePlayer().stop();
  }



  // =======================================
  // CLEANUP
  // =======================================

  Future<void> _cleanup() async {
    _ringTimer?.cancel();
    _durationTimer?.cancel();
    await _stopAllRingtones();      // ✅ Stop ringtones

    try { await _pc?.close(); } catch (_) {}
    _pc = null;

    _localStream?.getTracks().forEach((t) => t.stop());
    _localStream = null;
    localRenderer?.srcObject = null;

    _remoteStream = null;
    remoteRenderer?.srcObject = null;
    _remoteStreamController.add(null);

    _pendingCandidates.clear();
    _pendingSdp = null;
    _pendingSdpType = null;

    // Reset to idle after delay (let UI show "ended")
    Future.delayed(const Duration(seconds: 2), () {
      if (_state == CallState.ended || _state == CallState.failed) {
        _state = CallState.idle;
        _callId = null;
        _remotePublicKey = null;
        _remoteHandle = null;
        _startedAt = null;
        _connectedAt = null;
        _duration = Duration.zero;
        _endReason = null;
        _emit();
      }
    });
  }

  @override
  void dispose() {
    _cleanup();
    localRenderer?.dispose();
    remoteRenderer?.dispose();
    _stateController.close();
    _remoteStreamController.close();
    super.dispose();
  }
}
