// ===========================================
// GNS - PAYMENT PAYLOAD TYPES
//
// SECURITY FIXES (v1.1 - Relay Attack Resilience):
//   [MEDIUM] Added channelBindingToken field to GeoAuthPayload
//   [MEDIUM] GeoAuthPayload.isValid() now checks CBT presence
//   [MEDIUM] Factory constructor GeoAuthPayload.create() enforces CBT
// ===========================================

// ===========================================
// BASE PAYLOAD
// ===========================================

abstract class GnsPayload {
  String get type;
  Map<String, dynamic> toJson();
}

// ===========================================
// PAYLOAD TYPE CONSTANTS
// ===========================================

class PaymentPayloadType {
  static const transfer = 'gns/payment.transfer';
  static const request  = 'gns/payment.request';
  static const ack      = 'gns/payment.ack';
  static const geoAuth  = 'gns/auth.geo';
}

// ===========================================
// PAYMENT TRANSFER PAYLOAD
// ===========================================

class PaymentTransferPayload extends GnsPayload {
  @override
  String get type => PaymentPayloadType.transfer;

  final String currency;
  final double amount;
  final String? memo;
  final String? routeType;

  PaymentTransferPayload({
    required this.currency,
    required this.amount,
    this.memo,
    this.routeType,
  });

  @override
  Map<String, dynamic> toJson() => {
    'currency': currency,
    'amount': amount,
    if (memo != null) 'memo': memo,
    if (routeType != null) 'route_type': routeType,
  };

  factory PaymentTransferPayload.fromJson(Map<String, dynamic> json) {
    return PaymentTransferPayload(
      currency: json['currency'] as String,
      amount: (json['amount'] as num).toDouble(),
      memo: json['memo'] as String?,
      routeType: json['route_type'] as String?,
    );
  }
}

// ===========================================
// PAYMENT REQUEST PAYLOAD
// ===========================================

class PaymentRequestPayload extends GnsPayload {
  @override
  String get type => PaymentPayloadType.request;

  final String currency;
  final double amount;
  final String? memo;

  PaymentRequestPayload({
    required this.currency,
    required this.amount,
    this.memo,
  });

  @override
  Map<String, dynamic> toJson() => {
    'currency': currency,
    'amount': amount,
    if (memo != null) 'memo': memo,
  };

  factory PaymentRequestPayload.fromJson(Map<String, dynamic> json) {
    return PaymentRequestPayload(
      currency: json['currency'] as String,
      amount: (json['amount'] as num).toDouble(),
      memo: json['memo'] as String?,
    );
  }
}

// ===========================================
// PAYMENT ACK PAYLOAD
// ===========================================

class PaymentAckPayload extends GnsPayload {
  @override
  String get type => PaymentPayloadType.ack;

  final String paymentId;
  final String status;
  final String? reason;

  PaymentAckPayload({
    required this.paymentId,
    required this.status,
    this.reason,
  });

  factory PaymentAckPayload.accepted(String paymentId) =>
    PaymentAckPayload(paymentId: paymentId, status: 'accepted');

  factory PaymentAckPayload.rejected(String paymentId, {String? reason}) =>
    PaymentAckPayload(paymentId: paymentId, status: 'rejected', reason: reason);

  bool get isAccepted => status == 'accepted';
  bool get isRejected => status == 'rejected';
  bool get isPending  => status == 'pending';

  @override
  Map<String, dynamic> toJson() => {
    'payment_id': paymentId,
    'status': status,
    if (reason != null) 'reason': reason,
  };

  factory PaymentAckPayload.fromJson(Map<String, dynamic> json) {
    return PaymentAckPayload(
      paymentId: json['payment_id'] as String,
      status: json['status'] as String,
      reason: json['reason'] as String?,
    );
  }
}

// ===========================================
// GEOAUTH SUPPORTING TYPES
// ===========================================

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

// ===========================================
// GEOAUTH PAYLOAD — FIXED
// Added channelBindingToken for relay attack resilience
// ===========================================

/// GNS-GeoAuth payload (Chapter 8) — v1.1
///
/// The [channelBindingToken] field is derived by the mobile client
/// using IdentityWallet.deriveChannelBindingToken() and binds this
/// token to the current app session. The server verifies the CBT
/// matches the active connection, preventing relay replay attacks.
class GeoAuthPayload extends GnsPayload {
  @override
  String get type => PaymentPayloadType.geoAuth;

  final int version;
  final String authId;
  final String fromPublicKey;
  final String h3Cell;
  final int timestamp;
  final String deviceId;
  final String paymentHash;
  final String? merchantId;
  final GeoAuthConstraints? geoConstraints;
  final GeoAuthRiskMetadata? riskMetadata;

  /// Channel Binding Token — derived from current app session fingerprint.
  /// Required in v1.1 for relay attack detection.
  /// Server will warn (and in future: reject) if absent.
  final String? channelBindingToken;

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
    this.channelBindingToken, // NEW in v1.1
  });

  /// Factory constructor that enforces CBT presence.
  /// Prefer this over the default constructor in production.
  factory GeoAuthPayload.create({
    required String authId,
    required String fromPublicKey,
    required String h3Cell,
    required String deviceId,
    required String paymentHash,
    required String channelBindingToken, // enforced non-nullable here
    String? merchantId,
    GeoAuthConstraints? geoConstraints,
    GeoAuthRiskMetadata? riskMetadata,
  }) {
    return GeoAuthPayload(
      authId: authId,
      fromPublicKey: fromPublicKey,
      h3Cell: h3Cell,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      deviceId: deviceId,
      paymentHash: paymentHash,
      channelBindingToken: channelBindingToken,
      merchantId: merchantId,
      geoConstraints: geoConstraints,
      riskMetadata: riskMetadata,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'version': version,
    'auth_id': authId,
    'from_public_key': fromPublicKey,
    'h3_cell': h3Cell,
    'timestamp': timestamp,
    'device_id': deviceId,
    'payment_hash': paymentHash,
    if (channelBindingToken != null) 'channel_binding_token': channelBindingToken,
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
      channelBindingToken: json['channel_binding_token'] as String?,
      merchantId: json['merchant_id'] as String?,
      geoConstraints: json['geo_constraints'] != null
          ? GeoAuthConstraints.fromJson(json['geo_constraints'] as Map<String, dynamic>)
          : null,
      riskMetadata: json['risk_metadata'] != null
          ? GeoAuthRiskMetadata.fromJson(json['risk_metadata'] as Map<String, dynamic>)
          : null,
    );
  }

  /// Token is expired per the geoConstraints window.
  bool get isExpired => geoConstraints?.isExpired ?? false;

  /// Token was created within the last 60 seconds.
  bool get isFresh {
    final now = DateTime.now().millisecondsSinceEpoch;
    return (now - timestamp).abs() < 60000;
  }

  /// Token has a channel binding token (relay attack protection active).
  bool get hasChannelBinding => channelBindingToken != null && channelBindingToken!.isNotEmpty;

  /// Full validity check: fresh, not expired, has CBT.
  bool get isValid => isFresh && !isExpired && hasChannelBinding;

  @override
  String toString() => 'GeoAuthPayload($authId @ $h3Cell, cbt=${hasChannelBinding ? "✅" : "⚠️ missing"})';
}

// ===========================================
// PAYLOAD PARSER
// ===========================================

class PaymentPayloadParser {
  static GnsPayload? parse(String type, Map<String, dynamic> json) {
    switch (type) {
      case PaymentPayloadType.transfer: return PaymentTransferPayload.fromJson(json);
      case PaymentPayloadType.request:  return PaymentRequestPayload.fromJson(json);
      case PaymentPayloadType.ack:      return PaymentAckPayload.fromJson(json);
      case PaymentPayloadType.geoAuth:  return GeoAuthPayload.fromJson(json);
      default: return null;
    }
  }

  static bool isPaymentType(String type) =>
    type.startsWith('gns/payment.') || type == PaymentPayloadType.geoAuth;
}

// ===========================================
// POST-SERVICE CONVENIENCE EXTENSION
// ===========================================

extension PostServiceExtensions on GeoAuthPayload {
  /// Log a warning if this token lacks channel binding.
  void assertChannelBinding() {
    if (!hasChannelBinding) {
      debugPrint('⚠️  GeoAuthPayload created without channelBindingToken — relay attack detection disabled');
    }
  }
}
