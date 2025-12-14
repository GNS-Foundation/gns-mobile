// Financial Module - Phase 5
//
// Data model for payment endpoints within GnsModule.config.
// Schema: gns.module.financial/v1
//
// This module does NOT store private keys - only public endpoints
// and policy preferences. Private keys remain in secure storage.
//
// Location: lib/core/financial/financial_module.dart

import '../gns/gns_record.dart';

/// Payment endpoint types supported by GNS
abstract class PaymentEndpointType {
  // === FIAT RAILS ===
  static const sepaIban = 'sepa_iban';
  static const swiftAccount = 'swift_account';
  
  // === LIGHTNING ===
  static const lightningLnurl = 'lightning_lnurl';
  static const lightningAddress = 'lightning_address';
  
  // === ETHEREUM / EVM ===
  static const ethAddress = 'eth_address';
  static const evmToken = 'evm_token';  // ERC-20 (USDC, etc.)
  
  // === OTHER CHAINS ===
  static const solAddress = 'sol_address';
  static const btcAddress = 'btc_address';
  
  /// Get display name for endpoint type
  static String displayName(String type) {
    switch (type) {
      case sepaIban: return 'SEPA/IBAN';
      case swiftAccount: return 'SWIFT';
      case lightningLnurl: return 'Lightning (LNURL)';
      case lightningAddress: return 'Lightning Address';
      case ethAddress: return 'Ethereum';
      case evmToken: return 'EVM Token';
      case solAddress: return 'Solana';
      case btcAddress: return 'Bitcoin';
      default: return type;
    }
  }
  
  /// Get icon for endpoint type
  static String icon(String type) {
    switch (type) {
      case sepaIban:
      case swiftAccount:
        return '🏦';
      case lightningLnurl:
      case lightningAddress:
        return '⚡';
      case ethAddress:
      case evmToken:
        return '💎';
      case solAddress:
        return '☀️';
      case btcAddress:
        return '₿';
      default:
        return '💰';
    }
  }
  
  /// Check if this is a crypto rail
  static bool isCrypto(String type) {
    return [
      lightningLnurl, lightningAddress,
      ethAddress, evmToken,
      solAddress, btcAddress,
    ].contains(type);
  }
  
  /// Check if this is a fiat rail
  static bool isFiat(String type) {
    return [sepaIban, swiftAccount].contains(type);
  }
}

/// A single payment endpoint
class PaymentEndpoint {
  /// Endpoint identifier (unique within the financial module)
  final String id;
  
  /// Endpoint type (see PaymentEndpointType)
  final String type;
  
  /// Currency code (EUR, USD, BTC, ETH, USDC, etc.)
  final String currency;
  
  /// The actual address/value
  /// - IBAN: "IT60X0542811101000000123456"
  /// - LNURL: "lnurlp://pay.example.com/user"
  /// - Lightning Address: "user@pay.example.com"
  /// - ETH: "0xabc123..."
  /// - SOL: "So1anaPubKey..."
  final String value;
  
  /// Optional display label
  final String? label;
  
  /// For EVM tokens: chain name (ethereum, polygon, arbitrum, etc.)
  final String? chain;
  
  /// Additional metadata
  final Map<String, dynamic>? metadata;

  PaymentEndpoint({
    required this.id,
    required this.type,
    required this.currency,
    required this.value,
    this.label,
    this.chain,
    this.metadata,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'currency': currency,
    'value': value,
    if (label != null) 'label': label,
    if (chain != null) 'chain': chain,
    if (metadata != null) 'metadata': metadata,
  };

  factory PaymentEndpoint.fromJson(Map<String, dynamic> json) {
    return PaymentEndpoint(
      id: json['id'] as String,
      type: json['type'] as String,
      currency: json['currency'] as String,
      value: json['value'] as String,
      label: json['label'] as String?,
      chain: json['chain'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  /// Create SEPA/IBAN endpoint
  static PaymentEndpoint sepaIban(String iban, {String? label}) => PaymentEndpoint(
    id: 'iban_${iban.hashCode.abs()}',
    type: PaymentEndpointType.sepaIban,
    currency: 'EUR',
    value: iban.replaceAll(' ', '').toUpperCase(),
    label: label ?? 'Bank Account',
  );

  /// Create Lightning LNURL endpoint
  static PaymentEndpoint lightningLnurl(String lnurl, {String currency = 'BTC', String? label}) => PaymentEndpoint(
    id: 'ln_${lnurl.hashCode.abs()}',
    type: PaymentEndpointType.lightningLnurl,
    currency: currency,
    value: lnurl,
    label: label ?? 'Lightning',
  );

  /// Create Lightning Address endpoint
  static PaymentEndpoint lightningAddress(String address, {String currency = 'BTC', String? label}) => PaymentEndpoint(
    id: 'lna_${address.hashCode.abs()}',
    type: PaymentEndpointType.lightningAddress,
    currency: currency,
    value: address,
    label: label ?? 'Lightning Address',
  );

  /// Create Ethereum address endpoint
  static PaymentEndpoint ethereum(String address, {String? label}) => PaymentEndpoint(
    id: 'eth_${address.hashCode.abs()}',
    type: PaymentEndpointType.ethAddress,
    currency: 'ETH',
    value: address,
    label: label ?? 'Ethereum',
    chain: 'ethereum',
  );

  /// Create USDC endpoint on specific chain
  static PaymentEndpoint usdc(String address, {required String chain, String? label}) => PaymentEndpoint(
    id: 'usdc_${chain}_${address.hashCode.abs()}',
    type: PaymentEndpointType.evmToken,
    currency: 'USDC',
    value: address,
    label: label ?? 'USDC ($chain)',
    chain: chain,
  );

  /// Create Solana address endpoint
  static PaymentEndpoint solana(String address, {String? label}) => PaymentEndpoint(
    id: 'sol_${address.hashCode.abs()}',
    type: PaymentEndpointType.solAddress,
    currency: 'SOL',
    value: address,
    label: label ?? 'Solana',
  );

  /// Create Bitcoin address endpoint
  static PaymentEndpoint bitcoin(String address, {String? label}) => PaymentEndpoint(
    id: 'btc_${address.hashCode.abs()}',
    type: PaymentEndpointType.btcAddress,
    currency: 'BTC',
    value: address,
    label: label ?? 'Bitcoin',
  );

  /// Get display name
  String get displayName => label ?? PaymentEndpointType.displayName(type);
  
  /// Get icon
  String get icon => PaymentEndpointType.icon(type);
  
  /// Is this a crypto endpoint?
  bool get isCrypto => PaymentEndpointType.isCrypto(type);
  
  /// Is this a fiat endpoint?
  bool get isFiat => PaymentEndpointType.isFiat(type);

  @override
  String toString() => 'PaymentEndpoint($id: $type/$currency)';
}

/// Payment limits configuration
class PaymentLimits {
  /// Soft daily limit (warning threshold)
  final double dailySoftLimit;
  
  /// Hard daily limit (blocking threshold)
  final double dailyHardLimit;
  
  /// Per-transaction limit
  final double? perTransactionLimit;
  
  /// Monthly limit
  final double? monthlyLimit;

  PaymentLimits({
    this.dailySoftLimit = 200.0,
    this.dailyHardLimit = 1000.0,
    this.perTransactionLimit,
    this.monthlyLimit,
  });

  Map<String, dynamic> toJson() => {
    'daily_soft_limit': dailySoftLimit,
    'daily_hard_limit': dailyHardLimit,
    if (perTransactionLimit != null) 'per_transaction_limit': perTransactionLimit,
    if (monthlyLimit != null) 'monthly_limit': monthlyLimit,
  };

  factory PaymentLimits.fromJson(Map<String, dynamic>? json) {
    if (json == null) return PaymentLimits();
    return PaymentLimits(
      dailySoftLimit: (json['daily_soft_limit'] as num?)?.toDouble() ?? 200.0,
      dailyHardLimit: (json['daily_hard_limit'] as num?)?.toDouble() ?? 1000.0,
      perTransactionLimit: (json['per_transaction_limit'] as num?)?.toDouble(),
      monthlyLimit: (json['monthly_limit'] as num?)?.toDouble(),
    );
  }

  PaymentLimits copyWith({
    double? dailySoftLimit,
    double? dailyHardLimit,
    double? perTransactionLimit,
    double? monthlyLimit,
  }) {
    return PaymentLimits(
      dailySoftLimit: dailySoftLimit ?? this.dailySoftLimit,
      dailyHardLimit: dailyHardLimit ?? this.dailyHardLimit,
      perTransactionLimit: perTransactionLimit ?? this.perTransactionLimit,
      monthlyLimit: monthlyLimit ?? this.monthlyLimit,
    );
  }
}

/// Payment settings
class PaymentSettings {
  /// Auto-accept payments below this amount
  final bool autoAcceptSmallPayments;
  
  /// Threshold for auto-accept (in preferred currency)
  final double smallPaymentThreshold;
  
  /// Require same H3 cell for payments
  final bool requirePresence;
  
  /// Presence radius in meters (0 = same cell only)
  final int presenceRadiusMeters;

  PaymentSettings({
    this.autoAcceptSmallPayments = true,
    this.smallPaymentThreshold = 5.0,
    this.requirePresence = false,
    this.presenceRadiusMeters = 0,
  });

  Map<String, dynamic> toJson() => {
    'auto_accept_small_payments': autoAcceptSmallPayments,
    'small_payment_threshold': smallPaymentThreshold,
    'require_presence': requirePresence,
    'presence_radius_meters': presenceRadiusMeters,
  };

  factory PaymentSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) return PaymentSettings();
    return PaymentSettings(
      autoAcceptSmallPayments: json['auto_accept_small_payments'] as bool? ?? true,
      smallPaymentThreshold: (json['small_payment_threshold'] as num?)?.toDouble() ?? 5.0,
      requirePresence: json['require_presence'] as bool? ?? false,
      presenceRadiusMeters: json['presence_radius_meters'] as int? ?? 0,
    );
  }
}

/// Financial module data stored in GnsModule.config
class FinancialData {
  /// Supported currencies for receiving payments
  final List<String> supportedCurrencies;
  
  /// Preferred currency for display
  final String preferredCurrency;
  
  /// Payment endpoints
  final List<PaymentEndpoint> paymentEndpoints;
  
  /// Payment limits
  final PaymentLimits limits;
  
  /// Payment settings
  final PaymentSettings settings;

  FinancialData({
    List<String>? supportedCurrencies,
    this.preferredCurrency = 'EUR',
    List<PaymentEndpoint>? paymentEndpoints,
    PaymentLimits? limits,
    PaymentSettings? settings,
  }) : 
    supportedCurrencies = supportedCurrencies ?? ['EUR', 'USD'],
    paymentEndpoints = paymentEndpoints ?? [],
    limits = limits ?? PaymentLimits(),
    settings = settings ?? PaymentSettings();

  Map<String, dynamic> toJson() => {
    'supported_currencies': supportedCurrencies,
    'preferred_currency': preferredCurrency,
    'payment_endpoints': paymentEndpoints.map((e) => e.toJson()).toList(),
    'limits': limits.toJson(),
    'settings': settings.toJson(),
  };

  factory FinancialData.fromJson(Map<String, dynamic>? json) {
    if (json == null) return FinancialData();
    
    return FinancialData(
      supportedCurrencies: json['supported_currencies'] != null
          ? List<String>.from(json['supported_currencies'] as List)
          : null,
      preferredCurrency: json['preferred_currency'] as String? ?? 'EUR',
      paymentEndpoints: json['payment_endpoints'] != null
          ? (json['payment_endpoints'] as List)
              .map((e) => PaymentEndpoint.fromJson(e as Map<String, dynamic>))
              .toList()
          : null,
      limits: PaymentLimits.fromJson(json['limits'] as Map<String, dynamic>?),
      settings: PaymentSettings.fromJson(json['settings'] as Map<String, dynamic>?),
    );
  }

  /// Find endpoint by ID
  PaymentEndpoint? getEndpoint(String id) {
    try {
      return paymentEndpoints.firstWhere((e) => e.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Find endpoints by type
  List<PaymentEndpoint> getEndpointsByType(String type) {
    return paymentEndpoints.where((e) => e.type == type).toList();
  }

  /// Find endpoints by currency
  List<PaymentEndpoint> getEndpointsByCurrency(String currency) {
    return paymentEndpoints.where((e) => e.currency == currency).toList();
  }

  /// Get all unique currencies from endpoints
  Set<String> get availableCurrencies {
    return paymentEndpoints.map((e) => e.currency).toSet();
  }

  /// Check if any endpoint supports the given currency
  bool supportsCurrency(String currency) {
    return paymentEndpoints.any((e) => e.currency == currency);
  }

  /// Check if any endpoint supports the given type
  bool supportsType(String type) {
    return paymentEndpoints.any((e) => e.type == type);
  }

  /// Create a copy with updated fields
  FinancialData copyWith({
    List<String>? supportedCurrencies,
    String? preferredCurrency,
    List<PaymentEndpoint>? paymentEndpoints,
    PaymentLimits? limits,
    PaymentSettings? settings,
  }) {
    return FinancialData(
      supportedCurrencies: supportedCurrencies ?? this.supportedCurrencies,
      preferredCurrency: preferredCurrency ?? this.preferredCurrency,
      paymentEndpoints: paymentEndpoints ?? this.paymentEndpoints,
      limits: limits ?? this.limits,
      settings: settings ?? this.settings,
    );
  }

  /// Add a payment endpoint
  FinancialData addEndpoint(PaymentEndpoint endpoint) {
    // Remove existing endpoint with same ID if present
    final updated = paymentEndpoints.where((e) => e.id != endpoint.id).toList();
    updated.add(endpoint);
    return copyWith(paymentEndpoints: updated);
  }

  /// Remove a payment endpoint
  FinancialData removeEndpoint(String endpointId) {
    return copyWith(
      paymentEndpoints: paymentEndpoints.where((e) => e.id != endpointId).toList(),
    );
  }

  /// Check if module has any endpoints configured
  bool get isEmpty => paymentEndpoints.isEmpty;
  bool get isNotEmpty => !isEmpty;

  @override
  String toString() => 'FinancialData(${paymentEndpoints.length} endpoints)';
}

/// Schema identifier for Financial Module
abstract class FinancialModuleSchemas {
  static const financial = 'gns.module.financial/v1';
}

/// Helper class for creating and extracting financial modules
class FinancialModule {
  static const String moduleId = 'financial';
  static const String schema = FinancialModuleSchemas.financial;

  /// Create a GnsModule containing financial data
  static GnsModule create(FinancialData data) {
    return GnsModule(
      id: moduleId,
      schema: schema,
      name: 'Financial',
      description: 'Payment endpoints and financial preferences',
      isPublic: false,  // Financial data is private by default
      config: data.toJson(),
    );
  }

  /// Extract FinancialData from a GnsModule
  static FinancialData? extract(GnsModule module) {
    if (module.id != moduleId || module.schema != schema) {
      return null;
    }
    return FinancialData.fromJson(module.config);
  }

  /// Find and extract financial data from a list of modules
  static FinancialData? fromModules(List<GnsModule> modules) {
    try {
      final financialModule = modules.firstWhere(
        (m) => m.id == moduleId && m.schema == schema,
      );
      return extract(financialModule);
    } catch (_) {
      return null;
    }
  }

  /// Update or add financial module in a list
  static List<GnsModule> updateInModules(List<GnsModule> modules, FinancialData data) {
    final newModule = create(data);
    final index = modules.indexWhere((m) => m.id == moduleId);
    
    if (index >= 0) {
      // Replace existing
      final updated = List<GnsModule>.from(modules);
      updated[index] = newModule;
      return updated;
    } else {
      // Add new
      return [...modules, newModule];
    }
  }

  /// Extract financial data from a GnsRecord
  static FinancialData? fromRecord(GnsRecord record) {
    return fromModules(record.modules);
  }
}
