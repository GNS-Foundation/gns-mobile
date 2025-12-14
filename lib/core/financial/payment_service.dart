/// GNS Payment Service
/// 
/// Handles payment operations, polling, and transaction management.
/// Location: lib/core/financial/payment_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../gns/identity_wallet.dart';
import 'financial_module.dart';
import 'transaction_storage.dart';
import 'payment_payload.dart';
import 'idup_router.dart';

/// Incoming payment notification
class IncomingPayment {
  final String id;
  final String senderPk;
  final String? senderHandle;
  final String amount;
  final String currency;
  final String? memo;
  final DateTime createdAt;
  final Map<String, dynamic> rawPayload;

  IncomingPayment({
    required this.id,
    required this.senderPk,
    this.senderHandle,
    required this.amount,
    required this.currency,
    this.memo,
    required this.createdAt,
    required this.rawPayload,
  });

  String get senderDisplay => senderHandle != null ? '@$senderHandle' : '${senderPk.substring(0, 8)}...';
  
  String get amountFormatted {
    final symbol = _currencySymbols[currency.toUpperCase()] ?? currency;
    return '$symbol$amount';
  }

  static const _currencySymbols = {
    'EUR': '€',
    'USD': '\$',
    'GBP': '£',
    'BTC': '₿',
    'ETH': 'Ξ',
  };

  factory IncomingPayment.fromJson(Map<String, dynamic> json) {
    final payload = json['payload'] as Map<String, dynamic>? ?? {};
    return IncomingPayment(
      id: json['id'] as String? ?? '',
      senderPk: json['sender_pk'] as String? ?? json['from_public_key'] as String? ?? '',
      senderHandle: json['sender_handle'] as String? ?? json['from_handle'] as String?,
      amount: payload['amount']?.toString() ?? json['amount']?.toString() ?? '0',
      currency: payload['currency'] as String? ?? json['currency'] as String? ?? 'EUR',
      memo: payload['memo'] as String? ?? json['memo'] as String?,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      rawPayload: json,
    );
  }
}

/// Payment send result
class PaymentSendResult {
  final bool success;
  final String? transactionId;
  final String? error;
  final GnsTransaction? transaction;

  PaymentSendResult({
    required this.success,
    this.transactionId,
    this.error,
    this.transaction,
  });
}

/// Payment acknowledgment result
class PaymentAckResult {
  final bool success;
  final String? error;

  PaymentAckResult({required this.success, this.error});
}

/// Main payment service
class PaymentService {
  static PaymentService? _instance;
  static const _uuid = Uuid();
  
  final IdentityWallet _wallet;
  TransactionStorage? _transactionStorage;
  
  FinancialData? _financialData;
  Timer? _pollingTimer;
  bool _isPolling = false;
  bool _initialized = false;
  
  // Stream controllers
  final _incomingPaymentsController = StreamController<IncomingPayment>.broadcast();
  final _transactionUpdatesController = StreamController<GnsTransaction>.broadcast();
  
  // API configuration
  static const String _baseUrl = 'https://gns-server-production.up.railway.app';
  
  PaymentService._(this._wallet);
  
  /// Get singleton instance
  static PaymentService instance(IdentityWallet wallet) {
    _instance ??= PaymentService._(wallet);
    return _instance!;
  }
  
  /// Streams
  Stream<IncomingPayment> get incomingPayments => _incomingPaymentsController.stream;
  Stream<GnsTransaction> get transactionUpdates => _transactionUpdatesController.stream;
  
  /// Get financial data
  FinancialData? get myFinancialData => _financialData;
  
  /// Initialize the payment service
  Future<void> initialize() async {
    if (_initialized) return;
    
    // Initialize transaction storage with wallet's private key
    final privateKey = _wallet.privateKeyBytes;
    if (privateKey != null) {
      _transactionStorage = TransactionStorage();
      await _transactionStorage!.initialize(privateKey);
    }
    
    await _loadFinancialData();
    _initialized = true;
    debugPrint('💰 PaymentService initialized');
  }
  
  /// Load or create financial data
  Future<void> _loadFinancialData() async {
    // Try to load from wallet's local record
    final record = _wallet.localRecord;
    if (record != null) {
      _financialData = FinancialModule.fromRecord(record);
    }
    
    // Create default if none exists
    _financialData ??= FinancialData();
  }
  
  /// Start polling for incoming payments
  void startPolling({Duration interval = const Duration(seconds: 30)}) {
    if (_isPolling) return;
    _isPolling = true;
    
    _fetchIncomingPayments();
    
    _pollingTimer = Timer.periodic(interval, (_) {
      _fetchIncomingPayments();
    });
    
    debugPrint('📡 Payment polling started (${interval.inSeconds}s interval)');
  }
  
  /// Stop polling
  void stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _isPolling = false;
    debugPrint('📡 Payment polling stopped');
  }
  
  /// Fetch incoming payments from server
  Future<void> _fetchIncomingPayments() async {
    try {
      final pk = _wallet.publicKey;
      if (pk == null) return;
      
      final response = await http.get(
        Uri.parse('$_baseUrl/payments/inbox?recipient_pk=$pk'),
        headers: {'Content-Type': 'application/json'},
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final payments = (data['payments'] as List? ?? [])
            .map((p) => IncomingPayment.fromJson(p as Map<String, dynamic>))
            .toList();
        
        for (final payment in payments) {
          _incomingPaymentsController.add(payment);
        }
      }
    } catch (e) {
      debugPrint('Error fetching incoming payments: $e');
    }
  }
  
  /// Get pending incoming payments
  Future<List<IncomingPayment>> getPendingIncoming() async {
    try {
      final pk = _wallet.publicKey;
      if (pk == null) return [];
      
      final response = await http.get(
        Uri.parse('$_baseUrl/payments/inbox?recipient_pk=$pk&status=pending'),
        headers: {'Content-Type': 'application/json'},
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return (data['payments'] as List? ?? [])
            .map((p) => IncomingPayment.fromJson(p as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint('Error fetching pending payments: $e');
    }
    return [];
  }
  
  /// Send a payment
  Future<PaymentSendResult> sendPayment({
    required String recipientPk,
    String? recipientHandle,
    required String amount,
    required String currency,
    String? memo,
    PaymentRoute? route,
  }) async {
    try {
      final senderPk = _wallet.publicKey;
      if (senderPk == null) {
        return PaymentSendResult(success: false, error: 'Wallet not initialized');
      }
      
      final paymentId = _uuid.v4();
      final now = DateTime.now();
      
      // Create payment payload
      final payloadRoute = route ?? PaymentRoute(
        type: 'direct',
        endpointId: 'default',
      );
      
      final payload = PaymentTransferPayload(
        paymentId: paymentId,
        fromPublicKey: senderPk,
        toPublicKey: recipientPk,
        amount: amount,
        currency: currency,
        memo: memo,
        route: payloadRoute,
        createdAt: now.millisecondsSinceEpoch,
      );
      
      // Sign the payload
      final payloadJson = jsonEncode(payload.toJson());
      final payloadBytes = Uint8List.fromList(utf8.encode(payloadJson));
      final signatureBytes = await _wallet.signBytes(payloadBytes);
      final signature = signatureBytes != null ? base64Encode(signatureBytes) : '';
      
      // Get sender handle
      final senderHandle = await _wallet.getCurrentHandle();
      
      // Send to server
      final response = await http.post(
        Uri.parse('$_baseUrl/payments/send'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'payload': payload.toJson(),
          'signature': signature,
          'sender_handle': senderHandle,
          'recipient_handle': recipientHandle,
        }),
      );
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        final txId = data['transaction_id'] as String? ?? paymentId;
        
        // Create local transaction record
        final transaction = GnsTransaction(
          id: txId,
          fromPublicKey: senderPk,
          fromHandle: senderHandle,
          toPublicKey: recipientPk,
          toHandle: recipientHandle,
          amount: amount,
          currency: currency,
          memo: memo,
          routeType: payloadRoute.type,
          status: TransactionStatus.pending,
          direction: TransactionDirection.outgoing,
          createdAt: now,
          updatedAt: now,
        );
        
        // Save locally
        if (_transactionStorage != null) {
          await _transactionStorage!.saveTransaction(transaction);
        }
        _transactionUpdatesController.add(transaction);
        
        return PaymentSendResult(
          success: true,
          transactionId: txId,
          transaction: transaction,
        );
      } else {
        final errorData = jsonDecode(response.body);
        final error = errorData['error'] ?? 'Send failed';
        return PaymentSendResult(success: false, error: error.toString());
      }
    } catch (e) {
      debugPrint('Error sending payment: $e');
      return PaymentSendResult(success: false, error: e.toString());
    }
  }
  
  /// Acknowledge (accept/decline) an incoming payment
  Future<PaymentAckResult> acknowledgePayment({
    required String paymentId,
    required bool accept,
    String? declineReason,
  }) async {
    try {
      final pk = _wallet.publicKey;
      if (pk == null) {
        return PaymentAckResult(success: false, error: 'Wallet not initialized');
      }
      
      final response = await http.post(
        Uri.parse('$_baseUrl/payments/acknowledge'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'payment_id': paymentId,
          'recipient_pk': pk,
          'action': accept ? 'accept' : 'decline',
          'decline_reason': declineReason,
          'timestamp': DateTime.now().toIso8601String(),
        }),
      );
      
      if (response.statusCode == 200) {
        // Update local transaction if exists
        if (_transactionStorage != null) {
          await _transactionStorage!.updateStatus(
            paymentId,
            accept ? TransactionStatus.accepted : TransactionStatus.rejected,
          );
        }
        return PaymentAckResult(success: true);
      } else {
        final errorData = jsonDecode(response.body);
        final error = errorData['error'] ?? 'Acknowledgment failed';
        return PaymentAckResult(success: false, error: error.toString());
      }
    } catch (e) {
      debugPrint('Error acknowledging payment: $e');
      return PaymentAckResult(success: false, error: e.toString());
    }
  }
  
  /// Get transactions with optional filters
  Future<List<GnsTransaction>> getTransactions({
    TransactionDirection? direction,
    TransactionStatus? status,
    int limit = 50,
    int offset = 0,
  }) async {
    if (_transactionStorage == null) return [];
    
    return _transactionStorage!.getTransactions(
      direction: direction,
      status: status,
      limit: limit,
      offset: offset,
    );
  }
  
  /// Get total sent today
  Future<double> getTotalSentToday({String currency = 'EUR'}) async {
    if (_transactionStorage == null) return 0.0;
    
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    
    return await _transactionStorage!.getTotalSent(
      since: startOfDay,
      currency: currency,
    );
  }
  
  /// Get total received today
  Future<double> getTotalReceivedToday({String currency = 'EUR'}) async {
    if (_transactionStorage == null) return 0.0;
    
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    
    return await _transactionStorage!.getTotalReceived(
      since: startOfDay,
      currency: currency,
    );
  }
  
  /// Save financial data settings
  Future<void> saveFinancialData(FinancialData data) async {
    _financialData = data;
    // TODO: Persist to GNS record
    debugPrint('💾 Financial data saved');
  }
  
  /// Calculate route for a payment (using IdupRouter)
  RouteResult? calculateRoute({
    required String recipientPk,
    required String amount,
    required String currency,
    FinancialData? recipientFinancial,
  }) {
    // If we don't have recipient's financial data, return null
    if (recipientFinancial == null || recipientFinancial.paymentEndpoints.isEmpty) {
      return null;
    }
    
    final result = IdupRouter.selectRoute(
      senderFinancial: _financialData,
      recipientFinancial: recipientFinancial,
      amount: double.parse(amount),
      currency: currency,
    );
    
    if (result is RouteResult) {
      return result;
    }
    
    return null;
  }
  
  /// Dispose resources
  void dispose() {
    stopPolling();
    _incomingPaymentsController.close();
    _transactionUpdatesController.close();
    _transactionStorage?.close();
  }
}
