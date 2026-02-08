/// GNS Payment Link Service - Sprint 8
/// 
/// Creates and manages shareable payment links.
/// 
/// Features:
/// - One-time and reusable links
/// - Fixed or variable amounts
/// - QR code generation
/// - Link analytics
/// - Expiration control
/// 
/// Location: lib/core/financial/payment_link_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Payment link type
enum PaymentLinkType {
  oneTime,     // Single use, deactivates after payment
  reusable,    // Can be paid multiple times
  subscription, // Creates subscription on payment
}

/// Payment link status
enum PaymentLinkStatus {
  active,
  inactive,
  expired,
  completed,  // One-time link that was paid
}

/// Payment link model
class PaymentLink {
  final String linkId;
  final String shortCode;
  final String merchantId;
  final String? merchantName;
  final PaymentLinkType type;
  final PaymentLinkStatus status;
  
  // Amount configuration
  final double? fixedAmount;
  final double? minAmount;
  final double? maxAmount;
  final String currency;
  final bool allowCustomAmount;
  
  // Display
  final String? title;
  final String? description;
  final String? imageUrl;
  final String? successMessage;
  final String? redirectUrl;
  
  // Settings
  final DateTime? expiresAt;
  final int? maxPayments;
  final bool collectEmail;
  final bool collectPhone;
  final bool collectAddress;
  final Map<String, dynamic>? metadata;
  
  // Stats
  final int viewCount;
  final int paymentCount;
  final double totalCollected;
  
  // Timestamps
  final DateTime createdAt;
  final DateTime? lastPaymentAt;
  
  PaymentLink({
    required this.linkId,
    required this.shortCode,
    required this.merchantId,
    this.merchantName,
    required this.type,
    required this.status,
    this.fixedAmount,
    this.minAmount,
    this.maxAmount,
    required this.currency,
    this.allowCustomAmount = false,
    this.title,
    this.description,
    this.imageUrl,
    this.successMessage,
    this.redirectUrl,
    this.expiresAt,
    this.maxPayments,
    this.collectEmail = false,
    this.collectPhone = false,
    this.collectAddress = false,
    this.metadata,
    this.viewCount = 0,
    this.paymentCount = 0,
    this.totalCollected = 0,
    required this.createdAt,
    this.lastPaymentAt,
  });
  
  /// Full URL
  String get url => 'https://pay.gns.network/$shortCode';
  
  /// QR code data
  String get qrData => url;
  
  /// Check if link is usable
  bool get isUsable {
    if (status != PaymentLinkStatus.active) return false;
    if (expiresAt != null && DateTime.now().isAfter(expiresAt!)) return false;
    if (type == PaymentLinkType.oneTime && paymentCount > 0) return false;
    if (maxPayments != null && paymentCount >= maxPayments!) return false;
    return true;
  }
  
  /// Display amount
  String get displayAmount {
    if (fixedAmount != null) {
      return _formatCurrency(fixedAmount!, currency);
    }
    if (minAmount != null && maxAmount != null) {
      return '${_formatCurrency(minAmount!, currency)} - ${_formatCurrency(maxAmount!, currency)}';
    }
    if (minAmount != null) {
      return 'Min ${_formatCurrency(minAmount!, currency)}';
    }
    return 'Any amount';
  }
  
  static String _formatCurrency(double amount, String currency) {
    const symbols = {'USDC': '\$', 'EURC': '€', 'GNS': '🌐', 'XLM': '✨'};
    final symbol = symbols[currency] ?? currency;
    return '$symbol${amount.toStringAsFixed(2)}';
  }
  
  factory PaymentLink.fromJson(Map<String, dynamic> json) {
    return PaymentLink(
      linkId: json['link_id'] as String,
      shortCode: json['short_code'] as String,
      merchantId: json['merchant_id'] as String,
      merchantName: json['merchant_name'] as String?,
      type: PaymentLinkType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => PaymentLinkType.oneTime,
      ),
      status: PaymentLinkStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => PaymentLinkStatus.active,
      ),
      fixedAmount: (json['fixed_amount'] as num?)?.toDouble(),
      minAmount: (json['min_amount'] as num?)?.toDouble(),
      maxAmount: (json['max_amount'] as num?)?.toDouble(),
      currency: json['currency'] as String? ?? 'USDC',
      allowCustomAmount: json['allow_custom_amount'] as bool? ?? false,
      title: json['title'] as String?,
      description: json['description'] as String?,
      imageUrl: json['image_url'] as String?,
      successMessage: json['success_message'] as String?,
      redirectUrl: json['redirect_url'] as String?,
      expiresAt: json['expires_at'] != null
          ? DateTime.parse(json['expires_at'] as String)
          : null,
      maxPayments: json['max_payments'] as int?,
      collectEmail: json['collect_email'] as bool? ?? false,
      collectPhone: json['collect_phone'] as bool? ?? false,
      collectAddress: json['collect_address'] as bool? ?? false,
      metadata: json['metadata'] as Map<String, dynamic>?,
      viewCount: json['view_count'] as int? ?? 0,
      paymentCount: json['payment_count'] as int? ?? 0,
      totalCollected: (json['total_collected'] as num?)?.toDouble() ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
      lastPaymentAt: json['last_payment_at'] != null
          ? DateTime.parse(json['last_payment_at'] as String)
          : null,
    );
  }
  
  Map<String, dynamic> toJson() => {
    'link_id': linkId,
    'short_code': shortCode,
    'merchant_id': merchantId,
    if (merchantName != null) 'merchant_name': merchantName,
    'type': type.name,
    'status': status.name,
    if (fixedAmount != null) 'fixed_amount': fixedAmount,
    if (minAmount != null) 'min_amount': minAmount,
    if (maxAmount != null) 'max_amount': maxAmount,
    'currency': currency,
    'allow_custom_amount': allowCustomAmount,
    if (title != null) 'title': title,
    if (description != null) 'description': description,
    if (imageUrl != null) 'image_url': imageUrl,
    if (successMessage != null) 'success_message': successMessage,
    if (redirectUrl != null) 'redirect_url': redirectUrl,
    if (expiresAt != null) 'expires_at': expiresAt!.toIso8601String(),
    if (maxPayments != null) 'max_payments': maxPayments,
    'collect_email': collectEmail,
    'collect_phone': collectPhone,
    'collect_address': collectAddress,
    if (metadata != null) 'metadata': metadata,
    'view_count': viewCount,
    'payment_count': paymentCount,
    'total_collected': totalCollected,
    'created_at': createdAt.toIso8601String(),
    if (lastPaymentAt != null) 'last_payment_at': lastPaymentAt!.toIso8601String(),
  };
}

/// Payment via link record
class LinkPayment {
  final String paymentId;
  final String linkId;
  final String payerPublicKey;
  final String? payerHandle;
  final double amount;
  final String currency;
  final String? payerEmail;
  final String? payerPhone;
  final String? stellarTxHash;
  final DateTime paidAt;
  
  LinkPayment({
    required this.paymentId,
    required this.linkId,
    required this.payerPublicKey,
    this.payerHandle,
    required this.amount,
    required this.currency,
    this.payerEmail,
    this.payerPhone,
    this.stellarTxHash,
    required this.paidAt,
  });
  
  String get payerDisplay => payerHandle ?? '${payerPublicKey.substring(0, 8)}...';
  
  factory LinkPayment.fromJson(Map<String, dynamic> json) {
    return LinkPayment(
      paymentId: json['payment_id'] as String,
      linkId: json['link_id'] as String,
      payerPublicKey: json['payer_public_key'] as String,
      payerHandle: json['payer_handle'] as String?,
      amount: (json['amount'] as num).toDouble(),
      currency: json['currency'] as String,
      payerEmail: json['payer_email'] as String?,
      payerPhone: json['payer_phone'] as String?,
      stellarTxHash: json['stellar_tx_hash'] as String?,
      paidAt: DateTime.parse(json['paid_at'] as String),
    );
  }
}

/// Link creation options
class CreatePaymentLinkOptions {
  final PaymentLinkType type;
  final double? fixedAmount;
  final double? minAmount;
  final double? maxAmount;
  final String currency;
  final bool allowCustomAmount;
  final String? title;
  final String? description;
  final String? imageUrl;
  final String? successMessage;
  final String? redirectUrl;
  final Duration? expiresIn;
  final int? maxPayments;
  final bool collectEmail;
  final bool collectPhone;
  final bool collectAddress;
  final Map<String, dynamic>? metadata;
  
  CreatePaymentLinkOptions({
    this.type = PaymentLinkType.oneTime,
    this.fixedAmount,
    this.minAmount,
    this.maxAmount,
    this.currency = 'USDC',
    this.allowCustomAmount = false,
    this.title,
    this.description,
    this.imageUrl,
    this.successMessage,
    this.redirectUrl,
    this.expiresIn,
    this.maxPayments,
    this.collectEmail = false,
    this.collectPhone = false,
    this.collectAddress = false,
    this.metadata,
  });
  
  Map<String, dynamic> toJson() => {
    'type': type.name,
    if (fixedAmount != null) 'fixed_amount': fixedAmount,
    if (minAmount != null) 'min_amount': minAmount,
    if (maxAmount != null) 'max_amount': maxAmount,
    'currency': currency,
    'allow_custom_amount': allowCustomAmount,
    if (title != null) 'title': title,
    if (description != null) 'description': description,
    if (imageUrl != null) 'image_url': imageUrl,
    if (successMessage != null) 'success_message': successMessage,
    if (redirectUrl != null) 'redirect_url': redirectUrl,
    if (expiresIn != null) 'expires_in_seconds': expiresIn!.inSeconds,
    if (maxPayments != null) 'max_payments': maxPayments,
    'collect_email': collectEmail,
    'collect_phone': collectPhone,
    'collect_address': collectAddress,
    if (metadata != null) 'metadata': metadata,
  };
}

/// GNS Payment Link Service
class PaymentLinkService {
  static final PaymentLinkService _instance = PaymentLinkService._internal();
  factory PaymentLinkService() => _instance;
  PaymentLinkService._internal();
  
  static const _baseUrl = 'https://api.gns.network';
  
  String? _merchantApiKey;
  String? _merchantId;
  String? _userPublicKey;
  
  /// Initialize for merchant (creating links)
  void initializeAsMerchant({
    required String merchantApiKey,
    required String merchantId,
  }) {
    _merchantApiKey = merchantApiKey;
    _merchantId = merchantId;
    debugPrint('🔗 Payment Link Service initialized (merchant)');
  }
  
  /// Initialize for user (paying links)
  void initializeAsUser(String userPublicKey) {
    _userPublicKey = userPublicKey;
    debugPrint('🔗 Payment Link Service initialized (user)');
  }
  
  // ==================== MERCHANT METHODS ====================
  
  /// Create payment link
  Future<PaymentLink?> createLink(CreatePaymentLinkOptions options) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/payment-links'),
        headers: _merchantHeaders,
        body: jsonEncode(options.toJson()),
      );
      
      if (response.statusCode == 201) {
        final data = jsonDecode(response.body)['data'];
        debugPrint('✅ Payment link created');
        return PaymentLink.fromJson(data);
      }
      return null;
    } catch (e) {
      debugPrint('Create link error: $e');
      return null;
    }
  }
  
  /// Get merchant's payment links
  Future<List<PaymentLink>> getLinks({
    PaymentLinkStatus? status,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final queryParams = <String, String>{
        'limit': limit.toString(),
        'offset': offset.toString(),
      };
      if (status != null) queryParams['status'] = status.name;
      
      final uri = Uri.parse('$_baseUrl/payment-links')
          .replace(queryParameters: queryParams);
      
      final response = await http.get(uri, headers: _merchantHeaders);
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'] as List;
        return data.map((l) => PaymentLink.fromJson(l)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('Get links error: $e');
      return [];
    }
  }
  
  /// Get single link details
  Future<PaymentLink?> getLink(String linkId) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/payment-links/$linkId'),
        headers: _merchantHeaders,
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'];
        return PaymentLink.fromJson(data);
      }
      return null;
    } catch (e) {
      debugPrint('Get link error: $e');
      return null;
    }
  }
  
  /// Update link
  Future<PaymentLink?> updateLink(
    String linkId, {
    PaymentLinkStatus? status,
    String? title,
    String? description,
    DateTime? expiresAt,
  }) async {
    try {
      final response = await http.put(
        Uri.parse('$_baseUrl/payment-links/$linkId'),
        headers: _merchantHeaders,
        body: jsonEncode({
          if (status != null) 'status': status.name,
          if (title != null) 'title': title,
          if (description != null) 'description': description,
          if (expiresAt != null) 'expires_at': expiresAt.toIso8601String(),
        }),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'];
        return PaymentLink.fromJson(data);
      }
      return null;
    } catch (e) {
      debugPrint('Update link error: $e');
      return null;
    }
  }
  
  /// Deactivate link
  Future<bool> deactivateLink(String linkId) async {
    final result = await updateLink(linkId, status: PaymentLinkStatus.inactive);
    return result != null;
  }
  
  /// Delete link
  Future<bool> deleteLink(String linkId) async {
    try {
      final response = await http.delete(
        Uri.parse('$_baseUrl/payment-links/$linkId'),
        headers: _merchantHeaders,
      );
      
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Delete link error: $e');
      return false;
    }
  }
  
  /// Get payments for a link
  Future<List<LinkPayment>> getLinkPayments(
    String linkId, {
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/payment-links/$linkId/payments')
          .replace(queryParameters: {
        'limit': limit.toString(),
        'offset': offset.toString(),
      });
      
      final response = await http.get(uri, headers: _merchantHeaders);
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'] as List;
        return data.map((p) => LinkPayment.fromJson(p)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('Get link payments error: $e');
      return [];
    }
  }
  
  // ==================== USER METHODS ====================
  
  /// Get link details by short code (public)
  Future<PaymentLink?> getLinkByCode(String shortCode) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/pay/$shortCode'),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'];
        return PaymentLink.fromJson(data);
      }
      return null;
    } catch (e) {
      debugPrint('Get link by code error: $e');
      return null;
    }
  }
  
  /// Pay a link
  Future<LinkPaymentResult> payLink({
    required String shortCode,
    required double amount,
    String? email,
    String? phone,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/pay/$shortCode'),
        headers: _userHeaders,
        body: jsonEncode({
          'amount': amount,
          if (email != null) 'email': email,
          if (phone != null) 'phone': phone,
        }),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'];
        return LinkPaymentResult(
          success: true,
          paymentId: data['payment_id'] as String?,
          transactionHash: data['stellar_tx_hash'] as String?,
        );
      } else {
        final error = jsonDecode(response.body)['error'];
        return LinkPaymentResult(success: false, error: error);
      }
    } catch (e) {
      return LinkPaymentResult(success: false, error: e.toString());
    }
  }
  
  // ==================== HEADERS ====================
  
  Map<String, String> get _merchantHeaders => {
    'Content-Type': 'application/json',
    'X-GNS-Merchant-Key': _merchantApiKey ?? '',
  };
  
  Map<String, String> get _userHeaders => {
    'Content-Type': 'application/json',
    'X-GNS-Public-Key': _userPublicKey ?? '',
  };
}

/// Payment result
class LinkPaymentResult {
  final bool success;
  final String? paymentId;
  final String? transactionHash;
  final String? error;
  
  LinkPaymentResult({
    required this.success,
    this.paymentId,
    this.transactionHash,
    this.error,
  });
}

/// Payment link type extensions
extension PaymentLinkTypeExtension on PaymentLinkType {
  String get displayName {
    switch (this) {
      case PaymentLinkType.oneTime:
        return 'One-time';
      case PaymentLinkType.reusable:
        return 'Reusable';
      case PaymentLinkType.subscription:
        return 'Subscription';
    }
  }
  
  String get description {
    switch (this) {
      case PaymentLinkType.oneTime:
        return 'Can only be paid once';
      case PaymentLinkType.reusable:
        return 'Can be paid multiple times';
      case PaymentLinkType.subscription:
        return 'Creates recurring subscription';
    }
  }
  
  String get emoji {
    switch (this) {
      case PaymentLinkType.oneTime:
        return '1️⃣';
      case PaymentLinkType.reusable:
        return '🔄';
      case PaymentLinkType.subscription:
        return '📅';
    }
  }
}
