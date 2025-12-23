/// Floating Home Button - Quick Smart Home Access
/// 
/// A draggable floating button that provides instant access to smart home controls.
/// Shows a quick control card when tapped.
/// 
/// FIXES:
/// - Added mounted checks to prevent setState after dispose
/// - Ensured no debug highlighting on text
/// - Improved text decoration to prevent selection highlight
/// - Fixed connection by getting userPublicKey from IdentityWallet
/// 
/// Usage: Wrap your app's main content with FloatingHomeButton.wrap()
/// 
/// Location: lib/ui/widgets/floating_home_button.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/home/home_service.dart';
import '../../core/gns/identity_wallet.dart';
import '../../core/theme/theme_service.dart';
import '../screens/tv_remote_screen.dart';

class FloatingHomeButton extends StatefulWidget {
  final Widget child;

  const FloatingHomeButton({
    super.key,
    required this.child,
  });

  /// Wrap a widget with the floating home button
  static Widget wrap(Widget child) {
    return FloatingHomeButton(child: child);
  }

  @override
  State<FloatingHomeButton> createState() => _FloatingHomeButtonState();
}

class _FloatingHomeButtonState extends State<FloatingHomeButton> with SingleTickerProviderStateMixin {
  static const _positionKeyX = 'floating_home_x';
  static const _positionKeyY = 'floating_home_y';
  static const _hubUrlKey = 'gns_home_hub_url';
  final _storage = const FlutterSecureStorage();
  final _wallet = IdentityWallet();

  double _xPosition = 0;
  double _yPosition = 0;
  bool _initialized = false;
  bool _isDragging = false;
  bool _isCardOpen = false;
  bool _isConnected = false;
  bool _isConnecting = false;

  List<HomeDevice> _devices = [];
  StreamSubscription? _devicesSub;
  StreamSubscription? _connectionSub;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _loadPosition();
    _setupSubscriptions();
    _initializeAndConnect();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  void _setupSubscriptions() {
    _devicesSub = homeService.devicesStream.listen((devices) {
      if (mounted) setState(() => _devices = devices);
    });

    _connectionSub = homeService.connectionStream.listen((connected) {
      if (mounted) setState(() => _isConnected = connected);
    });
  }

  Future<void> _initializeAndConnect() async {
    // First initialize the wallet to get the user's public key
    try {
      if (!_wallet.isInitialized) {
        await _wallet.initialize();
      }
    } catch (e) {
      debugPrint('FloatingHomeButton: Failed to initialize wallet: $e');
    }
    
    // Now try to auto-connect
    await _autoConnect();
  }

  Future<void> _autoConnect() async {
    if (homeService.isConnected) {
      if (mounted) {
        setState(() {
          _isConnected = true;
          _devices = homeService.devices;
        });
      }
      return;
    }

    // Try to auto-connect with saved URL
    final savedUrl = await _storage.read(key: _hubUrlKey);
    if (savedUrl != null && savedUrl.isNotEmpty) {
      if (mounted) setState(() => _isConnecting = true);
      
      // Get user's public key from wallet
      final userPublicKey = _wallet.publicKey ?? '';
      
      final success = await homeService.initialize(
        hubUrl: savedUrl,
        userPublicKey: userPublicKey,
      );

      if (mounted) {
        setState(() {
          _isConnecting = false;
          _isConnected = success;
          if (success) {
            _devices = homeService.devices;
            homeService.connectWebSocket();
          }
        });
      }
    }
  }

  Future<void> _loadPosition() async {
    try {
      final xStr = await _storage.read(key: _positionKeyX);
      final yStr = await _storage.read(key: _positionKeyY);
      if (xStr != null && yStr != null) {
        _xPosition = double.tryParse(xStr) ?? 0;
        _yPosition = double.tryParse(yStr) ?? 0;
      }
    } catch (e) {
      // Use defaults
    }
    if (mounted) setState(() => _initialized = true);
  }

  Future<void> _savePosition() async {
    try {
      await _storage.write(key: _positionKeyX, value: _xPosition.toString());
      await _storage.write(key: _positionKeyY, value: _yPosition.toString());
    } catch (e) {
      // Ignore
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _devicesSub?.cancel();
    _connectionSub?.cancel();
    super.dispose();
  }

  void _toggleCard() {
    HapticFeedback.mediumImpact();
    if (mounted) setState(() => _isCardOpen = !_isCardOpen);
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return widget.child;
    }

    final screenSize = MediaQuery.of(context).size;
    final buttonSize = 56.0;
    final padding = 16.0;

    // Ensure button stays within screen bounds
    if (_xPosition == 0 && _yPosition == 0) {
      _xPosition = screenSize.width - buttonSize - padding;
      _yPosition = screenSize.height * 0.7;
    }

    return Stack(
      children: [
        // Main app content
        widget.child,

        // Dimmed overlay when card is open
        if (_isCardOpen)
          GestureDetector(
            onTap: _toggleCard,
            child: Container(
              color: Colors.black.withValues(alpha: 0.5),
            ),
          ),

        // Quick controls card
        if (_isCardOpen)
          Positioned(
            bottom: 100,
            left: 16,
            right: 16,
            child: _buildQuickControlsCard(),
          ),

        // Floating button
        Positioned(
          left: _xPosition,
          top: _yPosition,
          child: GestureDetector(
            onTap: _toggleCard,
            onPanStart: (_) {
              if (mounted) setState(() => _isDragging = true);
            },
            onPanUpdate: (details) {
              if (mounted) {
                setState(() {
                  _xPosition = (_xPosition + details.delta.dx)
                      .clamp(padding, screenSize.width - buttonSize - padding);
                  _yPosition = (_yPosition + details.delta.dy)
                      .clamp(padding + 50, screenSize.height - buttonSize - padding - 50);
                });
              }
            },
            onPanEnd: (_) {
              if (mounted) setState(() => _isDragging = false);
              _savePosition();
            },
            child: _buildFloatingButton(),
          ),
        ),
      ],
    );
  }

  Widget _buildFloatingButton() {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _isConnected
              ? [const Color(0xFF6366F1), const Color(0xFF8B5CF6)]
              : [const Color(0xFF9CA3AF), const Color(0xFF6B7280)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: (_isConnected ? const Color(0xFF6366F1) : Colors.black).withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Text(
            'H',
            style: TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w700,
              decoration: TextDecoration.none,
            ),
          ),
          if (_isConnecting)
            const SizedBox(
              width: 56,
              height: 56,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
          if (_isConnected)
            Positioned(
              right: 2,
              top: 2,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildQuickControlsCard() {
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface(context),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.primary.withValues(alpha: 0.1),
                    AppTheme.accent.withValues(alpha: 0.05),
                  ],
                ),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Row(
                children: [
                  const Text('🏠', style: TextStyle(fontSize: 28)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Quick Controls',
                          style: TextStyle(
                            color: AppTheme.textPrimary(context),
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            decoration: TextDecoration.none,
                          ),
                        ),
                        Text(
                          _isConnected
                              ? '${_devices.length} device${_devices.length == 1 ? '' : 's'} online'
                              : 'Not connected',
                          style: TextStyle(
                            color: AppTheme.textMuted(context),
                            fontSize: 13,
                            fontWeight: FontWeight.normal,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _isConnected
                          ? AppTheme.secondary.withValues(alpha: 0.2)
                          : AppTheme.error.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: _isConnected ? AppTheme.secondary : AppTheme.error,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _isConnected ? 'Online' : 'Offline',
                          style: TextStyle(
                            color: _isConnected ? AppTheme.secondary : AppTheme.error,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Device list or placeholder
            if (!_isConnected)
              _buildNotConnectedView()
            else if (_devices.isEmpty)
              _buildNoDevicesView()
            else
              _buildDevicesList(),

            // Footer
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () {
                        _toggleCard();
                        // Navigate to full home facet screen
                        // Navigator.pushNamed(context, '/home');
                      },
                      icon: Icon(Icons.settings, color: AppTheme.textMuted(context), size: 18),
                      label: Text(
                        'Settings',
                        style: TextStyle(color: AppTheme.textMuted(context)),
                      ),
                    ),
                  ),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () async {
                        await homeService.refreshDevices();
                        HapticFeedback.mediumImpact();
                      },
                      icon: Icon(Icons.refresh, color: AppTheme.primary, size: 18),
                      label: Text(
                        'Refresh',
                        style: TextStyle(color: AppTheme.primary),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotConnectedView() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(Icons.cloud_off, size: 48, color: AppTheme.textMuted(context)),
          const SizedBox(height: 12),
          Text(
            'Not connected to Home Hub',
            style: TextStyle(
              color: AppTheme.textSecondary(context),
              fontSize: 15,
              decoration: TextDecoration.none,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                if (mounted) setState(() => _isCardOpen = false);
                Future.delayed(const Duration(milliseconds: 100), () {
                  _showConnectionDialog();
                });
              },
              icon: const Icon(Icons.link),
              label: const Text('Connect to Hub'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Show connection dialog with URL input
  void _showConnectionDialog() {
    final urlController = TextEditingController(text: 'http://192.168.1.223:3500');
    
    // Try to load saved URL
    _storage.read(key: _hubUrlKey).then((savedUrl) {
      if (savedUrl != null && savedUrl.isNotEmpty) {
        urlController.text = savedUrl;
      }
    });

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.surface(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: AppTheme.textMuted(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              
              // Title
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(
                      child: Text('🏠', style: TextStyle(fontSize: 24)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Connect to Home Hub',
                          style: TextStyle(
                            color: AppTheme.textPrimary(context),
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Enter your hub URL',
                          style: TextStyle(
                            color: AppTheme.textMuted(context),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 24),
              
              // URL Input
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.surfaceLight(context),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.border(context)),
                ),
                child: TextField(
                  controller: urlController,
                  style: TextStyle(color: AppTheme.textPrimary(context)),
                  decoration: InputDecoration(
                    hintText: 'http://192.168.1.100:3500',
                    hintStyle: TextStyle(color: AppTheme.textMuted(context)),
                    prefixIcon: Icon(Icons.link, color: AppTheme.textMuted(context)),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.all(16),
                  ),
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Connect button
              StatefulBuilder(
                builder: (context, setDialogState) {
                  return SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isConnecting ? null : () async {
                        final url = urlController.text.trim();
                        if (url.isEmpty) return;
                        
                        setDialogState(() {});
                        if (mounted) setState(() => _isConnecting = true);
                        
                        // Save URL
                        await _storage.write(key: _hubUrlKey, value: url);
                        
                        // Get user's public key from wallet
                        final userPublicKey = _wallet.publicKey ?? '';
                        
                        // Try to connect
                        final success = await homeService.initialize(
                          hubUrl: url,
                          userPublicKey: userPublicKey,
                        );
                        
                        if (mounted) {
                          setState(() {
                            _isConnecting = false;
                            _isConnected = success;
                            if (success) {
                              _devices = homeService.devices;
                              homeService.connectWebSocket();
                            }
                          });
                        }
                        
                        if (context.mounted) {
                          Navigator.pop(context);
                          if (success) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Connected to Home Hub!'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Failed to connect. Check URL and try again.'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isConnecting
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Connect',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                            ),
                    ),
                  );
                },
              ),
              
              const SizedBox(height: 12),
              
              Text(
                'Make sure your Home Hub is running',
                style: TextStyle(
                  color: AppTheme.textMuted(context),
                  fontSize: 12,
                ),
              ),
              
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNoDevicesView() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(Icons.devices, size: 48, color: AppTheme.textMuted(context)),
          const SizedBox(height: 12),
          Text(
            'No devices found',
            style: TextStyle(
              color: AppTheme.textSecondary(context),
              fontSize: 15,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDevicesList() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: _devices.map((device) => _buildDeviceRow(device)).toList(),
      ),
    );
  }

  Widget _buildDeviceRow(HomeDevice device) {
    final isOn = device.isPoweredOn;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border(context)),
      ),
      child: Row(
        children: [
          // Device icon
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isOn
                  ? AppTheme.primary.withValues(alpha: 0.2)
                  : AppTheme.surface(context),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(device.icon, style: const TextStyle(fontSize: 22)),
            ),
          ),
          const SizedBox(width: 12),

          // Device info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.name,
                  style: TextStyle(
                    color: AppTheme.textPrimary(context),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    decoration: TextDecoration.none,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  isOn ? 'On' : 'Off',
                  style: TextStyle(
                    color: isOn ? AppTheme.secondary : AppTheme.textMuted(context),
                    fontSize: 12,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
          ),

          // Quick actions based on device type
          if (device.type == 'tv') ...[
            // Open full remote
            GestureDetector(
              onTap: () {
                _toggleCard();
                TvRemoteScreen.show(context, device);
              },
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.surface(context),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.border(context)),
                ),
                child: Icon(
                  Icons.open_in_full,
                  color: AppTheme.textSecondary(context),
                  size: 18,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],

          // Power toggle
          GestureDetector(
            onTap: () async {
              HapticFeedback.mediumImpact();
              await homeService.executeCommand(
                deviceId: device.id,
                action: 'power',
                value: isOn ? 'off' : 'on',
              );
            },
            child: Container(
              width: 56,
              height: 36,
              decoration: BoxDecoration(
                color: isOn ? AppTheme.primary : AppTheme.surface(context),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isOn ? AppTheme.primary : AppTheme.border(context),
                ),
              ),
              child: Stack(
                children: [
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    left: isOn ? 24 : 4,
                    top: 4,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
