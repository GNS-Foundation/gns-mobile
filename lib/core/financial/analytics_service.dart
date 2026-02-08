/// GNS Analytics Service - Sprint 7
/// 
/// Provides spending insights, financial analytics, and
/// transaction patterns for users.
/// 
/// Features:
/// - Spending by category/merchant
/// - Income vs expenses
/// - Trend analysis
/// - Budget tracking
/// - Savings goals
/// 
/// Location: lib/core/financial/analytics_service.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Time period for analytics
enum AnalyticsPeriod {
  today,
  thisWeek,
  thisMonth,
  last30Days,
  last90Days,
  thisYear,
  allTime,
  custom,
}

/// Category for transactions
enum SpendingCategory {
  food,
  shopping,
  entertainment,
  transport,
  utilities,
  health,
  education,
  travel,
  subscriptions,
  transfers,
  other,
}

/// Daily spending summary
class DailySpending {
  final DateTime date;
  final double totalSpent;
  final double totalReceived;
  final int transactionCount;
  final Map<String, double> byCurrency;
  
  DailySpending({
    required this.date,
    required this.totalSpent,
    required this.totalReceived,
    required this.transactionCount,
    required this.byCurrency,
  });
  
  double get netFlow => totalReceived - totalSpent;
  
  factory DailySpending.fromJson(Map<String, dynamic> json) {
    return DailySpending(
      date: DateTime.parse(json['date'] as String),
      totalSpent: (json['total_spent'] as num).toDouble(),
      totalReceived: (json['total_received'] as num).toDouble(),
      transactionCount: json['transaction_count'] as int,
      byCurrency: (json['by_currency'] as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, (v as num).toDouble())),
    );
  }
}

/// Category spending breakdown
class CategorySpending {
  final SpendingCategory category;
  final String categoryName;
  final double amount;
  final int transactionCount;
  final double percentOfTotal;
  final double? previousPeriodAmount;
  final double? changePercent;
  
  CategorySpending({
    required this.category,
    required this.categoryName,
    required this.amount,
    required this.transactionCount,
    required this.percentOfTotal,
    this.previousPeriodAmount,
    this.changePercent,
  });
  
  bool get isIncreased => (changePercent ?? 0) > 0;
  bool get isDecreased => (changePercent ?? 0) < 0;
  
  factory CategorySpending.fromJson(Map<String, dynamic> json) {
    return CategorySpending(
      category: SpendingCategory.values.firstWhere(
        (c) => c.name == json['category'],
        orElse: () => SpendingCategory.other,
      ),
      categoryName: json['category_name'] as String,
      amount: (json['amount'] as num).toDouble(),
      transactionCount: json['transaction_count'] as int,
      percentOfTotal: (json['percent_of_total'] as num).toDouble(),
      previousPeriodAmount: (json['previous_period_amount'] as num?)?.toDouble(),
      changePercent: (json['change_percent'] as num?)?.toDouble(),
    );
  }
}

/// Merchant spending summary
class MerchantSpending {
  final String merchantId;
  final String merchantName;
  final String? merchantCategory;
  final double amount;
  final int transactionCount;
  final double percentOfTotal;
  final DateTime lastTransaction;
  
  MerchantSpending({
    required this.merchantId,
    required this.merchantName,
    this.merchantCategory,
    required this.amount,
    required this.transactionCount,
    required this.percentOfTotal,
    required this.lastTransaction,
  });
  
  double get averageTransaction => transactionCount > 0 
      ? amount / transactionCount 
      : 0;
  
  factory MerchantSpending.fromJson(Map<String, dynamic> json) {
    return MerchantSpending(
      merchantId: json['merchant_id'] as String,
      merchantName: json['merchant_name'] as String,
      merchantCategory: json['merchant_category'] as String?,
      amount: (json['amount'] as num).toDouble(),
      transactionCount: json['transaction_count'] as int,
      percentOfTotal: (json['percent_of_total'] as num).toDouble(),
      lastTransaction: DateTime.parse(json['last_transaction'] as String),
    );
  }
}

/// Overall spending summary
class SpendingSummary {
  final AnalyticsPeriod period;
  final DateTime periodStart;
  final DateTime periodEnd;
  final double totalSpent;
  final double totalReceived;
  final double netFlow;
  final int totalTransactions;
  final double averageTransaction;
  final double largestTransaction;
  final Map<String, double> spendingByCurrency;
  final List<CategorySpending> topCategories;
  final List<MerchantSpending> topMerchants;
  final double? previousPeriodSpent;
  final double? changePercent;
  
  SpendingSummary({
    required this.period,
    required this.periodStart,
    required this.periodEnd,
    required this.totalSpent,
    required this.totalReceived,
    required this.netFlow,
    required this.totalTransactions,
    required this.averageTransaction,
    required this.largestTransaction,
    required this.spendingByCurrency,
    required this.topCategories,
    required this.topMerchants,
    this.previousPeriodSpent,
    this.changePercent,
  });
  
  bool get isPositiveFlow => netFlow > 0;
  
  factory SpendingSummary.fromJson(Map<String, dynamic> json) {
    return SpendingSummary(
      period: AnalyticsPeriod.values.firstWhere(
        (p) => p.name == json['period'],
        orElse: () => AnalyticsPeriod.thisMonth,
      ),
      periodStart: DateTime.parse(json['period_start'] as String),
      periodEnd: DateTime.parse(json['period_end'] as String),
      totalSpent: (json['total_spent'] as num).toDouble(),
      totalReceived: (json['total_received'] as num).toDouble(),
      netFlow: (json['net_flow'] as num).toDouble(),
      totalTransactions: json['total_transactions'] as int,
      averageTransaction: (json['average_transaction'] as num).toDouble(),
      largestTransaction: (json['largest_transaction'] as num).toDouble(),
      spendingByCurrency: (json['spending_by_currency'] as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, (v as num).toDouble())),
      topCategories: (json['top_categories'] as List)
          .map((c) => CategorySpending.fromJson(c))
          .toList(),
      topMerchants: (json['top_merchants'] as List)
          .map((m) => MerchantSpending.fromJson(m))
          .toList(),
      previousPeriodSpent: (json['previous_period_spent'] as num?)?.toDouble(),
      changePercent: (json['change_percent'] as num?)?.toDouble(),
    );
  }
}

/// Budget model
class Budget {
  final String budgetId;
  final String name;
  final SpendingCategory? category;
  final String? merchantId;
  final double amount;
  final BudgetPeriod period;
  final double spent;
  final DateTime periodStart;
  final DateTime periodEnd;
  final bool alertEnabled;
  final double alertThreshold; // 0.0-1.0
  
  Budget({
    required this.budgetId,
    required this.name,
    this.category,
    this.merchantId,
    required this.amount,
    required this.period,
    required this.spent,
    required this.periodStart,
    required this.periodEnd,
    this.alertEnabled = true,
    this.alertThreshold = 0.8,
  });
  
  double get remaining => amount - spent;
  double get percentUsed => amount > 0 ? spent / amount : 0;
  bool get isOverBudget => spent > amount;
  bool get isNearLimit => percentUsed >= alertThreshold;
  int get daysRemaining => periodEnd.difference(DateTime.now()).inDays;
  double get dailyBudget => daysRemaining > 0 ? remaining / daysRemaining : 0;
  
  factory Budget.fromJson(Map<String, dynamic> json) {
    return Budget(
      budgetId: json['budget_id'] as String,
      name: json['name'] as String,
      category: json['category'] != null
          ? SpendingCategory.values.firstWhere(
              (c) => c.name == json['category'],
              orElse: () => SpendingCategory.other,
            )
          : null,
      merchantId: json['merchant_id'] as String?,
      amount: (json['amount'] as num).toDouble(),
      period: BudgetPeriod.values.firstWhere(
        (p) => p.name == json['period'],
        orElse: () => BudgetPeriod.monthly,
      ),
      spent: (json['spent'] as num).toDouble(),
      periodStart: DateTime.parse(json['period_start'] as String),
      periodEnd: DateTime.parse(json['period_end'] as String),
      alertEnabled: json['alert_enabled'] as bool? ?? true,
      alertThreshold: (json['alert_threshold'] as num?)?.toDouble() ?? 0.8,
    );
  }
  
  Map<String, dynamic> toJson() => {
    'budget_id': budgetId,
    'name': name,
    if (category != null) 'category': category!.name,
    if (merchantId != null) 'merchant_id': merchantId,
    'amount': amount,
    'period': period.name,
    'alert_enabled': alertEnabled,
    'alert_threshold': alertThreshold,
  };
}

enum BudgetPeriod {
  weekly,
  monthly,
  quarterly,
  yearly,
}

/// Savings goal model
class SavingsGoal {
  final String goalId;
  final String name;
  final double targetAmount;
  final double currentAmount;
  final DateTime? targetDate;
  final String? imageUrl;
  final DateTime createdAt;
  final bool isCompleted;
  
  SavingsGoal({
    required this.goalId,
    required this.name,
    required this.targetAmount,
    required this.currentAmount,
    this.targetDate,
    this.imageUrl,
    required this.createdAt,
    this.isCompleted = false,
  });
  
  double get progress => targetAmount > 0 ? currentAmount / targetAmount : 0;
  double get remaining => targetAmount - currentAmount;
  int? get daysRemaining => targetDate?.difference(DateTime.now()).inDays;
  double? get dailySavingsNeeded {
    final days = daysRemaining;
    if (days == null || days <= 0) return null;
    return remaining / days;
  }
  
  factory SavingsGoal.fromJson(Map<String, dynamic> json) {
    return SavingsGoal(
      goalId: json['goal_id'] as String,
      name: json['name'] as String,
      targetAmount: (json['target_amount'] as num).toDouble(),
      currentAmount: (json['current_amount'] as num).toDouble(),
      targetDate: json['target_date'] != null
          ? DateTime.parse(json['target_date'] as String)
          : null,
      imageUrl: json['image_url'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      isCompleted: json['is_completed'] as bool? ?? false,
    );
  }
  
  Map<String, dynamic> toJson() => {
    'goal_id': goalId,
    'name': name,
    'target_amount': targetAmount,
    'current_amount': currentAmount,
    if (targetDate != null) 'target_date': targetDate!.toIso8601String(),
    if (imageUrl != null) 'image_url': imageUrl,
  };
}

/// Spending insight/tip
class SpendingInsight {
  final String insightId;
  final String title;
  final String description;
  final InsightType type;
  final String? actionLabel;
  final String? actionUrl;
  final Map<String, dynamic>? data;
  
  SpendingInsight({
    required this.insightId,
    required this.title,
    required this.description,
    required this.type,
    this.actionLabel,
    this.actionUrl,
    this.data,
  });
  
  factory SpendingInsight.fromJson(Map<String, dynamic> json) {
    return SpendingInsight(
      insightId: json['insight_id'] as String,
      title: json['title'] as String,
      description: json['description'] as String,
      type: InsightType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => InsightType.tip,
      ),
      actionLabel: json['action_label'] as String?,
      actionUrl: json['action_url'] as String?,
      data: json['data'] as Map<String, dynamic>?,
    );
  }
}

enum InsightType {
  tip,
  warning,
  achievement,
  trend,
  recommendation,
}

/// GNS Analytics Service
class AnalyticsService {
  static final AnalyticsService _instance = AnalyticsService._internal();
  factory AnalyticsService() => _instance;
  AnalyticsService._internal();
  
  static const _baseUrl = 'https://api.gns.network';
  
  String? _userPublicKey;
  
  /// Initialize
  Future<void> initialize(String userPublicKey) async {
    _userPublicKey = userPublicKey;
    debugPrint('📊 Analytics Service initialized');
  }
  
  /// Get spending summary
  Future<SpendingSummary?> getSpendingSummary({
    AnalyticsPeriod period = AnalyticsPeriod.thisMonth,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final queryParams = <String, String>{
        'period': period.name,
      };
      if (startDate != null) queryParams['start_date'] = startDate.toIso8601String();
      if (endDate != null) queryParams['end_date'] = endDate.toIso8601String();
      
      final uri = Uri.parse('$_baseUrl/analytics/summary')
          .replace(queryParameters: queryParams);
      
      final response = await http.get(uri, headers: _headers);
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'];
        return SpendingSummary.fromJson(data);
      }
      return null;
    } catch (e) {
      debugPrint('Get spending summary error: $e');
      return null;
    }
  }
  
  /// Get daily spending history
  Future<List<DailySpending>> getDailySpending({
    int days = 30,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/analytics/daily?days=$days'),
        headers: _headers,
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'] as List;
        return data.map((d) => DailySpending.fromJson(d)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('Get daily spending error: $e');
      return [];
    }
  }
  
  /// Get spending by category
  Future<List<CategorySpending>> getSpendingByCategory({
    AnalyticsPeriod period = AnalyticsPeriod.thisMonth,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/analytics/categories?period=${period.name}'),
        headers: _headers,
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'] as List;
        return data.map((c) => CategorySpending.fromJson(c)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('Get spending by category error: $e');
      return [];
    }
  }
  
  /// Get spending by merchant
  Future<List<MerchantSpending>> getSpendingByMerchant({
    AnalyticsPeriod period = AnalyticsPeriod.thisMonth,
    int limit = 10,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/analytics/merchants?period=${period.name}&limit=$limit'),
        headers: _headers,
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'] as List;
        return data.map((m) => MerchantSpending.fromJson(m)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('Get spending by merchant error: $e');
      return [];
    }
  }
  
  /// Get budgets
  Future<List<Budget>> getBudgets() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/analytics/budgets'),
        headers: _headers,
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'] as List;
        return data.map((b) => Budget.fromJson(b)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('Get budgets error: $e');
      return [];
    }
  }
  
  /// Create budget
  Future<Budget?> createBudget({
    required String name,
    required double amount,
    required BudgetPeriod period,
    SpendingCategory? category,
    String? merchantId,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/analytics/budgets'),
        headers: _headers,
        body: jsonEncode({
          'name': name,
          'amount': amount,
          'period': period.name,
          if (category != null) 'category': category.name,
          if (merchantId != null) 'merchant_id': merchantId,
        }),
      );
      
      if (response.statusCode == 201) {
        final data = jsonDecode(response.body)['data'];
        return Budget.fromJson(data);
      }
      return null;
    } catch (e) {
      debugPrint('Create budget error: $e');
      return null;
    }
  }
  
  /// Delete budget
  Future<bool> deleteBudget(String budgetId) async {
    try {
      final response = await http.delete(
        Uri.parse('$_baseUrl/analytics/budgets/$budgetId'),
        headers: _headers,
      );
      
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Delete budget error: $e');
      return false;
    }
  }
  
  /// Get savings goals
  Future<List<SavingsGoal>> getSavingsGoals() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/analytics/savings-goals'),
        headers: _headers,
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'] as List;
        return data.map((g) => SavingsGoal.fromJson(g)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('Get savings goals error: $e');
      return [];
    }
  }
  
  /// Create savings goal
  Future<SavingsGoal?> createSavingsGoal({
    required String name,
    required double targetAmount,
    DateTime? targetDate,
    String? imageUrl,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/analytics/savings-goals'),
        headers: _headers,
        body: jsonEncode({
          'name': name,
          'target_amount': targetAmount,
          if (targetDate != null) 'target_date': targetDate.toIso8601String(),
          if (imageUrl != null) 'image_url': imageUrl,
        }),
      );
      
      if (response.statusCode == 201) {
        final data = jsonDecode(response.body)['data'];
        return SavingsGoal.fromJson(data);
      }
      return null;
    } catch (e) {
      debugPrint('Create savings goal error: $e');
      return null;
    }
  }
  
  /// Add to savings goal
  Future<SavingsGoal?> addToSavingsGoal(String goalId, double amount) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/analytics/savings-goals/$goalId/add'),
        headers: _headers,
        body: jsonEncode({'amount': amount}),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'];
        return SavingsGoal.fromJson(data);
      }
      return null;
    } catch (e) {
      debugPrint('Add to savings goal error: $e');
      return null;
    }
  }
  
  /// Get spending insights
  Future<List<SpendingInsight>> getInsights() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/analytics/insights'),
        headers: _headers,
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'] as List;
        return data.map((i) => SpendingInsight.fromJson(i)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('Get insights error: $e');
      return [];
    }
  }
  
  /// Export transaction data
  Future<String?> exportData({
    required String format, // 'csv' or 'json'
    AnalyticsPeriod period = AnalyticsPeriod.thisYear,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/analytics/export?format=$format&period=${period.name}'),
        headers: _headers,
      );
      
      if (response.statusCode == 200) {
        return response.body;
      }
      return null;
    } catch (e) {
      debugPrint('Export data error: $e');
      return null;
    }
  }
  
  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'X-GNS-Public-Key': _userPublicKey ?? '',
  };
}

/// Category display extensions
extension SpendingCategoryExtension on SpendingCategory {
  String get displayName {
    switch (this) {
      case SpendingCategory.food:
        return 'Food & Dining';
      case SpendingCategory.shopping:
        return 'Shopping';
      case SpendingCategory.entertainment:
        return 'Entertainment';
      case SpendingCategory.transport:
        return 'Transportation';
      case SpendingCategory.utilities:
        return 'Utilities';
      case SpendingCategory.health:
        return 'Health & Medical';
      case SpendingCategory.education:
        return 'Education';
      case SpendingCategory.travel:
        return 'Travel';
      case SpendingCategory.subscriptions:
        return 'Subscriptions';
      case SpendingCategory.transfers:
        return 'Transfers';
      case SpendingCategory.other:
        return 'Other';
    }
  }
  
  String get emoji {
    switch (this) {
      case SpendingCategory.food:
        return '🍔';
      case SpendingCategory.shopping:
        return '🛍️';
      case SpendingCategory.entertainment:
        return '🎬';
      case SpendingCategory.transport:
        return '🚗';
      case SpendingCategory.utilities:
        return '💡';
      case SpendingCategory.health:
        return '🏥';
      case SpendingCategory.education:
        return '📚';
      case SpendingCategory.travel:
        return '✈️';
      case SpendingCategory.subscriptions:
        return '📱';
      case SpendingCategory.transfers:
        return '💸';
      case SpendingCategory.other:
        return '📦';
    }
  }
}
