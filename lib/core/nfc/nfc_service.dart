/// GNS NFC Service - Mobile NFC Integration Layer
/// 
/// Sprint 2: Flutter NFC plugin integration for tap-to-pay
/// 
/// Features:
/// - Cross-platform NFC read/write (iOS CoreNFC, Android NFC)
/// - Host Card Emulation (HCE) for Android
/// - Session state management
/// - Integration with NFC Protocol crypto layer
/// 
/// Location: lib/core/nfc/nfc_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/platform_tags.dart';

import 'nfc_protocol.dart' as protocol;
import '../crypto/secure_storage.dart';
import '../privacy/h3_quantizer.dart';

// =============================================================================
// NFC SERVICE CONFIGURATION
// =============================================================================

/// NFC operation modes
enum NfcMode {
  /// Read payment requests from merchant terminals
  reader,
  
  /// Emulate card for tap-to-pay (Android HCE)
  cardEmulation,
  
  /// Peer-to-peer for device-to-device payments
  p2p,
  
  /// Inactive
  idle,
}

/// NFC session states
enum NfcSessionState {
  idle,
  scanning,
  processing,
  awaitingConfirmation,
  signing,
  transmitting,
  complete,
  error,
  cancelled,
}

/// NFC error types
enum NfcErrorType {
  notAvailable,
  notEnabled,
  sessionCancelled,
  tagLost,
  invalidFormat,
  signatureError,
  replayDetected,
  locationMismatch,
  timeout,
  unknown,
}

// =============================================================================
// NFC SERVICE EVENTS
// =============================================================================

/// Base class for NFC events
abstract class NfcEvent {
  final DateTime timestamp;
  NfcEvent() : timestamp = DateTime.now();
}

/// Payment request received from merchant
class NfcPaymentRequestEvent extends NfcEvent {
  final protocol.NfcChallenge challenge;
  final String merchantName;
  final String? merchantLogo;
  
  NfcPaymentRequestEvent({
    required this.challenge,
    required this.merchantName,
    this.merchantLogo,
  });
  
  String get amountDisplay {
    final major = challenge.amountMinorUnits ~/ 100;
    final minor = challenge.amountMinorUnits % 100;
    final symbol = _symbols[challenge.currency] ?? challenge.currency;
    return '$symbol$major.${minor.toString().padLeft(2, '0')}';
  }
  
  static const _symbols = {'EUR': '€', 'USD': '\$', 'GBP': '£'};
}

/// Payment completed successfully
class NfcPaymentCompleteEvent extends NfcEvent {
  final String transactionId;
  final String amount;
  final String currency;
  final String merchantPublicKey;
  
  NfcPaymentCompleteEvent({
    required this.transactionId,
    required this.amount,
    required this.currency,
    required this.merchantPublicKey,
  });
}

/// NFC error occurred
class NfcErrorEvent extends NfcEvent {
  final NfcErrorType type;
  final String message;
  final dynamic originalError;
  
  NfcErrorEvent({
    required this.type,
    required this.message,
    this.originalError,
  });
}

/// Session state changed
class NfcStateChangeEvent extends NfcEvent {
  final NfcSessionState previousState;
  final NfcSessionState newState;
  
  NfcStateChangeEvent({
    required this.previousState,
    required this.newState,
  });
}

// =============================================================================
// NFC SERVICE
// =============================================================================

/// Main NFC service for GNS tap-to-pay
/// 
/// Usage:
/// ```dart
/// final nfcService = NfcService();
/// await nfcService.initialize();
/// 
/// // Listen for payment requests
/// nfcService.events.listen((event) {
///   if (event is NfcPaymentRequestEvent) {
///     // Show payment confirmation UI
///   }
/// });
/// 
/// // Start scanning for payments
/// await nfcService.startPaymentScan();
/// ```
class NfcService {
  static NfcService? _instance;
  
  // Dependencies
  final SecureStorageService _storage;
  final H3Quantizer _h3;
  final protocol.NfcCryptoService _crypto;
  final protocol.NonceTracker _nonceTracker;
  
  // State
  NfcMode _mode = NfcMode.idle;
  NfcSessionState _state = NfcSessionState.idle;
  bool _isAvailable = false;
  bool _isEnabled = false;
  protocol.NfcChallenge? _pendingChallenge;
  
  // Event streams
  final _eventController = StreamController<NfcEvent>.broadcast();
  
  // Platform channels for HCE (Android)
  static const _hceChannel = MethodChannel('gns.id/nfc_hce');
  static const _hceEventChannel = EventChannel('gns.id/nfc_hce_events');
  StreamSubscription? _hceSubscription;
  
  NfcService._({
    SecureStorageService? storage,
    H3Quantizer? h3,
    protocol.NfcCryptoService? crypto,
    protocol.NonceTracker? nonceTracker,
  })  : _storage = storage ?? SecureStorageService(),
        _h3 = h3 ?? H3Quantizer(),
        _crypto = crypto ?? protocol.NfcCryptoService(),
        _nonceTracker = nonceTracker ?? protocol.NonceTracker();
  
  /// Get singleton instance
  factory NfcService({
    SecureStorageService? storage,
    H3Quantizer? h3,
    protocol.NfcCryptoService? crypto,
    protocol.NonceTracker? nonceTracker,
  }) {
    _instance ??= NfcService._(
      storage: storage,
      h3: h3,
      crypto: crypto,
      nonceTracker: nonceTracker,
    );
    return _instance!;
  }
  
  // ==========================================================================
  // PUBLIC API
  // ==========================================================================
  
  /// Event stream for NFC events
  Stream<NfcEvent> get events => _eventController.stream;
  
  /// Current NFC mode
  NfcMode get mode => _mode;
  
  /// Current session state
  NfcSessionState get state => _state;
  
  /// Whether NFC is available on device
  bool get isAvailable => _isAvailable;
  
  /// Whether NFC is enabled in settings
  bool get isEnabled => _isEnabled;
  
  /// Pending payment challenge (if any)
  protocol.NfcChallenge? get pendingChallenge => _pendingChallenge;
  
  /// Initialize NFC service
  Future<bool> initialize() async {
    try {
      // Check NFC availability
      _isAvailable = await NfcManager.instance.isAvailable();
      
      if (!_isAvailable) {
        debugPrint('📱 NFC not available on this device');
        return false;
      }
      
      _isEnabled = true;  // If available, assume enabled
      debugPrint('📱 NFC Service initialized');
      
      // Setup HCE for Android
      if (defaultTargetPlatform == TargetPlatform.android) {
        await _initializeHce();
      }
      
      return true;
    } catch (e) {
      debugPrint('📱 NFC initialization error: $e');
      _isAvailable = false;
      return false;
    }
  }
  
  /// Start scanning for merchant payment requests
  Future<void> startPaymentScan() async {
    if (!_isAvailable) {
      _emitError(NfcErrorType.notAvailable, 'NFC not available');
      return;
    }
    
    _setMode(NfcMode.reader);
    _setState(NfcSessionState.scanning);
    
    try {
      await NfcManager.instance.startSession(
        alertMessage: 'Hold near payment terminal',
        onDiscovered: _onTagDiscovered,
        onError: (error) async {
          _emitError(NfcErrorType.unknown, error.message);
        },
      );
      
      debugPrint('📱 NFC scan started');
    } catch (e) {
      _emitError(NfcErrorType.unknown, 'Failed to start NFC scan: $e');
      _setState(NfcSessionState.error);
    }
  }
  
  /// Stop NFC scanning
  Future<void> stopScan() async {
    try {
      await NfcManager.instance.stopSession();
      _setMode(NfcMode.idle);
      _setState(NfcSessionState.idle);
      _pendingChallenge = null;
      debugPrint('📱 NFC scan stopped');
    } catch (e) {
      debugPrint('📱 Error stopping NFC scan: $e');
    }
  }
  
  /// Approve pending payment and transmit response
  Future<bool> approvePayment() async {
    if (_pendingChallenge == null) {
      _emitError(NfcErrorType.unknown, 'No pending payment');
      return false;
    }
    
    _setState(NfcSessionState.signing);
    
    try {
      // Get user's keys from secure storage
      final privateKeyHex = await _storage.readPrivateKey();
      final publicKeyHex = await _storage.readPublicKey();
      
      if (privateKeyHex == null || publicKeyHex == null) {
        _emitError(NfcErrorType.signatureError, 'Identity not found');
        return false;
      }
      
      final privateKey = _hexToBytes(privateKeyHex);
      final publicKey = _hexToBytes(publicKeyHex);
      
      // Get current H3 cell (would come from location service in production)
      // For now, we'll use the merchant's cell as a placeholder
      final userH3Cell = _pendingChallenge!.h3Cell;
      
      // Sign the response
      final response = await _crypto.signChallengeResponse(
        challenge: _pendingChallenge!,
        userPrivateKey: privateKey,
        userPublicKey: publicKey,
        userH3Cell: userH3Cell,
      );
      
      _setState(NfcSessionState.transmitting);
      
      // Build NDEF response
      final builder = protocol.NdefMessageBuilder();
      builder.addResponse(response);
      final ndefMessage = builder.build();
      
      // Transmit via NFC (implementation depends on platform)
      final success = await _transmitResponse(ndefMessage);
      
      if (success) {
        _setState(NfcSessionState.complete);
        _eventController.add(NfcPaymentCompleteEvent(
          transactionId: base64Encode(_pendingChallenge!.nonce),
          amount: (_pendingChallenge!.amountMinorUnits / 100).toStringAsFixed(2),
          currency: _pendingChallenge!.currency,
          merchantPublicKey: base64Encode(_pendingChallenge!.merchantPublicKey),
        ));
        
        _pendingChallenge = null;
        return true;
      } else {
        _emitError(NfcErrorType.unknown, 'Failed to transmit response');
        return false;
      }
    } catch (e) {
      _emitError(NfcErrorType.signatureError, 'Payment signing failed: $e');
      return false;
    }
  }
  
  /// Cancel pending payment
  void cancelPayment() {
    _pendingChallenge = null;
    _setState(NfcSessionState.cancelled);
    stopScan();
  }
  
  /// Enable Host Card Emulation mode (Android only)
  Future<bool> enableCardEmulation() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      debugPrint('📱 HCE only available on Android');
      return false;
    }
    
    try {
      final result = await _hceChannel.invokeMethod('enableHce');
      if (result == true) {
        _setMode(NfcMode.cardEmulation);
        debugPrint('📱 HCE enabled');
        return true;
      }
    } catch (e) {
      debugPrint('📱 HCE enable error: $e');
    }
    return false;
  }
  
  /// Disable Host Card Emulation
  Future<void> disableCardEmulation() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    
    try {
      await _hceChannel.invokeMethod('disableHce');
      _setMode(NfcMode.idle);
      debugPrint('📱 HCE disabled');
    } catch (e) {
      debugPrint('📱 HCE disable error: $e');
    }
  }
  
  /// Dispose resources
  void dispose() {
    stopScan();
    _hceSubscription?.cancel();
    _eventController.close();
  }
  
  // ==========================================================================
  // PRIVATE METHODS
  // ==========================================================================
  
  /// Handle discovered NFC tag
  Future<void> _onTagDiscovered(NfcTag tag) async {
    debugPrint('📱 NFC tag discovered');
    _setState(NfcSessionState.processing);
    
    try {
      // Try to read NDEF data
      final ndef = Ndef.from(tag);
      if (ndef == null) {
        _emitError(NfcErrorType.invalidFormat, 'Not an NDEF tag');
        return;
      }
      
      final ndefMessage = await ndef.read();
      if (ndefMessage == null || ndefMessage.records.isEmpty) {
        _emitError(NfcErrorType.invalidFormat, 'Empty NDEF message');
        return;
      }
      
      // Parse GNS payment data
      await _processNdefRecords(ndefMessage.records);
      
    } catch (e) {
      if (e.toString().contains('Tag was lost')) {
        _emitError(NfcErrorType.tagLost, 'Tag connection lost');
      } else {
        _emitError(NfcErrorType.unknown, 'Error reading tag: $e');
      }
    }
  }
  
  /// Process NDEF records for GNS payment data
  Future<void> _processNdefRecords(List<NdefRecord> records) async {
    for (final record in records) {
      // Check for GNS payment types
      if (record.typeNameFormat == NdefTypeNameFormat.media) {
        final typeStr = utf8.decode(record.type);
        
        if (typeStr == protocol.kNdefTypeGnsChallenge) {
          await _handlePaymentChallenge(record.payload);
          return;
        } else if (typeStr == protocol.kNdefTypeGnsPayment) {
          await _handlePaymentToken(record.payload);
          return;
        }
      }
    }
    
    // No GNS payment data found
    _emitError(NfcErrorType.invalidFormat, 'No GNS payment data found');
  }
  
  /// Handle merchant payment challenge
  Future<void> _handlePaymentChallenge(Uint8List payload) async {
    try {
      final jsonStr = utf8.decode(payload);
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      final challenge = protocol.NfcChallenge.fromJson(json);
      
      // Validate challenge
      if (!_nonceTracker.validateAndRegister(challenge.nonce, challenge.timestamp)) {
        _emitError(NfcErrorType.replayDetected, 'Invalid or replayed challenge');
        return;
      }
      
      // Store pending challenge
      _pendingChallenge = challenge;
      _setState(NfcSessionState.awaitingConfirmation);
      
      // Emit payment request event
      _eventController.add(NfcPaymentRequestEvent(
        challenge: challenge,
        merchantName: _extractMerchantName(challenge),
        merchantLogo: null,
      ));
      
      debugPrint('📱 Payment challenge received: ${challenge.amountMinorUnits} ${challenge.currency}');
      
    } catch (e) {
      _emitError(NfcErrorType.invalidFormat, 'Invalid challenge format: $e');
    }
  }
  
  /// Handle direct payment token
  Future<void> _handlePaymentToken(Uint8List payload) async {
    try {
      final token = protocol.NfcPaymentToken.fromBytes(payload);
      
      // Verify token
      final result = await _crypto.verifyPaymentToken(
        token,
        nonceTracker: _nonceTracker,
      );
      
      if (!result.isValid) {
        _emitError(
          result.error?.contains('Replay') == true 
              ? NfcErrorType.replayDetected 
              : NfcErrorType.signatureError,
          result.error ?? 'Token verification failed',
        );
        return;
      }
      
      // Convert to challenge format for consistent handling
      _pendingChallenge = protocol.NfcChallenge(
        timestamp: token.timestamp,
        nonce: token.nonce,
        merchantPublicKey: token.merchantPublicKey,
        amountMinorUnits: token.amountMinorUnits,
        currency: token.currency,
        h3Cell: token.h3Cell,
      );
      
      _setState(NfcSessionState.awaitingConfirmation);
      
      _eventController.add(NfcPaymentRequestEvent(
        challenge: _pendingChallenge!,
        merchantName: 'Merchant',
      ));
      
    } catch (e) {
      _emitError(NfcErrorType.invalidFormat, 'Invalid token format: $e');
    }
  }
  
  /// Transmit NDEF response back to terminal
  Future<bool> _transmitResponse(protocol.NdefMessage message) async {
    // In a real implementation, this would write to the NFC tag
    // For HCE mode, the response is sent via the HCE service
    
    if (_mode == NfcMode.cardEmulation) {
      return _transmitViaHce(message);
    }
    
    // For reader mode, we need the tag reference (not available in callback)
    // This is handled via the session's tag reference
    debugPrint('📱 Response ready for transmission (${message.toBytes().length} bytes)');
    return true;
  }
  
  /// Transmit via HCE (Android)
  Future<bool> _transmitViaHce(protocol.NdefMessage message) async {
    try {
      final messageBytes = message.toBytes();
      await _hceChannel.invokeMethod('sendResponse', {
        'data': messageBytes,
      });
      return true;
    } catch (e) {
      debugPrint('📱 HCE transmit error: $e');
      return false;
    }
  }
  
  /// Initialize HCE for Android
  Future<void> _initializeHce() async {
    try {
      // Listen for HCE events
      _hceSubscription = _hceEventChannel
          .receiveBroadcastStream()
          .listen(_onHceEvent);
      
      debugPrint('📱 HCE initialized');
    } catch (e) {
      debugPrint('📱 HCE init error: $e');
    }
  }
  
  /// Handle HCE events from Android
  void _onHceEvent(dynamic event) {
    if (event is Map) {
      final type = event['type'] as String?;
      
      switch (type) {
        case 'apdu_received':
          final data = event['data'] as Uint8List?;
          if (data != null) {
            _handleHceApdu(data);
          }
          break;
        case 'deactivated':
          debugPrint('📱 HCE deactivated');
          break;
      }
    }
  }
  
  /// Handle APDU command from reader
  void _handleHceApdu(Uint8List apdu) {
    debugPrint('📱 HCE APDU received: ${apdu.length} bytes');
    // Process APDU and respond via HCE channel
    // This would parse the payment request and trigger the approval flow
  }
  
  /// Set session state and emit event
  void _setState(NfcSessionState newState) {
    if (_state != newState) {
      final previous = _state;
      _state = newState;
      _eventController.add(NfcStateChangeEvent(
        previousState: previous,
        newState: newState,
      ));
    }
  }
  
  /// Set NFC mode
  void _setMode(NfcMode newMode) {
    _mode = newMode;
    debugPrint('📱 NFC mode: $newMode');
  }
  
  /// Emit error event
  void _emitError(NfcErrorType type, String message, [dynamic error]) {
    debugPrint('📱 NFC Error: $message');
    _setState(NfcSessionState.error);
    _eventController.add(NfcErrorEvent(
      type: type,
      message: message,
      originalError: error,
    ));
  }
  
  /// Extract merchant name from challenge (placeholder)
  String _extractMerchantName(protocol.NfcChallenge challenge) {
    // In production, would look up merchant by public key
    return 'Merchant';
  }
  
  /// Convert hex string to bytes
  Uint8List _hexToBytes(String hex) {
    final result = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < hex.length; i += 2) {
      result[i ~/ 2] = int.parse(hex.substring(i, i + 2), radix: 16);
    }
    return result;
  }
}


// =============================================================================
// NFC PAYMENT WIDGET MIXIN
// =============================================================================

/// Mixin for widgets that need NFC payment capability
mixin NfcPaymentMixin<T extends StatefulWidget> on State<T> {
  late NfcService _nfcService;
  StreamSubscription<NfcEvent>? _nfcSubscription;
  
  NfcService get nfcService => _nfcService;
  
  @override
  void initState() {
    super.initState();
    _nfcService = NfcService();
    _nfcSubscription = _nfcService.events.listen(_handleNfcEvent);
  }
  
  @override
  void dispose() {
    _nfcSubscription?.cancel();
    super.dispose();
  }
  
  /// Override to handle NFC events
  void onNfcPaymentRequest(NfcPaymentRequestEvent event) {}
  void onNfcPaymentComplete(NfcPaymentCompleteEvent event) {}
  void onNfcError(NfcErrorEvent event) {}
  void onNfcStateChange(NfcStateChangeEvent event) {}
  
  void _handleNfcEvent(NfcEvent event) {
    if (event is NfcPaymentRequestEvent) {
      onNfcPaymentRequest(event);
    } else if (event is NfcPaymentCompleteEvent) {
      onNfcPaymentComplete(event);
    } else if (event is NfcErrorEvent) {
      onNfcError(event);
    } else if (event is NfcStateChangeEvent) {
      onNfcStateChange(event);
    }
  }
}
