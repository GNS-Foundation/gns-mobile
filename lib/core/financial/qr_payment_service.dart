/// GNS QR Payment Service - Sprint 8
/// 
/// Generates and processes dynamic QR codes for payments.
/// 
/// Features:
/// - Dynamic QR code generation
/// - Static merchant QR codes
/// - QR code scanning and parsing
/// - Payment request encoding
/// - Universal link handling
/// 
/// Location: lib/core/financial/qr_payment_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// QR code type
enum QrCodeType {
  staticMerchant,   // Fixed merchant QR (customer enters amount)
  dynamicPayment,   // Specific payment request with amount
  paymentLink,      // Links to payment link
  p2pRequest,       // Person-to-person payment request
  invoice,          // Links to invoice
}

/// QR code data model
class GnsQrCode {
  final String qrId;
  final QrCodeType type;
  final String data;           // The actual QR content
  final String? merchantId;
  final String? recipientPk;
  final String? recipientHandle;
  final double? amount;
  final String? currency;
  final String? memo;
  final String? reference;
  final DateTime? expiresAt;
  final DateTime createdAt;
  
  GnsQrCode({
    required this.qrId,
    required this.type,
    required this.data,
    this.merchantId,
    this.recipientPk,
    this.recipientHandle,
    this.amount,
    this.currency,
    this.memo,
    this.reference,
    this.expiresAt,
    required this.createdAt,
  });
  
  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);
  bool get hasAmount => amount != null && amount! > 0;
  
  String get displayRecipient => recipientHandle ?? 
      (recipientPk != null ? '${recipientPk!.substring(0, 8)}...' : 'Unknown');
  
  String get formattedAmount {
    if (amount == null) return 'Any amount';
    const symbols = {'USDC': '\$', 'EURC': '€', 'GNS': '🌐', 'XLM': '✨'};
    final symbol = symbols[currency] ?? (currency ?? '');
    return '$symbol${amount!.toStringAsFixed(2)}';
  }
  
  factory GnsQrCode.fromJson(Map<String, dynamic> json) {
    return GnsQrCode(
      qrId: json['qr_id'] as String,
      type: QrCodeType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => QrCodeType.dynamicPayment,
      ),
      data: json['data'] as String,
      merchantId: json['merchant_id'] as String?,
      recipientPk: json['recipient_pk'] as String?,
      recipientHandle: json['recipient_handle'] as String?,
      amount: (json['amount'] as num?)?.toDouble(),
      currency: json['currency'] as String?,
      memo: json['memo'] as String?,
      reference: json['reference'] as String?,
      expiresAt: json['expires_at'] != null
          ? DateTime.parse(json['expires_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
  
  Map<String, dynamic> toJson() => {
    'qr_id': qrId,
    'type': type.name,
    'data': data,
    if (merchantId != null) 'merchant_id': merchantId,
    if (recipientPk != null) 'recipient_pk': recipientPk,
    if (recipientHandle != null) 'recipient_handle': recipientHandle,
    if (amount != null) 'amount': amount,
    if (currency != null) 'currency': currency,
    if (memo != null) 'memo': memo,
    if (reference != null) 'reference': reference,
    if (expiresAt != null) 'expires_at': expiresAt!.toIso8601String(),
    'created_at': createdAt.toIso8601String(),
  };
}

/// Parsed QR data (from scanning)
class ParsedQrData {
  final bool isValid;
  final QrCodeType? type;
  final String? recipientPk;
  final String? recipientHandle;
  final double? amount;
  final String? currency;
  final String? memo;
  final String? reference;
  final String? paymentLinkCode;
  final String? invoiceId;
  final String? error;
  
  ParsedQrData({
    required this.isValid,
    this.type,
    this.recipientPk,
    this.recipientHandle,
    this.amount,
    this.currency,
    this.memo,
    this.reference,
    this.paymentLinkCode,
    this.invoiceId,
    this.error,
  });
  
  factory ParsedQrData.invalid(String error) => ParsedQrData(
    isValid: false,
    error: error,
  );
}

/// QR code generation options
class GenerateQrOptions {
  final QrCodeType type;
  final double? amount;
  final String currency;
  final String? memo;
  final String? reference;
  final Duration? expiresIn;
  final int? singleUse;  // Max number of uses
  
  GenerateQrOptions({
    this.type = QrCodeType.dynamicPayment,
    this.amount,
    this.currency = 'USDC',
    this.memo,
    this.reference,
    this.expiresIn,
    this.singleUse,
  });
  
  Map<String, dynamic> toJson() => {
    'type': type.name,
    if (amount != null) 'amount': amount,
    'currency': currency,
    if (memo != null) 'memo': memo,
    if (reference != null) 'reference': reference,
    if (expiresIn != null) 'expires_in_seconds': expiresIn!.inSeconds,
    if (singleUse != null) 'single_use': singleUse,
  };
}

/// GNS QR Payment Service
class QrPaymentService {
  static final QrPaymentService _instance = QrPaymentService._internal();
  factory QrPaymentService() => _instance;
  QrPaymentService._internal();
  
  static const _baseUrl = 'https://api.gns.network';
  
  /// GNS QR URI scheme: gns://pay?...
  static const _gnsScheme = 'gns';
  static const _payHost = 'pay';
  
  String? _userPublicKey;
  String? _userHandle;
  String? _merchantApiKey;
  
  /// Initialize for user
  void initializeAsUser({
    required String publicKey,
    String? handle,
  }) {
    _userPublicKey = publicKey;
    _userHandle = handle;
    debugPrint('📱 QR Payment Service initialized (user)');
  }
  
  /// Initialize for merchant
  void initializeAsMerchant(String merchantApiKey) {
    _merchantApiKey = merchantApiKey;
    debugPrint('📱 QR Payment Service initialized (merchant)');
  }
  
  // ==================== GENERATION ====================
  
  /// Generate QR code for receiving payment
  Future<GnsQrCode?> generateQrCode(GenerateQrOptions options) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/qr/generate'),
        headers: _userHeaders,
        body: jsonEncode(options.toJson()),
      );
      
      if (response.statusCode == 201) {
        final data = jsonDecode(response.body)['data'];
        return GnsQrCode.fromJson(data);
      }
      return null;
    } catch (e) {
      debugPrint('Generate QR error: $e');
      return null;
    }
  }
  
  /// Generate static merchant QR
  Future<GnsQrCode?> generateMerchantQr({
    String currency = 'USDC',
    String? defaultMemo,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/qr/merchant'),
        headers: _merchantHeaders,
        body: jsonEncode({
          'currency': currency,
          if (defaultMemo != null) 'default_memo': defaultMemo,
        }),
      );
      
      if (response.statusCode == 201) {
        final data = jsonDecode(response.body)['data'];
        return GnsQrCode.fromJson(data);
      }
      return null;
    } catch (e) {
      debugPrint('Generate merchant QR error: $e');
      return null;
    }
  }
  
  /// Generate local QR data (no server call)
  String generateLocalQrData({
    double? amount,
    String currency = 'USDC',
    String? memo,
    String? reference,
  }) {
    if (_userPublicKey == null) throw Exception('Not initialized');
    
    final uri = Uri(
      scheme: _gnsScheme,
      host: _payHost,
      queryParameters: {
        'to': _userPublicKey!,
        if (_userHandle != null) 'handle': _userHandle!,
        if (amount != null) 'amount': amount.toString(),
        'currency': currency,
        if (memo != null) 'memo': memo,
        if (reference != null) 'ref': reference,
        'ts': DateTime.now().millisecondsSinceEpoch.toString(),
      },
    );
    
    return uri.toString();
  }
  
  // ==================== PARSING ====================
  
  /// Parse scanned QR data
  ParsedQrData parseQrData(String rawData) {
    // Check for GNS URI scheme
    if (rawData.startsWith('gns://pay')) {
      return _parseGnsUri(rawData);
    }
    
    // Check for payment link URL
    if (rawData.contains('pay.gns.network/')) {
      return _parsePaymentLink(rawData);
    }
    
    // Check for invoice URL
    if (rawData.contains('invoice.gns.network/')) {
      return _parseInvoiceLink(rawData);
    }
    
    // Check for Stellar address (starts with G)
    if (rawData.startsWith('G') && rawData.length == 56) {
      return ParsedQrData(
        isValid: true,
        type: QrCodeType.p2pRequest,
        recipientPk: rawData,
      );
    }
    
    // Try to parse as JSON
    try {
      final json = jsonDecode(rawData);
      if (json is Map<String, dynamic>) {
        return _parseJsonQr(json);
      }
    } catch (_) {}
    
    return ParsedQrData.invalid('Unrecognized QR code format');
  }
  
  ParsedQrData _parseGnsUri(String uri) {
    try {
      final parsed = Uri.parse(uri);
      
      if (parsed.scheme != _gnsScheme || parsed.host != _payHost) {
        return ParsedQrData.invalid('Invalid GNS URI');
      }
      
      final params = parsed.queryParameters;
      
      return ParsedQrData(
        isValid: true,
        type: QrCodeType.dynamicPayment,
        recipientPk: params['to'],
        recipientHandle: params['handle'],
        amount: params['amount'] != null ? double.tryParse(params['amount']!) : null,
        currency: params['currency'],
        memo: params['memo'],
        reference: params['ref'],
      );
    } catch (e) {
      return ParsedQrData.invalid('Failed to parse GNS URI: $e');
    }
  }
  
  ParsedQrData _parsePaymentLink(String url) {
    try {
      final uri = Uri.parse(url);
      final pathParts = uri.pathSegments;
      
      if (pathParts.isEmpty) {
        return ParsedQrData.invalid('Invalid payment link');
      }
      
      return ParsedQrData(
        isValid: true,
        type: QrCodeType.paymentLink,
        paymentLinkCode: pathParts.last,
      );
    } catch (e) {
      return ParsedQrData.invalid('Failed to parse payment link: $e');
    }
  }
  
  ParsedQrData _parseInvoiceLink(String url) {
    try {
      final uri = Uri.parse(url);
      final pathParts = uri.pathSegments;
      
      if (pathParts.isEmpty) {
        return ParsedQrData.invalid('Invalid invoice link');
      }
      
      return ParsedQrData(
        isValid: true,
        type: QrCodeType.invoice,
        invoiceId: pathParts.last,
      );
    } catch (e) {
      return ParsedQrData.invalid('Failed to parse invoice link: $e');
    }
  }
  
  ParsedQrData _parseJsonQr(Map<String, dynamic> json) {
    // Check for GNS format
    if (json.containsKey('gns_version')) {
      return ParsedQrData(
        isValid: true,
        type: QrCodeType.values.firstWhere(
          (t) => t.name == json['type'],
          orElse: () => QrCodeType.dynamicPayment,
        ),
        recipientPk: json['to'] as String?,
        recipientHandle: json['handle'] as String?,
        amount: (json['amount'] as num?)?.toDouble(),
        currency: json['currency'] as String?,
        memo: json['memo'] as String?,
        reference: json['reference'] as String?,
      );
    }
    
    return ParsedQrData.invalid('Unknown JSON QR format');
  }
  
  // ==================== LOOKUP ====================
  
  /// Get QR code details by ID
  Future<GnsQrCode?> getQrCode(String qrId) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/qr/$qrId'),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'];
        return GnsQrCode.fromJson(data);
      }
      return null;
    } catch (e) {
      debugPrint('Get QR code error: $e');
      return null;
    }
  }
  
  /// Get merchant's QR codes
  Future<List<GnsQrCode>> getMerchantQrCodes() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/qr/merchant/list'),
        headers: _merchantHeaders,
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'] as List;
        return data.map((q) => GnsQrCode.fromJson(q)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('Get merchant QR codes error: $e');
      return [];
    }
  }
  
  /// Get user's generated QR codes
  Future<List<GnsQrCode>> getUserQrCodes() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/qr/user/list'),
        headers: _userHeaders,
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'] as List;
        return data.map((q) => GnsQrCode.fromJson(q)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('Get user QR codes error: $e');
      return [];
    }
  }
  
  /// Deactivate QR code
  Future<bool> deactivateQrCode(String qrId) async {
    try {
      final response = await http.delete(
        Uri.parse('$_baseUrl/qr/$qrId'),
        headers: _userHeaders,
      );
      
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Deactivate QR code error: $e');
      return false;
    }
  }
  
  // ==================== HEADERS ====================
  
  Map<String, String> get _userHeaders => {
    'Content-Type': 'application/json',
    'X-GNS-Public-Key': _userPublicKey ?? '',
  };
  
  Map<String, String> get _merchantHeaders => {
    'Content-Type': 'application/json',
    'X-GNS-Merchant-Key': _merchantApiKey ?? '',
  };
}

/// QR code type extensions
extension QrCodeTypeExtension on QrCodeType {
  String get displayName {
    switch (this) {
      case QrCodeType.staticMerchant:
        return 'Merchant QR';
      case QrCodeType.dynamicPayment:
        return 'Payment Request';
      case QrCodeType.paymentLink:
        return 'Payment Link';
      case QrCodeType.p2pRequest:
        return 'P2P Transfer';
      case QrCodeType.invoice:
        return 'Invoice';
    }
  }
  
  String get description {
    switch (this) {
      case QrCodeType.staticMerchant:
        return 'Fixed QR for your business';
      case QrCodeType.dynamicPayment:
        return 'One-time payment request';
      case QrCodeType.paymentLink:
        return 'Shareable payment link';
      case QrCodeType.p2pRequest:
        return 'Person-to-person transfer';
      case QrCodeType.invoice:
        return 'Pay an invoice';
    }
  }
  
  String get emoji {
    switch (this) {
      case QrCodeType.staticMerchant:
        return '🏪';
      case QrCodeType.dynamicPayment:
        return '💳';
      case QrCodeType.paymentLink:
        return '🔗';
      case QrCodeType.p2pRequest:
        return '👤';
      case QrCodeType.invoice:
        return '📄';
    }
  }
}
