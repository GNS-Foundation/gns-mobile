/// GNS Merchant Registry - Sprint 5
/// 
/// Manages merchant registration, verification, and lookup.
/// Used by NFC payment flow to validate merchant terminals.
/// 
/// Location: lib/core/financial/merchant_registry.dart

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Merchant status
enum MerchantStatus {
  pending,
  active,
  suspended,
  terminated,
}

/// Merchant category codes (MCC)
enum MerchantCategory {
  retail,
  restaurant,
  grocery,
  entertainment,
  travel,
  services,
  healthcare,
  education,
  utilities,
  other,
}

/// Registered merchant
class RegisteredMerchant {
  final String merchantId;
  final String name;
  final String? displayName;
  final String stellarAddress;
  final MerchantStatus status;
  final MerchantCategory category;
  final String? logoUrl;
  final String? website;
  final String? phone;
  final String? email;
  final String? address;
  final String? h3Cell;  // Merchant location (H3 hex)
  final List<String> acceptedCurrencies;
  final double? tipPercent;  // Suggested tip percentage
  final DateTime registeredAt;
  final DateTime? verifiedAt;
  final Map<String, dynamic>? metadata;
  
  RegisteredMerchant({
    required this.merchantId,
    required this.name,
    this.displayName,
    required this.stellarAddress,
    required this.status,
    required this.category,
    this.logoUrl,
    this.website,
    this.phone,
    this.email,
    this.address,
    this.h3Cell,
    required this.acceptedCurrencies,
    this.tipPercent,
    required this.registeredAt,
    this.verifiedAt,
    this.metadata,
  });
  
  String get effectiveName => displayName ?? name;
  bool get isVerified => verifiedAt != null;
  bool get isActive => status == MerchantStatus.active;
  
  factory RegisteredMerchant.fromJson(Map<String, dynamic> json) {
    return RegisteredMerchant(
      merchantId: json['merchant_id'] as String,
      name: json['name'] as String,
      displayName: json['display_name'] as String?,
      stellarAddress: json['stellar_address'] as String,
      status: MerchantStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => MerchantStatus.pending,
      ),
      category: MerchantCategory.values.firstWhere(
        (c) => c.name == json['category'],
        orElse: () => MerchantCategory.other,
      ),
      logoUrl: json['logo_url'] as String?,
      website: json['website'] as String?,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      address: json['address'] as String?,
      h3Cell: json['h3_cell'] as String?,
      acceptedCurrencies: (json['accepted_currencies'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ?? ['GNS', 'USDC', 'EURC'],
      tipPercent: (json['tip_percent'] as num?)?.toDouble(),
      registeredAt: DateTime.parse(json['registered_at'] as String),
      verifiedAt: json['verified_at'] != null 
          ? DateTime.parse(json['verified_at'] as String) 
          : null,
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }
  
  Map<String, dynamic> toJson() => {
    'merchant_id': merchantId,
    'name': name,
    if (displayName != null) 'display_name': displayName,
    'stellar_address': stellarAddress,
    'status': status.name,
    'category': category.name,
    if (logoUrl != null) 'logo_url': logoUrl,
    if (website != null) 'website': website,
    if (phone != null) 'phone': phone,
    if (email != null) 'email': email,
    if (address != null) 'address': address,
    if (h3Cell != null) 'h3_cell': h3Cell,
    'accepted_currencies': acceptedCurrencies,
    if (tipPercent != null) 'tip_percent': tipPercent,
    'registered_at': registeredAt.toIso8601String(),
    if (verifiedAt != null) 'verified_at': verifiedAt!.toIso8601String(),
    if (metadata != null) 'metadata': metadata,
  };
}

/// Merchant terminal (POS device)
class MerchantTerminal {
  final String terminalId;
  final String merchantId;
  final String? name;
  final String? location;
  final bool isActive;
  final DateTime lastSeen;
  
  MerchantTerminal({
    required this.terminalId,
    required this.merchantId,
    this.name,
    this.location,
    required this.isActive,
    required this.lastSeen,
  });
  
  factory MerchantTerminal.fromJson(Map<String, dynamic> json) {
    return MerchantTerminal(
      terminalId: json['terminal_id'] as String,
      merchantId: json['merchant_id'] as String,
      name: json['name'] as String?,
      location: json['location'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      lastSeen: DateTime.parse(json['last_seen'] as String),
    );
  }
}

/// Merchant registry service
class MerchantRegistry {
  static final MerchantRegistry _instance = MerchantRegistry._internal();
  factory MerchantRegistry() => _instance;
  MerchantRegistry._internal();
  
  static const String _apiBase = 'https://gns-browser-production.up.railway.app';
  static const String _cacheKey = 'merchant_cache';
  static const Duration _cacheDuration = Duration(hours: 24);
  
  // Local cache
  final Map<String, RegisteredMerchant> _cache = {};
  DateTime? _lastCacheUpdate;
  
  /// Get merchant by ID
  Future<RegisteredMerchant?> getMerchant(String merchantId) async {
    // Check cache first
    if (_cache.containsKey(merchantId)) {
      return _cache[merchantId];
    }
    
    // Fetch from backend
    try {
      final response = await http.get(
        Uri.parse('$_apiBase/merchants/$merchantId'),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          final merchant = RegisteredMerchant.fromJson(data['data']);
          _cache[merchantId] = merchant;
          return merchant;
        }
      }
    } catch (e) {
      debugPrint('Error fetching merchant: $e');
    }
    
    // Try loading from local cache
    return await _loadFromLocalCache(merchantId);
  }
  
  /// Search merchants by name or location
  Future<List<RegisteredMerchant>> searchMerchants({
    String? query,
    MerchantCategory? category,
    String? nearH3Cell,
    int limit = 20,
  }) async {
    try {
      final params = <String, String>{
        if (query != null) 'q': query,
        if (category != null) 'category': category.name,
        if (nearH3Cell != null) 'near': nearH3Cell,
        'limit': limit.toString(),
      };
      
      final uri = Uri.parse('$_apiBase/merchants/search')
          .replace(queryParameters: params);
      
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          final merchants = (data['data'] as List)
              .map((m) => RegisteredMerchant.fromJson(m))
              .toList();
          
          // Update cache
          for (final merchant in merchants) {
            _cache[merchant.merchantId] = merchant;
          }
          
          return merchants;
        }
      }
    } catch (e) {
      debugPrint('Error searching merchants: $e');
    }
    
    return [];
  }
  
  /// Get nearby merchants
  Future<List<RegisteredMerchant>> getNearbyMerchants(String h3Cell) async {
    return searchMerchants(nearH3Cell: h3Cell);
  }
  
  /// Verify merchant signature
  Future<bool> verifyMerchantSignature({
    required String merchantId,
    required String data,
    required String signature,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_apiBase/merchants/verify-signature'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'merchant_id': merchantId,
          'data': data,
          'signature': signature,
        }),
      ).timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        return result['valid'] == true;
      }
    } catch (e) {
      debugPrint('Error verifying merchant signature: $e');
    }
    
    return false;
  }
  
  /// Report a suspicious merchant
  Future<bool> reportMerchant({
    required String merchantId,
    required String reason,
    String? details,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_apiBase/merchants/$merchantId/report'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'reason': reason,
          'details': details,
          'reported_at': DateTime.now().toIso8601String(),
        }),
      );
      
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      debugPrint('Error reporting merchant: $e');
      return false;
    }
  }
  
  /// Get favorite/frequent merchants
  Future<List<RegisteredMerchant>> getFrequentMerchants(
    List<String> merchantIds,
  ) async {
    final merchants = <RegisteredMerchant>[];
    
    for (final id in merchantIds) {
      final merchant = await getMerchant(id);
      if (merchant != null) {
        merchants.add(merchant);
      }
    }
    
    return merchants;
  }
  
  /// Refresh merchant cache
  Future<void> refreshCache() async {
    try {
      final response = await http.get(
        Uri.parse('$_apiBase/merchants/popular'),
      ).timeout(const Duration(seconds: 15));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          for (final m in data['data']) {
            final merchant = RegisteredMerchant.fromJson(m);
            _cache[merchant.merchantId] = merchant;
          }
          
          _lastCacheUpdate = DateTime.now();
          await _saveToLocalCache();
        }
      }
    } catch (e) {
      debugPrint('Error refreshing merchant cache: $e');
    }
  }
  
  /// Save cache to local storage
  Future<void> _saveToLocalCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheData = {
        'updated_at': _lastCacheUpdate?.toIso8601String(),
        'merchants': _cache.map((k, v) => MapEntry(k, v.toJson())),
      };
      await prefs.setString(_cacheKey, jsonEncode(cacheData));
    } catch (e) {
      debugPrint('Error saving merchant cache: $e');
    }
  }
  
  /// Load from local cache
  Future<RegisteredMerchant?> _loadFromLocalCache(String merchantId) async {
    try {
      if (_cache.isEmpty) {
        await _loadFullCache();
      }
      return _cache[merchantId];
    } catch (e) {
      debugPrint('Error loading from cache: $e');
      return null;
    }
  }
  
  /// Load full cache from storage
  Future<void> _loadFullCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheJson = prefs.getString(_cacheKey);
      
      if (cacheJson != null) {
        final cacheData = jsonDecode(cacheJson);
        
        // Check if cache is still valid
        final updatedAt = cacheData['updated_at'] != null
            ? DateTime.parse(cacheData['updated_at'])
            : null;
        
        if (updatedAt != null && 
            DateTime.now().difference(updatedAt) < _cacheDuration) {
          final merchants = cacheData['merchants'] as Map<String, dynamic>;
          for (final entry in merchants.entries) {
            _cache[entry.key] = RegisteredMerchant.fromJson(entry.value);
          }
          _lastCacheUpdate = updatedAt;
        }
      }
    } catch (e) {
      debugPrint('Error loading merchant cache: $e');
    }
  }
  
  /// Clear cache
  void clearCache() {
    _cache.clear();
    _lastCacheUpdate = null;
  }
}

/// Merchant settlement configuration
class MerchantSettlementConfig {
  /// Primary currency for settlement
  final String settlementCurrency;
  
  /// Settlement frequency
  final SettlementFrequency frequency;
  
  /// Minimum amount before settlement
  final double minimumAmount;
  
  /// Bank details for fiat offramp (optional)
  final BankDetails? bankDetails;
  
  /// Instant settlement enabled
  final bool instantSettlement;
  
  /// Settlement fee percentage
  final double feePercent;
  
  MerchantSettlementConfig({
    required this.settlementCurrency,
    required this.frequency,
    required this.minimumAmount,
    this.bankDetails,
    this.instantSettlement = true,
    this.feePercent = 0.1, // 0.1% for GNS settlements
  });
  
  factory MerchantSettlementConfig.fromJson(Map<String, dynamic> json) {
    return MerchantSettlementConfig(
      settlementCurrency: json['settlement_currency'] as String,
      frequency: SettlementFrequency.values.firstWhere(
        (f) => f.name == json['frequency'],
        orElse: () => SettlementFrequency.instant,
      ),
      minimumAmount: (json['minimum_amount'] as num).toDouble(),
      bankDetails: json['bank_details'] != null
          ? BankDetails.fromJson(json['bank_details'])
          : null,
      instantSettlement: json['instant_settlement'] as bool? ?? true,
      feePercent: (json['fee_percent'] as num?)?.toDouble() ?? 0.1,
    );
  }
}

enum SettlementFrequency {
  instant,
  daily,
  weekly,
  monthly,
}

class BankDetails {
  final String bankName;
  final String accountNumber;
  final String routingNumber;
  final String accountHolderName;
  final String? swiftCode;
  final String? iban;
  
  BankDetails({
    required this.bankName,
    required this.accountNumber,
    required this.routingNumber,
    required this.accountHolderName,
    this.swiftCode,
    this.iban,
  });
  
  factory BankDetails.fromJson(Map<String, dynamic> json) {
    return BankDetails(
      bankName: json['bank_name'] as String,
      accountNumber: json['account_number'] as String,
      routingNumber: json['routing_number'] as String,
      accountHolderName: json['account_holder_name'] as String,
      swiftCode: json['swift_code'] as String?,
      iban: json['iban'] as String?,
    );
  }
}
