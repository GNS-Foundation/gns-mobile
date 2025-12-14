/// IDUP Router - Identity-Driven Universal Payment Router
/// 
/// Client-side subsystem that selects payment rails between GNS identities.
/// GNS does NOT move money - it routes payment intents to the best rail.
/// 
/// Chapter 6 of GNS Financial Layer Specification
/// 
/// Location: lib/core/financial/idup_router.dart

import 'package:uuid/uuid.dart';
import 'financial_module.dart';
import 'payment_payload.dart';

/// Result of route selection
class RouteResult {
  /// Selected route
  final PaymentRoute route;
  
  /// Recipient's endpoint
  final PaymentEndpoint endpoint;
  
  /// Effective currency (after any conversion)
  final String effectiveCurrency;
  
  /// Estimated fee (if available)
  final double? estimatedFee;
  
  /// Estimated time to settlement
  final Duration? estimatedSettlementTime;
  
  /// Why this route was selected
  final String selectionReason;

  RouteResult({
    required this.route,
    required this.endpoint,
    required this.effectiveCurrency,
    this.estimatedFee,
    this.estimatedSettlementTime,
    required this.selectionReason,
  });

  @override
  String toString() => 'RouteResult(${route.type} -> ${endpoint.id})';
}

/// Route selection error
class RouteSelectionError {
  final String code;
  final String message;

  RouteSelectionError(this.code, this.message);

  static final noCompatibleRail = RouteSelectionError(
    'NO_COMPATIBLE_RAIL',
    'No compatible payment rail found between sender and recipient',
  );
  
  static final currencyMismatch = RouteSelectionError(
    'CURRENCY_MISMATCH',
    'No endpoint supports the requested currency',
  );
  
  static final noEndpoints = RouteSelectionError(
    'NO_ENDPOINTS',
    'Recipient has no payment endpoints configured',
  );
  
  static final senderNotSupported = RouteSelectionError(
    'SENDER_NOT_SUPPORTED',
    'Sender does not support any of the recipient\'s rails',
  );

  @override
  String toString() => 'RouteSelectionError($code: $message)';
}

/// Sender's routing preferences
class RoutingPreferences {
  /// Preferred fiat rail (sepa_iban, swift_account)
  final String? preferredFiatRail;
  
  /// Preferred crypto rail (lightning_lnurl, eth_address, etc.)
  final String? preferredCryptoRail;
  
  /// Avoid high fees
  final bool avoidHighFees;
  
  /// Maximum acceptable fee (in sender's currency)
  final double? maxFee;
  
  /// Prefer instant settlement
  final bool preferInstant;
  
  /// Rails the sender can actually use (has wallets/accounts for)
  final Set<String> supportedRails;

  RoutingPreferences({
    this.preferredFiatRail,
    this.preferredCryptoRail,
    this.avoidHighFees = true,
    this.maxFee,
    this.preferInstant = true,
    Set<String>? supportedRails,
  }) : supportedRails = supportedRails ?? _defaultSupportedRails;

  static final _defaultSupportedRails = {
    PaymentEndpointType.sepaIban,
    PaymentEndpointType.lightningLnurl,
    PaymentEndpointType.lightningAddress,
    PaymentEndpointType.ethAddress,
    PaymentEndpointType.evmToken,
  };

  Map<String, dynamic> toJson() => {
    if (preferredFiatRail != null) 'preferred_fiat_rail': preferredFiatRail,
    if (preferredCryptoRail != null) 'preferred_crypto_rail': preferredCryptoRail,
    'avoid_high_fees': avoidHighFees,
    if (maxFee != null) 'max_fee': maxFee,
    'prefer_instant': preferInstant,
    'supported_rails': supportedRails.toList(),
  };

  factory RoutingPreferences.fromJson(Map<String, dynamic>? json) {
    if (json == null) return RoutingPreferences();
    return RoutingPreferences(
      preferredFiatRail: json['preferred_fiat_rail'] as String?,
      preferredCryptoRail: json['preferred_crypto_rail'] as String?,
      avoidHighFees: json['avoid_high_fees'] as bool? ?? true,
      maxFee: (json['max_fee'] as num?)?.toDouble(),
      preferInstant: json['prefer_instant'] as bool? ?? true,
      supportedRails: json['supported_rails'] != null
          ? Set<String>.from(json['supported_rails'] as List)
          : null,
    );
  }
}

/// Rail characteristics for scoring
class _RailCharacteristics {
  final bool isInstant;
  final double typicalFeePercent;
  final int priorityScore;

  const _RailCharacteristics({
    required this.isInstant,
    required this.typicalFeePercent,
    required this.priorityScore,
  });
}

/// IDUP Router - selects payment rails between GNS identities
class IdupRouter {
  static const _uuid = Uuid();

  /// Rail characteristics (for scoring)
  static const _railCharacteristics = {
    PaymentEndpointType.lightningLnurl: _RailCharacteristics(
      isInstant: true,
      typicalFeePercent: 0.1,
      priorityScore: 100,
    ),
    PaymentEndpointType.lightningAddress: _RailCharacteristics(
      isInstant: true,
      typicalFeePercent: 0.1,
      priorityScore: 95,
    ),
    PaymentEndpointType.sepaIban: _RailCharacteristics(
      isInstant: false,  // SEPA Instant is fast, regular SEPA is 1-2 days
      typicalFeePercent: 0.0,
      priorityScore: 80,
    ),
    PaymentEndpointType.ethAddress: _RailCharacteristics(
      isInstant: false,  // ~15 seconds, but feels slower than Lightning
      typicalFeePercent: 1.0,  // Gas fees vary
      priorityScore: 60,
    ),
    PaymentEndpointType.evmToken: _RailCharacteristics(
      isInstant: false,
      typicalFeePercent: 1.0,
      priorityScore: 55,
    ),
    PaymentEndpointType.solAddress: _RailCharacteristics(
      isInstant: true,  // ~400ms
      typicalFeePercent: 0.01,
      priorityScore: 70,
    ),
    PaymentEndpointType.btcAddress: _RailCharacteristics(
      isInstant: false,  // 10+ minutes
      typicalFeePercent: 0.5,
      priorityScore: 40,
    ),
  };

  /// Select the best route for a payment
  /// 
  /// Returns either a RouteResult or a RouteSelectionError
  static dynamic selectRoute({
    required FinancialData? senderFinancial,
    required FinancialData recipientFinancial,
    required double amount,
    required String currency,
    RoutingPreferences? preferences,
  }) {
    preferences ??= RoutingPreferences();

    // Check recipient has endpoints
    if (recipientFinancial.paymentEndpoints.isEmpty) {
      return RouteSelectionError.noEndpoints;
    }

    // Find compatible endpoints
    final candidates = <_RouteCandidate>[];

    for (final endpoint in recipientFinancial.paymentEndpoints) {
      // Check currency compatibility
      if (!_isCurrencyCompatible(endpoint.currency, currency)) {
        continue;
      }

      // Check sender supports this rail
      if (!preferences.supportedRails.contains(endpoint.type)) {
        continue;
      }

      // Score this route
      final score = _scoreRoute(endpoint, preferences, amount);
      candidates.add(_RouteCandidate(endpoint: endpoint, score: score));
    }

    if (candidates.isEmpty) {
      return RouteSelectionError.noCompatibleRail;
    }

    // Sort by score (highest first)
    candidates.sort((a, b) => b.score.compareTo(a.score));

    final bestCandidate = candidates.first;
    final endpoint = bestCandidate.endpoint;
    final characteristics = _railCharacteristics[endpoint.type];

    return RouteResult(
      route: PaymentRoute(
        type: endpoint.type,
        endpointId: endpoint.id,
        chain: endpoint.chain,
      ),
      endpoint: endpoint,
      effectiveCurrency: endpoint.currency,
      estimatedFee: characteristics != null
          ? amount * (characteristics.typicalFeePercent / 100)
          : null,
      estimatedSettlementTime: _estimatedSettlementTime(endpoint.type),
      selectionReason: _selectionReason(endpoint, preferences),
    );
  }

  /// Check if currencies are compatible
  static bool _isCurrencyCompatible(String endpointCurrency, String requestedCurrency) {
    // Direct match
    if (endpointCurrency == requestedCurrency) return true;

    // Stablecoin equivalence (USDC, USDT ~ USD)
    final usdEquivalent = {'USD', 'USDC', 'USDT', 'DAI'};
    if (usdEquivalent.contains(endpointCurrency) && 
        usdEquivalent.contains(requestedCurrency)) {
      return true;
    }

    // Euro stablecoins
    final eurEquivalent = {'EUR', 'EURS', 'EUROC'};
    if (eurEquivalent.contains(endpointCurrency) && 
        eurEquivalent.contains(requestedCurrency)) {
      return true;
    }

    // BTC via Lightning
    if (endpointCurrency == 'BTC' && requestedCurrency == 'SATS') return true;
    if (endpointCurrency == 'SATS' && requestedCurrency == 'BTC') return true;

    return false;
  }

  /// Score a route candidate
  static int _scoreRoute(
    PaymentEndpoint endpoint,
    RoutingPreferences preferences,
    double amount,
  ) {
    int score = 0;

    final characteristics = _railCharacteristics[endpoint.type];
    if (characteristics != null) {
      score += characteristics.priorityScore;

      // Bonus for instant if preferred
      if (preferences.preferInstant && characteristics.isInstant) {
        score += 20;
      }

      // Penalty for high fees if avoiding
      if (preferences.avoidHighFees && characteristics.typicalFeePercent > 0.5) {
        score -= 15;
      }
    }

    // Bonus for preferred rails
    if (endpoint.isFiat && endpoint.type == preferences.preferredFiatRail) {
      score += 30;
    }
    if (endpoint.isCrypto && endpoint.type == preferences.preferredCryptoRail) {
      score += 30;
    }

    return score;
  }

  /// Get estimated settlement time for a rail
  static Duration? _estimatedSettlementTime(String railType) {
    switch (railType) {
      case PaymentEndpointType.lightningLnurl:
      case PaymentEndpointType.lightningAddress:
        return const Duration(seconds: 2);
      case PaymentEndpointType.solAddress:
        return const Duration(seconds: 1);
      case PaymentEndpointType.ethAddress:
      case PaymentEndpointType.evmToken:
        return const Duration(seconds: 15);
      case PaymentEndpointType.btcAddress:
        return const Duration(minutes: 10);
      case PaymentEndpointType.sepaIban:
        return const Duration(days: 1);
      default:
        return null;
    }
  }

  /// Generate selection reason for debugging/UI
  static String _selectionReason(PaymentEndpoint endpoint, RoutingPreferences preferences) {
    final reasons = <String>[];

    if (endpoint.type == preferences.preferredFiatRail ||
        endpoint.type == preferences.preferredCryptoRail) {
      reasons.add('Preferred rail');
    }

    final characteristics = _railCharacteristics[endpoint.type];
    if (characteristics != null) {
      if (characteristics.isInstant) {
        reasons.add('Instant settlement');
      }
      if (characteristics.typicalFeePercent < 0.5) {
        reasons.add('Low fees');
      }
    }

    if (reasons.isEmpty) {
      reasons.add('Best available option');
    }

    return reasons.join(', ');
  }

  /// Build a PaymentTransferPayload from route selection
  static PaymentTransferPayload buildPayload({
    required String fromPublicKey,
    required String toPublicKey,
    required RouteResult routeResult,
    required String amount,
    required String currency,
    String? memo,
    String? clientReference,
    PaymentConstraints? constraints,
  }) {
    return PaymentTransferPayload(
      paymentId: _uuid.v4(),
      fromPublicKey: fromPublicKey,
      toPublicKey: toPublicKey,
      amount: amount,
      currency: currency,
      memo: memo,
      clientReference: clientReference,
      route: routeResult.route,
      constraints: constraints,
    );
  }

  /// Quick helper to select route and build payload in one call
  static dynamic createPayment({
    required String fromPublicKey,
    required String toPublicKey,
    required FinancialData? senderFinancial,
    required FinancialData recipientFinancial,
    required String amount,
    required String currency,
    String? memo,
    String? clientReference,
    PaymentConstraints? constraints,
    RoutingPreferences? preferences,
  }) {
    final routeResult = selectRoute(
      senderFinancial: senderFinancial,
      recipientFinancial: recipientFinancial,
      amount: double.parse(amount),
      currency: currency,
      preferences: preferences,
    );

    if (routeResult is RouteSelectionError) {
      return routeResult;
    }

    return buildPayload(
      fromPublicKey: fromPublicKey,
      toPublicKey: toPublicKey,
      routeResult: routeResult as RouteResult,
      amount: amount,
      currency: currency,
      memo: memo,
      clientReference: clientReference,
      constraints: constraints,
    );
  }
}

/// Internal route candidate for scoring
class _RouteCandidate {
  final PaymentEndpoint endpoint;
  final int score;

  _RouteCandidate({required this.endpoint, required this.score});
}

/// Extension to check if a FinancialData supports sending to a specific rail
extension FinancialDataRouting on FinancialData {
  /// Check if we have an endpoint that can send to this rail type
  bool canSendVia(String railType) {
    // For now, we assume the sender can send via any rail they have an endpoint for
    // In practice, this would check wallet integrations
    return supportsType(railType);
  }

  /// Get the best endpoint for a specific currency
  PaymentEndpoint? getBestEndpointForCurrency(String currency) {
    final endpoints = getEndpointsByCurrency(currency);
    if (endpoints.isEmpty) return null;
    
    // Prefer Lightning for speed
    final lightning = endpoints.where((e) => 
      e.type == PaymentEndpointType.lightningLnurl ||
      e.type == PaymentEndpointType.lightningAddress
    ).firstOrNull;
    if (lightning != null) return lightning;
    
    return endpoints.first;
  }
}
