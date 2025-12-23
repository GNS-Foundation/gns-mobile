/// Home Facet Service - GNS Home Hub Communication
/// 
/// Handles all communication with the GNS Home Hub:
/// - Device discovery and listing
/// - Command execution
/// - Backup sync
/// - Recovery flow
/// 
/// Location: lib/core/home/home_service.dart

import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

/// Represents an IoT device from the Home Hub
class HomeDevice {
  final String id;
  final String name;
  final String type;
  final String brand;
  final String protocol;
  final List<String> capabilities;
  final DeviceStatus status;

  HomeDevice({
    required this.id,
    required this.name,
    required this.type,
    required this.brand,
    required this.protocol,
    required this.capabilities,
    required this.status,
  });

  factory HomeDevice.fromJson(Map<String, dynamic> json) {
    return HomeDevice(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      type: json['type'] ?? 'unknown',
      brand: json['brand'] ?? '',
      protocol: json['protocol'] ?? '',
      capabilities: List<String>.from(json['capabilities'] ?? []),
      status: DeviceStatus.fromJson(json['status'] ?? {}),
    );
  }

  /// Get icon for device type
  String get icon {
    switch (type) {
      case 'tv':
        return '📺';
      case 'lights':
        return '💡';
      case 'thermostat':
        return '🌡️';
      case 'lock':
        return '🔐';
      case 'camera':
        return '📷';
      default:
        return '📱';
    }
  }

  bool get isOnline => status.online;
  bool get isPoweredOn => status.state['power'] == 'on';
}

/// Device status from the Hub
class DeviceStatus {
  final bool online;
  final String lastSeen;
  final Map<String, dynamic> state;

  DeviceStatus({
    required this.online,
    required this.lastSeen,
    required this.state,
  });

  factory DeviceStatus.fromJson(Map<String, dynamic> json) {
    return DeviceStatus(
      online: json['online'] ?? false,
      lastSeen: json['lastSeen'] ?? '',
      state: Map<String, dynamic>.from(json['state'] ?? {}),
    );
  }
}

/// Hub information
class HubInfo {
  final String name;
  final String publicKey;
  final String? owner;
  final int deviceCount;
  final String version;

  HubInfo({
    required this.name,
    required this.publicKey,
    this.owner,
    required this.deviceCount,
    required this.version,
  });

  factory HubInfo.fromJson(Map<String, dynamic> json) {
    return HubInfo(
      name: json['name'] ?? 'GNS Home Hub',
      publicKey: json['publicKey'] ?? '',
      owner: json['owner'],
      deviceCount: json['deviceCount'] ?? 0,
      version: json['version'] ?? '0.0.0',
    );
  }
}

/// Command result from Hub
class CommandResult {
  final bool success;
  final Map<String, dynamic>? state;
  final String? error;

  CommandResult({
    required this.success,
    this.state,
    this.error,
  });

  factory CommandResult.fromJson(Map<String, dynamic> json) {
    return CommandResult(
      success: json['success'] ?? false,
      state: json['data'] != null 
          ? Map<String, dynamic>.from(json['data']) 
          : null,
      error: json['error'],
    );
  }
}

/// Recovery session info
class RecoverySession {
  final String sessionId;
  final String message;
  final int expiresIn;

  RecoverySession({
    required this.sessionId,
    required this.message,
    required this.expiresIn,
  });

  factory RecoverySession.fromJson(Map<String, dynamic> json) {
    return RecoverySession(
      sessionId: json['sessionId'] ?? '',
      message: json['message'] ?? '',
      expiresIn: json['expiresIn'] ?? 300,
    );
  }
}

/// Main service for communicating with GNS Home Hub
class HomeService {
  String? _hubUrl;
  String? _userPublicKey;
  WebSocketChannel? _wsChannel;
  
  final _deviceController = StreamController<List<HomeDevice>>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();
  
  Stream<List<HomeDevice>> get devicesStream => _deviceController.stream;
  Stream<bool> get connectionStream => _connectionController.stream;
  
  bool _isConnected = false;
  bool get isConnected => _isConnected;
  
  List<HomeDevice> _devices = [];
  List<HomeDevice> get devices => _devices;
  
  HubInfo? _hubInfo;
  HubInfo? get hubInfo => _hubInfo;

  /// Initialize with hub URL and user's public key
  Future<bool> initialize({
    required String hubUrl,
    required String userPublicKey,
  }) async {
    _hubUrl = hubUrl.replaceAll(RegExp(r'/$'), ''); // Remove trailing slash
    _userPublicKey = userPublicKey.toLowerCase();
    
    try {
      // Test connection
      final info = await getHubInfo();
      if (info != null) {
        _hubInfo = info;
        _isConnected = true;
        _connectionController.add(true);
        
        // Load devices
        await refreshDevices();
        
        return true;
      }
    } catch (e) {
      print('HomeService: Failed to connect to hub: $e');
    }
    
    _isConnected = false;
    _connectionController.add(false);
    return false;
  }

  /// Connect via WebSocket for real-time updates
  Future<void> connectWebSocket() async {
    if (_hubUrl == null || _userPublicKey == null) return;
    
    try {
      final wsUrl = _hubUrl!.replaceFirst('http', 'ws');
      _wsChannel = WebSocketChannel.connect(
        Uri.parse('$wsUrl/ws?pubkey=$_userPublicKey'),
      );
      
      _wsChannel!.stream.listen(
        (message) => _handleWebSocketMessage(message),
        onError: (error) {
          print('HomeService: WebSocket error: $error');
          _isConnected = false;
          _connectionController.add(false);
        },
        onDone: () {
          print('HomeService: WebSocket closed');
          _isConnected = false;
          _connectionController.add(false);
        },
      );
    } catch (e) {
      print('HomeService: WebSocket connection failed: $e');
    }
  }

  void _handleWebSocketMessage(dynamic message) {
    try {
      final data = jsonDecode(message as String);
      
      switch (data['type']) {
        case 'connected':
          print('HomeService: WebSocket connected to ${data['hubName']}');
          break;
        case 'device_update':
          refreshDevices();
          break;
        case 'command_result':
          // Handle real-time command results
          break;
      }
    } catch (e) {
      print('HomeService: Failed to parse WebSocket message: $e');
    }
  }

  /// Get hub info
  Future<HubInfo?> getHubInfo() async {
    try {
      final response = await http.get(
        Uri.parse('$_hubUrl/api/hub'),
      );
      
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['success'] == true) {
          return HubInfo.fromJson(json['data']);
        }
      }
    } catch (e) {
      print('HomeService: Failed to get hub info: $e');
    }
    return null;
  }

  /// Get all devices
  Future<List<HomeDevice>> refreshDevices() async {
    if (_hubUrl == null || _userPublicKey == null) return [];
    
    try {
      final response = await http.get(
        Uri.parse('$_hubUrl/api/devices'),
        headers: {'X-GNS-PublicKey': _userPublicKey!},
      );
      
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['success'] == true) {
          _devices = (json['data'] as List)
              .map((d) => HomeDevice.fromJson(d))
              .toList();
          _deviceController.add(_devices);
          return _devices;
        }
      }
    } catch (e) {
      print('HomeService: Failed to get devices: $e');
    }
    return [];
  }

  /// Execute a command on a device
  Future<CommandResult> executeCommand({
    required String deviceId,
    required String action,
    dynamic value,
  }) async {
    if (_hubUrl == null || _userPublicKey == null) {
      return CommandResult(success: false, error: 'Not connected');
    }
    
    try {
      final response = await http.post(
        Uri.parse('$_hubUrl/api/command'),
        headers: {
          'Content-Type': 'application/json',
          'X-GNS-PublicKey': _userPublicKey!,
        },
        body: jsonEncode({
          'device': deviceId,
          'action': action,
          if (value != null) 'value': value,
        }),
      );
      
      final json = jsonDecode(response.body);
      final result = CommandResult.fromJson(json);
      
      // Update local device state
      if (result.success && result.state != null) {
        final deviceIndex = _devices.indexWhere((d) => d.id == deviceId);
        if (deviceIndex != -1) {
          // Refresh to get updated state
          await refreshDevices();
        }
      }
      
      return result;
    } catch (e) {
      print('HomeService: Command failed: $e');
      return CommandResult(success: false, error: e.toString());
    }
  }

  /// Sync backup to hub
  Future<bool> syncBackup({
    required String encryptedSeed,
    required String nonce,
  }) async {
    if (_hubUrl == null || _userPublicKey == null) return false;
    
    try {
      final response = await http.post(
        Uri.parse('$_hubUrl/api/sync'),
        headers: {
          'Content-Type': 'application/json',
          'X-GNS-PublicKey': _userPublicKey!,
        },
        body: jsonEncode({
          'backup': {
            'version': 1,
            'encryptedSeed': encryptedSeed,
            'nonce': nonce,
          },
        }),
      );
      
      final json = jsonDecode(response.body);
      return json['success'] == true;
    } catch (e) {
      print('HomeService: Sync failed: $e');
      return false;
    }
  }

  /// Initiate recovery
  Future<RecoverySession?> initiateRecovery({
    required String handle,
    required String newDeviceKey,
  }) async {
    if (_hubUrl == null) return null;
    
    try {
      final response = await http.post(
        Uri.parse('$_hubUrl/api/recovery/initiate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'handle': handle,
          'newDeviceKey': newDeviceKey,
        }),
      );
      
      final json = jsonDecode(response.body);
      if (json['success'] == true) {
        return RecoverySession.fromJson(json['data']);
      }
    } catch (e) {
      print('HomeService: Recovery initiation failed: $e');
    }
    return null;
  }

  /// Verify recovery PIN
  Future<Map<String, dynamic>?> verifyRecoveryPin({
    required String sessionId,
    required String pin,
  }) async {
    if (_hubUrl == null) return null;
    
    try {
      final response = await http.post(
        Uri.parse('$_hubUrl/api/recovery/verify'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'sessionId': sessionId,
          'pin': pin,
        }),
      );
      
      final json = jsonDecode(response.body);
      if (json['success'] == true) {
        return json['data']['backup'];
      }
    } catch (e) {
      print('HomeService: Recovery verification failed: $e');
    }
    return null;
  }

  /// Discover hubs on local network (mDNS/SSDP)
  /// For now, returns empty - implement with multicast_dns package
  Future<List<String>> discoverHubs() async {
    // TODO: Implement mDNS discovery
    // For now, user enters hub URL manually
    return [];
  }

  /// Dispose resources
  void dispose() {
    _wsChannel?.sink.close();
    _deviceController.close();
    _connectionController.close();
  }
}

/// Singleton instance
final homeService = HomeService();
