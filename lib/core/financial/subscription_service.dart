/// GNS Subscription Service - Sprint 7
/// 
/// Manages recurring payments and subscriptions.
/// 
/// Features:
/// - Create/manage subscriptions
/// - Automatic billing cycles
/// - Payment retry logic
/// - Subscription lifecycle management
/// - Merchant subscription plans
/// 
/// Location: lib/core/financial/subscription_service.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Subscription status
enum SubscriptionStatus {
  active,
  paused,
  cancelled,
  expired,
  pastDue,
  trialing,
  pendingActivation,
}

/// Billing cycle frequency
enum BillingCycle {
  daily,
  weekly,
  biweekly,
  monthly,
  quarterly,
  semiannually,
  annually,
}

/// Payment method for subscription
enum SubscriptionPaymentMethod {
  gnsWallet,
  stellarDirect,
  linkedCard,
}

/// Subscription plan model
class SubscriptionPlan {
  final String planId;
  final String merchantId;
  final String merchantName;
  final String name;
  final String description;
  final double price;
  final String currency;
  final BillingCycle billingCycle;
  final int? trialDays;
  final List<String> features;
  final bool isActive;
  final DateTime createdAt;
  
  SubscriptionPlan({
    required this.planId,
    required this.merchantId,
    required this.merchantName,
    required this.name,
    required this.description,
    required this.price,
    required this.currency,
    required this.billingCycle,
    this.trialDays,
    required this.features,
    this.isActive = true,
    required this.createdAt,
  });
  
  String get formattedPrice {
    final symbol = _getCurrencySymbol(currency);
    return '$symbol${price.toStringAsFixed(2)}/${billingCycle.shortName}';
  }
  
  static String _getCurrencySymbol(String currency) {
    const symbols = {'GNS': '🌐', 'USDC': '\$', 'EURC': '€', 'XLM': '✨'};
    return symbols[currency] ?? currency;
  }
  
  factory SubscriptionPlan.fromJson(Map<String, dynamic> json) {
    return SubscriptionPlan(
      planId: json['plan_id'] as String,
      merchantId: json['merchant_id'] as String,
      merchantName: json['merchant_name'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      price: (json['price'] as num).toDouble(),
      currency: json['currency'] as String,
      billingCycle: BillingCycle.values.firstWhere(
        (c) => c.name == json['billing_cycle'],
        orElse: () => BillingCycle.monthly,
      ),
      trialDays: json['trial_days'] as int?,
      features: List<String>.from(json['features'] ?? []),
      isActive: json['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
  
  Map<String, dynamic> toJson() => {
    'plan_id': planId,
    'merchant_id': merchantId,
    'merchant_name': merchantName,
    'name': name,
    'description': description,
    'price': price,
    'currency': currency,
    'billing_cycle': billingCycle.name,
    if (trialDays != null) 'trial_days': trialDays,
    'features': features,
    'is_active': isActive,
    'created_at': createdAt.toIso8601String(),
  };
}

/// User subscription model
class Subscription {
  final String subscriptionId;
  final String planId;
  final String userId;
  final String merchantId;
  final String merchantName;
  final String planName;
  final double amount;
  final String currency;
  final BillingCycle billingCycle;
  final SubscriptionStatus status;
  final SubscriptionPaymentMethod paymentMethod;
  final DateTime startDate;
  final DateTime? trialEndDate;
  final DateTime currentPeriodStart;
  final DateTime currentPeriodEnd;
  final DateTime? nextBillingDate;
  final DateTime? cancelledAt;
  final DateTime? pausedAt;
  final int failedPaymentAttempts;
  final DateTime? lastPaymentDate;
  final String? lastPaymentId;
  final bool autoRenew;
  
  Subscription({
    required this.subscriptionId,
    required this.planId,
    required this.userId,
    required this.merchantId,
    required this.merchantName,
    required this.planName,
    required this.amount,
    required this.currency,
    required this.billingCycle,
    required this.status,
    required this.paymentMethod,
    required this.startDate,
    this.trialEndDate,
    required this.currentPeriodStart,
    required this.currentPeriodEnd,
    this.nextBillingDate,
    this.cancelledAt,
    this.pausedAt,
    this.failedPaymentAttempts = 0,
    this.lastPaymentDate,
    this.lastPaymentId,
    this.autoRenew = true,
  });
  
  bool get isActive => status == SubscriptionStatus.active;
  bool get isTrialing => status == SubscriptionStatus.trialing;
  bool get isPastDue => status == SubscriptionStatus.pastDue;
  bool get isCancelled => status == SubscriptionStatus.cancelled;
  
  int get daysUntilRenewal {
    if (nextBillingDate == null) return 0;
    return nextBillingDate!.difference(DateTime.now()).inDays;
  }
  
  int get daysInCurrentPeriod {
    return currentPeriodEnd.difference(currentPeriodStart).inDays;
  }
  
  double get periodProgress {
    final total = daysInCurrentPeriod;
    if (total == 0) return 1.0;
    final elapsed = DateTime.now().difference(currentPeriodStart).inDays;
    return (elapsed / total).clamp(0.0, 1.0);
  }
  
  String get formattedAmount {
    final symbol = _getCurrencySymbol(currency);
    return '$symbol${amount.toStringAsFixed(2)}/${billingCycle.shortName}';
  }
  
  static String _getCurrencySymbol(String currency) {
    const symbols = {'GNS': '🌐', 'USDC': '\$', 'EURC': '€', 'XLM': '✨'};
    return symbols[currency] ?? currency;
  }
  
  factory Subscription.fromJson(Map<String, dynamic> json) {
    return Subscription(
      subscriptionId: json['subscription_id'] as String,
      planId: json['plan_id'] as String,
      userId: json['user_id'] as String,
      merchantId: json['merchant_id'] as String,
      merchantName: json['merchant_name'] as String,
      planName: json['plan_name'] as String,
      amount: (json['amount'] as num).toDouble(),
      currency: json['currency'] as String,
      billingCycle: BillingCycle.values.firstWhere(
        (c) => c.name == json['billing_cycle'],
        orElse: () => BillingCycle.monthly,
      ),
      status: SubscriptionStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => SubscriptionStatus.active,
      ),
      paymentMethod: SubscriptionPaymentMethod.values.firstWhere(
        (m) => m.name == json['payment_method'],
        orElse: () => SubscriptionPaymentMethod.gnsWallet,
      ),
      startDate: DateTime.parse(json['start_date'] as String),
      trialEndDate: json['trial_end_date'] != null
          ? DateTime.parse(json['trial_end_date'] as String)
          : null,
      currentPeriodStart: DateTime.parse(json['current_period_start'] as String),
      currentPeriodEnd: DateTime.parse(json['current_period_end'] as String),
      nextBillingDate: json['next_billing_date'] != null
          ? DateTime.parse(json['next_billing_date'] as String)
          : null,
      cancelledAt: json['cancelled_at'] != null
          ? DateTime.parse(json['cancelled_at'] as String)
          : null,
      pausedAt: json['paused_at'] != null
          ? DateTime.parse(json['paused_at'] as String)
          : null,
      failedPaymentAttempts: json['failed_payment_attempts'] as int? ?? 0,
      lastPaymentDate: json['last_payment_date'] != null
          ? DateTime.parse(json['last_payment_date'] as String)
          : null,
      lastPaymentId: json['last_payment_id'] as String?,
      autoRenew: json['auto_renew'] as bool? ?? true,
    );
  }
  
  Map<String, dynamic> toJson() => {
    'subscription_id': subscriptionId,
    'plan_id': planId,
    'user_id': userId,
    'merchant_id': merchantId,
    'merchant_name': merchantName,
    'plan_name': planName,
    'amount': amount,
    'currency': currency,
    'billing_cycle': billingCycle.name,
    'status': status.name,
    'payment_method': paymentMethod.name,
    'start_date': startDate.toIso8601String(),
    if (trialEndDate != null) 'trial_end_date': trialEndDate!.toIso8601String(),
    'current_period_start': currentPeriodStart.toIso8601String(),
    'current_period_end': currentPeriodEnd.toIso8601String(),
    if (nextBillingDate != null) 'next_billing_date': nextBillingDate!.toIso8601String(),
    if (cancelledAt != null) 'cancelled_at': cancelledAt!.toIso8601String(),
    if (pausedAt != null) 'paused_at': pausedAt!.toIso8601String(),
    'failed_payment_attempts': failedPaymentAttempts,
    if (lastPaymentDate != null) 'last_payment_date': lastPaymentDate!.toIso8601String(),
    if (lastPaymentId != null) 'last_payment_id': lastPaymentId,
    'auto_renew': autoRenew,
  };
}

/// Subscription invoice
class SubscriptionInvoice {
  final String invoiceId;
  final String subscriptionId;
  final double amount;
  final String currency;
  final String status; // paid, pending, failed, refunded
  final DateTime periodStart;
  final DateTime periodEnd;
  final DateTime? paidAt;
  final String? paymentId;
  final String? failureReason;
  final DateTime createdAt;
  
  SubscriptionInvoice({
    required this.invoiceId,
    required this.subscriptionId,
    required this.amount,
    required this.currency,
    required this.status,
    required this.periodStart,
    required this.periodEnd,
    this.paidAt,
    this.paymentId,
    this.failureReason,
    required this.createdAt,
  });
  
  bool get isPaid => status == 'paid';
  bool get isPending => status == 'pending';
  bool get isFailed => status == 'failed';
  
  factory SubscriptionInvoice.fromJson(Map<String, dynamic> json) {
    return SubscriptionInvoice(
      invoiceId: json['invoice_id'] as String,
      subscriptionId: json['subscription_id'] as String,
      amount: (json['amount'] as num).toDouble(),
      currency: json['currency'] as String,
      status: json['status'] as String,
      periodStart: DateTime.parse(json['period_start'] as String),
      periodEnd: DateTime.parse(json['period_end'] as String),
      paidAt: json['paid_at'] != null 
          ? DateTime.parse(json['paid_at'] as String)
          : null,
      paymentId: json['payment_id'] as String?,
      failureReason: json['failure_reason'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

/// Result of subscription operations
class SubscriptionResult {
  final bool success;
  final Subscription? subscription;
  final String? error;
  
  SubscriptionResult({
    required this.success,
    this.subscription,
    this.error,
  });
}

/// GNS Subscription Service
class SubscriptionService {
  static final SubscriptionService _instance = SubscriptionService._internal();
  factory SubscriptionService() => _instance;
  SubscriptionService._internal();
  
  static const _baseUrl = 'https://api.gns.network';
  
  String? _userPublicKey;
  
  // Subscription change stream
  final _subscriptionController = StreamController<Subscription>.broadcast();
  Stream<Subscription> get subscriptionChanges => _subscriptionController.stream;
  
  /// Initialize
  Future<void> initialize(String userPublicKey) async {
    _userPublicKey = userPublicKey;
    debugPrint('🔄 Subscription Service initialized');
  }
  
  /// Get available plans from a merchant
  Future<List<SubscriptionPlan>> getMerchantPlans(String merchantId) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/subscriptions/plans?merchant_id=$merchantId'),
        headers: _headers,
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'] as List;
        return data.map((p) => SubscriptionPlan.fromJson(p)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('Get merchant plans error: $e');
      return [];
    }
  }
  
  /// Get user's subscriptions
  Future<List<Subscription>> getSubscriptions({
    SubscriptionStatus? status,
  }) async {
    try {
      final queryParams = <String, String>{};
      if (status != null) queryParams['status'] = status.name;
      
      final uri = Uri.parse('$_baseUrl/subscriptions')
          .replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);
      
      final response = await http.get(uri, headers: _headers);
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'] as List;
        return data.map((s) => Subscription.fromJson(s)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('Get subscriptions error: $e');
      return [];
    }
  }
  
  /// Get single subscription
  Future<Subscription?> getSubscription(String subscriptionId) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/subscriptions/$subscriptionId'),
        headers: _headers,
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'];
        return Subscription.fromJson(data);
      }
      return null;
    } catch (e) {
      debugPrint('Get subscription error: $e');
      return null;
    }
  }
  
  /// Subscribe to a plan
  Future<SubscriptionResult> subscribe({
    required String planId,
    SubscriptionPaymentMethod paymentMethod = SubscriptionPaymentMethod.gnsWallet,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/subscriptions/subscribe'),
        headers: _headers,
        body: jsonEncode({
          'plan_id': planId,
          'payment_method': paymentMethod.name,
        }),
      );
      
      if (response.statusCode == 201) {
        final data = jsonDecode(response.body)['data'];
        final subscription = Subscription.fromJson(data);
        
        _subscriptionController.add(subscription);
        debugPrint('✅ Subscribed to plan: $planId');
        
        return SubscriptionResult(success: true, subscription: subscription);
      } else {
        final error = jsonDecode(response.body)['error'];
        return SubscriptionResult(success: false, error: error);
      }
    } catch (e) {
      debugPrint('Subscribe error: $e');
      return SubscriptionResult(success: false, error: e.toString());
    }
  }
  
  /// Cancel subscription
  Future<SubscriptionResult> cancel(
    String subscriptionId, {
    bool immediately = false,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/subscriptions/$subscriptionId/cancel'),
        headers: _headers,
        body: jsonEncode({
          'immediately': immediately,
        }),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'];
        final subscription = Subscription.fromJson(data);
        
        _subscriptionController.add(subscription);
        debugPrint('✅ Subscription cancelled: $subscriptionId');
        
        return SubscriptionResult(success: true, subscription: subscription);
      } else {
        final error = jsonDecode(response.body)['error'];
        return SubscriptionResult(success: false, error: error);
      }
    } catch (e) {
      debugPrint('Cancel subscription error: $e');
      return SubscriptionResult(success: false, error: e.toString());
    }
  }
  
  /// Pause subscription
  Future<SubscriptionResult> pause(String subscriptionId) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/subscriptions/$subscriptionId/pause'),
        headers: _headers,
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'];
        final subscription = Subscription.fromJson(data);
        
        _subscriptionController.add(subscription);
        return SubscriptionResult(success: true, subscription: subscription);
      } else {
        final error = jsonDecode(response.body)['error'];
        return SubscriptionResult(success: false, error: error);
      }
    } catch (e) {
      debugPrint('Pause subscription error: $e');
      return SubscriptionResult(success: false, error: e.toString());
    }
  }
  
  /// Resume paused subscription
  Future<SubscriptionResult> resume(String subscriptionId) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/subscriptions/$subscriptionId/resume'),
        headers: _headers,
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'];
        final subscription = Subscription.fromJson(data);
        
        _subscriptionController.add(subscription);
        return SubscriptionResult(success: true, subscription: subscription);
      } else {
        final error = jsonDecode(response.body)['error'];
        return SubscriptionResult(success: false, error: error);
      }
    } catch (e) {
      debugPrint('Resume subscription error: $e');
      return SubscriptionResult(success: false, error: e.toString());
    }
  }
  
  /// Update payment method
  Future<SubscriptionResult> updatePaymentMethod(
    String subscriptionId,
    SubscriptionPaymentMethod newMethod,
  ) async {
    try {
      final response = await http.put(
        Uri.parse('$_baseUrl/subscriptions/$subscriptionId/payment-method'),
        headers: _headers,
        body: jsonEncode({
          'payment_method': newMethod.name,
        }),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'];
        final subscription = Subscription.fromJson(data);
        return SubscriptionResult(success: true, subscription: subscription);
      } else {
        final error = jsonDecode(response.body)['error'];
        return SubscriptionResult(success: false, error: error);
      }
    } catch (e) {
      debugPrint('Update payment method error: $e');
      return SubscriptionResult(success: false, error: e.toString());
    }
  }
  
  /// Toggle auto-renew
  Future<SubscriptionResult> setAutoRenew(
    String subscriptionId,
    bool autoRenew,
  ) async {
    try {
      final response = await http.put(
        Uri.parse('$_baseUrl/subscriptions/$subscriptionId/auto-renew'),
        headers: _headers,
        body: jsonEncode({
          'auto_renew': autoRenew,
        }),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'];
        final subscription = Subscription.fromJson(data);
        return SubscriptionResult(success: true, subscription: subscription);
      } else {
        final error = jsonDecode(response.body)['error'];
        return SubscriptionResult(success: false, error: error);
      }
    } catch (e) {
      debugPrint('Set auto-renew error: $e');
      return SubscriptionResult(success: false, error: e.toString());
    }
  }
  
  /// Get invoices for a subscription
  Future<List<SubscriptionInvoice>> getInvoices(String subscriptionId) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/subscriptions/$subscriptionId/invoices'),
        headers: _headers,
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'] as List;
        return data.map((i) => SubscriptionInvoice.fromJson(i)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('Get invoices error: $e');
      return [];
    }
  }
  
  /// Retry failed payment
  Future<bool> retryPayment(String subscriptionId) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/subscriptions/$subscriptionId/retry-payment'),
        headers: _headers,
      );
      
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Retry payment error: $e');
      return false;
    }
  }
  
  /// Get upcoming renewals
  Future<List<Subscription>> getUpcomingRenewals({int days = 7}) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/subscriptions/upcoming?days=$days'),
        headers: _headers,
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'] as List;
        return data.map((s) => Subscription.fromJson(s)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('Get upcoming renewals error: $e');
      return [];
    }
  }
  
  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'X-GNS-Public-Key': _userPublicKey ?? '',
  };
  
  void dispose() {
    _subscriptionController.close();
  }
}

/// Billing cycle extensions
extension BillingCycleExtension on BillingCycle {
  String get displayName {
    switch (this) {
      case BillingCycle.daily:
        return 'Daily';
      case BillingCycle.weekly:
        return 'Weekly';
      case BillingCycle.biweekly:
        return 'Every 2 weeks';
      case BillingCycle.monthly:
        return 'Monthly';
      case BillingCycle.quarterly:
        return 'Quarterly';
      case BillingCycle.semiannually:
        return 'Every 6 months';
      case BillingCycle.annually:
        return 'Annually';
    }
  }
  
  String get shortName {
    switch (this) {
      case BillingCycle.daily:
        return 'day';
      case BillingCycle.weekly:
        return 'wk';
      case BillingCycle.biweekly:
        return '2wk';
      case BillingCycle.monthly:
        return 'mo';
      case BillingCycle.quarterly:
        return 'qtr';
      case BillingCycle.semiannually:
        return '6mo';
      case BillingCycle.annually:
        return 'yr';
    }
  }
  
  int get daysInCycle {
    switch (this) {
      case BillingCycle.daily:
        return 1;
      case BillingCycle.weekly:
        return 7;
      case BillingCycle.biweekly:
        return 14;
      case BillingCycle.monthly:
        return 30;
      case BillingCycle.quarterly:
        return 90;
      case BillingCycle.semiannually:
        return 180;
      case BillingCycle.annually:
        return 365;
    }
  }
}

/// Subscription status extensions
extension SubscriptionStatusExtension on SubscriptionStatus {
  String get displayName {
    switch (this) {
      case SubscriptionStatus.active:
        return 'Active';
      case SubscriptionStatus.paused:
        return 'Paused';
      case SubscriptionStatus.cancelled:
        return 'Cancelled';
      case SubscriptionStatus.expired:
        return 'Expired';
      case SubscriptionStatus.pastDue:
        return 'Past Due';
      case SubscriptionStatus.trialing:
        return 'Trial';
      case SubscriptionStatus.pendingActivation:
        return 'Pending';
    }
  }
  
  String get emoji {
    switch (this) {
      case SubscriptionStatus.active:
        return '✅';
      case SubscriptionStatus.paused:
        return '⏸️';
      case SubscriptionStatus.cancelled:
        return '❌';
      case SubscriptionStatus.expired:
        return '⏰';
      case SubscriptionStatus.pastDue:
        return '⚠️';
      case SubscriptionStatus.trialing:
        return '🎁';
      case SubscriptionStatus.pendingActivation:
        return '⏳';
    }
  }
}
