
// lib/core/gns/gns_types.dart
// GNS Data Types for API v1

enum PaymentStatus {
  pending,
  completed,
  expired,
  cancelled,
  failed,
}

enum PaymentCurrency {
  GNS,
  XLM,
  USDC,
  EUR,
  BTC,
}

enum VerificationLevel {
  none,
  basic,
  standard,
  advanced,
  maximum,
}

class GnsPaymentRequest {
  final String paymentId;
  final PaymentStatus status;
  final String? fromPk;
  final String? fromHandle;
  final String? toPk;
  final String? toHandle;
  final String amount;
  final String currency;
  final String? memo;
  final String? referenceId;
  final String? qrUrl;
  final String? deepLink;
  final String? webUrl;
  final String? stellarTxHash;
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime? completedAt;

  GnsPaymentRequest({
    required this.paymentId,
    required this.status,
    this.fromPk,
    this.fromHandle,
    this.toPk,
    this.toHandle,
    required this.amount,
    required this.currency,
    this.memo,
    this.referenceId,
    this.qrUrl,
    this.deepLink,
    this.webUrl,
    this.stellarTxHash,
    required this.createdAt,
    required this.expiresAt,
    this.completedAt,
  });

  factory GnsPaymentRequest.fromJson(Map<String, dynamic> json) {
    return GnsPaymentRequest(
      paymentId: json['payment_id'],
      status: PaymentStatus.values.firstWhere(
        (e) => e.toString().split('.').last == json['status'],
        orElse: () => PaymentStatus.pending,
      ),
      fromPk: json['from_pk'],
      fromHandle: json['from_handle'],
      toPk: json['to_pk'],
      toHandle: json['to_handle'],
      amount: json['amount'],
      currency: json['currency'],
      memo: json['memo'],
      referenceId: json['reference_id'],
      qrUrl: json['qr_url'],
      deepLink: json['deep_link'],
      webUrl: json['web_url'],
      stellarTxHash: json['stellar_tx_hash'],
      createdAt: DateTime.parse(json['created_at']),
      expiresAt: DateTime.parse(json['expires_at']),
      completedAt: json['completed_at'] != null ? DateTime.parse(json['completed_at']) : null,
    );
  }
}

class VerificationChallenge {
  final String challengeId;
  final String challenge;
  final DateTime expiresAt;
  final List<String>? requiredH3Cells;

  VerificationChallenge({
    required this.challengeId,
    required this.challenge,
    required this.expiresAt,
    this.requiredH3Cells,
  });

  factory VerificationChallenge.fromJson(Map<String, dynamic> json) {
    return VerificationChallenge(
      challengeId: json['challenge_id'],
      challenge: json['challenge'],
      expiresAt: DateTime.parse(json['expires_at']),
      requiredH3Cells: json['required_h3_cells'] != null 
          ? List<String>.from(json['required_h3_cells']) 
          : null,
    );
  }
}

class ProofOfHumanity {
  final bool verified;
  final String publicKey;
  final String? handle;
  final double trustScore;
  final int breadcrumbCount;
  final int trajectoryDays;
  final String? proofHash;
  final String? verifiedSince;
  final VerificationLevel verificationLevel;
  final bool chainValid;
  final String? lastActivity;

  ProofOfHumanity({
    required this.verified,
    required this.publicKey,
    this.handle,
    required this.trustScore,
    required this.breadcrumbCount,
    required this.trajectoryDays,
    this.proofHash,
    this.verifiedSince,
    required this.verificationLevel,
    required this.chainValid,
    this.lastActivity,
  });

  factory ProofOfHumanity.fromJson(Map<String, dynamic> json) {
    return ProofOfHumanity(
      verified: json['verified'] ?? false,
      publicKey: json['public_key'],
      handle: json['handle'],
      trustScore: (json['trust_score'] ?? 0).toDouble(),
      breadcrumbCount: json['breadcrumb_count'] ?? 0,
      trajectoryDays: json['trajectory_days'] ?? 0,
      proofHash: json['proof_hash'],
      verifiedSince: json['verified_since'],
      verificationLevel: VerificationLevel.values.firstWhere(
        (e) => e.toString().split('.').last == json['verification_level'],
        orElse: () => VerificationLevel.none,
      ),
      chainValid: json['chain_valid'] ?? false,
      lastActivity: json['last_activity'],
    );
  }
}
