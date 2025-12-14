/// GNS Payment Payloads - Financial Content Types
/// 
/// Extends the GNS payload system with payment-specific types.
/// These payloads are transported inside encrypted GNS envelopes.
/// 
/// Location: lib/core/financial/payment_payload.dart

import 'dart:convert';
import 'dart:typed_data';

// Base class for all GNS payloads
abstract class GnsPayload {
  String get type;
  Map<String, dynamic> toJson();
}

/// Payment-specific payload type identifiers
/// 
/// Format: gns/payment.<subtype>
abstract class PaymentPayloadType {
  // === CORE PAYMENT TYPES ===
  
  /// Standard one-to-one payment intent
  static const transfer = 'gns/payment.transfer';
  
  /// Payment request / invoice
  static const request = 'gns/payment.request';
  
  /// Payment confirmation / settlement proof
  static const settlement = 'gns/payment.settlement';
  
  /// Payment acknowledgment (accepted/rejected)
  static const ack = 'gns/payment.ack';
  
  // === GNS-GEOAUTH TYPES ===
  
  /// Geospatial payment authorization token
  static const geoAuth = 'gns/auth.geo';
  
  /// GeoAuth challenge (from merchant)
  static const geoAuthChallenge = 'gns/auth.geo.challenge';
  
  /// GeoAuth response (from user)
  static const geoAuthResponse = 'gns/auth.geo.response';
}

/// Route information for payment
class PaymentRoute {
  /// Rail type (lightning_lnurl, sepa_iban, eth_address, etc.)
  final String type;
  
  /// Endpoint ID from recipient's FinancialModule
  final String endpointId;
  
  /// Chain (for EVM/multi-chain payments)
  final String? chain;
  
  /// Additional route metadata
  final Map<String, dynamic>? metadata;

  PaymentRoute({
    required this.type,
    required this.endpointId,
    this.chain,
    this.metadata,
  });

  Map<String, dynamic> toJson() => {
    'type': type,
    'endpoint_id': endpointId,
    if (chain != null) 'chain': chain,
    if (metadata != null) 'metadata': metadata,
  };

  factory PaymentRoute.fromJson(Map<String, dynamic> json) {
    return PaymentRoute(
      type: json['type'] as String,
      endpointId: json['endpoint_id'] as String,
      chain: json['chain'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  @override
  String toString() => 'PaymentRoute($type -> $endpointId)';
}

/// Constraints on a payment
class PaymentConstraints {
  /// Payment expires at this Unix timestamp
  final int? expiresAt;
  
  /// Maximum slippage for FX/crypto (0.01 = 1%)
  final double? maxSlippage;
  
  /// Require same H3 cell (geo-limited payment)
  final bool requireSameCell;
  
  /// Maximum distance in meters (if requireSameCell is false)
  final int? maxDistanceMeters;
  
  /// Allowed H3 cells (whitelist)
  final List<String>? allowedCells;

  PaymentConstraints({
    this.expiresAt,
    this.maxSlippage,
    this.requireSameCell = false,
    this.maxDistanceMeters,
    this.allowedCells,
  });

  Map<String, dynamic> toJson() => {
    if (expiresAt != null) 'expires_at': expiresAt,
    if (maxSlippage != null) 'max_slippage': maxSlippage,
    'require_same_cell': requireSameCell,
    if (maxDistanceMeters != null) 'max_distance_meters': maxDistanceMeters,
    if (allowedCells != null) 'allowed_cells': allowedCells,
  };

  factory PaymentConstraints.fromJson(Map<String, dynamic>? json) {
    if (json == null) return PaymentConstraints();
    return PaymentConstraints(
      expiresAt: json['expires_at'] as int?,
      maxSlippage: (json['max_slippage'] as num?)?.toDouble(),
      requireSameCell: json['require_same_cell'] as bool? ?? false,
      maxDistanceMeters: json['max_distance_meters'] as int?,
      allowedCells: json['allowed_cells'] != null 
          ? List<String>.from(json['allowed_cells'] as List)
          : null,
    );
  }

  /// Check if payment has expired
  bool get isExpired {
    if (expiresAt == null) return false;
    return DateTime.now().millisecondsSinceEpoch > expiresAt!;
  }

  /// Create constraints with expiration
  static PaymentConstraints withExpiry(Duration duration) {
    return PaymentConstraints(
      expiresAt: DateTime.now().add(duration).millisecondsSinceEpoch,
    );
  }

  /// Create geo-limited constraints
  static PaymentConstraints geoLimited({bool sameCell = true, int? maxMeters}) {
    return PaymentConstraints(
      requireSameCell: sameCell,
      maxDistanceMeters: maxMeters,
    );
  }
}

/// Payment transfer payload (the main payment intent)
/// 
/// This is the plaintext structure before encryption.
/// Sent with payloadType: gns/payment.transfer
class PaymentTransferPayload extends GnsPayload {
  @override
  String get type => PaymentPayloadType.transfer;
  
  /// Payload schema version
  final int version;
  
  /// Client-generated payment ID (UUID)
  final String paymentId;
  
  /// Sender's public key (pkRoot)
  final String fromPublicKey;
  
  /// Recipient's public key (pkRoot)
  final String toPublicKey;
  
  /// Amount as string (to preserve precision)
  final String amount;
  
  /// Currency code (EUR, USD, BTC, etc.)
  final String currency;
  
  /// Human-readable memo/description
  final String? memo;
  
  /// Client-side reference (order ID, etc.)
  final String? clientReference;
  
  /// Selected payment route
  final PaymentRoute route;
  
  /// Payment constraints
  final PaymentConstraints? constraints;
  
  /// Creation timestamp (Unix ms)
  final int createdAt;

  PaymentTransferPayload({
    this.version = 1,
    required this.paymentId,
    required this.fromPublicKey,
    required this.toPublicKey,
    required this.amount,
    required this.currency,
    this.memo,
    this.clientReference,
    required this.route,
    this.constraints,
    int? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;

  @override
  Map<String, dynamic> toJson() => {
    'version': version,
    'payment_id': paymentId,
    'from_public_key': fromPublicKey,
    'to_public_key': toPublicKey,
    'amount': amount,
    'currency': currency,
    if (memo != null) 'memo': memo,
    if (clientReference != null) 'client_reference': clientReference,
    'route': route.toJson(),
    if (constraints != null) 'constraints': constraints!.toJson(),
    'created_at': createdAt,
  };

  factory PaymentTransferPayload.fromJson(Map<String, dynamic> json) {
    return PaymentTransferPayload(
      version: json['version'] as int? ?? 1,
      paymentId: json['payment_id'] as String,
      fromPublicKey: json['from_public_key'] as String,
      toPublicKey: json['to_public_key'] as String,
      amount: json['amount'] as String,
      currency: json['currency'] as String,
      memo: json['memo'] as String?,
      clientReference: json['client_reference'] as String?,
      route: PaymentRoute.fromJson(json['route'] as Map<String, dynamic>),
      constraints: json['constraints'] != null
          ? PaymentConstraints.fromJson(json['constraints'] as Map<String, dynamic>)
          : null,
      createdAt: json['created_at'] as int,
    );
  }

  /// Parse amount to double
  double get amountDouble => double.parse(amount);

  /// Check if payment is expired
  bool get isExpired => constraints?.isExpired ?? false;

  /// Check if geo-limited
  bool get isGeoLimited => constraints?.requireSameCell ?? false;

  @override
  String toString() => 'PaymentTransferPayload($paymentId: $amount $currency)';
}

/// Payment request payload (invoice/request for payment)
/// 
/// Sent with payloadType: gns/payment.request
class PaymentRequestPayload extends GnsPayload {
  @override
  String get type => PaymentPayloadType.request;
  
  final int version;
  final String requestId;
  final String fromPublicKey;  // Requester (who wants money)
  final String toPublicKey;    // Requestee (who should pay)
  final String amount;
  final String currency;
  final String? memo;
  final String? invoiceData;   // External invoice (BOLT11, etc.)
  final PaymentConstraints? constraints;
  final int createdAt;

  PaymentRequestPayload({
    this.version = 1,
    required this.requestId,
    required this.fromPublicKey,
    required this.toPublicKey,
    required this.amount,
    required this.currency,
    this.memo,
    this.invoiceData,
    this.constraints,
    int? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;

  @override
  Map<String, dynamic> toJson() => {
    'version': version,
    'request_id': requestId,
    'from_public_key': fromPublicKey,
    'to_public_key': toPublicKey,
    'amount': amount,
    'currency': currency,
    if (memo != null) 'memo': memo,
    if (invoiceData != null) 'invoice_data': invoiceData,
    if (constraints != null) 'constraints': constraints!.toJson(),
    'created_at': createdAt,
  };

  factory PaymentRequestPayload.fromJson(Map<String, dynamic> json) {
    return PaymentRequestPayload(
      version: json['version'] as int? ?? 1,
      requestId: json['request_id'] as String,
      fromPublicKey: json['from_public_key'] as String,
      toPublicKey: json['to_public_key'] as String,
      amount: json['amount'] as String,
      currency: json['currency'] as String,
      memo: json['memo'] as String?,
      invoiceData: json['invoice_data'] as String?,
      constraints: json['constraints'] != null
          ? PaymentConstraints.fromJson(json['constraints'] as Map<String, dynamic>)
          : null,
      createdAt: json['created_at'] as int,
    );
  }
}

/// Payment acknowledgment payload
/// 
/// Sent with payloadType: gns/payment.ack
class PaymentAckPayload extends GnsPayload {
  @override
  String get type => PaymentPayloadType.ack;
  
  final String paymentId;
  final String status;  // 'accepted' | 'rejected' | 'pending'
  final String? reason;
  final int timestamp;

  PaymentAckPayload({
    required this.paymentId,
    required this.status,
    this.reason,
    int? timestamp,
  }) : timestamp = timestamp ?? DateTime.now().millisecondsSinceEpoch;

  @override
  Map<String, dynamic> toJson() => {
    'payment_id': paymentId,
    'status': status,
    if (reason != null) 'reason': reason,
    'timestamp': timestamp,
  };

  factory PaymentAckPayload.fromJson(Map<String, dynamic> json) {
    return PaymentAckPayload(
      paymentId: json['payment_id'] as String,
      status: json['status'] as String,
      reason: json['reason'] as String?,
      timestamp: json['timestamp'] as int,
    );
  }

  /// Create accepted acknowledgment
  factory PaymentAckPayload.accepted(String paymentId) => PaymentAckPayload(
    paymentId: paymentId,
    status: 'accepted',
  );

  /// Create rejected acknowledgment
  factory PaymentAckPayload.rejected(String paymentId, {String? reason}) => PaymentAckPayload(
    paymentId: paymentId,
    status: 'rejected',
    reason: reason,
  );

  bool get isAccepted => status == 'accepted';
  bool get isRejected => status == 'rejected';
  bool get isPending => status == 'pending';
}

/// Risk metadata for GeoAuth tokens
class GeoAuthRiskMetadata {
  final double trustScore;
  final int breadcrumbCount;
  final int daysActive;
  final String? deviceModel;
  final String? osVersion;

  GeoAuthRiskMetadata({
    required this.trustScore,
    required this.breadcrumbCount,
    required this.daysActive,
    this.deviceModel,
    this.osVersion,
  });

  Map<String, dynamic> toJson() => {
    'trust_score': trustScore,
    'breadcrumb_count': breadcrumbCount,
    'days_active': daysActive,
    if (deviceModel != null) 'device_model': deviceModel,
    if (osVersion != null) 'os_version': osVersion,
  };

  factory GeoAuthRiskMetadata.fromJson(Map<String, dynamic> json) {
    return GeoAuthRiskMetadata(
      trustScore: (json['trust_score'] as num).toDouble(),
      breadcrumbCount: json['breadcrumb_count'] as int,
      daysActive: json['days_active'] as int,
      deviceModel: json['device_model'] as String?,
      osVersion: json['os_version'] as String?,
    );
  }
}

/// GeoAuth constraints
class GeoAuthConstraints {
  final int maxDistanceMeters;
  final int expiresAt;

  GeoAuthConstraints({
    this.maxDistanceMeters = 50,
    required this.expiresAt,
  });

  Map<String, dynamic> toJson() => {
    'max_distance_meters': maxDistanceMeters,
    'expires_at': expiresAt,
  };

  factory GeoAuthConstraints.fromJson(Map<String, dynamic> json) {
    return GeoAuthConstraints(
      maxDistanceMeters: json['max_distance_meters'] as int? ?? 50,
      expiresAt: json['expires_at'] as int,
    );
  }

  bool get isExpired => DateTime.now().millisecondsSinceEpoch > expiresAt;
}

/// GNS-GeoAuth payload (Chapter 8)
/// 
/// Geospatial Payment Authentication token.
/// Sent with payloadType: gns/auth.geo
class GeoAuthPayload extends GnsPayload {
  @override
  String get type => PaymentPayloadType.geoAuth;
  
  final int version;
  
  /// Auth token ID
  final String authId;
  
  /// User's public key (pkRoot)
  final String fromPublicKey;
  
  /// H3 cell at time of authorization
  final String h3Cell;
  
  /// Authorization timestamp
  final int timestamp;
  
  /// Hashed device identifier
  final String deviceId;
  
  /// SHA256 hash of the payment/order being authorized
  final String paymentHash;
  
  /// Merchant identifier (e.g., "stripe:acct_123")
  final String? merchantId;
  
  /// Geospatial constraints
  final GeoAuthConstraints? geoConstraints;
  
  /// Risk metadata for fraud scoring
  final GeoAuthRiskMetadata? riskMetadata;

  GeoAuthPayload({
    this.version = 1,
    required this.authId,
    required this.fromPublicKey,
    required this.h3Cell,
    required this.timestamp,
    required this.deviceId,
    required this.paymentHash,
    this.merchantId,
    this.geoConstraints,
    this.riskMetadata,
  });

  @override
  Map<String, dynamic> toJson() => {
    'version': version,
    'auth_id': authId,
    'from_public_key': fromPublicKey,
    'h3_cell': h3Cell,
    'timestamp': timestamp,
    'device_id': deviceId,
    'payment_hash': paymentHash,
    if (merchantId != null) 'merchant_id': merchantId,
    if (geoConstraints != null) 'geo_constraints': geoConstraints!.toJson(),
    if (riskMetadata != null) 'risk_metadata': riskMetadata!.toJson(),
  };

  factory GeoAuthPayload.fromJson(Map<String, dynamic> json) {
    return GeoAuthPayload(
      version: json['version'] as int? ?? 1,
      authId: json['auth_id'] as String,
      fromPublicKey: json['from_public_key'] as String,
      h3Cell: json['h3_cell'] as String,
      timestamp: json['timestamp'] as int,
      deviceId: json['device_id'] as String,
      paymentHash: json['payment_hash'] as String,
      merchantId: json['merchant_id'] as String?,
      geoConstraints: json['geo_constraints'] != null
          ? GeoAuthConstraints.fromJson(json['geo_constraints'] as Map<String, dynamic>)
          : null,
      riskMetadata: json['risk_metadata'] != null
          ? GeoAuthRiskMetadata.fromJson(json['risk_metadata'] as Map<String, dynamic>)
          : null,
    );
  }

  /// Check if token is expired
  bool get isExpired => geoConstraints?.isExpired ?? false;

  /// Check if timestamp is fresh (within 60 seconds)
  bool get isFresh {
    final now = DateTime.now().millisecondsSinceEpoch;
    return (now - timestamp).abs() < 60000;  // 60 seconds
  }

  @override
  String toString() => 'GeoAuthPayload($authId @ $h3Cell)';
}

/// Parser for payment payloads
class PaymentPayloadParser {
  /// Parse a payment payload from JSON
  static GnsPayload? parse(String type, Map<String, dynamic> json) {
    switch (type) {
      case PaymentPayloadType.transfer:
        return PaymentTransferPayload.fromJson(json);
      case PaymentPayloadType.request:
        return PaymentRequestPayload.fromJson(json);
      case PaymentPayloadType.ack:
        return PaymentAckPayload.fromJson(json);
      case PaymentPayloadType.geoAuth:
        return GeoAuthPayload.fromJson(json);
      default:
        return null;
    }
  }

  /// Check if a type is a payment type
  static bool isPaymentType(String type) {
    return type.startsWith('gns/payment.') || type.startsWith('gns/auth.geo');
  }
}
