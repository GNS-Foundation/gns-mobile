/// GNS Batch Settlement Service - Sprint 7
/// 
/// Enables merchants to batch multiple small transactions
/// into a single end-of-day settlement on Stellar.
/// 
/// Benefits:
/// - Reduced Stellar fees (one tx vs many)
/// - Simplified bookkeeping
/// - Configurable settlement schedules
/// 
/// Location: lib/core/financial/batch_settlement_service.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

/// Settlement frequency options
enum SettlementFrequency {
  realtime,    // Instant settlement (default)
  hourly,      // Every hour
  daily,       // End of day (midnight UTC)
  weekly,      // End of week (Sunday midnight UTC)
  manual,      // Only when merchant triggers
}

/// Settlement status
enum BatchSettlementStatus {
  pending,      // Transactions accumulating
  processing,   // Settlement in progress
  completed,    // Successfully settled
  failed,       // Settlement failed
  cancelled,    // Cancelled by merchant
}

/// Individual transaction in a batch
class BatchTransaction {
  final String transactionId;
  final String userPublicKey;
  final double amount;
  final String currency;
  final String? orderId;
  final DateTime timestamp;
  final double feeAmount;
  
  BatchTransaction({
    required this.transactionId,
    required this.userPublicKey,
    required this.amount,
    required this.currency,
    this.orderId,
    required this.timestamp,
    required this.feeAmount,
  });
  
  double get netAmount => amount - feeAmount;
  
  factory BatchTransaction.fromJson(Map<String, dynamic> json) {
    return BatchTransaction(
      transactionId: json['transaction_id'] as String,
      userPublicKey: json['user_public_key'] as String,
      amount: (json['amount'] as num).toDouble(),
      currency: json['currency'] as String,
      orderId: json['order_id'] as String?,
      timestamp: DateTime.parse(json['timestamp'] as String),
      feeAmount: (json['fee_amount'] as num?)?.toDouble() ?? 0,
    );
  }
  
  Map<String, dynamic> toJson() => {
    'transaction_id': transactionId,
    'user_public_key': userPublicKey,
    'amount': amount,
    'currency': currency,
    if (orderId != null) 'order_id': orderId,
    'timestamp': timestamp.toIso8601String(),
    'fee_amount': feeAmount,
  };
}

/// Batch settlement record
class BatchSettlement {
  final String batchId;
  final String merchantId;
  final String merchantName;
  final BatchSettlementStatus status;
  final List<BatchTransaction> transactions;
  final String currency;
  final double totalGross;
  final double totalFees;
  final double totalNet;
  final String? stellarTxHash;
  final DateTime periodStart;
  final DateTime periodEnd;
  final DateTime? settledAt;
  final String? failureReason;
  
  BatchSettlement({
    required this.batchId,
    required this.merchantId,
    required this.merchantName,
    required this.status,
    required this.transactions,
    required this.currency,
    required this.totalGross,
    required this.totalFees,
    required this.totalNet,
    this.stellarTxHash,
    required this.periodStart,
    required this.periodEnd,
    this.settledAt,
    this.failureReason,
  });
  
  int get transactionCount => transactions.length;
  double get averageTransaction => transactionCount > 0 
      ? totalGross / transactionCount 
      : 0;
  
  String get formattedTotal {
    final symbol = _getCurrencySymbol(currency);
    return '$symbol${totalNet.toStringAsFixed(2)}';
  }
  
  static String _getCurrencySymbol(String currency) {
    const symbols = {'GNS': '🌐', 'USDC': '\$', 'EURC': '€', 'XLM': '✨'};
    return symbols[currency] ?? currency;
  }
  
  factory BatchSettlement.fromJson(Map<String, dynamic> json) {
    return BatchSettlement(
      batchId: json['batch_id'] as String,
      merchantId: json['merchant_id'] as String,
      merchantName: json['merchant_name'] as String,
      status: BatchSettlementStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => BatchSettlementStatus.pending,
      ),
      transactions: (json['transactions'] as List? ?? [])
          .map((t) => BatchTransaction.fromJson(t))
          .toList(),
      currency: json['currency'] as String,
      totalGross: (json['total_gross'] as num).toDouble(),
      totalFees: (json['total_fees'] as num).toDouble(),
      totalNet: (json['total_net'] as num).toDouble(),
      stellarTxHash: json['stellar_tx_hash'] as String?,
      periodStart: DateTime.parse(json['period_start'] as String),
      periodEnd: DateTime.parse(json['period_end'] as String),
      settledAt: json['settled_at'] != null 
          ? DateTime.parse(json['settled_at'] as String)
          : null,
      failureReason: json['failure_reason'] as String?,
    );
  }
  
  Map<String, dynamic> toJson() => {
    'batch_id': batchId,
    'merchant_id': merchantId,
    'merchant_name': merchantName,
    'status': status.name,
    'transactions': transactions.map((t) => t.toJson()).toList(),
    'currency': currency,
    'total_gross': totalGross,
    'total_fees': totalFees,
    'total_net': totalNet,
    if (stellarTxHash != null) 'stellar_tx_hash': stellarTxHash,
    'period_start': periodStart.toIso8601String(),
    'period_end': periodEnd.toIso8601String(),
    if (settledAt != null) 'settled_at': settledAt!.toIso8601String(),
    if (failureReason != null) 'failure_reason': failureReason,
  };
}

/// Merchant settlement configuration
class SettlementConfig {
  final String merchantId;
  final SettlementFrequency frequency;
  final int? settlementHour; // 0-23, for daily settlements
  final int? settlementDayOfWeek; // 0-6, for weekly (0=Sunday)
  final double minimumAmount; // Minimum to trigger settlement
  final bool autoSettle; // Auto-settle when minimum reached
  final String preferredCurrency;
  final String settlementAddress; // Stellar address for settlements
  
  SettlementConfig({
    required this.merchantId,
    this.frequency = SettlementFrequency.daily,
    this.settlementHour = 0, // Midnight UTC
    this.settlementDayOfWeek = 0, // Sunday
    this.minimumAmount = 10.0,
    this.autoSettle = true,
    this.preferredCurrency = 'USDC',
    required this.settlementAddress,
  });
  
  factory SettlementConfig.fromJson(Map<String, dynamic> json) {
    return SettlementConfig(
      merchantId: json['merchant_id'] as String,
      frequency: SettlementFrequency.values.firstWhere(
        (f) => f.name == json['frequency'],
        orElse: () => SettlementFrequency.daily,
      ),
      settlementHour: json['settlement_hour'] as int?,
      settlementDayOfWeek: json['settlement_day_of_week'] as int?,
      minimumAmount: (json['minimum_amount'] as num?)?.toDouble() ?? 10.0,
      autoSettle: json['auto_settle'] as bool? ?? true,
      preferredCurrency: json['preferred_currency'] as String? ?? 'USDC',
      settlementAddress: json['settlement_address'] as String,
    );
  }
  
  Map<String, dynamic> toJson() => {
    'merchant_id': merchantId,
    'frequency': frequency.name,
    if (settlementHour != null) 'settlement_hour': settlementHour,
    if (settlementDayOfWeek != null) 'settlement_day_of_week': settlementDayOfWeek,
    'minimum_amount': minimumAmount,
    'auto_settle': autoSettle,
    'preferred_currency': preferredCurrency,
    'settlement_address': settlementAddress,
  };
  
  SettlementConfig copyWith({
    SettlementFrequency? frequency,
    int? settlementHour,
    int? settlementDayOfWeek,
    double? minimumAmount,
    bool? autoSettle,
    String? preferredCurrency,
    String? settlementAddress,
  }) {
    return SettlementConfig(
      merchantId: merchantId,
      frequency: frequency ?? this.frequency,
      settlementHour: settlementHour ?? this.settlementHour,
      settlementDayOfWeek: settlementDayOfWeek ?? this.settlementDayOfWeek,
      minimumAmount: minimumAmount ?? this.minimumAmount,
      autoSettle: autoSettle ?? this.autoSettle,
      preferredCurrency: preferredCurrency ?? this.preferredCurrency,
      settlementAddress: settlementAddress ?? this.settlementAddress,
    );
  }
}

/// Pending batch summary
class PendingBatchSummary {
  final String merchantId;
  final String currency;
  final int transactionCount;
  final double totalGross;
  final double totalFees;
  final double totalNet;
  final DateTime oldestTransaction;
  final DateTime newestTransaction;
  
  PendingBatchSummary({
    required this.merchantId,
    required this.currency,
    required this.transactionCount,
    required this.totalGross,
    required this.totalFees,
    required this.totalNet,
    required this.oldestTransaction,
    required this.newestTransaction,
  });
  
  Duration get batchAge => DateTime.now().difference(oldestTransaction);
  
  factory PendingBatchSummary.fromJson(Map<String, dynamic> json) {
    return PendingBatchSummary(
      merchantId: json['merchant_id'] as String,
      currency: json['currency'] as String,
      transactionCount: json['transaction_count'] as int,
      totalGross: (json['total_gross'] as num).toDouble(),
      totalFees: (json['total_fees'] as num).toDouble(),
      totalNet: (json['total_net'] as num).toDouble(),
      oldestTransaction: DateTime.parse(json['oldest_transaction'] as String),
      newestTransaction: DateTime.parse(json['newest_transaction'] as String),
    );
  }
}

/// Settlement result
class SettlementResult {
  final bool success;
  final BatchSettlement? settlement;
  final String? error;
  final String? transactionHash;
  
  SettlementResult({
    required this.success,
    this.settlement,
    this.error,
    this.transactionHash,
  });
}

/// GNS Batch Settlement Service
class BatchSettlementService {
  static final BatchSettlementService _instance = BatchSettlementService._internal();
  factory BatchSettlementService() => _instance;
  BatchSettlementService._internal();
  
  static const _baseUrl = 'https://api.gns.network';
  
  String? _merchantApiKey;
  String? _merchantId;
  SettlementConfig? _config;
  
  /// Initialize with merchant credentials
  Future<void> initialize({
    required String merchantApiKey,
    required String merchantId,
  }) async {
    _merchantApiKey = merchantApiKey;
    _merchantId = merchantId;
    
    // Load config
    _config = await getConfig();
    
    debugPrint('📦 Batch Settlement Service initialized');
  }
  
  /// Get current settlement configuration
  Future<SettlementConfig?> getConfig() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/settlement/config'),
        headers: _headers,
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'];
        _config = SettlementConfig.fromJson(data);
        return _config;
      }
      return null;
    } catch (e) {
      debugPrint('Get settlement config error: $e');
      return null;
    }
  }
  
  /// Update settlement configuration
  Future<bool> updateConfig(SettlementConfig config) async {
    try {
      final response = await http.put(
        Uri.parse('$_baseUrl/settlement/config'),
        headers: _headers,
        body: jsonEncode(config.toJson()),
      );
      
      if (response.statusCode == 200) {
        _config = config;
        debugPrint('✅ Settlement config updated');
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Update settlement config error: $e');
      return false;
    }
  }
  
  /// Get pending batch summary
  Future<PendingBatchSummary?> getPendingBatch({String? currency}) async {
    try {
      final uri = Uri.parse('$_baseUrl/settlement/pending')
          .replace(queryParameters: currency != null ? {'currency': currency} : null);
      
      final response = await http.get(uri, headers: _headers);
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'];
        if (data != null) {
          return PendingBatchSummary.fromJson(data);
        }
      }
      return null;
    } catch (e) {
      debugPrint('Get pending batch error: $e');
      return null;
    }
  }
  
  /// Trigger manual settlement
  Future<SettlementResult> triggerSettlement({String? currency}) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/settlement/trigger'),
        headers: _headers,
        body: jsonEncode({
          if (currency != null) 'currency': currency,
        }),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'];
        final settlement = BatchSettlement.fromJson(data);
        
        debugPrint('✅ Settlement triggered: ${settlement.batchId}');
        return SettlementResult(
          success: true,
          settlement: settlement,
          transactionHash: settlement.stellarTxHash,
        );
      } else {
        final error = jsonDecode(response.body)['error'];
        return SettlementResult(success: false, error: error);
      }
    } catch (e) {
      debugPrint('Trigger settlement error: $e');
      return SettlementResult(success: false, error: e.toString());
    }
  }
  
  /// Get settlement history
  Future<List<BatchSettlement>> getSettlementHistory({
    BatchSettlementStatus? status,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final queryParams = <String, String>{
        'limit': limit.toString(),
        'offset': offset.toString(),
      };
      if (status != null) queryParams['status'] = status.name;
      
      final uri = Uri.parse('$_baseUrl/settlement/history')
          .replace(queryParameters: queryParams);
      
      final response = await http.get(uri, headers: _headers);
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'] as List;
        return data.map((s) => BatchSettlement.fromJson(s)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('Get settlement history error: $e');
      return [];
    }
  }
  
  /// Get specific settlement details
  Future<BatchSettlement?> getSettlement(String batchId) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/settlement/$batchId'),
        headers: _headers,
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'];
        return BatchSettlement.fromJson(data);
      }
      return null;
    } catch (e) {
      debugPrint('Get settlement error: $e');
      return null;
    }
  }
  
  /// Get settlement statistics
  Future<SettlementStats?> getStats({String period = '30d'}) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/settlement/stats?period=$period'),
        headers: _headers,
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'];
        return SettlementStats.fromJson(data);
      }
      return null;
    } catch (e) {
      debugPrint('Get settlement stats error: $e');
      return null;
    }
  }
  
  /// Cancel pending batch (before settlement)
  Future<bool> cancelPendingBatch({String? currency}) async {
    try {
      final response = await http.delete(
        Uri.parse('$_baseUrl/settlement/pending'),
        headers: _headers,
        body: jsonEncode({
          if (currency != null) 'currency': currency,
        }),
      );
      
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Cancel pending batch error: $e');
      return false;
    }
  }
  
  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'X-GNS-Merchant-Key': _merchantApiKey ?? '',
  };
}

/// Settlement statistics
class SettlementStats {
  final int totalSettlements;
  final double totalVolume;
  final double totalFees;
  final double averageSettlement;
  final int totalTransactions;
  final Map<String, double> volumeByCurrency;
  
  SettlementStats({
    required this.totalSettlements,
    required this.totalVolume,
    required this.totalFees,
    required this.averageSettlement,
    required this.totalTransactions,
    required this.volumeByCurrency,
  });
  
  factory SettlementStats.fromJson(Map<String, dynamic> json) {
    return SettlementStats(
      totalSettlements: json['total_settlements'] as int,
      totalVolume: (json['total_volume'] as num).toDouble(),
      totalFees: (json['total_fees'] as num).toDouble(),
      averageSettlement: (json['average_settlement'] as num).toDouble(),
      totalTransactions: json['total_transactions'] as int,
      volumeByCurrency: (json['volume_by_currency'] as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, (v as num).toDouble())),
    );
  }
}

/// Extension for frequency display
extension SettlementFrequencyExtension on SettlementFrequency {
  String get displayName {
    switch (this) {
      case SettlementFrequency.realtime:
        return 'Real-time (Instant)';
      case SettlementFrequency.hourly:
        return 'Hourly';
      case SettlementFrequency.daily:
        return 'Daily';
      case SettlementFrequency.weekly:
        return 'Weekly';
      case SettlementFrequency.manual:
        return 'Manual Only';
    }
  }
  
  String get description {
    switch (this) {
      case SettlementFrequency.realtime:
        return 'Each transaction settles immediately';
      case SettlementFrequency.hourly:
        return 'Batched and settled every hour';
      case SettlementFrequency.daily:
        return 'Batched and settled at end of day';
      case SettlementFrequency.weekly:
        return 'Batched and settled weekly';
      case SettlementFrequency.manual:
        return 'Only settled when you trigger it';
    }
  }
}
