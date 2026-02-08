/// GNS Invoice Service - Sprint 8
/// 
/// Generates and manages invoices for payments.
/// 
/// Features:
/// - PDF invoice generation
/// - Invoice templates
/// - Multi-currency support
/// - Invoice tracking
/// - Downloadable invoices
/// 
/// Location: lib/core/financial/invoice_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Invoice status
enum InvoiceStatus {
  draft,
  sent,
  viewed,
  paid,
  overdue,
  cancelled,
  refunded,
}

/// Invoice line item
class InvoiceLineItem {
  final String description;
  final int quantity;
  final double unitPrice;
  final double? taxRate;
  final double? discountPercent;
  
  InvoiceLineItem({
    required this.description,
    this.quantity = 1,
    required this.unitPrice,
    this.taxRate,
    this.discountPercent,
  });
  
  double get subtotal => quantity * unitPrice;
  double get discount => discountPercent != null ? subtotal * (discountPercent! / 100) : 0;
  double get tax => taxRate != null ? (subtotal - discount) * (taxRate! / 100) : 0;
  double get total => subtotal - discount + tax;
  
  factory InvoiceLineItem.fromJson(Map<String, dynamic> json) {
    return InvoiceLineItem(
      description: json['description'] as String,
      quantity: json['quantity'] as int? ?? 1,
      unitPrice: (json['unit_price'] as num).toDouble(),
      taxRate: (json['tax_rate'] as num?)?.toDouble(),
      discountPercent: (json['discount_percent'] as num?)?.toDouble(),
    );
  }
  
  Map<String, dynamic> toJson() => {
    'description': description,
    'quantity': quantity,
    'unit_price': unitPrice,
    if (taxRate != null) 'tax_rate': taxRate,
    if (discountPercent != null) 'discount_percent': discountPercent,
  };
}

/// Invoice model
class Invoice {
  final String invoiceId;
  final String invoiceNumber;
  final String merchantId;
  final InvoiceStatus status;
  
  // Customer info
  final String? customerPublicKey;
  final String? customerHandle;
  final String? customerName;
  final String? customerEmail;
  final String? customerAddress;
  
  // Merchant info (cached)
  final String merchantName;
  final String? merchantEmail;
  final String? merchantAddress;
  final String? merchantLogo;
  
  // Line items
  final List<InvoiceLineItem> lineItems;
  
  // Amounts
  final double subtotal;
  final double totalDiscount;
  final double totalTax;
  final double total;
  final String currency;
  
  // Dates
  final DateTime issueDate;
  final DateTime dueDate;
  final DateTime? paidAt;
  final DateTime? viewedAt;
  
  // Payment info
  final String? paymentLinkId;
  final String? paymentId;
  final String? stellarTxHash;
  
  // Customization
  final String? notes;
  final String? terms;
  final String? footer;
  
  // Tracking
  final DateTime createdAt;
  final DateTime? sentAt;
  
  Invoice({
    required this.invoiceId,
    required this.invoiceNumber,
    required this.merchantId,
    required this.status,
    this.customerPublicKey,
    this.customerHandle,
    this.customerName,
    this.customerEmail,
    this.customerAddress,
    required this.merchantName,
    this.merchantEmail,
    this.merchantAddress,
    this.merchantLogo,
    required this.lineItems,
    required this.subtotal,
    required this.totalDiscount,
    required this.totalTax,
    required this.total,
    required this.currency,
    required this.issueDate,
    required this.dueDate,
    this.paidAt,
    this.viewedAt,
    this.paymentLinkId,
    this.paymentId,
    this.stellarTxHash,
    this.notes,
    this.terms,
    this.footer,
    required this.createdAt,
    this.sentAt,
  });
  
  bool get isPaid => status == InvoiceStatus.paid;
  bool get isOverdue => status == InvoiceStatus.overdue || 
      (status == InvoiceStatus.sent && DateTime.now().isAfter(dueDate));
  int get daysUntilDue => dueDate.difference(DateTime.now()).inDays;
  int get daysOverdue => DateTime.now().difference(dueDate).inDays;
  
  String get formattedTotal {
    const symbols = {'USDC': '\$', 'EURC': '€', 'GNS': '🌐', 'XLM': '✨'};
    final symbol = symbols[currency] ?? currency;
    return '$symbol${total.toStringAsFixed(2)}';
  }
  
  factory Invoice.fromJson(Map<String, dynamic> json) {
    return Invoice(
      invoiceId: json['invoice_id'] as String,
      invoiceNumber: json['invoice_number'] as String,
      merchantId: json['merchant_id'] as String,
      status: InvoiceStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => InvoiceStatus.draft,
      ),
      customerPublicKey: json['customer_public_key'] as String?,
      customerHandle: json['customer_handle'] as String?,
      customerName: json['customer_name'] as String?,
      customerEmail: json['customer_email'] as String?,
      customerAddress: json['customer_address'] as String?,
      merchantName: json['merchant_name'] as String,
      merchantEmail: json['merchant_email'] as String?,
      merchantAddress: json['merchant_address'] as String?,
      merchantLogo: json['merchant_logo'] as String?,
      lineItems: (json['line_items'] as List)
          .map((i) => InvoiceLineItem.fromJson(i))
          .toList(),
      subtotal: (json['subtotal'] as num).toDouble(),
      totalDiscount: (json['total_discount'] as num?)?.toDouble() ?? 0,
      totalTax: (json['total_tax'] as num?)?.toDouble() ?? 0,
      total: (json['total'] as num).toDouble(),
      currency: json['currency'] as String,
      issueDate: DateTime.parse(json['issue_date'] as String),
      dueDate: DateTime.parse(json['due_date'] as String),
      paidAt: json['paid_at'] != null
          ? DateTime.parse(json['paid_at'] as String)
          : null,
      viewedAt: json['viewed_at'] != null
          ? DateTime.parse(json['viewed_at'] as String)
          : null,
      paymentLinkId: json['payment_link_id'] as String?,
      paymentId: json['payment_id'] as String?,
      stellarTxHash: json['stellar_tx_hash'] as String?,
      notes: json['notes'] as String?,
      terms: json['terms'] as String?,
      footer: json['footer'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      sentAt: json['sent_at'] != null
          ? DateTime.parse(json['sent_at'] as String)
          : null,
    );
  }
  
  Map<String, dynamic> toJson() => {
    'invoice_id': invoiceId,
    'invoice_number': invoiceNumber,
    'merchant_id': merchantId,
    'status': status.name,
    if (customerPublicKey != null) 'customer_public_key': customerPublicKey,
    if (customerHandle != null) 'customer_handle': customerHandle,
    if (customerName != null) 'customer_name': customerName,
    if (customerEmail != null) 'customer_email': customerEmail,
    if (customerAddress != null) 'customer_address': customerAddress,
    'merchant_name': merchantName,
    if (merchantEmail != null) 'merchant_email': merchantEmail,
    if (merchantAddress != null) 'merchant_address': merchantAddress,
    if (merchantLogo != null) 'merchant_logo': merchantLogo,
    'line_items': lineItems.map((i) => i.toJson()).toList(),
    'subtotal': subtotal,
    'total_discount': totalDiscount,
    'total_tax': totalTax,
    'total': total,
    'currency': currency,
    'issue_date': issueDate.toIso8601String(),
    'due_date': dueDate.toIso8601String(),
    if (paidAt != null) 'paid_at': paidAt!.toIso8601String(),
    if (viewedAt != null) 'viewed_at': viewedAt!.toIso8601String(),
    if (paymentLinkId != null) 'payment_link_id': paymentLinkId,
    if (paymentId != null) 'payment_id': paymentId,
    if (stellarTxHash != null) 'stellar_tx_hash': stellarTxHash,
    if (notes != null) 'notes': notes,
    if (terms != null) 'terms': terms,
    if (footer != null) 'footer': footer,
    'created_at': createdAt.toIso8601String(),
    if (sentAt != null) 'sent_at': sentAt!.toIso8601String(),
  };
}

/// Invoice creation options
class CreateInvoiceOptions {
  // Customer
  final String? customerPublicKey;
  final String? customerHandle;
  final String? customerName;
  final String? customerEmail;
  final String? customerAddress;
  
  // Items
  final List<InvoiceLineItem> lineItems;
  
  // Settings
  final String currency;
  final DateTime? issueDate;
  final int dueDays;
  final String? notes;
  final String? terms;
  final String? footer;
  
  // Options
  final bool sendEmail;
  final bool createPaymentLink;
  
  CreateInvoiceOptions({
    this.customerPublicKey,
    this.customerHandle,
    this.customerName,
    this.customerEmail,
    this.customerAddress,
    required this.lineItems,
    this.currency = 'USDC',
    this.issueDate,
    this.dueDays = 30,
    this.notes,
    this.terms,
    this.footer,
    this.sendEmail = false,
    this.createPaymentLink = true,
  });
  
  Map<String, dynamic> toJson() => {
    if (customerPublicKey != null) 'customer_public_key': customerPublicKey,
    if (customerHandle != null) 'customer_handle': customerHandle,
    if (customerName != null) 'customer_name': customerName,
    if (customerEmail != null) 'customer_email': customerEmail,
    if (customerAddress != null) 'customer_address': customerAddress,
    'line_items': lineItems.map((i) => i.toJson()).toList(),
    'currency': currency,
    if (issueDate != null) 'issue_date': issueDate!.toIso8601String(),
    'due_days': dueDays,
    if (notes != null) 'notes': notes,
    if (terms != null) 'terms': terms,
    if (footer != null) 'footer': footer,
    'send_email': sendEmail,
    'create_payment_link': createPaymentLink,
  };
}

/// Invoice template
class InvoiceTemplate {
  final String templateId;
  final String name;
  final String? logoUrl;
  final String primaryColor;
  final String? headerText;
  final String? footerText;
  final String? terms;
  final bool isDefault;
  
  InvoiceTemplate({
    required this.templateId,
    required this.name,
    this.logoUrl,
    this.primaryColor = '#4F46E5',
    this.headerText,
    this.footerText,
    this.terms,
    this.isDefault = false,
  });
  
  factory InvoiceTemplate.fromJson(Map<String, dynamic> json) {
    return InvoiceTemplate(
      templateId: json['template_id'] as String,
      name: json['name'] as String,
      logoUrl: json['logo_url'] as String?,
      primaryColor: json['primary_color'] as String? ?? '#4F46E5',
      headerText: json['header_text'] as String?,
      footerText: json['footer_text'] as String?,
      terms: json['terms'] as String?,
      isDefault: json['is_default'] as bool? ?? false,
    );
  }
  
  Map<String, dynamic> toJson() => {
    'template_id': templateId,
    'name': name,
    if (logoUrl != null) 'logo_url': logoUrl,
    'primary_color': primaryColor,
    if (headerText != null) 'header_text': headerText,
    if (footerText != null) 'footer_text': footerText,
    if (terms != null) 'terms': terms,
    'is_default': isDefault,
  };
}

/// GNS Invoice Service
class InvoiceService {
  static final InvoiceService _instance = InvoiceService._internal();
  factory InvoiceService() => _instance;
  InvoiceService._internal();
  
  static const _baseUrl = 'https://api.gns.network';
  
  String? _merchantApiKey;
  String? _merchantId;
  
  /// Initialize service
  Future<void> initialize({
    required String merchantApiKey,
    required String merchantId,
  }) async {
    _merchantApiKey = merchantApiKey;
    _merchantId = merchantId;
    debugPrint('📄 Invoice Service initialized');
  }
  
  /// Create invoice
  Future<Invoice?> createInvoice(CreateInvoiceOptions options) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/invoices'),
        headers: _headers,
        body: jsonEncode(options.toJson()),
      );
      
      if (response.statusCode == 201) {
        final data = jsonDecode(response.body)['data'];
        debugPrint('✅ Invoice created');
        return Invoice.fromJson(data);
      }
      return null;
    } catch (e) {
      debugPrint('Create invoice error: $e');
      return null;
    }
  }
  
  /// Get invoices
  Future<List<Invoice>> getInvoices({
    InvoiceStatus? status,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final queryParams = <String, String>{
        'limit': limit.toString(),
        'offset': offset.toString(),
      };
      if (status != null) queryParams['status'] = status.name;
      
      final uri = Uri.parse('$_baseUrl/invoices')
          .replace(queryParameters: queryParams);
      
      final response = await http.get(uri, headers: _headers);
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'] as List;
        return data.map((i) => Invoice.fromJson(i)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('Get invoices error: $e');
      return [];
    }
  }
  
  /// Get single invoice
  Future<Invoice?> getInvoice(String invoiceId) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/invoices/$invoiceId'),
        headers: _headers,
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'];
        return Invoice.fromJson(data);
      }
      return null;
    } catch (e) {
      debugPrint('Get invoice error: $e');
      return null;
    }
  }
  
  /// Update invoice (draft only)
  Future<Invoice?> updateInvoice(
    String invoiceId, {
    List<InvoiceLineItem>? lineItems,
    String? customerName,
    String? customerEmail,
    String? notes,
    DateTime? dueDate,
  }) async {
    try {
      final response = await http.put(
        Uri.parse('$_baseUrl/invoices/$invoiceId'),
        headers: _headers,
        body: jsonEncode({
          if (lineItems != null) 'line_items': lineItems.map((i) => i.toJson()).toList(),
          if (customerName != null) 'customer_name': customerName,
          if (customerEmail != null) 'customer_email': customerEmail,
          if (notes != null) 'notes': notes,
          if (dueDate != null) 'due_date': dueDate.toIso8601String(),
        }),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'];
        return Invoice.fromJson(data);
      }
      return null;
    } catch (e) {
      debugPrint('Update invoice error: $e');
      return null;
    }
  }
  
  /// Send invoice to customer
  Future<bool> sendInvoice(String invoiceId, {String? email}) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/invoices/$invoiceId/send'),
        headers: _headers,
        body: jsonEncode({
          if (email != null) 'email': email,
        }),
      );
      
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Send invoice error: $e');
      return false;
    }
  }
  
  /// Mark invoice as paid (manual)
  Future<Invoice?> markAsPaid(
    String invoiceId, {
    String? transactionHash,
    String? notes,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/invoices/$invoiceId/mark-paid'),
        headers: _headers,
        body: jsonEncode({
          if (transactionHash != null) 'transaction_hash': transactionHash,
          if (notes != null) 'notes': notes,
        }),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'];
        return Invoice.fromJson(data);
      }
      return null;
    } catch (e) {
      debugPrint('Mark as paid error: $e');
      return null;
    }
  }
  
  /// Cancel invoice
  Future<bool> cancelInvoice(String invoiceId) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/invoices/$invoiceId/cancel'),
        headers: _headers,
      );
      
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Cancel invoice error: $e');
      return false;
    }
  }
  
  /// Download invoice PDF
  Future<Uint8List?> downloadPdf(String invoiceId) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/invoices/$invoiceId/pdf'),
        headers: _headers,
      );
      
      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
      return null;
    } catch (e) {
      debugPrint('Download PDF error: $e');
      return null;
    }
  }
  
  /// Get PDF URL (for sharing)
  String getPdfUrl(String invoiceId) {
    return '$_baseUrl/invoices/$invoiceId/pdf?key=$_merchantApiKey';
  }
  
  /// Get public invoice URL (for customer)
  String getPublicUrl(String invoiceId) {
    return 'https://invoice.gns.network/$invoiceId';
  }
  
  // ==================== TEMPLATES ====================
  
  /// Get invoice templates
  Future<List<InvoiceTemplate>> getTemplates() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/invoices/templates'),
        headers: _headers,
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'] as List;
        return data.map((t) => InvoiceTemplate.fromJson(t)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('Get templates error: $e');
      return [];
    }
  }
  
  /// Create template
  Future<InvoiceTemplate?> createTemplate(InvoiceTemplate template) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/invoices/templates'),
        headers: _headers,
        body: jsonEncode(template.toJson()),
      );
      
      if (response.statusCode == 201) {
        final data = jsonDecode(response.body)['data'];
        return InvoiceTemplate.fromJson(data);
      }
      return null;
    } catch (e) {
      debugPrint('Create template error: $e');
      return null;
    }
  }
  
  /// Delete template
  Future<bool> deleteTemplate(String templateId) async {
    try {
      final response = await http.delete(
        Uri.parse('$_baseUrl/invoices/templates/$templateId'),
        headers: _headers,
      );
      
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Delete template error: $e');
      return false;
    }
  }
  
  // ==================== STATS ====================
  
  /// Get invoice statistics
  Future<InvoiceStats?> getStats({String period = '30d'}) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/invoices/stats?period=$period'),
        headers: _headers,
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'];
        return InvoiceStats.fromJson(data);
      }
      return null;
    } catch (e) {
      debugPrint('Get stats error: $e');
      return null;
    }
  }
  
  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'X-GNS-Merchant-Key': _merchantApiKey ?? '',
  };
}

/// Invoice statistics
class InvoiceStats {
  final int totalInvoices;
  final int paidInvoices;
  final int overdueInvoices;
  final double totalBilled;
  final double totalCollected;
  final double totalOutstanding;
  final double averageInvoice;
  final double collectionRate;
  
  InvoiceStats({
    required this.totalInvoices,
    required this.paidInvoices,
    required this.overdueInvoices,
    required this.totalBilled,
    required this.totalCollected,
    required this.totalOutstanding,
    required this.averageInvoice,
    required this.collectionRate,
  });
  
  factory InvoiceStats.fromJson(Map<String, dynamic> json) {
    return InvoiceStats(
      totalInvoices: json['total_invoices'] as int,
      paidInvoices: json['paid_invoices'] as int,
      overdueInvoices: json['overdue_invoices'] as int,
      totalBilled: (json['total_billed'] as num).toDouble(),
      totalCollected: (json['total_collected'] as num).toDouble(),
      totalOutstanding: (json['total_outstanding'] as num).toDouble(),
      averageInvoice: (json['average_invoice'] as num).toDouble(),
      collectionRate: (json['collection_rate'] as num).toDouble(),
    );
  }
}

/// Invoice status extensions
extension InvoiceStatusExtension on InvoiceStatus {
  String get displayName {
    switch (this) {
      case InvoiceStatus.draft:
        return 'Draft';
      case InvoiceStatus.sent:
        return 'Sent';
      case InvoiceStatus.viewed:
        return 'Viewed';
      case InvoiceStatus.paid:
        return 'Paid';
      case InvoiceStatus.overdue:
        return 'Overdue';
      case InvoiceStatus.cancelled:
        return 'Cancelled';
      case InvoiceStatus.refunded:
        return 'Refunded';
    }
  }
  
  String get emoji {
    switch (this) {
      case InvoiceStatus.draft:
        return '📝';
      case InvoiceStatus.sent:
        return '📤';
      case InvoiceStatus.viewed:
        return '👀';
      case InvoiceStatus.paid:
        return '✅';
      case InvoiceStatus.overdue:
        return '⚠️';
      case InvoiceStatus.cancelled:
        return '❌';
      case InvoiceStatus.refunded:
        return '↩️';
    }
  }
}
