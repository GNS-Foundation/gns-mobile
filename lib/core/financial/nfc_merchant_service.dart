/// GNS NFC Merchant Payment Service - Sprint 5
/// 
/// Handles NFC tap-to-pay flow for merchant transactions:
/// 1. Reads merchant payment request via NFC
/// 2. Validates request and user authorization
/// 3. Executes Stellar payment (GNS/USDC/EURC)
/// 4. Sends confirmation back via NFC response
/// 5. Generates digital receipt
/// 
/// Location: lib/core/financial/nfc_merchant_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

// Forward declarations for GNS types
import '../gns/identity_wallet.dart';
import 'stellar_service.dart';
import 'payment_receipt.dart';
import 'merchant_registry.dart';

/// NFC Payment Request from merchant terminal
class NfcPaymentRequest {
  final String requestId;
  final String merchantId;
  final String merchantName;
  final String merchantStellarAddress;
  final double amount;
  final String currency;  // GNS, USDC, EURC, XLM
  final String? memo;
  final String? orderId;
  final DateTime expiresAt;
  final String? h3Cell;  // Merchant location for GeoAuth
  final String signature;  // Merchant signature for verification
  
  NfcPaymentRequest({
    required this.requestId,
    required this.merchantId,
    required this.merchantName,
    required this.merchantStellarAddress,
    required this.amount,
    required this.currency,
    this.memo,
    this.orderId,
    required this.expiresAt,
    this.h3Cell,
    required this.signature,
  });
  
  bool get isExpired => DateTime.now().isAfter(expiresAt);
  
  /// Parse from NFC NDEF payload
  factory NfcPaymentRequest.fromNdefPayload(Uint8List payload) {
    try {
      final json = utf8.decode(payload);
      final data = jsonDecode(json) as Map<String, dynamic>;
      return NfcPaymentRequest.fromJson(data);
    } catch (e) {
      throw NfcPaymentException('Invalid payment request format: $e');
    }
  }
  
  factory NfcPaymentRequest.fromJson(Map<String, dynamic> json) {
    return NfcPaymentRequest(
      requestId: json['request_id'] as String,
      merchantId: json['merchant_id'] as String,
      merchantName: json['merchant_name'] as String,
      merchantStellarAddress: json['merchant_stellar_address'] as String,
      amount: (json['amount'] as num).toDouble(),
      currency: json['currency'] as String? ?? 'USDC',
      memo: json['memo'] as String?,
      orderId: json['order_id'] as String?,
      expiresAt: DateTime.parse(json['expires_at'] as String),
      h3Cell: json['h3_cell'] as String?,
      signature: json['signature'] as String,
    );
  }
  
  Map<String, dynamic> toJson() => {
    'request_id': requestId,
    'merchant_id': merchantId,
    'merchant_name': merchantName,
    'merchant_stellar_address': merchantStellarAddress,
    'amount': amount,
    'currency': currency,
    if (memo != null) 'memo': memo,
    if (orderId != null) 'order_id': orderId,
    'expires_at': expiresAt.toIso8601String(),
    if (h3Cell != null) 'h3_cell': h3Cell,
    'signature': signature,
  };
  
  String get formattedAmount {
    final symbols = {
      'GNS': '🌐',
      'USDC': '\$',
      'EURC': '€',
      'XLM': '✨',
    };
    final symbol = symbols[currency] ?? currency;
    return '$symbol${amount.toStringAsFixed(2)}';
  }
}

/// NFC Payment Response sent back to terminal
class NfcPaymentResponse {
  final String requestId;
  final bool success;
  final String? transactionHash;
  final String? error;
  final DateTime timestamp;
  final String userPublicKey;
  final String? userHandle;
  final String signature;
  
  NfcPaymentResponse({
    required this.requestId,
    required this.success,
    this.transactionHash,
    this.error,
    required this.timestamp,
    required this.userPublicKey,
    this.userHandle,
    required this.signature,
  });
  
  /// Serialize to NDEF payload for NFC response
  Uint8List toNdefPayload() {
    return Uint8List.fromList(utf8.encode(jsonEncode(toJson())));
  }
  
  Map<String, dynamic> toJson() => {
    'request_id': requestId,
    'success': success,
    if (transactionHash != null) 'transaction_hash': transactionHash,
    if (error != null) 'error': error,
    'timestamp': timestamp.toIso8601String(),
    'user_public_key': userPublicKey,
    if (userHandle != null) 'user_handle': userHandle,
    'signature': signature,
  };
}

/// Payment result from NFC transaction
class NfcPaymentResult {
  final bool success;
  final String? transactionHash;
  final String? error;
  final PaymentReceipt? receipt;
  final Duration? processingTime;
  
  NfcPaymentResult({
    required this.success,
    this.transactionHash,
    this.error,
    this.receipt,
    this.processingTime,
  });
}

/// Exception types for NFC payments
class NfcPaymentException implements Exception {
  final String message;
  final String? code;
  
  NfcPaymentException(this.message, {this.code});
  
  @override
  String toString() => 'NfcPaymentException: $message${code != null ? ' ($code)' : ''}';
}

/// NFC Payment States
enum NfcPaymentState {
  idle,
  scanning,
  requestReceived,
  processing,
  awaitingConfirmation,
  completed,
  failed,
}

/// Main NFC Merchant Service
class NfcMerchantService {
  static final NfcMerchantService _instance = NfcMerchantService._internal();
  factory NfcMerchantService() => _instance;
  NfcMerchantService._internal();
  
  // Dependencies
  IdentityWallet? _wallet;
  StellarService? _stellarService;
  MerchantRegistry? _merchantRegistry;
  
  // State
  NfcPaymentState _state = NfcPaymentState.idle;
  NfcPaymentRequest? _currentRequest;
  bool _isAvailable = false;
  
  // Platform channel for native NFC
  static const _nfcChannel = MethodChannel('gns.protocol/nfc');
  static const _nfcEventChannel = EventChannel('gns.protocol/nfc/events');
  
  // Stream controllers
  final _stateController = StreamController<NfcPaymentState>.broadcast();
  final _requestController = StreamController<NfcPaymentRequest>.broadcast();
  final _resultController = StreamController<NfcPaymentResult>.broadcast();
  
  // API configuration
  static const String _apiBase = 'https://gns-browser-production.up.railway.app';
  static const _uuid = Uuid();
  
  // Streams
  Stream<NfcPaymentState> get stateStream => _stateController.stream;
  Stream<NfcPaymentRequest> get requestStream => _requestController.stream;
  Stream<NfcPaymentResult> get resultStream => _resultController.stream;
  
  NfcPaymentState get state => _state;
  NfcPaymentRequest? get currentRequest => _currentRequest;
  bool get isAvailable => _isAvailable;
  
  /// Initialize the service
  Future<void> initialize({
    required IdentityWallet wallet,
  }) async {
    _wallet = wallet;
    _stellarService = StellarService();
    _merchantRegistry = MerchantRegistry();
    
    // Check NFC availability
    try {
      _isAvailable = await _nfcChannel.invokeMethod<bool>('isAvailable') ?? false;
      
      if (_isAvailable) {
        // Set up NFC event listener
        _nfcEventChannel.receiveBroadcastStream().listen(
          _handleNfcEvent,
          onError: (error) => debugPrint('NFC event error: $error'),
        );
      }
      
      debugPrint('📶 NFC Merchant Service initialized (available: $_isAvailable)');
    } catch (e) {
      debugPrint('NFC not available: $e');
      _isAvailable = false;
    }
  }
  
  /// Start scanning for NFC payment requests
  Future<void> startScanning() async {
    if (!_isAvailable) {
      throw NfcPaymentException('NFC not available', code: 'NFC_UNAVAILABLE');
    }
    
    if (_state != NfcPaymentState.idle) {
      throw NfcPaymentException('Already scanning or processing', code: 'BUSY');
    }
    
    try {
      await _nfcChannel.invokeMethod('startSession', {
        'alertMessage': 'Hold your phone near the payment terminal',
        'pollingOptions': ['iso14443', 'iso15693'],
      });
      
      _setState(NfcPaymentState.scanning);
      debugPrint('📶 NFC scanning started');
    } catch (e) {
      throw NfcPaymentException('Failed to start NFC: $e', code: 'START_FAILED');
    }
  }
  
  /// Stop NFC scanning
  Future<void> stopScanning() async {
    try {
      await _nfcChannel.invokeMethod('stopSession');
      _setState(NfcPaymentState.idle);
      _currentRequest = null;
      debugPrint('📶 NFC scanning stopped');
    } catch (e) {
      debugPrint('Error stopping NFC: $e');
    }
  }
  
  /// Handle incoming NFC events from platform
  void _handleNfcEvent(dynamic event) {
    if (event is! Map) return;
    
    final eventType = event['type'] as String?;
    final payload = event['payload'] as List<int>?;
    
    switch (eventType) {
      case 'tagDiscovered':
        _handleTagDiscovered(payload);
        break;
      case 'sessionClosed':
        if (_state == NfcPaymentState.scanning) {
          _setState(NfcPaymentState.idle);
        }
        break;
      case 'error':
        final error = event['error'] as String?;
        debugPrint('NFC error: $error');
        break;
    }
  }
  
  /// Handle discovered NFC tag
  Future<void> _handleTagDiscovered(List<int>? payload) async {
    if (payload == null || payload.isEmpty) {
      debugPrint('Empty NFC payload');
      return;
    }
    
    try {
      // Parse payment request from NDEF
      final request = NfcPaymentRequest.fromNdefPayload(Uint8List.fromList(payload));
      
      // Validate request
      await _validateRequest(request);
      
      // Store current request and notify
      _currentRequest = request;
      _setState(NfcPaymentState.requestReceived);
      _requestController.add(request);
      
      debugPrint('💳 Payment request received: ${request.formattedAmount} to ${request.merchantName}');
      
    } catch (e) {
      debugPrint('Error parsing payment request: $e');
      _resultController.add(NfcPaymentResult(
        success: false,
        error: e.toString(),
      ));
    }
  }
  
  /// Validate payment request
  Future<void> _validateRequest(NfcPaymentRequest request) async {
    // Check expiration
    if (request.isExpired) {
      throw NfcPaymentException('Payment request expired', code: 'EXPIRED');
    }
    
    // Verify merchant is registered
    if (_merchantRegistry != null) {
      final merchant = await _merchantRegistry!.getMerchant(request.merchantId);
      if (merchant == null) {
        throw NfcPaymentException('Unknown merchant', code: 'UNKNOWN_MERCHANT');
      }
      if (merchant.status != 'active') {
        throw NfcPaymentException('Merchant not active', code: 'INACTIVE_MERCHANT');
      }
    }
    
    // Validate Stellar address format
    if (!_isValidStellarAddress(request.merchantStellarAddress)) {
      throw NfcPaymentException('Invalid merchant Stellar address', code: 'INVALID_ADDRESS');
    }
    
    // TODO: Verify merchant signature
  }
  
  /// Execute payment for current request
  Future<NfcPaymentResult> executePayment({
    bool requireBiometric = true,
  }) async {
    final request = _currentRequest;
    if (request == null) {
      throw NfcPaymentException('No payment request', code: 'NO_REQUEST');
    }
    
    if (_wallet == null || _stellarService == null) {
      throw NfcPaymentException('Service not initialized', code: 'NOT_INITIALIZED');
    }
    
    final startTime = DateTime.now();
    _setState(NfcPaymentState.processing);
    
    try {
      // Get user's Stellar credentials
      final userPublicKey = _wallet!.publicKey;
      final userPrivateKeyBytes = _wallet!.privateKeyBytes;
      
      if (userPublicKey == null || userPrivateKeyBytes == null) {
        throw NfcPaymentException('Wallet not unlocked', code: 'WALLET_LOCKED');
      }
      
      // Convert GNS key to Stellar address
      final userStellarAddress = _stellarService!.gnsKeyToStellar(userPublicKey);
      
      // Execute the appropriate payment based on currency
      TransactionResult result;
      
      switch (request.currency.toUpperCase()) {
        case 'GNS':
          result = await _sendGnsPayment(
            userStellarAddress: userStellarAddress,
            userPrivateKeyBytes: userPrivateKeyBytes,
            merchantAddress: request.merchantStellarAddress,
            amount: request.amount,
            memo: request.memo ?? 'GNS Pay: ${request.orderId ?? request.requestId}',
          );
          break;
          
        case 'USDC':
        case 'EURC':
        case 'XLM':
          result = await _sendStellarPayment(
            userStellarAddress: userStellarAddress,
            userPrivateKeyBytes: userPrivateKeyBytes,
            merchantAddress: request.merchantStellarAddress,
            amount: request.amount,
            assetCode: request.currency,
            memo: request.memo ?? 'GNS Pay: ${request.orderId ?? request.requestId}',
          );
          break;
          
        default:
          throw NfcPaymentException('Unsupported currency: ${request.currency}', code: 'UNSUPPORTED_CURRENCY');
      }
      
      final processingTime = DateTime.now().difference(startTime);
      
      if (result.success) {
        // Generate receipt
        final receipt = await _generateReceipt(
          request: request,
          transactionHash: result.hash!,
          userPublicKey: userPublicKey,
        );
        
        // Send confirmation to backend
        await _notifyBackend(
          request: request,
          transactionHash: result.hash!,
          userPublicKey: userPublicKey,
        );
        
        // Send NFC response to terminal
        await _sendNfcResponse(
          request: request,
          success: true,
          transactionHash: result.hash,
        );
        
        _setState(NfcPaymentState.completed);
        
        final paymentResult = NfcPaymentResult(
          success: true,
          transactionHash: result.hash,
          receipt: receipt,
          processingTime: processingTime,
        );
        
        _resultController.add(paymentResult);
        debugPrint('✅ Payment successful: ${result.hash}');
        
        return paymentResult;
        
      } else {
        throw NfcPaymentException(result.error ?? 'Payment failed', code: 'PAYMENT_FAILED');
      }
      
    } catch (e) {
      _setState(NfcPaymentState.failed);
      
      // Send failure response to terminal
      await _sendNfcResponse(
        request: request,
        success: false,
        error: e.toString(),
      );
      
      final paymentResult = NfcPaymentResult(
        success: false,
        error: e.toString(),
        processingTime: DateTime.now().difference(startTime),
      );
      
      _resultController.add(paymentResult);
      debugPrint('❌ Payment failed: $e');
      
      return paymentResult;
    }
  }
  
  /// Send GNS token payment
  Future<TransactionResult> _sendGnsPayment({
    required String userStellarAddress,
    required Uint8List userPrivateKeyBytes,
    required String merchantAddress,
    required double amount,
    String? memo,
  }) async {
    return await _stellarService!.sendGns(
      senderStellarPublicKey: userStellarAddress,
      senderPrivateKeyBytes: userPrivateKeyBytes,
      recipientStellarPublicKey: merchantAddress,
      amount: amount,
    );
  }
  
  /// Send Stellar payment (XLM, USDC, EURC)
  Future<TransactionResult> _sendStellarPayment({
    required String userStellarAddress,
    required Uint8List userPrivateKeyBytes,
    required String merchantAddress,
    required double amount,
    required String assetCode,
    String? memo,
  }) async {
    // This would use the Stellar SDK to send the appropriate asset
    // For now, delegate to backend for stablecoin handling
    
    final response = await http.post(
      Uri.parse('$_apiBase/merchant/settle'),
      headers: {
        'Content-Type': 'application/json',
        'X-GNS-PublicKey': _wallet!.publicKey!,
      },
      body: jsonEncode({
        'from_stellar_address': userStellarAddress,
        'to_stellar_address': merchantAddress,
        'amount': amount.toString(),
        'asset_code': assetCode,
        'memo': memo,
        // Signed authorization would go here in production
        'user_signature': 'pending_implementation',
      }),
    );
    
    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        return TransactionResult(
          success: true,
          hash: data['data']['transaction_hash'] as String?,
        );
      }
    }
    
    final errorData = jsonDecode(response.body);
    return TransactionResult(
      success: false,
      error: errorData['error'] as String? ?? 'Settlement failed',
    );
  }
  
  /// Generate payment receipt
  Future<PaymentReceipt> _generateReceipt({
    required NfcPaymentRequest request,
    required String transactionHash,
    required String userPublicKey,
  }) async {
    final receipt = PaymentReceipt(
      receiptId: _uuid.v4(),
      transactionHash: transactionHash,
      merchantId: request.merchantId,
      merchantName: request.merchantName,
      amount: request.amount,
      currency: request.currency,
      orderId: request.orderId,
      userPublicKey: userPublicKey,
      timestamp: DateTime.now(),
      status: ReceiptStatus.confirmed,
    );
    
    // Store receipt locally
    await receipt.saveLocally();
    
    // Upload to backend
    await _uploadReceipt(receipt);
    
    return receipt;
  }
  
  /// Upload receipt to backend
  Future<void> _uploadReceipt(PaymentReceipt receipt) async {
    try {
      await http.post(
        Uri.parse('$_apiBase/receipts/store'),
        headers: {
          'Content-Type': 'application/json',
          'X-GNS-PublicKey': _wallet!.publicKey!,
        },
        body: jsonEncode(receipt.toJson()),
      );
    } catch (e) {
      debugPrint('Warning: Failed to upload receipt: $e');
      // Non-fatal - receipt is stored locally
    }
  }
  
  /// Notify backend of completed transaction
  Future<void> _notifyBackend({
    required NfcPaymentRequest request,
    required String transactionHash,
    required String userPublicKey,
  }) async {
    try {
      await http.post(
        Uri.parse('$_apiBase/merchant/payment-complete'),
        headers: {
          'Content-Type': 'application/json',
          'X-GNS-PublicKey': userPublicKey,
        },
        body: jsonEncode({
          'request_id': request.requestId,
          'merchant_id': request.merchantId,
          'transaction_hash': transactionHash,
          'amount': request.amount,
          'currency': request.currency,
          'order_id': request.orderId,
          'completed_at': DateTime.now().toIso8601String(),
        }),
      );
    } catch (e) {
      debugPrint('Warning: Failed to notify backend: $e');
      // Non-fatal - transaction is on-chain
    }
  }
  
  /// Send NFC response back to terminal
  Future<void> _sendNfcResponse({
    required NfcPaymentRequest request,
    required bool success,
    String? transactionHash,
    String? error,
  }) async {
    if (!_isAvailable) return;
    
    try {
      final userPublicKey = _wallet?.publicKey ?? '';
      final userHandle = await _wallet?.getCurrentHandle();
      
      // Create signature for response
      final responseData = '$request.requestId:$success:${transactionHash ?? 'null'}';
      final signatureBytes = await _wallet?.signBytes(
        Uint8List.fromList(utf8.encode(responseData)),
      );
      final signature = signatureBytes != null ? base64Encode(signatureBytes) : '';
      
      final response = NfcPaymentResponse(
        requestId: request.requestId,
        success: success,
        transactionHash: transactionHash,
        error: error,
        timestamp: DateTime.now(),
        userPublicKey: userPublicKey,
        userHandle: userHandle,
        signature: signature,
      );
      
      await _nfcChannel.invokeMethod('sendResponse', {
        'payload': response.toNdefPayload(),
      });
      
    } catch (e) {
      debugPrint('Warning: Failed to send NFC response: $e');
    }
  }
  
  /// Cancel current payment
  void cancelPayment() {
    _currentRequest = null;
    _setState(NfcPaymentState.idle);
    stopScanning();
  }
  
  /// Reset to idle state
  void reset() {
    _currentRequest = null;
    _setState(NfcPaymentState.idle);
  }
  
  void _setState(NfcPaymentState newState) {
    _state = newState;
    _stateController.add(newState);
  }
  
  bool _isValidStellarAddress(String address) {
    return address.length == 56 && address.startsWith('G');
  }
  
  /// Dispose resources
  void dispose() {
    stopScanning();
    _stateController.close();
    _requestController.close();
    _resultController.close();
  }
}

/// Extension for Stellar Service to add specific payment methods
extension StellarMerchantPayments on StellarService {
  /// Send USDC payment via Stellar
  Future<TransactionResult> sendUsdc({
    required String senderStellarPublicKey,
    required Uint8List senderPrivateKeyBytes,
    required String recipientStellarPublicKey,
    required double amount,
    String? memo,
  }) async {
    // USDC on Stellar configuration
    const usdcIssuer = 'GA5ZSEJYB37JRC5AVCIA5MOP4RHTM335X2KGX3IHOJAPP5RE34K4KZVN'; // Circle USDC issuer
    
    return _sendAsset(
      senderStellarPublicKey: senderStellarPublicKey,
      senderPrivateKeyBytes: senderPrivateKeyBytes,
      recipientStellarPublicKey: recipientStellarPublicKey,
      amount: amount,
      assetCode: 'USDC',
      assetIssuer: usdcIssuer,
      memo: memo,
    );
  }
  
  /// Send EURC payment via Stellar
  Future<TransactionResult> sendEurc({
    required String senderStellarPublicKey,
    required Uint8List senderPrivateKeyBytes,
    required String recipientStellarPublicKey,
    required double amount,
    String? memo,
  }) async {
    // EURC on Stellar configuration  
    const eurcIssuer = 'GDHU6WRG4IEQXM5NZ4BMPKOXHW76MZM4Y2IEMFDVXBSDP6SJY4ITNPP2'; // Circle EURC issuer
    
    return _sendAsset(
      senderStellarPublicKey: senderStellarPublicKey,
      senderPrivateKeyBytes: senderPrivateKeyBytes,
      recipientStellarPublicKey: recipientStellarPublicKey,
      amount: amount,
      assetCode: 'EURC',
      assetIssuer: eurcIssuer,
      memo: memo,
    );
  }
  
  /// Generic asset send (placeholder - implement with Stellar SDK)
  Future<TransactionResult> _sendAsset({
    required String senderStellarPublicKey,
    required Uint8List senderPrivateKeyBytes,
    required String recipientStellarPublicKey,
    required double amount,
    required String assetCode,
    required String assetIssuer,
    String? memo,
  }) async {
    // Implementation would use stellar_flutter_sdk similar to sendGns
    // For now, return placeholder
    return TransactionResult(
      success: false,
      error: 'Direct asset send not yet implemented - use backend settlement',
    );
  }
}
