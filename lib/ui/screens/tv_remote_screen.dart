/// TV Remote Screen - Full Screen TV Controller
/// 
/// A beautiful full-screen remote control for Samsung TVs.
/// Opens as a modal when tapping a TV device card.
/// 
/// FIXES:
/// - Fixed "RIGHT OVERFLOWED BY 27 PIXELS" on d-pad by using Flexible widgets
/// - Added mounted check to prevent setState after dispose
/// 
/// Location: lib/ui/screens/tv_remote_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/home/home_service.dart';
import '../../core/theme/theme_service.dart';

class TvRemoteScreen extends StatefulWidget {
  final HomeDevice device;
  final String deviceId;

  const TvRemoteScreen({
    super.key,
    required this.device,
    required this.deviceId,
  });

  /// Show as a full-screen modal
  static Future<void> show(BuildContext context, HomeDevice device) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => TvRemoteScreen(
        device: device,
        deviceId: device.id,
      ),
    );
  }

  @override
  State<TvRemoteScreen> createState() => _TvRemoteScreenState();
}

class _TvRemoteScreenState extends State<TvRemoteScreen> {
  Timer? _repeatTimer;
  late HomeDevice _device;
  StreamSubscription? _devicesSub;

  @override
  void initState() {
    super.initState();
    _device = widget.device;
    _devicesSub = homeService.devicesStream.listen((devices) {
      final updated = devices.where((d) => d.id == widget.deviceId).firstOrNull;
      if (updated != null && mounted) {
        setState(() => _device = updated);
      }
    });
  }

  @override
  void dispose() {
    _repeatTimer?.cancel();
    _devicesSub?.cancel();
    super.dispose();
  }

  Future<void> _executeCommand(String action, [dynamic value]) async {
    HapticFeedback.mediumImpact();
    await homeService.executeCommand(
      deviceId: widget.deviceId,
      action: action,
      value: value,
    );
  }

  void _startRepeat(String action, [dynamic value]) {
    HapticFeedback.heavyImpact();
    _executeCommand(action, value);
    _repeatTimer = Timer.periodic(const Duration(milliseconds: 150), (_) {
      HapticFeedback.selectionClick();
      _executeCommand(action, value);
    });
  }

  void _stopRepeat() {
    _repeatTimer?.cancel();
    _repeatTimer = null;
  }

  @override
  Widget build(BuildContext context) {
    final state = _device.status.state;
    final volume = state['volume'] ?? 0;
    final muted = state['muted'] ?? false;
    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      height: screenHeight * 0.92,
      decoration: BoxDecoration(
        color: AppTheme.background(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.textMuted(context),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child: Text('📺', style: TextStyle(fontSize: 22)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _device.name,
                        style: TextStyle(
                          color: AppTheme.textPrimary(context),
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${_device.brand} • ${_device.isPoweredOn ? "On" : "Off"}',
                        style: TextStyle(
                          color: AppTheme.textMuted(context),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                // Power button
                _buildPowerButton(),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Main content - scrollable
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  // Top row: Home, Back, Menu, Source
                  _buildTopControls(),

                  const SizedBox(height: 24),

                  // Main control area: Volume | Nav Pad | Channel
                  _buildMainControls(volume, muted),

                  const SizedBox(height: 24),

                  // Apps
                  _buildAppsSection(),

                  const SizedBox(height: 24),

                  // Media controls
                  _buildMediaControls(),

                  const SizedBox(height: 24),

                  // Number pad (collapsible)
                  _buildNumberPad(),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPowerButton() {
    final isOn = _device.isPoweredOn;
    return GestureDetector(
      onTap: () => _executeCommand('power', isOn ? 'off' : 'on'),
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: isOn ? AppTheme.error : AppTheme.surfaceLight(context),
          borderRadius: BorderRadius.circular(14),
          boxShadow: isOn
              ? [BoxShadow(color: AppTheme.error.withValues(alpha: 0.4), blurRadius: 12)]
              : null,
        ),
        child: Icon(
          Icons.power_settings_new,
          color: isOn ? Colors.white : AppTheme.textMuted(context),
          size: 26,
        ),
      ),
    );
  }

  Widget _buildTopControls() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border(context)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildTopButton(Icons.home_rounded, 'Home', () => _executeCommand('key', 'home')),
          _buildTopButton(Icons.arrow_back_rounded, 'Back', () => _executeCommand('key', 'back')),
          _buildTopButton(Icons.menu_rounded, 'Menu', () => _executeCommand('key', 'menu')),
          _buildTopButton(Icons.input_rounded, 'Source', () => _executeCommand('key', 'source')),
          _buildTopButton(Icons.settings_rounded, 'Settings', () => _executeCommand('key', 'tools')),
        ],
      ),
    );
  }

  Widget _buildTopButton(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        onTap();
      },
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppTheme.surfaceLight(context),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppTheme.textSecondary(context), size: 24),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(color: AppTheme.textMuted(context), fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildMainControls(int volume, bool muted) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Volume controls (left) - fixed width
        SizedBox(
          width: 80,
          child: _buildVolumeControl(volume, muted),
        ),

        // Navigation pad (center) - takes remaining space and centers content
        Expanded(
          child: Center(
            child: _buildNavigationPad(),
          ),
        ),

        // Channel controls (right) - fixed width
        SizedBox(
          width: 80,
          child: _buildChannelControl(),
        ),
      ],
    );
  }

  Widget _buildVolumeControl(int volume, bool muted) {
    return Column(
      children: [
        Text(
          'VOLUME',
          style: TextStyle(
            color: AppTheme.textMuted(context),
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        _buildLongPressButton(
          icon: Icons.add_rounded,
          onTap: () => _executeCommand('volume_up'),
          onLongPressStart: () => _startRepeat('volume_up'),
          onLongPressEnd: _stopRepeat,
        ),
        const SizedBox(height: 8),
        Container(
          width: 56,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: AppTheme.surface(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border(context)),
          ),
          child: Center(
            child: Text(
              muted ? '🔇' : '$volume',
              style: TextStyle(
                color: muted ? AppTheme.warning : AppTheme.textPrimary(context),
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        _buildLongPressButton(
          icon: Icons.remove_rounded,
          onTap: () => _executeCommand('volume_down'),
          onLongPressStart: () => _startRepeat('volume_down'),
          onLongPressEnd: _stopRepeat,
        ),
        const SizedBox(height: 12),
        _buildSmallButton(
          icon: muted ? Icons.volume_off_rounded : Icons.volume_mute_rounded,
          label: 'Mute',
          isActive: muted,
          onTap: () => _executeCommand('mute'),
        ),
      ],
    );
  }

  /// Navigation pad - fixed size, will be centered by parent
  Widget _buildNavigationPad() {
    const double arrowSize = 44.0;
    const double okSize = 56.0;
    const double gap = 4.0;
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border(context)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Up arrow
          _buildNavArrowSized(
            Icons.keyboard_arrow_up_rounded,
            () => _executeCommand('key', 'up'),
            arrowSize,
          ),
          const SizedBox(height: gap),
          // Left - OK - Right row
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildNavArrowSized(
                Icons.keyboard_arrow_left_rounded,
                () => _executeCommand('key', 'left'),
                arrowSize,
              ),
              const SizedBox(width: gap),
              _buildOkButtonSized(okSize),
              const SizedBox(width: gap),
              _buildNavArrowSized(
                Icons.keyboard_arrow_right_rounded,
                () => _executeCommand('key', 'right'),
                arrowSize,
              ),
            ],
          ),
          const SizedBox(height: gap),
          // Down arrow
          _buildNavArrowSized(
            Icons.keyboard_arrow_down_rounded,
            () => _executeCommand('key', 'down'),
            arrowSize,
          ),
        ],
      ),
    );
  }

  Widget _buildNavArrowSized(IconData icon, VoidCallback onTap, double size) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        onTap();
      },
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppTheme.surfaceLight(context),
          borderRadius: BorderRadius.circular(size / 4),
        ),
        child: Icon(icon, color: AppTheme.textSecondary(context), size: size * 0.55),
      ),
    );
  }

  Widget _buildOkButtonSized(double size) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.heavyImpact();
        _executeCommand('key', 'enter');
      },
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [AppTheme.primary, AppTheme.primary.withValues(alpha: 0.8)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppTheme.primary.withValues(alpha: 0.4),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Center(
          child: Text(
            'OK',
            style: TextStyle(
              color: Colors.white,
              fontSize: size * 0.28,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChannelControl() {
    return Column(
      children: [
        Text(
          'CHANNEL',
          style: TextStyle(
            color: AppTheme.textMuted(context),
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        _buildLongPressButton(
          icon: Icons.keyboard_arrow_up_rounded,
          onTap: () => _executeCommand('key', 'channel_up'),
          onLongPressStart: () => _startRepeat('key', 'channel_up'),
          onLongPressEnd: _stopRepeat,
        ),
        const SizedBox(height: 8),
        Container(
          width: 56,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: AppTheme.surface(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border(context)),
          ),
          child: Center(
            child: Text(
              'CH',
              style: TextStyle(
                color: AppTheme.textSecondary(context),
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        _buildLongPressButton(
          icon: Icons.keyboard_arrow_down_rounded,
          onTap: () => _executeCommand('key', 'channel_down'),
          onLongPressStart: () => _startRepeat('key', 'channel_down'),
          onLongPressEnd: _stopRepeat,
        ),
        const SizedBox(height: 12),
        _buildSmallButton(
          icon: Icons.info_outline_rounded,
          label: 'Info',
          onTap: () => _executeCommand('key', 'info'),
        ),
      ],
    );
  }

  Widget _buildLongPressButton({
    required IconData icon,
    required VoidCallback onTap,
    required VoidCallback onLongPressStart,
    required VoidCallback onLongPressEnd,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        onTap();
      },
      onLongPressStart: (_) => onLongPressStart(),
      onLongPressEnd: (_) => onLongPressEnd(),
      onLongPressCancel: onLongPressEnd,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: AppTheme.surfaceLight(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.border(context)),
        ),
        child: Icon(icon, color: AppTheme.textSecondary(context), size: 28),
      ),
    );
  }

  Widget _buildSmallButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isActive = false,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        onTap();
      },
      child: Column(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isActive ? AppTheme.primary.withValues(alpha: 0.2) : AppTheme.surfaceLight(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isActive ? AppTheme.primary : AppTheme.border(context),
              ),
            ),
            child: Icon(
              icon,
              color: isActive ? AppTheme.primary : AppTheme.textMuted(context),
              size: 20,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(color: AppTheme.textMuted(context), fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _buildAppsSection() {
    final apps = [
      ('Netflix', 'netflix', '🎬', const Color(0xFFE50914)),
      ('YouTube', 'youtube', '▶️', const Color(0xFFFF0000)),
      ('Prime', 'prime', '📦', const Color(0xFF00A8E1)),
      ('Disney+', 'disney', '✨', const Color(0xFF113CCF)),
      ('Spotify', 'spotify', '🎵', const Color(0xFF1DB954)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'APPS',
          style: TextStyle(
            color: AppTheme.textMuted(context),
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: apps.map((app) {
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    _executeCommand('app', app.$2);
                  },
                  child: Container(
                    width: 72,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: app.$4.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: app.$4.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      children: [
                        Text(app.$3, style: const TextStyle(fontSize: 28)),
                        const SizedBox(height: 6),
                        Text(
                          app.$1,
                          style: TextStyle(
                            color: AppTheme.textSecondary(context),
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildMediaControls() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border(context)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildMediaButton(Icons.fast_rewind_rounded, () => _executeCommand('key', 'rewind')),
          _buildMediaButton(Icons.skip_previous_rounded, () => _executeCommand('key', 'stop')),
          _buildMediaButton(Icons.play_arrow_rounded, () => _executeCommand('key', 'play'), isPrimary: true),
          _buildMediaButton(Icons.pause_rounded, () => _executeCommand('key', 'pause'), isPrimary: true),
          _buildMediaButton(Icons.skip_next_rounded, () => _executeCommand('key', 'stop')),
          _buildMediaButton(Icons.fast_forward_rounded, () => _executeCommand('key', 'fastforward')),
        ],
      ),
    );
  }

  Widget _buildMediaButton(IconData icon, VoidCallback onTap, {bool isPrimary = false}) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        onTap();
      },
      child: Container(
        width: isPrimary ? 48 : 40,
        height: isPrimary ? 48 : 40,
        decoration: BoxDecoration(
          color: isPrimary ? AppTheme.primary : AppTheme.surfaceLight(context),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          color: isPrimary ? Colors.white : AppTheme.textSecondary(context),
          size: isPrimary ? 24 : 20,
        ),
      ),
    );
  }

  Widget _buildNumberPad() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'NUMBER PAD',
          style: TextStyle(
            color: AppTheme.textMuted(context),
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 3,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.5,
          children: [
            for (int i = 1; i <= 9; i++)
              _buildNumberButton('$i'),
            _buildNumberButton('⏮', key: 'previous'),
            _buildNumberButton('0'),
            _buildNumberButton('⏭', key: 'next'),
          ],
        ),
      ],
    );
  }

  Widget _buildNumberButton(String label, {String? key}) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        _executeCommand('key', key ?? label);
      },
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surfaceLight(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border(context)),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: AppTheme.textPrimary(context),
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
