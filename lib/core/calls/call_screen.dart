/// GNS Call Screen — Voice & Video Call UI
///
/// Full-screen overlay for active calls:
/// - Voice: avatar, status, duration, mute/speaker/hangup
/// - Video: remote video, PiP local, mute/camera/flip/hangup
/// - Incoming: caller info, accept/reject buttons
///
/// Location: lib/screens/calls/call_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../core/calls/call_service.dart';

class CallScreen extends StatefulWidget {
  /// For outgoing calls: set remotePublicKey + remoteHandle + callType
  /// For incoming calls: CallService already has the state, just show UI
  final String? remotePublicKey;
  final String? remoteHandle;
  final CallType? callType;
  final bool isIncoming;

  const CallScreen({
    super.key,
    this.remotePublicKey,
    this.remoteHandle,
    this.callType,
    this.isIncoming = false,
  });

  /// Show as a full-screen route
  static Future<void> show(
    BuildContext context, {
    String? remotePublicKey,
    String? remoteHandle,
    CallType? callType,
    bool isIncoming = false,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => CallScreen(
          remotePublicKey: remotePublicKey,
          remoteHandle: remoteHandle,
          callType: callType,
          isIncoming: isIncoming,
        ),
      ),
    );
  }

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final _callService = CallService();
  StreamSubscription<CallInfo>? _sub;
  CallInfo? _callInfo;
  bool _showControls = true;

  @override
  void initState() {
    super.initState();

    // Subscribe to call state
    _sub = _callService.callStream.listen((info) {
      if (mounted) {
        setState(() => _callInfo = info);

        // Auto-dismiss when call ends
        if (info.isEnded) {
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) Navigator.of(context).pop();
          });
        }
      }
    });

    // Start outgoing call if not incoming
    if (!widget.isIncoming && widget.remotePublicKey != null) {
      _callService.startCall(
        remotePublicKey: widget.remotePublicKey!,
        remoteHandle: widget.remoteHandle,
        type: widget.callType ?? CallType.voice,
      );
    }

    _callInfo = _callService.currentCall;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final info = _callInfo ?? _callService.currentCall;
    final isVideo = info.type == CallType.video;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () {
          if (isVideo && info.isActive) {
            setState(() => _showControls = !_showControls);
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Background
            if (isVideo && info.isActive)
              _buildRemoteVideo()
            else
              _buildVoiceBackground(info),

            // Local video PiP (video calls)
            if (isVideo && info.isActive) _buildLocalVideoPiP(),

            // Top bar (handle, status)
            SafeArea(
              child: AnimatedOpacity(
                opacity: _showControls ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: _buildTopBar(info),
              ),
            ),

            // Bottom controls
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                child: AnimatedOpacity(
                  opacity: _showControls ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: info.state == CallState.incomingRinging
                      ? _buildIncomingControls(info)
                      : _buildActiveControls(info),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ======= Voice call background =======

  Widget _buildVoiceBackground(CallInfo info) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1a1a2e), Color(0xFF16213e), Color(0xFF0f3460)],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Avatar circle
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.1),
              border: Border.all(
                color: info.isActive
                    ? Colors.green.withOpacity(0.6)
                    : Colors.white.withOpacity(0.3),
                width: 3,
              ),
            ),
            child: Center(
              child: Text(
                _avatarInitials(info),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 40,
                  fontWeight: FontWeight.w300,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Handle
          Text(
            info.remoteHandle ?? _truncatedKey(info.remotePublicKey),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),

          // Status / duration
          Text(
            info.stateLabel,
            style: TextStyle(
              color: info.isActive
                  ? Colors.green.shade300
                  : Colors.white70,
              fontSize: 16,
            ),
          ),

          // Animated dots for ringing
          if (info.isRinging) _buildRingingIndicator(),
        ],
      ),
    );
  }

  Widget _buildRingingIndicator() {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: SizedBox(
        width: 60,
        height: 20,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(3, (i) => _PulsingDot(delay: i * 200)),
        ),
      ),
    );
  }

  // ======= Video views =======

  Widget _buildRemoteVideo() {
    if (_callService.remoteRenderer == null) {
      return const Center(
        child: Text(
          'Connecting video...',
          style: TextStyle(color: Colors.white54),
        ),
      );
    }
    return RTCVideoView(
      _callService.remoteRenderer!,
      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
    );
  }

  Widget _buildLocalVideoPiP() {
    if (_callService.localRenderer == null) return const SizedBox.shrink();

    return Positioned(
      top: MediaQuery.of(context).padding.top + 60,
      right: 16,
      child: GestureDetector(
        onTap: () => _callService.switchCamera(),
        child: Container(
          width: 100,
          height: 140,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white30, width: 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: RTCVideoView(
            _callService.localRenderer!,
            mirror: true,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          ),
        ),
      ),
    );
  }

  // ======= Top bar =======

  Widget _buildTopBar(CallInfo info) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // Back / minimize
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 28),
          ),
          const Spacer(),

          // Encryption indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock, color: Colors.green, size: 14),
                SizedBox(width: 4),
                Text(
                  'E2E Encrypted',
                  style: TextStyle(color: Colors.green, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ======= Incoming call controls =======

  Widget _buildIncomingControls(CallInfo info) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            info.type == CallType.video ? 'Incoming Video Call' : 'Incoming Voice Call',
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Reject
              _CallButton(
                icon: Icons.call_end,
                label: 'Decline',
                color: Colors.red,
                onPressed: () {
                  _callService.rejectCall();
                  Navigator.of(context).pop();
                },
              ),
              // Accept
              _CallButton(
                icon: info.type == CallType.video
                    ? Icons.videocam
                    : Icons.call,
                label: 'Accept',
                color: Colors.green,
                onPressed: () => _callService.acceptCall(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ======= Active call controls =======

  Widget _buildActiveControls(CallInfo info) {
    final isVideo = info.type == CallType.video;

    return Padding(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Control row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Mute
              _CallButton(
                icon: info.isAudioMuted ? Icons.mic_off : Icons.mic,
                label: info.isAudioMuted ? 'Unmute' : 'Mute',
                color: info.isAudioMuted ? Colors.red : Colors.white24,
                onPressed: () => _callService.toggleMute(),
                small: true,
              ),

              // Speaker (voice) or Camera (video)
              if (isVideo)
                _CallButton(
                  icon: info.isVideoEnabled
                      ? Icons.videocam
                      : Icons.videocam_off,
                  label: info.isVideoEnabled ? 'Cam On' : 'Cam Off',
                  color: info.isVideoEnabled ? Colors.white24 : Colors.red,
                  onPressed: () => _callService.toggleVideo(),
                  small: true,
                )
              else
                _CallButton(
                  icon: info.isSpeakerOn ? Icons.volume_up : Icons.volume_down,
                  label: info.isSpeakerOn ? 'Speaker' : 'Earpiece',
                  color: info.isSpeakerOn ? Colors.blue : Colors.white24,
                  onPressed: () => _callService.toggleSpeaker(),
                  small: true,
                ),

              // Flip camera (video only)
              if (isVideo)
                _CallButton(
                  icon: Icons.flip_camera_ios,
                  label: 'Flip',
                  color: Colors.white24,
                  onPressed: () => _callService.switchCamera(),
                  small: true,
                )
              else
                _CallButton(
                  icon: Icons.volume_up,
                  label: info.isSpeakerOn ? 'Speaker' : 'Earpiece',
                  color: info.isSpeakerOn ? Colors.blue : Colors.white24,
                  onPressed: () => _callService.toggleSpeaker(),
                  small: true,
                ),
            ],
          ),

          const SizedBox(height: 24),

          // Hangup
          _CallButton(
            icon: Icons.call_end,
            label: info.isEnded ? 'Call Ended' : 'End',
            color: Colors.red,
            onPressed: info.isEnded
                ? null
                : () async {
                    await _callService.endCall();
                  },
          ),
        ],
      ),
    );
  }

  // ======= Helpers =======

  String _avatarInitials(CallInfo info) {
    final h = info.remoteHandle;
    if (h != null && h.isNotEmpty) {
      final clean = h.replaceAll('@', '');
      return clean.substring(0, clean.length.clamp(0, 2)).toUpperCase();
    }
    return info.remotePublicKey.isNotEmpty
        ? info.remotePublicKey.substring(0, 2).toUpperCase()
        : '?';
  }

  String _truncatedKey(String pk) {
    if (pk.length > 12) return '${pk.substring(0, 6)}...${pk.substring(pk.length - 6)}';
    return pk;
  }
}

// ======= Reusable call button =======

class _CallButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onPressed;
  final bool small;

  const _CallButton({
    required this.icon,
    required this.label,
    required this.color,
    this.onPressed,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    final size = small ? 52.0 : 64.0;
    final iconSize = small ? 24.0 : 30.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onPressed,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: onPressed != null ? color : color.withOpacity(0.3),
            ),
            child: Icon(icon, color: Colors.white, size: iconSize),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
      ],
    );
  }
}

// ======= Pulsing dot animation =======

class _PulsingDot extends StatefulWidget {
  final int delay;
  const _PulsingDot({required this.delay});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _anim = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _ctrl.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: Container(
        width: 8,
        height: 8,
        margin: const EdgeInsets.symmetric(horizontal: 3),
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
        ),
      ),
    );
  }
}
