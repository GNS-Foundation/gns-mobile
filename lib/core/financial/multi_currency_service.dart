/// GNS Multi-Currency Service - Sprint 8
/// 
/// Manages multiple Stellar assets and currency operations.
/// 
/// Features:
/// - Asset registry with metadata
/// - Trustline management
/// - Exchange rate fetching
/// - Currency conversion
/// - User currency preferences
/// 
/// Location: lib/core/financial/multi_currency_service.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Supported asset types
enum AssetType {
  native,      // XLM
  stablecoin,  // USDC, EURC
  token,       // GNS, custom tokens
  anchor,      // Anchored assets (BTC, ETH)
}

/// Asset information
class StellarAsset {
  final String code;
  final String? issuer;
  final AssetType type;
  final String name;
  final String symbol;
  final int decimals;
  final String? iconUrl;
  final bool isVerified;
  final String? anchorDomain;
  final String? description;
  
  StellarAsset({
    required this.code,
    this.issuer,
    required this.type,
    required this.name,
    required this.symbol,
    this.decimals = 7,
    this.iconUrl,
    this.isVerified = false,
    this.anchorDomain,
    this.description,
  });
  
  /// Native XLM asset
  static final xlm = StellarAsset(
    code: 'XLM',
    issuer: null,
    type: AssetType.native,
    name: 'Stellar Lumens',
    symbol: '✨',
    decimals: 7,
    isVerified: true,
    description: 'Native Stellar network asset',
  );
  
  /// Check if native asset
  bool get isNative => issuer == null;
  
  /// Full asset identifier
  String get assetId => isNative ? code : '$code:$issuer';
  
  /// Short issuer display
  String get issuerShort => issuer != null 
      ? '${issuer!.substring(0, 4)}...${issuer!.substring(issuer!.length - 4)}'
      : '';
  
  factory StellarAsset.fromJson(Map<String, dynamic> json) {
    return StellarAsset(
      code: json['code'] as String,
      issuer: json['issuer'] as String?,
      type: AssetType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => AssetType.token,
      ),
      name: json['name'] as String,
      symbol: json['symbol'] as String,
      decimals: json['decimals'] as int? ?? 7,
      iconUrl: json['icon_url'] as String?,
      isVerified: json['is_verified'] as bool? ?? false,
      anchorDomain: json['anchor_domain'] as String?,
      description: json['description'] as String?,
    );
  }
  
  Map<String, dynamic> toJson() => {
    'code': code,
    if (issuer != null) 'issuer': issuer,
    'type': type.name,
    'name': name,
    'symbol': symbol,
    'decimals': decimals,
    if (iconUrl != null) 'icon_url': iconUrl,
    'is_verified': isVerified,
    if (anchorDomain != null) 'anchor_domain': anchorDomain,
    if (description != null) 'description': description,
  };
}

/// User's asset balance
class AssetBalance {
  final StellarAsset asset;
  final double balance;
  final double? limit;
  final bool hasTrustline;
  final double? usdValue;
  
  AssetBalance({
    required this.asset,
    required this.balance,
    this.limit,
    this.hasTrustline = true,
    this.usdValue,
  });
  
  String get formattedBalance {
    return '${asset.symbol}${balance.toStringAsFixed(asset.decimals > 2 ? 2 : asset.decimals)}';
  }
  
  factory AssetBalance.fromJson(Map<String, dynamic> json, StellarAsset asset) {
    return AssetBalance(
      asset: asset,
      balance: (json['balance'] as num).toDouble(),
      limit: (json['limit'] as num?)?.toDouble(),
      hasTrustline: json['has_trustline'] as bool? ?? true,
      usdValue: (json['usd_value'] as num?)?.toDouble(),
    );
  }
}

/// Exchange rate between two assets
class ExchangeRate {
  final String fromAsset;
  final String toAsset;
  final double rate;
  final DateTime timestamp;
  final String? source;
  
  ExchangeRate({
    required this.fromAsset,
    required this.toAsset,
    required this.rate,
    required this.timestamp,
    this.source,
  });
  
  /// Convert amount using this rate
  double convert(double amount) => amount * rate;
  
  /// Inverse rate
  double get inverseRate => 1 / rate;
  
  /// Check if rate is stale (>5 min old)
  bool get isStale => DateTime.now().difference(timestamp).inMinutes > 5;
  
  factory ExchangeRate.fromJson(Map<String, dynamic> json) {
    return ExchangeRate(
      fromAsset: json['from_asset'] as String,
      toAsset: json['to_asset'] as String,
      rate: (json['rate'] as num).toDouble(),
      timestamp: DateTime.parse(json['timestamp'] as String),
      source: json['source'] as String?,
    );
  }
}

/// Currency preferences
class CurrencyPreferences {
  final String defaultCurrency;
  final String displayCurrency; // For showing values
  final List<String> favoriteAssets;
  final bool showSmallBalances;
  final double smallBalanceThreshold;
  
  CurrencyPreferences({
    this.defaultCurrency = 'USDC',
    this.displayCurrency = 'USD',
    this.favoriteAssets = const ['USDC', 'XLM', 'GNS'],
    this.showSmallBalances = true,
    this.smallBalanceThreshold = 0.01,
  });
  
  factory CurrencyPreferences.fromJson(Map<String, dynamic> json) {
    return CurrencyPreferences(
      defaultCurrency: json['default_currency'] as String? ?? 'USDC',
      displayCurrency: json['display_currency'] as String? ?? 'USD',
      favoriteAssets: List<String>.from(json['favorite_assets'] ?? ['USDC', 'XLM', 'GNS']),
      showSmallBalances: json['show_small_balances'] as bool? ?? true,
      smallBalanceThreshold: (json['small_balance_threshold'] as num?)?.toDouble() ?? 0.01,
    );
  }
  
  Map<String, dynamic> toJson() => {
    'default_currency': defaultCurrency,
    'display_currency': displayCurrency,
    'favorite_assets': favoriteAssets,
    'show_small_balances': showSmallBalances,
    'small_balance_threshold': smallBalanceThreshold,
  };
  
  CurrencyPreferences copyWith({
    String? defaultCurrency,
    String? displayCurrency,
    List<String>? favoriteAssets,
    bool? showSmallBalances,
    double? smallBalanceThreshold,
  }) {
    return CurrencyPreferences(
      defaultCurrency: defaultCurrency ?? this.defaultCurrency,
      displayCurrency: displayCurrency ?? this.displayCurrency,
      favoriteAssets: favoriteAssets ?? this.favoriteAssets,
      showSmallBalances: showSmallBalances ?? this.showSmallBalances,
      smallBalanceThreshold: smallBalanceThreshold ?? this.smallBalanceThreshold,
    );
  }
}

/// Trustline operation result
class TrustlineResult {
  final bool success;
  final String? transactionHash;
  final String? error;
  
  TrustlineResult({
    required this.success,
    this.transactionHash,
    this.error,
  });
}

/// GNS Multi-Currency Service
class MultiCurrencyService {
  static final MultiCurrencyService _instance = MultiCurrencyService._internal();
  factory MultiCurrencyService() => _instance;
  MultiCurrencyService._internal();
  
  static const _baseUrl = 'https://api.gns.network';
  static const _horizonUrl = 'https://horizon.stellar.org';
  
  String? _userPublicKey;
  CurrencyPreferences _preferences = CurrencyPreferences();
  
  // Cached data
  final Map<String, StellarAsset> _assetRegistry = {};
  final Map<String, ExchangeRate> _rateCache = {};
  List<AssetBalance> _balances = [];
  
  // Rate update stream
  final _ratesController = StreamController<Map<String, ExchangeRate>>.broadcast();
  Stream<Map<String, ExchangeRate>> get ratesStream => _ratesController.stream;
  
  Timer? _rateRefreshTimer;
  
  /// Initialize service
  Future<void> initialize(String userPublicKey) async {
    _userPublicKey = userPublicKey;
    
    // Load asset registry
    await loadAssetRegistry();
    
    // Load user preferences
    await loadPreferences();
    
    // Load balances
    await refreshBalances();
    
    // Start rate refresh timer
    _startRateRefresh();
    
    debugPrint('💱 Multi-Currency Service initialized');
  }
  
  /// Load supported asset registry
  Future<void> loadAssetRegistry() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/assets/registry'),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'] as List;
        _assetRegistry.clear();
        
        // Always include XLM
        _assetRegistry['XLM'] = StellarAsset.xlm;
        
        for (final item in data) {
          final asset = StellarAsset.fromJson(item);
          _assetRegistry[asset.assetId] = asset;
        }
        
        debugPrint('📦 Loaded ${_assetRegistry.length} assets');
      }
    } catch (e) {
      debugPrint('Load asset registry error: $e');
      // Load defaults
      _loadDefaultAssets();
    }
  }
  
  void _loadDefaultAssets() {
    _assetRegistry['XLM'] = StellarAsset.xlm;
    
    _assetRegistry['USDC:GA5ZSEJYB37JRC5AVCIA5MOP4RHTM335X2KGX3IHOJAPP5RE34K4KZVN'] = StellarAsset(
      code: 'USDC',
      issuer: 'GA5ZSEJYB37JRC5AVCIA5MOP4RHTM335X2KGX3IHOJAPP5RE34K4KZVN',
      type: AssetType.stablecoin,
      name: 'USD Coin',
      symbol: '\$',
      isVerified: true,
      anchorDomain: 'centre.io',
    );
    
    _assetRegistry['EURC:GDHU6WRG4IEQXM5NZ4BMPKOXHW76MZM4Y2IEMFDVXBSDP6SJY4ITNPP2'] = StellarAsset(
      code: 'EURC',
      issuer: 'GDHU6WRG4IEQXM5NZ4BMPKOXHW76MZM4Y2IEMFDVXBSDP6SJY4ITNPP2',
      type: AssetType.stablecoin,
      name: 'Euro Coin',
      symbol: '€',
      isVerified: true,
      anchorDomain: 'circle.com',
    );
  }
  
  /// Get all registered assets
  List<StellarAsset> get registeredAssets => _assetRegistry.values.toList();
  
  /// Get asset by code (returns first match)
  StellarAsset? getAssetByCode(String code) {
    return _assetRegistry.values.firstWhere(
      (a) => a.code == code,
      orElse: () => _assetRegistry['XLM']!,
    );
  }
  
  /// Get asset by full ID
  StellarAsset? getAsset(String assetId) => _assetRegistry[assetId];
  
  /// Load user preferences
  Future<CurrencyPreferences> loadPreferences() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/currency/preferences'),
        headers: _headers,
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'];
        _preferences = CurrencyPreferences.fromJson(data);
      }
    } catch (e) {
      debugPrint('Load preferences error: $e');
    }
    return _preferences;
  }
  
  /// Save user preferences
  Future<bool> savePreferences(CurrencyPreferences prefs) async {
    try {
      final response = await http.put(
        Uri.parse('$_baseUrl/currency/preferences'),
        headers: _headers,
        body: jsonEncode(prefs.toJson()),
      );
      
      if (response.statusCode == 200) {
        _preferences = prefs;
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Save preferences error: $e');
      return false;
    }
  }
  
  CurrencyPreferences get preferences => _preferences;
  
  /// Refresh user balances from Horizon
  Future<List<AssetBalance>> refreshBalances() async {
    if (_userPublicKey == null) return [];
    
    try {
      final response = await http.get(
        Uri.parse('$_horizonUrl/accounts/$_userPublicKey'),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final balances = data['balances'] as List;
        
        _balances = balances.map((b) {
          final assetType = b['asset_type'] as String;
          
          StellarAsset asset;
          if (assetType == 'native') {
            asset = StellarAsset.xlm;
          } else {
            final code = b['asset_code'] as String;
            final issuer = b['asset_issuer'] as String;
            final assetId = '$code:$issuer';
            asset = _assetRegistry[assetId] ?? StellarAsset(
              code: code,
              issuer: issuer,
              type: AssetType.token,
              name: code,
              symbol: code,
            );
          }
          
          return AssetBalance(
            asset: asset,
            balance: double.parse(b['balance'] as String),
            limit: b['limit'] != null ? double.parse(b['limit'] as String) : null,
            hasTrustline: true,
          );
        }).toList();
        
        debugPrint('💰 Refreshed ${_balances.length} balances');
      }
    } catch (e) {
      debugPrint('Refresh balances error: $e');
    }
    
    return _balances;
  }
  
  List<AssetBalance> get balances => _balances;
  
  /// Get balance for specific asset
  AssetBalance? getBalance(String assetCode) {
    return _balances.firstWhere(
      (b) => b.asset.code == assetCode,
      orElse: () => AssetBalance(
        asset: getAssetByCode(assetCode) ?? StellarAsset.xlm,
        balance: 0,
        hasTrustline: false,
      ),
    );
  }
  
  /// Add trustline for an asset
  Future<TrustlineResult> addTrustline(StellarAsset asset, {double? limit}) async {
    if (asset.isNative) {
      return TrustlineResult(success: false, error: 'Cannot add trustline for native asset');
    }
    
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/trustlines/add'),
        headers: _headers,
        body: jsonEncode({
          'asset_code': asset.code,
          'asset_issuer': asset.issuer,
          if (limit != null) 'limit': limit.toString(),
        }),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'];
        await refreshBalances();
        
        return TrustlineResult(
          success: true,
          transactionHash: data['transaction_hash'] as String?,
        );
      } else {
        final error = jsonDecode(response.body)['error'];
        return TrustlineResult(success: false, error: error);
      }
    } catch (e) {
      return TrustlineResult(success: false, error: e.toString());
    }
  }
  
  /// Remove trustline (must have zero balance)
  Future<TrustlineResult> removeTrustline(StellarAsset asset) async {
    if (asset.isNative) {
      return TrustlineResult(success: false, error: 'Cannot remove trustline for native asset');
    }
    
    // Check balance is zero
    final balance = getBalance(asset.code);
    if (balance != null && balance.balance > 0) {
      return TrustlineResult(success: false, error: 'Balance must be zero to remove trustline');
    }
    
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/trustlines/remove'),
        headers: _headers,
        body: jsonEncode({
          'asset_code': asset.code,
          'asset_issuer': asset.issuer,
        }),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'];
        await refreshBalances();
        
        return TrustlineResult(
          success: true,
          transactionHash: data['transaction_hash'] as String?,
        );
      } else {
        final error = jsonDecode(response.body)['error'];
        return TrustlineResult(success: false, error: error);
      }
    } catch (e) {
      return TrustlineResult(success: false, error: e.toString());
    }
  }
  
  /// Get exchange rate between two assets
  Future<ExchangeRate?> getExchangeRate(String fromAsset, String toAsset) async {
    if (fromAsset == toAsset) {
      return ExchangeRate(
        fromAsset: fromAsset,
        toAsset: toAsset,
        rate: 1.0,
        timestamp: DateTime.now(),
      );
    }
    
    final cacheKey = '$fromAsset:$toAsset';
    
    // Check cache
    if (_rateCache.containsKey(cacheKey) && !_rateCache[cacheKey]!.isStale) {
      return _rateCache[cacheKey];
    }
    
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/exchange/rate?from=$fromAsset&to=$toAsset'),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'];
        final rate = ExchangeRate.fromJson(data);
        _rateCache[cacheKey] = rate;
        return rate;
      }
      return null;
    } catch (e) {
      debugPrint('Get exchange rate error: $e');
      return null;
    }
  }
  
  /// Convert amount between currencies
  Future<double?> convert(double amount, String fromAsset, String toAsset) async {
    final rate = await getExchangeRate(fromAsset, toAsset);
    if (rate == null) return null;
    return rate.convert(amount);
  }
  
  /// Get all current rates (for display)
  Future<Map<String, ExchangeRate>> getAllRates() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/exchange/rates'),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'] as Map<String, dynamic>;
        _rateCache.clear();
        
        for (final entry in data.entries) {
          final rate = ExchangeRate.fromJson(entry.value);
          _rateCache[entry.key] = rate;
        }
        
        _ratesController.add(_rateCache);
      }
    } catch (e) {
      debugPrint('Get all rates error: $e');
    }
    
    return _rateCache;
  }
  
  void _startRateRefresh() {
    _rateRefreshTimer?.cancel();
    _rateRefreshTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => getAllRates(),
    );
  }
  
  /// Format amount with currency symbol
  String formatAmount(double amount, String assetCode) {
    final asset = getAssetByCode(assetCode);
    if (asset == null) return '$amount $assetCode';
    
    return '${asset.symbol}${amount.toStringAsFixed(2)}';
  }
  
  /// Get total portfolio value in display currency
  Future<double> getTotalPortfolioValue() async {
    double total = 0;
    
    for (final balance in _balances) {
      if (balance.balance > 0) {
        final usdValue = await convert(
          balance.balance,
          balance.asset.code,
          _preferences.displayCurrency,
        );
        if (usdValue != null) {
          total += usdValue;
        }
      }
    }
    
    return total;
  }
  
  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'X-GNS-Public-Key': _userPublicKey ?? '',
  };
  
  void dispose() {
    _rateRefreshTimer?.cancel();
    _ratesController.close();
  }
}

/// Asset type display extension
extension AssetTypeExtension on AssetType {
  String get displayName {
    switch (this) {
      case AssetType.native:
        return 'Native';
      case AssetType.stablecoin:
        return 'Stablecoin';
      case AssetType.token:
        return 'Token';
      case AssetType.anchor:
        return 'Anchored Asset';
    }
  }
  
  String get emoji {
    switch (this) {
      case AssetType.native:
        return '⭐';
      case AssetType.stablecoin:
        return '💵';
      case AssetType.token:
        return '🪙';
      case AssetType.anchor:
        return '⚓';
    }
  }
}
