/// GNS Refund Service - Sprint 6
/// 
/// Handles payment reversals, refund requests, and dispute management.
/// Supports both full and partial refunds via Stellar.
/// 
/// Refund flow:
/// 1. User or merchant initiates refund request
/// 2. System validates original transaction
/// 3. Refund executed on Stellar (merchant → user)
/// 4. Original receipt updated with refund status
/// 
/// Location: lib/core/financial/refund_service.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../gns/identity_wallet.dart';
import 'stellar_service.dart';
import 'payment_receipt.dart';

/// Refund status
enum RefundStatus {
  pending,
  approved,
  processing,
  completed,
  rejected,
  failed,
  cancelled,
}

/// Refund reason categories
enum RefundReason {
  customerRequest,
  duplicatePayment,
  incorrectAmount,
  productNotReceived,
  productDefective,
  serviceNotProvided,
  fraudulent,
  merchantInitiated,
  other,
}

/// Refund Request model
class RefundRequest {
  final String refundId;
  final String originalTransactionHash;
  final String originalReceiptId;
  final String merchantId;
  final String merchantName;
  final String userPublicKey;
  final double originalAmount;
  final double refundAmount;
  final String currency;
  final RefundReason reason;
  final String? reasonDetails;
  final RefundStatus status;
  final String? refundTransactionHash;
  final DateTime createdAt;
  final DateTime? processedAt;
  final String? processedBy;
  final String? rejectionReason;
  
  RefundRequest({
    required this.refundId,
    required this.originalTransactionHash,
    required this.originalReceiptId,
    required this.merchantId,
    required this.merchantName,
    required this.userPublicKey,
    required this.originalAmount,
    required this.refundAmount,
    required this.currency,
    required this.reason,
    this.reasonDetails,
    required this.status,
    this.refundTransactionHash,
    required this.createdAt,
    this.processedAt,
    this.processedBy,
    this.rejectionReason,
  });
  
  bool get isPartialRefund => refundAmount < originalAmount;
  bool get isPending => status == RefundStatus.pending;
  bool get isCompleted => status == RefundStatus.completed;
  bool get canCancel => status == RefundStatus.pending;
  
  double get refundPercentage => (refundAmount / originalAmount) * 100;
  
  String get formattedAmount {
    final symbol = _getCurrencySymbol(currency);
    return '$symbol${refundAmount.toStringAsFixed(2)}';
  }
  
  String get formattedOriginalAmount {
    final symbol = _getCurrencySymbol(currency);
    return '$symbol${originalAmount.toStringAsFixed(2)}';
  }
  
  static String _getCurrencySymbol(String currency) {
    const symbols = {
      'GNS': '🌐',
      'USDC': '\$',
      'EURC': '€',
      'XLM': '✨',
    };
    return symbols[currency] ?? currency;
  }
  
  Map<String, dynamic> toJson() => {
    'refund_id': refundId,
    'original_transaction_hash': originalTransactionHash,
    'original_receipt_id': originalReceiptId,
    'merchant_id': merchantId,
    'merchant_name': merchantName,
    'user_public_key': userPublicKey,
    'original_amount': originalAmount,
    'refund_amount': refundAmount,
    'currency': currency,
    'reason': reason.name,
    if (reasonDetails != null) 'reason_details': reasonDetails,
    'status': status.name,
    if (refundTransactionHash != null) 'refund_transaction_hash': refundTransactionHash,
    'created_at': createdAt.toIso8601String(),
    if (processedAt != null) 'processed_at': processedAt!.toIso8601String(),
    if (processedBy != null) 'processed_by': processedBy,
    if (rejectionReason != null) 'rejection_reason': rejectionReason,
  };
  
  factory RefundRequest.fromJson(Map<String, dynamic> json) {
    return RefundRequest(
      refundId: json['refund_id'] as String,
      originalTransactionHash: json['original_transaction_hash'] as String,
      originalReceiptId: json['original_receipt_id'] as String,
      merchantId: json['merchant_id'] as String,
      merchantName: json['merchant_name'] as String,
      userPublicKey: json['user_public_key'] as String,
      originalAmount: (json['original_amount'] as num).toDouble(),
      refundAmount: (json['refund_amount'] as num).toDouble(),
      currency: json['currency'] as String,
      reason: RefundReason.values.firstWhere(
        (r) => r.name == json['reason'],
        orElse: () => RefundReason.other,
      ),
      reasonDetails: json['reason_details'] as String?,
      status: RefundStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => RefundStatus.pending,
      ),
      refundTransactionHash: json['refund_transaction_hash'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      processedAt: json['processed_at'] != null 
          ? DateTime.parse(json['processed_at'] as String)
          : null,
      processedBy: json['processed_by'] as String?,
      rejectionReason: json['rejection_reason'] as String?,
    );
  }
  
  RefundRequest copyWith({
    RefundStatus? status,
    String? refundTransactionHash,
    DateTime? processedAt,
    String? processedBy,
    String? rejectionReason,
  }) {
    return RefundRequest(
      refundId: refundId,
      originalTransactionHash: originalTransactionHash,
      originalReceiptId: originalReceiptId,
      merchantId: merchantId,
      merchantName: merchantName,
      userPublicKey: userPublicKey,
      originalAmount: originalAmount,
      refundAmount: refundAmount,
      currency: currency,
      reason: reason,
      reasonDetails: reasonDetails,
      status: status ?? this.status,
      refundTransactionHash: refundTransactionHash ?? this.refundTransactionHash,
      createdAt: createdAt,
      processedAt: processedAt ?? this.processedAt,
      processedBy: processedBy ?? this.processedBy,
      rejectionReason: rejectionReason ?? this.rejectionReason,
    );
  }
}

/// Refund Service Result
class RefundResult {
  final bool success;
  final RefundRequest? refund;
  final String? error;
  final String? transactionHash;
  
  RefundResult({
    required this.success,
    this.refund,
    this.error,
    this.transactionHash,
  });
}

/// GNS Refund Service
class RefundService {
  static final RefundService _instance = RefundService._internal();
  factory RefundService() => _instance;
  RefundService._internal();
  
  static const _baseUrl = 'https://api.gns.network';
  static const _uuid = Uuid();
  
  IdentityWallet? _wallet;
  StellarService? _stellarService;
  final _receiptStorage = ReceiptStorage();
  
  /// Initialize service
  Future<void> initialize(IdentityWallet wallet) async {
    _wallet = wallet;
    _stellarService = StellarService();
  }
  
  /// Request a refund (user initiated)
  Future<RefundResult> requestRefund({
    required String receiptId,
    required RefundReason reason,
    String? reasonDetails,
    double? partialAmount,
  }) async {
    if (_wallet == null) {
      return RefundResult(success: false, error: 'Service not initialized');
    }
    
    try {
      // Load original receipt
      final receipt = await PaymentReceipt.loadLocally(receiptId);
      if (receipt == null) {
        return RefundResult(success: false, error: 'Receipt not found');
      }
      
      // Check if already refunded
      if (receipt.status == ReceiptStatus.refunded) {
        return RefundResult(success: false, error: 'Payment already refunded');
      }
      
      // Validate partial amount
      final refundAmount = partialAmount ?? receipt.amount;
      if (refundAmount > receipt.amount) {
        return RefundResult(success: false, error: 'Refund amount exceeds original payment');
      }
      if (refundAmount <= 0) {
        return RefundResult(success: false, error: 'Invalid refund amount');
      }
      
      // Create refund request
      final refundId = 'REF-${_uuid.v4().substring(0, 8).toUpperCase()}';
      final refundRequest = RefundRequest(
        refundId: refundId,
        originalTransactionHash: receipt.transactionHash,
        originalReceiptId: receipt.receiptId,
        merchantId: receipt.merchantId,
        merchantName: receipt.merchantName,
        userPublicKey: receipt.userPublicKey,
        originalAmount: receipt.amount,
        refundAmount: refundAmount,
        currency: receipt.currency,
        reason: reason,
        reasonDetails: reasonDetails,
        status: RefundStatus.pending,
        createdAt: DateTime.now(),
      );
      
      // Sign request
      final signature = await _signRefundRequest(refundRequest);
      
      // Submit to backend
      final response = await http.post(
        Uri.parse('$_baseUrl/refunds/request'),
        headers: {
          'Content-Type': 'application/json',
          'X-GNS-Public-Key': _wallet!.publicKeyHex,
          'X-GNS-Signature': signature,
        },
        body: jsonEncode(refundRequest.toJson()),
      );
      
      if (response.statusCode == 201) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final createdRefund = RefundRequest.fromJson(data['data']);
        
        debugPrint('🔄 Refund requested: ${createdRefund.refundId}');
        return RefundResult(success: true, refund: createdRefund);
      } else {
        final error = jsonDecode(response.body)['error'] ?? 'Failed to submit refund';
        return RefundResult(success: false, error: error);
      }
      
    } catch (e) {
      debugPrint('Refund request error: $e');
      return RefundResult(success: false, error: e.toString());
    }
  }
  
  /// Process refund (merchant/admin side)
  Future<RefundResult> processRefund({
    required String refundId,
    required bool approve,
    String? rejectionReason,
  }) async {
    if (_wallet == null || _stellarService == null) {
      return RefundResult(success: false, error: 'Service not initialized');
    }
    
    try {
      // Fetch refund details
      final refund = await getRefund(refundId);
      if (refund == null) {
        return RefundResult(success: false, error: 'Refund not found');
      }
      
      if (refund.status != RefundStatus.pending) {
        return RefundResult(success: false, error: 'Refund already processed');
      }
      
      if (!approve) {
        // Reject refund
        final response = await http.post(
          Uri.parse('$_baseUrl/refunds/$refundId/reject'),
          headers: {
            'Content-Type': 'application/json',
            'X-GNS-Public-Key': _wallet!.publicKeyHex,
          },
          body: jsonEncode({
            'rejection_reason': rejectionReason ?? 'Refund rejected by merchant',
          }),
        );
        
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body)['data'];
          return RefundResult(
            success: true,
            refund: RefundRequest.fromJson(data),
          );
        } else {
          return RefundResult(success: false, error: 'Failed to reject refund');
        }
      }
      
      // Approve and execute refund
      final response = await http.post(
        Uri.parse('$_baseUrl/refunds/$refundId/approve'),
        headers: {
          'Content-Type': 'application/json',
          'X-GNS-Public-Key': _wallet!.publicKeyHex,
        },
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'];
        final approvedRefund = RefundRequest.fromJson(data);
        
        debugPrint('✅ Refund approved: ${approvedRefund.refundId}');
        return RefundResult(
          success: true,
          refund: approvedRefund,
          transactionHash: approvedRefund.refundTransactionHash,
        );
      } else {
        final error = jsonDecode(response.body)['error'] ?? 'Failed to approve refund';
        return RefundResult(success: false, error: error);
      }
      
    } catch (e) {
      debugPrint('Process refund error: $e');
      return RefundResult(success: false, error: e.toString());
    }
  }
  
  /// Get refund details
  Future<RefundRequest?> getRefund(String refundId) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/refunds/$refundId'),
        headers: {
          'X-GNS-Public-Key': _wallet?.publicKeyHex ?? '',
        },
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'];
        return RefundRequest.fromJson(data);
      }
      return null;
    } catch (e) {
      debugPrint('Get refund error: $e');
      return null;
    }
  }
  
  /// Get user's refund requests
  Future<List<RefundRequest>> getUserRefunds({
    RefundStatus? status,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final queryParams = <String, String>{
        'limit': limit.toString(),
        'offset': offset.toString(),
      };
      if (status != null) {
        queryParams['status'] = status.name;
      }
      
      final uri = Uri.parse('$_baseUrl/refunds/user')
          .replace(queryParameters: queryParams);
      
      final response = await http.get(
        uri,
        headers: {
          'X-GNS-Public-Key': _wallet?.publicKeyHex ?? '',
        },
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'] as List;
        return data.map((r) => RefundRequest.fromJson(r)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('Get user refunds error: $e');
      return [];
    }
  }
  
  /// Get merchant's refund requests
  Future<List<RefundRequest>> getMerchantRefunds({
    required String merchantId,
    RefundStatus? status,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final queryParams = <String, String>{
        'merchant_id': merchantId,
        'limit': limit.toString(),
        'offset': offset.toString(),
      };
      if (status != null) {
        queryParams['status'] = status.name;
      }
      
      final uri = Uri.parse('$_baseUrl/refunds/merchant')
          .replace(queryParameters: queryParams);
      
      final response = await http.get(
        uri,
        headers: {
          'X-GNS-Public-Key': _wallet?.publicKeyHex ?? '',
        },
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'] as List;
        return data.map((r) => RefundRequest.fromJson(r)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('Get merchant refunds error: $e');
      return [];
    }
  }
  
  /// Cancel pending refund request
  Future<RefundResult> cancelRefund(String refundId) async {
    try {
      final refund = await getRefund(refundId);
      if (refund == null) {
        return RefundResult(success: false, error: 'Refund not found');
      }
      
      if (!refund.canCancel) {
        return RefundResult(success: false, error: 'Refund cannot be cancelled');
      }
      
      final response = await http.post(
        Uri.parse('$_baseUrl/refunds/$refundId/cancel'),
        headers: {
          'X-GNS-Public-Key': _wallet?.publicKeyHex ?? '',
        },
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'];
        return RefundResult(success: true, refund: RefundRequest.fromJson(data));
      } else {
        final error = jsonDecode(response.body)['error'] ?? 'Failed to cancel refund';
        return RefundResult(success: false, error: error);
      }
    } catch (e) {
      debugPrint('Cancel refund error: $e');
      return RefundResult(success: false, error: e.toString());
    }
  }
  
  /// Sign refund request
  Future<String> _signRefundRequest(RefundRequest request) async {
    if (_wallet == null) throw Exception('Wallet not initialized');
    
    final message = '${request.refundId}:${request.originalTransactionHash}:${request.refundAmount}';
    final signature = await _wallet!.sign(message);
    return signature;
  }
  
  /// Check if receipt is eligible for refund
  Future<RefundEligibility> checkRefundEligibility(String receiptId) async {
    try {
      final receipt = await PaymentReceipt.loadLocally(receiptId);
      if (receipt == null) {
        return RefundEligibility(
          eligible: false,
          reason: 'Receipt not found',
        );
      }
      
      // Check if already refunded
      if (receipt.status == ReceiptStatus.refunded) {
        return RefundEligibility(
          eligible: false,
          reason: 'Already refunded',
        );
      }
      
      // Check age (e.g., 90 day limit)
      final daysSincePayment = DateTime.now().difference(receipt.timestamp).inDays;
      if (daysSincePayment > 90) {
        return RefundEligibility(
          eligible: false,
          reason: 'Payment is older than 90 days',
        );
      }
      
      // Check pending refunds
      final pendingRefunds = await getUserRefunds(status: RefundStatus.pending);
      final hasPendingForReceipt = pendingRefunds.any(
        (r) => r.originalReceiptId == receiptId,
      );
      if (hasPendingForReceipt) {
        return RefundEligibility(
          eligible: false,
          reason: 'Refund request already pending',
        );
      }
      
      return RefundEligibility(
        eligible: true,
        maxRefundAmount: receipt.amount,
        originalAmount: receipt.amount,
        currency: receipt.currency,
      );
      
    } catch (e) {
      return RefundEligibility(
        eligible: false,
        reason: 'Error checking eligibility: $e',
      );
    }
  }
}

/// Refund eligibility check result
class RefundEligibility {
  final bool eligible;
  final String? reason;
  final double? maxRefundAmount;
  final double? originalAmount;
  final String? currency;
  
  RefundEligibility({
    required this.eligible,
    this.reason,
    this.maxRefundAmount,
    this.originalAmount,
    this.currency,
  });
}

/// Refund reason display helpers
extension RefundReasonExtension on RefundReason {
  String get displayName {
    switch (this) {
      case RefundReason.customerRequest:
        return 'Customer Request';
      case RefundReason.duplicatePayment:
        return 'Duplicate Payment';
      case RefundReason.incorrectAmount:
        return 'Incorrect Amount';
      case RefundReason.productNotReceived:
        return 'Product Not Received';
      case RefundReason.productDefective:
        return 'Product Defective';
      case RefundReason.serviceNotProvided:
        return 'Service Not Provided';
      case RefundReason.fraudulent:
        return 'Fraudulent Transaction';
      case RefundReason.merchantInitiated:
        return 'Merchant Initiated';
      case RefundReason.other:
        return 'Other';
    }
  }
  
  String get description {
    switch (this) {
      case RefundReason.customerRequest:
        return 'Customer requested cancellation or return';
      case RefundReason.duplicatePayment:
        return 'Payment was processed more than once';
      case RefundReason.incorrectAmount:
        return 'Charged amount was incorrect';
      case RefundReason.productNotReceived:
        return 'Customer did not receive the product';
      case RefundReason.productDefective:
        return 'Product was damaged or defective';
      case RefundReason.serviceNotProvided:
        return 'Service was not delivered as promised';
      case RefundReason.fraudulent:
        return 'Transaction was not authorized';
      case RefundReason.merchantInitiated:
        return 'Refund initiated by merchant';
      case RefundReason.other:
        return 'Other reason';
    }
  }
}

/// Refund status display helpers
extension RefundStatusExtension on RefundStatus {
  String get displayName {
    switch (this) {
      case RefundStatus.pending:
        return 'Pending';
      case RefundStatus.approved:
        return 'Approved';
      case RefundStatus.processing:
        return 'Processing';
      case RefundStatus.completed:
        return 'Completed';
      case RefundStatus.rejected:
        return 'Rejected';
      case RefundStatus.failed:
        return 'Failed';
      case RefundStatus.cancelled:
        return 'Cancelled';
    }
  }
  
  bool get isTerminal {
    return this == RefundStatus.completed ||
           this == RefundStatus.rejected ||
           this == RefundStatus.failed ||
           this == RefundStatus.cancelled;
  }
}
