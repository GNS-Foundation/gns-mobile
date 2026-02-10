/// Identity Claims - Cross-Platform Verification System
///
/// Manages verified claims linking a GNS @handle to external platforms:
/// - Organizations (DNS TXT verification) — already exists, now unified
/// - Twitter/X (signed tweet verification)
/// - Instagram (bio/story verification)
/// - TikTok (bio verification)
/// - YouTube (channel description verification)
/// - GitHub (gist verification)
/// - LinkedIn (post verification)
/// - Custom domains (DNS TXT verification)
///
/// Architecture:
///   id@handle = the verification facet (unified proof hub)
///   Each claim = { platform, foreign_username, proof, status }
///
/// The GNS handle is the CANONICAL identity.
/// Foreign usernames are ATTRIBUTES — verified links, not competing names.
///
/// Location: lib/core/identity/identity_claim.dart

import 'dart:convert';

// ============================================================
// PLATFORM DEFINITIONS
// ============================================================

/// Supported external platforms for identity claims
enum ClaimPlatform {
  twitter,
  instagram,
  tiktok,
  youtube,
  github,
  linkedin,
  domain,
  organization,
  mastodon,
  bluesky,
  custom;

  String get displayName {
    switch (this) {
      case ClaimPlatform.twitter: return 'X / Twitter';
      case ClaimPlatform.instagram: return 'Instagram';
      case ClaimPlatform.tiktok: return 'TikTok';
      case ClaimPlatform.youtube: return 'YouTube';
      case ClaimPlatform.github: return 'GitHub';
      case ClaimPlatform.linkedin: return 'LinkedIn';
      case ClaimPlatform.domain: return 'Domain';
      case ClaimPlatform.organization: return 'Organization';
      case ClaimPlatform.mastodon: return 'Mastodon';
      case ClaimPlatform.bluesky: return 'Bluesky';
      case ClaimPlatform.custom: return 'Custom';
    }
  }

  String get icon {
    switch (this) {
      case ClaimPlatform.twitter: return '𝕏';
      case ClaimPlatform.instagram: return '📸';
      case ClaimPlatform.tiktok: return '🎵';
      case ClaimPlatform.youtube: return '▶️';
      case ClaimPlatform.github: return '🐙';
      case ClaimPlatform.linkedin: return '💼';
      case ClaimPlatform.domain: return '🌐';
      case ClaimPlatform.organization: return '🏢';
      case ClaimPlatform.mastodon: return '🦣';
      case ClaimPlatform.bluesky: return '🦋';
      case ClaimPlatform.custom: return '🔗';
    }
  }

  String get color {
    switch (this) {
      case ClaimPlatform.twitter: return '#000000';
      case ClaimPlatform.instagram: return '#E4405F';
      case ClaimPlatform.tiktok: return '#010101';
      case ClaimPlatform.youtube: return '#FF0000';
      case ClaimPlatform.github: return '#181717';
      case ClaimPlatform.linkedin: return '#0A66C2';
      case ClaimPlatform.domain: return '#0EA5E9';
      case ClaimPlatform.organization: return '#8B5CF6';
      case ClaimPlatform.mastodon: return '#6364FF';
      case ClaimPlatform.bluesky: return '#0085FF';
      case ClaimPlatform.custom: return '#6B7280';
    }
  }

  /// Verification method description
  String get verificationMethod {
    switch (this) {
      case ClaimPlatform.twitter:
        return 'Post a tweet containing your verification code';
      case ClaimPlatform.instagram:
        return 'Add your verification code to your Instagram bio';
      case ClaimPlatform.tiktok:
        return 'Add your verification code to your TikTok bio';
      case ClaimPlatform.youtube:
        return 'Add your verification code to your channel description';
      case ClaimPlatform.github:
        return 'Create a public gist with your verification code';
      case ClaimPlatform.linkedin:
        return 'Add your verification code to your LinkedIn about section';
      case ClaimPlatform.domain:
        return 'Add a DNS TXT record with your verification code';
      case ClaimPlatform.organization:
        return 'Add a DNS TXT record to your organization domain';
      case ClaimPlatform.mastodon:
        return 'Post a toot containing your verification code';
      case ClaimPlatform.bluesky:
        return 'Post containing your verification code';
      case ClaimPlatform.custom:
        return 'Place your verification code at the specified URL';
    }
  }

  /// Placeholder text for the username input
  String get usernamePlaceholder {
    switch (this) {
      case ClaimPlatform.twitter: return '@username (without @)';
      case ClaimPlatform.instagram: return 'username';
      case ClaimPlatform.tiktok: return '@username (without @)';
      case ClaimPlatform.youtube: return 'Channel name or @handle';
      case ClaimPlatform.github: return 'username';
      case ClaimPlatform.linkedin: return 'linkedin.com/in/username';
      case ClaimPlatform.domain: return 'example.com';
      case ClaimPlatform.organization: return 'namespace';
      case ClaimPlatform.mastodon: return 'user@instance.social';
      case ClaimPlatform.bluesky: return 'handle.bsky.social';
      case ClaimPlatform.custom: return 'Platform URL';
    }
  }

  /// URL template for viewing the foreign profile
  String profileUrl(String username) {
    switch (this) {
      case ClaimPlatform.twitter: return 'https://x.com/$username';
      case ClaimPlatform.instagram: return 'https://instagram.com/$username';
      case ClaimPlatform.tiktok: return 'https://tiktok.com/@$username';
      case ClaimPlatform.youtube: return 'https://youtube.com/@$username';
      case ClaimPlatform.github: return 'https://github.com/$username';
      case ClaimPlatform.linkedin: return 'https://linkedin.com/in/$username';
      case ClaimPlatform.domain: return 'https://$username';
      case ClaimPlatform.organization: return ''; // N/A
      case ClaimPlatform.mastodon:
        final parts = username.split('@');
        return parts.length == 2 ? 'https://${parts[1]}/@${parts[0]}' : '';
      case ClaimPlatform.bluesky: return 'https://bsky.app/profile/$username';
      case ClaimPlatform.custom: return username;
    }
  }

  static ClaimPlatform fromString(String value) {
    return ClaimPlatform.values.firstWhere(
      (p) => p.name == value,
      orElse: () => ClaimPlatform.custom,
    );
  }
}

// ============================================================
// CLAIM STATUS
// ============================================================

/// Status of an identity claim
enum ClaimStatus {
  /// Claim initiated, waiting for user to place proof
  pending,

  /// Proof placed, waiting for server verification
  verifying,

  /// Successfully verified
  verified,

  /// Verification failed (proof not found or expired)
  failed,

  /// Claim expired (not verified within time limit)
  expired,

  /// User revoked the claim
  revoked;

  String get displayName {
    switch (this) {
      case ClaimStatus.pending: return 'Pending';
      case ClaimStatus.verifying: return 'Verifying...';
      case ClaimStatus.verified: return 'Verified';
      case ClaimStatus.failed: return 'Failed';
      case ClaimStatus.expired: return 'Expired';
      case ClaimStatus.revoked: return 'Revoked';
    }
  }

  bool get isActive => this == ClaimStatus.verified;
  bool get canRetry => this == ClaimStatus.failed || this == ClaimStatus.expired;
  bool get isPending => this == ClaimStatus.pending || this == ClaimStatus.verifying;
}

// ============================================================
// IDENTITY CLAIM
// ============================================================

/// A single cross-platform identity claim
///
/// Example:
///   IdentityClaim(
///     platform: ClaimPlatform.twitter,
///     foreignUsername: 'cayerbe',
///     gnsHandle: 'camiloayerbe',
///     status: ClaimStatus.verified,
///   )
///
/// This represents: @camiloayerbe on GNS === @cayerbe on Twitter
class IdentityClaim {
  /// Unique claim ID (server-generated)
  final String id;

  /// The external platform
  final ClaimPlatform platform;

  /// Username on the external platform
  /// NOTE: This may differ from the GNS handle!
  /// e.g., GNS: @camiloayerbe, Twitter: @cayerbe
  final String foreignUsername;

  /// The GNS handle making this claim
  final String gnsHandle;

  /// The GNS public key (identity root)
  final String publicKey;

  /// Current verification status
  final ClaimStatus status;

  /// Server-generated verification code
  /// User must place this on the external platform
  final String? verificationCode;

  /// Proof reference (e.g., tweet ID, gist URL, DNS record)
  final String? proofReference;

  /// When the claim was initiated
  final DateTime createdAt;

  /// When the claim was last verified
  final DateTime? verifiedAt;

  /// When the claim expires if not verified (typically 7 days)
  final DateTime? expiresAt;

  /// Ed25519 signature of the claim by the GNS identity
  final String? signature;

  IdentityClaim({
    required this.id,
    required this.platform,
    required this.foreignUsername,
    required this.gnsHandle,
    required this.publicKey,
    this.status = ClaimStatus.pending,
    this.verificationCode,
    this.proofReference,
    DateTime? createdAt,
    this.verifiedAt,
    this.expiresAt,
    this.signature,
  }) : createdAt = createdAt ?? DateTime.now();

  // ==================== HELPERS ====================

  /// Is this claim currently active and verified?
  bool get isVerified => status == ClaimStatus.verified;

  /// Can this claim be retried?
  bool get canRetry => status.canRetry;

  /// Is this claim still pending?
  bool get isPending => status.isPending;

  /// Has this claim expired?
  bool get isExpired =>
      expiresAt != null && DateTime.now().isAfter(expiresAt!) && !isVerified;

  /// Display string for the claim
  /// e.g., "𝕏 @cayerbe ✓"
  String get displayString {
    final checkmark = isVerified ? ' ✓' : '';
    final prefix = platform == ClaimPlatform.domain ? '' : '@';
    return '${platform.icon} $prefix$foreignUsername$checkmark';
  }

  /// The verification instruction for the user
  String get verificationInstruction {
    if (verificationCode == null) return 'Generating verification code...';

    switch (platform) {
      case ClaimPlatform.twitter:
        return 'Post this tweet:\n\n'
            'Verifying my GNS identity @$gnsHandle 🌐\n'
            'Code: $verificationCode\n\n'
            '#GNS #ProofOfTrajectory';
      case ClaimPlatform.instagram:
        return 'Add this to your Instagram bio:\n\n'
            'gns:$verificationCode';
      case ClaimPlatform.tiktok:
        return 'Add this to your TikTok bio:\n\n'
            'gns:$verificationCode';
      case ClaimPlatform.youtube:
        return 'Add this to your YouTube channel description:\n\n'
            'gns:$verificationCode';
      case ClaimPlatform.github:
        return 'Create a public gist named "gns-verify.txt" containing:\n\n'
            '$verificationCode';
      case ClaimPlatform.linkedin:
        return 'Add this to your LinkedIn About section:\n\n'
            'gns:$verificationCode';
      case ClaimPlatform.domain:
        return 'Add a DNS TXT record:\n\n'
            'Host: _gns.$foreignUsername\n'
            'Value: $verificationCode';
      case ClaimPlatform.organization:
        return 'Add a DNS TXT record:\n\n'
            'Host: _gns.$foreignUsername\n'
            'Value: $verificationCode';
      case ClaimPlatform.mastodon:
        return 'Post a toot containing:\n\n'
            'Verifying my GNS identity @$gnsHandle\n'
            'Code: $verificationCode';
      case ClaimPlatform.bluesky:
        return 'Post containing:\n\n'
            'Verifying my GNS identity @$gnsHandle\n'
            'Code: $verificationCode';
      case ClaimPlatform.custom:
        return 'Place this verification code at your specified URL:\n\n'
            '$verificationCode';
    }
  }

  // ==================== SERIALIZATION ====================

  Map<String, dynamic> toJson() => {
        'id': id,
        'platform': platform.name,
        'foreign_username': foreignUsername,
        'gns_handle': gnsHandle,
        'public_key': publicKey,
        'status': status.name,
        'verification_code': verificationCode,
        'proof_reference': proofReference,
        'created_at': createdAt.toIso8601String(),
        'verified_at': verifiedAt?.toIso8601String(),
        'expires_at': expiresAt?.toIso8601String(),
        'signature': signature,
      };

  factory IdentityClaim.fromJson(Map<String, dynamic> json) {
    return IdentityClaim(
      id: json['id'] as String,
      platform: ClaimPlatform.fromString(json['platform'] as String),
      foreignUsername: json['foreign_username'] as String,
      gnsHandle: json['gns_handle'] as String,
      publicKey: json['public_key'] as String,
      status: ClaimStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => ClaimStatus.pending,
      ),
      verificationCode: json['verification_code'] as String?,
      proofReference: json['proof_reference'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      verifiedAt: json['verified_at'] != null
          ? DateTime.parse(json['verified_at'] as String)
          : null,
      expiresAt: json['expires_at'] != null
          ? DateTime.parse(json['expires_at'] as String)
          : null,
      signature: json['signature'] as String?,
    );
  }

  IdentityClaim copyWith({
    ClaimStatus? status,
    String? verificationCode,
    String? proofReference,
    DateTime? verifiedAt,
    DateTime? expiresAt,
    String? signature,
  }) {
    return IdentityClaim(
      id: id,
      platform: platform,
      foreignUsername: foreignUsername,
      gnsHandle: gnsHandle,
      publicKey: publicKey,
      status: status ?? this.status,
      verificationCode: verificationCode ?? this.verificationCode,
      proofReference: proofReference ?? this.proofReference,
      createdAt: createdAt,
      verifiedAt: verifiedAt ?? this.verifiedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      signature: signature ?? this.signature,
    );
  }

  @override
  String toString() =>
      'IdentityClaim(${platform.name}: $foreignUsername → @$gnsHandle [${status.name}])';
}

// ============================================================
// IDENTITY CLAIMS COLLECTION (id@ facet data)
// ============================================================

/// The complete set of identity claims for a GNS identity.
/// This is the data model for the id@ facet.
///
/// Example rendering on a gSite:
///
///   id@camiloayerbe
///     ├── twitter: @cayerbe ✓         (verified 2025-03-15)
///     ├── instagram: @camiloayerbe ✓  (verified 2025-03-15)
///     ├── github: @camiloayerbe ✓     (verified 2025-04-01)
///     ├── domain: ulissy.app ✓        (DNS TXT verified)
///     └── humanity: PoT verified ✓    (trust score: 87)
///
class IdentityClaimsCollection {
  final String gnsHandle;
  final String publicKey;
  final List<IdentityClaim> claims;

  IdentityClaimsCollection({
    required this.gnsHandle,
    required this.publicKey,
    List<IdentityClaim>? claims,
  }) : claims = claims ?? [];

  /// Get all verified claims
  List<IdentityClaim> get verifiedClaims =>
      claims.where((c) => c.isVerified).toList();

  /// Get all pending claims
  List<IdentityClaim> get pendingClaims =>
      claims.where((c) => c.isPending).toList();

  /// Get claim for a specific platform
  IdentityClaim? getClaimForPlatform(ClaimPlatform platform) {
    try {
      return claims.firstWhere((c) => c.platform == platform);
    } catch (_) {
      return null;
    }
  }

  /// Check if a platform is verified
  bool isPlatformVerified(ClaimPlatform platform) {
    final claim = getClaimForPlatform(platform);
    return claim?.isVerified ?? false;
  }

  /// Count of verified platforms
  int get verifiedCount => verifiedClaims.length;

  /// All platforms that haven't been claimed yet
  List<ClaimPlatform> get unclaimedPlatforms {
    final claimed = claims.map((c) => c.platform).toSet();
    return ClaimPlatform.values
        .where((p) => !claimed.contains(p) && p != ClaimPlatform.custom)
        .toList();
  }

  Map<String, dynamic> toJson() => {
        'gns_handle': gnsHandle,
        'public_key': publicKey,
        'claims': claims.map((c) => c.toJson()).toList(),
      };

  factory IdentityClaimsCollection.fromJson(Map<String, dynamic> json) {
    return IdentityClaimsCollection(
      gnsHandle: json['gns_handle'] as String,
      publicKey: json['public_key'] as String,
      claims: (json['claims'] as List?)
              ?.map((c) => IdentityClaim.fromJson(c as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}
