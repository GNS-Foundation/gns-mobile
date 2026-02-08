/// GNS Host Card Emulation (HCE) Service - Sprint 6
/// 
/// Enables user's phone to act as a contactless payment card.
/// When tapped at a terminal, the phone presents GNS identity
/// and authorizes payment via Stellar.
/// 
/// Supported modes:
/// - GNS Native: Terminal reads GNS public key directly
/// - EMV Compatible: Emulates contactless card for legacy terminals
/// 
/// Location: lib/core/financial/hce_payment_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../gns/identity_wallet.dart';
import 'stellar_service.dart';
import 'payment_receipt.dart';

/// HCE Payment Mode
enum HcePaymentMode {
  /// GNS native protocol - terminal reads GNS public key
  gnsNative,
  
  /// EMV compatible - emulates contactless card
  emvCompatible,
  
  /// Auto-detect based on terminal capabilities
  autoDetect,
}

/// HCE State
enum HceState {
  disabled,
  ready,
  waitingForTerminal,
  processingPayment,
  awaitingApproval,
  completed,
  failed,
}

/// HCE Payment Request (from terminal)
class HcePaymentRequest {
  final String requestId;
  final String merchantId;
  final String merchantName;
  final double amount;
  final String currency;
  final String? orderId;
  final DateTime timestamp;
  final String terminalId;
  final HcePaymentMode mode;
  
  HcePaymentRequest({
    required this.requestId,
    required this.merchantId,
    required this.merchantName,
    required this.amount,
    required this.currency,
    this.orderId,
    required this.timestamp,
    required this.terminalId,
    required this.mode,
  });
  
  factory HcePaymentRequest.fromApdu(Uint8List apdu) {
    // Parse APDU command from terminal
    // This is a simplified parser - real implementation would follow EMV spec
    try {
      // Check for GNS-specific SELECT command
      if (apdu.length > 5 && apdu[0] == 0x00 && apdu[1] == 0xA4) {
        // SELECT command - extract AID
        final aidLength = apdu[4];
        final aid = apdu.sublist(5, 5 + aidLength);
        
        // Check if it's GNS AID (custom AID for GNS protocol)
        if (_isGnsAid(aid)) {
          // GNS native mode - parse GNS payment request
          return _parseGnsRequest(apdu.sublist(5 + aidLength));
        }
      }
      
      // Try to parse as GNS JSON payload (for simplified terminals)
      final jsonStr = utf8.decode(apdu);
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      return HcePaymentRequest._fromJson(data);
    } catch (e) {
      throw HceException('Failed to parse terminal request: $e');
    }
  }
  
  static bool _isGnsAid(Uint8List aid) {
    // GNS Application ID: A0 00 00 08 58 47 4E 53 (GNS)
    const gnsAid = [0xA0, 0x00, 0x00, 0x08, 0x58, 0x47, 0x4E, 0x53];
    if (aid.length != gnsAid.length) return false;
    for (var i = 0; i < aid.length; i++) {
      if (aid[i] != gnsAid[i]) return false;
    }
    return true;
  }
  
  static HcePaymentRequest _parseGnsRequest(Uint8List data) {
    final json = utf8.decode(data);
    final map = jsonDecode(json) as Map<String, dynamic>;
    return HcePaymentRequest._fromJson(map, mode: HcePaymentMode.gnsNative);
  }
  
  factory HcePaymentRequest._fromJson(Map<String, dynamic> json, {HcePaymentMode mode = HcePaymentMode.emvCompatible}) {
    return HcePaymentRequest(
      requestId: json['request_id'] ?? const Uuid().v4(),
      merchantId: json['merchant_id'] as String,
      merchantName: json['merchant_name'] as String,
      amount: (json['amount'] as num).toDouble(),
      currency: json['currency'] as String? ?? 'USDC',
      orderId: json['order_id'] as String?,
      timestamp: DateTime.now(),
      terminalId: json['terminal_id'] as String? ?? 'UNKNOWN',
      mode: mode,
    );
  }
  
  Map<String, dynamic> toJson() => {
    'request_id': requestId,
    'merchant_id': merchantId,
    'merchant_name': merchantName,
    'amount': amount,
    'currency': currency,
    if (orderId != null) 'order_id': orderId,
    'timestamp': timestamp.toIso8601String(),
    'terminal_id': terminalId,
    'mode': mode.name,
  };
}

/// HCE Payment Response (to terminal)
class HcePaymentResponse {
  final String requestId;
  final bool approved;
  final String? transactionHash;
  final String? authCode;
  final String? errorCode;
  final String? errorMessage;
  final String userPublicKey;
  final String? userHandle;
  final DateTime timestamp;
  
  HcePaymentResponse({
    required this.requestId,
    required this.approved,
    this.transactionHash,
    this.authCode,
    this.errorCode,
    this.errorMessage,
    required this.userPublicKey,
    this.userHandle,
    required this.timestamp,
  });
  
  /// Convert to APDU response
  Uint8List toApdu() {
    final json = jsonEncode(toJson());
    final bytes = utf8.encode(json);
    
    // Wrap in APDU response format
    final response = Uint8List(bytes.length + 2);
    response.setRange(0, bytes.length, bytes);
    
    // Status bytes: 90 00 = success, 6A 82 = file not found, etc.
    if (approved) {
      response[bytes.length] = 0x90;
      response[bytes.length + 1] = 0x00;
    } else {
      response[bytes.length] = 0x6A;
      response[bytes.length + 1] = 0x82;
    }
    
    return response;
  }
  
  Map<String, dynamic> toJson() => {
    'request_id': requestId,
    'approved': approved,
    if (transactionHash != null) 'transaction_hash': transactionHash,
    if (authCode != null) 'auth_code': authCode,
    if (errorCode != null) 'error_code': errorCode,
    if (errorMessage != null) 'error_message': errorMessage,
    'user_public_key': userPublicKey,
    if (userHandle != null) 'user_handle': userHandle,
    'timestamp': timestamp.toIso8601String(),
  };
}

/// HCE Settings
class HceSettings {
  /// Maximum amount that can be approved without PIN
  final double tapAndPayLimit;
  
  /// Require biometric for all transactions
  final bool alwaysRequireBiometric;
  
  /// Auto-approve for trusted merchants
  final bool autoApproveTristed;
  
  /// Preferred currency
  final String preferredCurrency;
  
  /// Payment mode
  final HcePaymentMode paymentMode;
  
  /// Enable vibration feedback
  final bool hapticFeedback;
  
  /// Show amount before approval
  final bool showAmountFirst;
  
  HceSettings({
    this.tapAndPayLimit = 50.0,
    this.alwaysRequireBiometric = false,
    this.autoApproveTristed = false,
    this.preferredCurrency = 'USDC',
    this.paymentMode = HcePaymentMode.autoDetect,
    this.hapticFeedback = true,
    this.showAmountFirst = true,
  });
  
  HceSettings copyWith({
    double? tapAndPayLimit,
    bool? alwaysRequireBiometric,
    bool? autoApproveTristed,
    String? preferredCurrency,
    HcePaymentMode? paymentMode,
    bool? hapticFeedback,
    bool? showAmountFirst,
  }) {
    return HceSettings(
      tapAndPayLimit: tapAndPayLimit ?? this.tapAndPayLimit,
      alwaysRequireBiometric: alwaysRequireBiometric ?? this.alwaysRequireBiometric,
      autoApproveTristed: autoApproveTristed ?? this.autoApproveTristed,
      preferredCurrency: preferredCurrency ?? this.preferredCurrency,
      paymentMode: paymentMode ?? this.paymentMode,
      hapticFeedback: hapticFeedback ?? this.hapticFeedback,
      showAmountFirst: showAmountFirst ?? this.showAmountFirst,
    );
  }
}

/// HCE Exception
class HceException implements Exception {
  final String message;
  final String? code;
  
  HceException(this.message, {this.code});
  
  @override
  String toString() => 'HceException: $message${code != null ? ' ($code)' : ''}';
}

/// GNS Host Card Emulation Service
/// 
/// Makes the phone act as a contactless payment card.
/// Works with both GNS-native terminals and legacy EMV readers.
class HcePaymentService {
  static final HcePaymentService _instance = HcePaymentService._internal();
  factory HcePaymentService() => _instance;
  HcePaymentService._internal();
  
  // Platform channel for native HCE
  static const _channel = MethodChannel('gns.protocol/hce');
  static const _eventChannel = EventChannel('gns.protocol/hce/events');
  
  // State
  HceState _state = HceState.disabled;
  HceSettings _settings = HceSettings();
  IdentityWallet? _wallet;
  StellarService? _stellarService;
  
  // Current transaction
  HcePaymentRequest? _currentRequest;
  Completer<bool>? _approvalCompleter;
  
  // Callbacks
  Function(HcePaymentRequest)? onPaymentRequest;
  Function(HcePaymentResponse)? onPaymentComplete;
  Function(HceState)? onStateChange;
  Function(String)? onError;
  
  // Stream subscription
  StreamSubscription? _eventSubscription;
  
  // Getters
  HceState get state => _state;
  HceSettings get settings => _settings;
  HcePaymentRequest? get currentRequest => _currentRequest;
  bool get isEnabled => _state != HceState.disabled;
  
  /// Initialize HCE service
  Future<void> initialize({
    required IdentityWallet wallet,
    HceSettings? settings,
  }) async {
    _wallet = wallet;
    _stellarService = StellarService();
    
    if (settings != null) {
      _settings = settings;
    }
    
    // Check if HCE is supported
    final isSupported = await _checkHceSupport();
    if (!isSupported) {
      throw HceException('HCE not supported on this device', code: 'NOT_SUPPORTED');
    }
    
    // Register HCE service
    await _registerHceService();
    
    // Listen for terminal events
    _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
      _handleTerminalEvent,
      onError: (error) {
        debugPrint('HCE event error: $error');
        onError?.call(error.toString());
      },
    );
    
    _updateState(HceState.ready);
    debugPrint('📱 HCE Payment Service initialized');
  }
  
  /// Check if device supports HCE
  Future<bool> _checkHceSupport() async {
    try {
      final result = await _channel.invokeMethod<bool>('checkHceSupport');
      return result ?? false;
    } catch (e) {
      debugPrint('HCE support check error: $e');
      return false;
    }
  }
  
  /// Register as HCE payment service
  Future<void> _registerHceService() async {
    try {
      await _channel.invokeMethod('registerHceService', {
        'aid': 'A0000008584E5347', // GNS AID
        'category': 'payment',
        'description': 'GNS Payment',
      });
    } catch (e) {
      throw HceException('Failed to register HCE service: $e');
    }
  }
  
  /// Handle events from terminal
  void _handleTerminalEvent(dynamic event) async {
    try {
      final eventMap = event as Map<dynamic, dynamic>;
      final eventType = eventMap['type'] as String;
      
      switch (eventType) {
        case 'terminal_detected':
          debugPrint('📡 Terminal detected');
          _updateState(HceState.waitingForTerminal);
          break;
          
        case 'payment_request':
          final apduData = eventMap['apdu'] as Uint8List;
          await _handlePaymentRequest(apduData);
          break;
          
        case 'terminal_disconnected':
          debugPrint('📡 Terminal disconnected');
          _updateState(HceState.ready);
          _currentRequest = null;
          break;
          
        case 'error':
          final errorMsg = eventMap['message'] as String;
          onError?.call(errorMsg);
          _updateState(HceState.failed);
          break;
      }
    } catch (e) {
      debugPrint('HCE event handling error: $e');
      onError?.call(e.toString());
    }
  }
  
  /// Handle payment request from terminal
  Future<void> _handlePaymentRequest(Uint8List apduData) async {
    try {
      _updateState(HceState.processingPayment);
      
      // Parse request
      final request = HcePaymentRequest.fromApdu(apduData);
      _currentRequest = request;
      
      debugPrint('💳 Payment request: ${request.amount} ${request.currency} from ${request.merchantName}');
      
      // Notify UI
      onPaymentRequest?.call(request);
      
      // Check if auto-approve
      final needsApproval = await _needsUserApproval(request);
      
      if (needsApproval) {
        // Wait for user approval
        _updateState(HceState.awaitingApproval);
        _approvalCompleter = Completer<bool>();
        
        final approved = await _approvalCompleter!.future
            .timeout(const Duration(seconds: 60), onTimeout: () => false);
        
        if (!approved) {
          await _sendDeclinedResponse(request, 'USER_DECLINED');
          return;
        }
      }
      
      // Execute payment
      await _executePayment(request);
      
    } catch (e) {
      debugPrint('Payment request error: $e');
      _updateState(HceState.failed);
      onError?.call(e.toString());
      
      if (_currentRequest != null) {
        await _sendDeclinedResponse(_currentRequest!, 'PROCESSING_ERROR');
      }
    }
  }
  
  /// Check if user approval is needed
  Future<bool> _needsUserApproval(HcePaymentRequest request) async {
    // Always require approval if setting enabled
    if (_settings.alwaysRequireBiometric) return true;
    
    // Check tap-and-pay limit
    if (request.amount > _settings.tapAndPayLimit) return true;
    
    // Check if trusted merchant (implement trusted merchant list)
    if (_settings.autoApproveTristed) {
      // TODO: Check trusted merchants list
      return false;
    }
    
    return true;
  }
  
  /// Execute the payment on Stellar
  Future<void> _executePayment(HcePaymentRequest request) async {
    _updateState(HceState.processingPayment);
    
    if (_wallet == null || _stellarService == null) {
      throw HceException('Service not initialized');
    }
    
    try {
      // Get user's Stellar address
      final userPk = _wallet!.publicKeyHex;
      final userStellarKey = _stellarService!.gnsKeyToStellar(userPk);
      
      // Get private key for signing
      final privateKeyBytes = _wallet!.privateKeyBytes;
      if (privateKeyBytes == null) {
        throw HceException('Wallet not unlocked');
      }
      
      // Execute payment based on currency
      TransactionResult result;
      
      switch (request.currency.toUpperCase()) {
        case 'GNS':
          result = await _stellarService!.sendGns(
            senderStellarPublicKey: userStellarKey,
            senderPrivateKeyBytes: privateKeyBytes,
            recipientStellarPublicKey: await _getMerchantStellarAddress(request.merchantId),
            amount: request.amount,
          );
          break;
          
        case 'USDC':
          result = await _sendUsdc(
            senderStellarKey: userStellarKey,
            senderPrivateKeyBytes: privateKeyBytes,
            merchantId: request.merchantId,
            amount: request.amount,
          );
          break;
          
        case 'EURC':
          result = await _sendEurc(
            senderStellarKey: userStellarKey,
            senderPrivateKeyBytes: privateKeyBytes,
            merchantId: request.merchantId,
            amount: request.amount,
          );
          break;
          
        default:
          throw HceException('Unsupported currency: ${request.currency}');
      }
      
      if (result.success) {
        // Create response
        final response = HcePaymentResponse(
          requestId: request.requestId,
          approved: true,
          transactionHash: result.hash,
          authCode: _generateAuthCode(),
          userPublicKey: userPk,
          userHandle: await _wallet!.getHandle(),
          timestamp: DateTime.now(),
        );
        
        // Send to terminal
        await _sendResponse(response);
        
        // Generate receipt
        await _generateReceipt(request, response);
        
        // Notify UI
        onPaymentComplete?.call(response);
        _updateState(HceState.completed);
        
        debugPrint('✅ HCE Payment completed: ${result.hash}');
        
      } else {
        await _sendDeclinedResponse(request, 'PAYMENT_FAILED', result.error);
      }
      
    } catch (e) {
      debugPrint('HCE payment execution error: $e');
      await _sendDeclinedResponse(request, 'EXECUTION_ERROR', e.toString());
      rethrow;
    }
  }
  
  /// Get merchant's Stellar address from backend
  Future<String> _getMerchantStellarAddress(String merchantId) async {
    // TODO: Call backend API to get merchant Stellar address
    // For now, return placeholder
    throw HceException('Merchant lookup not implemented');
  }
  
  /// Send USDC payment
  Future<TransactionResult> _sendUsdc({
    required String senderStellarKey,
    required Uint8List senderPrivateKeyBytes,
    required String merchantId,
    required double amount,
  }) async {
    // TODO: Implement USDC payment via Stellar
    throw HceException('USDC payment not implemented');
  }
  
  /// Send EURC payment
  Future<TransactionResult> _sendEurc({
    required String senderStellarKey,
    required Uint8List senderPrivateKeyBytes,
    required String merchantId,
    required double amount,
  }) async {
    // TODO: Implement EURC payment via Stellar
    throw HceException('EURC payment not implemented');
  }
  
  /// Generate auth code
  String _generateAuthCode() {
    final uuid = const Uuid().v4();
    return uuid.substring(0, 6).toUpperCase();
  }
  
  /// Send response to terminal
  Future<void> _sendResponse(HcePaymentResponse response) async {
    try {
      final apdu = response.toApdu();
      await _channel.invokeMethod('sendApduResponse', {
        'data': apdu,
      });
    } catch (e) {
      debugPrint('Failed to send HCE response: $e');
    }
  }
  
  /// Send declined response
  Future<void> _sendDeclinedResponse(
    HcePaymentRequest request,
    String errorCode, [
    String? errorMessage,
  ]) async {
    final response = HcePaymentResponse(
      requestId: request.requestId,
      approved: false,
      errorCode: errorCode,
      errorMessage: errorMessage,
      userPublicKey: _wallet?.publicKeyHex ?? '',
      timestamp: DateTime.now(),
    );
    
    await _sendResponse(response);
    onPaymentComplete?.call(response);
    _updateState(HceState.failed);
  }
  
  /// Generate receipt for completed payment
  Future<void> _generateReceipt(
    HcePaymentRequest request,
    HcePaymentResponse response,
  ) async {
    final receipt = PaymentReceipt(
      receiptId: 'RCP-${const Uuid().v4().substring(0, 8).toUpperCase()}',
      transactionHash: response.transactionHash ?? '',
      merchantId: request.merchantId,
      merchantName: request.merchantName,
      amount: request.amount,
      currency: request.currency,
      orderId: request.orderId,
      userPublicKey: response.userPublicKey,
      userHandle: response.userHandle,
      timestamp: DateTime.now(),
      status: ReceiptStatus.confirmed,
      metadata: {
        'payment_mode': 'hce',
        'terminal_id': request.terminalId,
        'auth_code': response.authCode,
      },
    );
    
    await receipt.saveLocally();
    
    // TODO: Sync to backend
  }
  
  /// User approves payment
  void approvePayment() {
    _approvalCompleter?.complete(true);
  }
  
  /// User declines payment
  void declinePayment() {
    _approvalCompleter?.complete(false);
  }
  
  /// Update settings
  void updateSettings(HceSettings newSettings) {
    _settings = newSettings;
  }
  
  /// Enable HCE
  Future<void> enable() async {
    if (_state == HceState.disabled) {
      await _registerHceService();
      _updateState(HceState.ready);
    }
  }
  
  /// Disable HCE
  Future<void> disable() async {
    try {
      await _channel.invokeMethod('unregisterHceService');
    } catch (e) {
      debugPrint('Failed to unregister HCE: $e');
    }
    _updateState(HceState.disabled);
  }
  
  /// Update state
  void _updateState(HceState newState) {
    _state = newState;
    onStateChange?.call(newState);
    debugPrint('📱 HCE State: ${newState.name}');
  }
  
  /// Clean up
  Future<void> dispose() async {
    await _eventSubscription?.cancel();
    await disable();
    _wallet = null;
    _stellarService = null;
  }
}

/// HCE Payment Card Widget
/// Shows the virtual card for tap-to-pay
class HcePaymentCard {
  final String cardNumber;
  final String cardHolder;
  final String expiryDate;
  final String cardType;
  
  HcePaymentCard({
    required this.cardNumber,
    required this.cardHolder,
    required this.expiryDate,
    this.cardType = 'GNS',
  });
  
  /// Generate virtual card from GNS identity
  factory HcePaymentCard.fromWallet(IdentityWallet wallet) {
    final pk = wallet.publicKeyHex;
    
    // Generate card number from public key (not a real card number)
    final cardNum = '4747 ${pk.substring(0, 4)} ${pk.substring(4, 8)} ${pk.substring(8, 12)}'.toUpperCase();
    
    return HcePaymentCard(
      cardNumber: cardNum,
      cardHolder: 'GNS IDENTITY',
      expiryDate: '12/99',
      cardType: 'GNS',
    );
  }
  
  String get maskedNumber {
    return '•••• •••• •••• ${cardNumber.substring(cardNumber.length - 4)}';
  }
}
