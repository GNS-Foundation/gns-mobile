/// Home Facet Screen - IoT Control Interface
/// 
/// The home@ facet UI for controlling smart home devices via GNS Home Hub.
/// Tapping a TV device opens a full-screen remote control.
/// 
/// Location: lib/ui/screens/home_facet_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/home/home_service.dart';
import '../../core/theme/theme_service.dart';
import 'tv_remote_screen.dart';

class HomeFacetScreen extends StatefulWidget {
  final String userPublicKey;
  final String? userHandle;

  const HomeFacetScreen({
    super.key,
    required this.userPublicKey,
    this.userHandle,
  });

  @override
  State<HomeFacetScreen> createState() => _HomeFacetScreenState();
}

class _HomeFacetScreenState extends State<HomeFacetScreen> {
  final _hubUrlController = TextEditingController();
  final _storage = const FlutterSecureStorage();
  static const _hubUrlKey = 'gns_home_hub_url';
  
  bool _isConnecting = false;
  bool _isConnected = false;
  bool _isLoading = true;
  String? _error;
  
  List<HomeDevice> _devices = [];
  HubInfo? _hubInfo;
  
  StreamSubscription? _devicesSub;
  StreamSubscription? _connectionSub;

  @override
  void initState() {
    super.initState();
    _loadSavedUrl();
    _setupSubscriptions();
    
    if (homeService.isConnected) {
      setState(() {
        _isConnected = true;
        _devices = homeService.devices;
        _hubInfo = homeService.hubInfo;
      });
    }
  }

  Future<void> _loadSavedUrl() async {
    try {
      final savedUrl = await _storage.read(key: _hubUrlKey);
      if (savedUrl != null && savedUrl.isNotEmpty) {
        _hubUrlController.text = savedUrl;
      } else {
        _hubUrlController.text = 'http://192.168.1.223:3500';
      }
    } catch (e) {
      _hubUrlController.text = 'http://192.168.1.223:3500';
    }
    setState(() => _isLoading = false);
  }

  Future<void> _saveUrl(String url) async {
    try {
      await _storage.write(key: _hubUrlKey, value: url);
    } catch (e) {
      // Ignore
    }
  }

  void _setupSubscriptions() {
    _devicesSub = homeService.devicesStream.listen((devices) {
      setState(() => _devices = devices);
    });
    
    _connectionSub = homeService.connectionStream.listen((connected) {
      setState(() => _isConnected = connected);
    });
  }

  @override
  void dispose() {
    _devicesSub?.cancel();
    _connectionSub?.cancel();
    _hubUrlController.dispose();
    super.dispose();
  }

  Future<void> _connectToHub() async {
    final url = _hubUrlController.text.trim();
    if (url.isEmpty) return;

    setState(() {
      _isConnecting = true;
      _error = null;
    });
    
    final success = await homeService.initialize(
      hubUrl: url,
      userPublicKey: widget.userPublicKey,
    );
    
    setState(() {
      _isConnecting = false;
      _isConnected = success;
      _hubInfo = homeService.hubInfo;
      _devices = homeService.devices;
      if (!success) {
        _error = 'Failed to connect. Check the hub URL and try again.';
      }
    });
    
    if (success) {
      await _saveUrl(url);
      homeService.connectWebSocket();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connected to ${_hubInfo?.name ?? "GNS Home Hub"}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background(context),
      appBar: AppBar(
        backgroundColor: AppTheme.background(context),
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppTheme.textPrimary(context)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🏠', style: TextStyle(fontSize: 20)),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'home@${widget.userHandle ?? "me"}',
                style: TextStyle(
                  color: AppTheme.textPrimary(context),
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          if (_isConnected)
            IconButton(
              icon: Icon(Icons.refresh, color: AppTheme.textSecondary(context)),
              onPressed: () => homeService.refreshDevices(),
            ),
          IconButton(
            icon: Icon(
              _isConnected ? Icons.cloud_done : Icons.cloud_off,
              color: _isConnected ? Colors.green : AppTheme.textMuted(context),
            ),
            onPressed: () => _showHubSettings(),
          ),
        ],
      ),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator())
          : _isConnected 
              ? _buildConnectedView() 
              : _buildConnectionView(),
    );
  }

  Widget _buildConnectionView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 40),
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: AppTheme.surfaceLight(context),
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Text('🏠', style: TextStyle(fontSize: 48)),
            ),
          ),
          const SizedBox(height: 24),
          
          Text(
            'Connect to Home Hub',
            style: TextStyle(
              color: AppTheme.textPrimary(context),
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Control your smart home devices',
            style: TextStyle(
              color: AppTheme.textSecondary(context),
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 32),
          
          Container(
            decoration: BoxDecoration(
              color: AppTheme.surfaceLight(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.border(context)),
            ),
            child: TextField(
              controller: _hubUrlController,
              style: TextStyle(color: AppTheme.textPrimary(context)),
              decoration: InputDecoration(
                hintText: 'Hub URL (e.g., http://192.168.1.100:3500)',
                hintStyle: TextStyle(color: AppTheme.textMuted(context)),
                prefixIcon: Icon(Icons.link, color: AppTheme.textMuted(context)),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(16),
              ),
            ),
          ),
          const SizedBox(height: 16),
          
          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: AppTheme.error, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(color: AppTheme.error, fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isConnecting ? null : _connectToHub,
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
          ),
          const SizedBox(height: 24),
          
          Text(
            'Make sure GNS Home Hub is running on your\nRaspberry Pi or local computer',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTheme.textMuted(context),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildConnectedView() {
    if (_devices.isEmpty) {
      return _buildEmptyDevicesView();
    }
    
    return RefreshIndicator(
      onRefresh: () => homeService.refreshDevices(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildHubInfoCard(),
          const SizedBox(height: 24),
          
          Text(
            'DEVICES',
            style: TextStyle(
              color: AppTheme.textMuted(context),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 12),
          
          ..._devices.map((device) => _buildDeviceCard(device)),
        ],
      ),
    );
  }

  Widget _buildEmptyDevicesView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('📱', style: TextStyle(fontSize: 64, color: AppTheme.textMuted(context))),
          const SizedBox(height: 16),
          Text('No devices yet', style: TextStyle(color: AppTheme.textSecondary(context), fontSize: 18)),
          const SizedBox(height: 8),
          Text('Add devices in the Hub settings', style: TextStyle(color: AppTheme.textMuted(context), fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildHubInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primary.withValues(alpha: 0.2),
            AppTheme.accent.withValues(alpha: 0.1),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(child: Text('🏠', style: TextStyle(fontSize: 24))),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _hubInfo?.name ?? 'GNS Home Hub',
                  style: TextStyle(
                    color: AppTheme.textPrimary(context),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_devices.length} device${_devices.length == 1 ? '' : 's'} • v${_hubInfo?.version ?? '?'}',
                  style: TextStyle(color: AppTheme.textSecondary(context), fontSize: 13),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.secondary.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(color: AppTheme.secondary, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                const Text('Online', style: TextStyle(color: AppTheme.secondary, fontSize: 12, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceCard(HomeDevice device) {
    final isOn = device.isPoweredOn;
    
    return GestureDetector(
      onTap: () {
        // Open full-screen remote for TV devices
        if (device.type == 'tv') {
          HapticFeedback.mediumImpact();
          TvRemoteScreen.show(context, device);
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surface(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.border(context)),
        ),
        child: Row(
          children: [
            // Device icon
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: isOn
                    ? AppTheme.primary.withValues(alpha: 0.2)
                    : AppTheme.surfaceLight(context),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: Text(device.icon, style: const TextStyle(fontSize: 28)),
              ),
            ),
            const SizedBox(width: 16),
            
            // Device info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    device.name,
                    style: TextStyle(
                      color: AppTheme.textPrimary(context),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: isOn ? AppTheme.secondary : AppTheme.textMuted(context),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isOn ? 'On' : 'Off',
                        style: TextStyle(
                          color: isOn ? AppTheme.secondary : AppTheme.textMuted(context),
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        ' • ${device.brand} ${device.type}',
                        style: TextStyle(
                          color: AppTheme.textMuted(context),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            // Open remote indicator for TVs
            if (device.type == 'tv')
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceLight(context),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.open_in_full,
                  color: AppTheme.textSecondary(context),
                  size: 20,
                ),
              ),
              
            // Power button for non-TV devices
            if (device.type != 'tv')
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
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: isOn ? AppTheme.primary : AppTheme.surfaceLight(context),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.power_settings_new,
                    color: isOn ? Colors.white : AppTheme.textMuted(context),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showHubSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hub Settings',
              style: TextStyle(
                color: AppTheme.textPrimary(context),
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                _isConnected ? Icons.cloud_done : Icons.cloud_off,
                color: _isConnected ? AppTheme.secondary : AppTheme.error,
              ),
              title: Text(
                _isConnected ? 'Connected' : 'Disconnected',
                style: TextStyle(color: AppTheme.textPrimary(context)),
              ),
              subtitle: Text(
                _hubInfo?.name ?? _hubUrlController.text,
                style: TextStyle(color: AppTheme.textMuted(context)),
              ),
            ),
            
            Divider(color: AppTheme.border(context)),
            
            if (_isConnected)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.logout, color: AppTheme.warning),
                title: const Text('Disconnect', style: TextStyle(color: AppTheme.warning)),
                onTap: () {
                  setState(() {
                    _isConnected = false;
                    _devices = [];
                    _hubInfo = null;
                  });
                  Navigator.pop(context);
                },
              ),
            
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.edit, color: AppTheme.textSecondary(context)),
              title: Text('Change Hub URL', style: TextStyle(color: AppTheme.textPrimary(context))),
              onTap: () {
                Navigator.pop(context);
                setState(() {
                  _isConnected = false;
                  _devices = [];
                  _hubInfo = null;
                });
              },
            ),
            
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
