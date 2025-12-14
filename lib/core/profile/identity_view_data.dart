// Identity View Data - Phase 3A
//
// Unified data model for displaying any identity (self or others).
// Used by Identity Card, Identity Viewer, and Contact List.
//
// Location: lib/core/profile/identity_view_data.dart

import 'profile_module.dart';
import '../gns/gns_record.dart';

class IdentityViewData {
  final String publicKey;
  final String? handle;
  final String? displayName;
  final String? bio;
  final String? avatarUrl;
  final List<ProfileLink> links;
  final double trustScore;
  final int breadcrumbCount;
  final int daysSinceCreation;
  final String? lastLocationRegion;  // City-level H3 or region name
  final DateTime? lastSeen;
  final DateTime createdAt;
  final bool isOwnIdentity;
  final bool isContact;
  final bool chainValid;

  IdentityViewData({
    required this.publicKey,
    this.handle,
    this.displayName,
    this.bio,
    this.avatarUrl,
    List<ProfileLink>? links,
    required this.trustScore,
    required this.breadcrumbCount,
    required this.daysSinceCreation,
    this.lastLocationRegion,
    this.lastSeen,
    required this.createdAt,
    this.isOwnIdentity = false,
    this.isContact = false,
    this.chainValid = true,
  }) : links = links ?? [];

  /// GNS ID derived from public key
  String get gnsId => 'gns_${publicKey.substring(0, 16)}';

  /// Display title: @handle or gnsId
  String get displayTitle => handle != null ? '@$handle' : gnsId;

  /// Display name: profile name or title
  String get displayLabel => displayName ?? displayTitle;

  /// Short public key for display (first 8 chars + ...)
  String get shortPublicKey => '${publicKey.substring(0, 8)}...';

  /// Trust score as percentage string
  String get trustLabel => '${trustScore.toStringAsFixed(0)}%';

  /// Trust level category
  TrustLevel get trustLevel {
    if (trustScore >= 80) return TrustLevel.high;
    if (trustScore >= 50) return TrustLevel.medium;
    if (trustScore >= 20) return TrustLevel.low;
    return TrustLevel.minimal;
  }

  /// Breadcrumb count formatted
  String get breadcrumbLabel {
    if (breadcrumbCount >= 1000) {
      return '${(breadcrumbCount / 1000).toStringAsFixed(1)}k';
    }
    return breadcrumbCount.toString();
  }

  /// Days active formatted
  String get daysLabel {
    if (daysSinceCreation == 0) return 'Today';
    if (daysSinceCreation == 1) return '1 day';
    if (daysSinceCreation < 30) return '$daysSinceCreation days';
    if (daysSinceCreation < 365) {
      final months = daysSinceCreation ~/ 30;
      return '$months month${months > 1 ? 's' : ''}';
    }
    final years = daysSinceCreation ~/ 365;
    return '$years year${years > 1 ? 's' : ''}';
  }

  /// Last seen formatted
  String get lastSeenLabel {
    if (lastSeen == null) return 'Unknown';
    
    final now = DateTime.now();
    final diff = now.difference(lastSeen!);
    
    if (diff.inMinutes < 5) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    if (diff.inDays < 30) return '${diff.inDays ~/ 7}w ago';
    
    return '${diff.inDays ~/ 30}mo ago';
  }

  /// Location with last seen
  String get locationLabel {
    if (lastLocationRegion == null) return 'Location hidden';
    final location = lastLocationRegion!;
    if (lastSeen != null) {
      return '$location ($lastSeenLabel)';
    }
    return location;
  }

  /// Member since formatted
  String get memberSinceLabel {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[createdAt.month - 1]} ${createdAt.year}';
  }

  /// Can claim handle (enough breadcrumbs + trust)
  bool get canClaimHandle => breadcrumbCount >= 100 && trustScore >= 20;

  /// Create from GnsRecord
  factory IdentityViewData.fromRecord(
    GnsRecord record, {
    bool isOwnIdentity = false,
    bool isContact = false,
    bool chainValid = true,
    String? lastLocationRegion,
    DateTime? lastSeen,
  }) {
    final profile = ProfileModule.fromRecord(record);
    final daysSinceCreation = DateTime.now().difference(record.createdAt).inDays;

    return IdentityViewData(
      publicKey: record.identity,
      handle: record.handle,
      displayName: profile?.displayName,
      bio: profile?.bio,
      avatarUrl: profile?.avatarUrl,
      links: profile?.links ?? [],
      trustScore: record.trustScore,
      breadcrumbCount: record.breadcrumbCount,
      daysSinceCreation: daysSinceCreation,
      lastLocationRegion: lastLocationRegion,
      lastSeen: lastSeen,
      createdAt: record.createdAt,
      isOwnIdentity: isOwnIdentity,
      isContact: isContact,
      chainValid: chainValid,
    );
  }

  /// Create a copy with updated fields
  IdentityViewData copyWith({
    String? displayName,
    String? bio,
    String? avatarUrl,
    List<ProfileLink>? links,
    double? trustScore,
    int? breadcrumbCount,
    String? lastLocationRegion,
    DateTime? lastSeen,
    bool? isContact,
  }) {
    return IdentityViewData(
      publicKey: publicKey,
      handle: handle,
      displayName: displayName ?? this.displayName,
      bio: bio ?? this.bio,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      links: links ?? this.links,
      trustScore: trustScore ?? this.trustScore,
      breadcrumbCount: breadcrumbCount ?? this.breadcrumbCount,
      daysSinceCreation: daysSinceCreation,
      lastLocationRegion: lastLocationRegion ?? this.lastLocationRegion,
      lastSeen: lastSeen ?? this.lastSeen,
      createdAt: createdAt,
      isOwnIdentity: isOwnIdentity,
      isContact: isContact ?? this.isContact,
      chainValid: chainValid,
    );
  }

  @override
  String toString() => 'IdentityViewData($displayTitle, trust: $trustLabel)';
}

/// Trust level categories for visual display
enum TrustLevel {
  minimal,  // < 20%
  low,      // 20-49%
  medium,   // 50-79%
  high,     // 80%+
}

extension TrustLevelExtension on TrustLevel {
  String get label {
    switch (this) {
      case TrustLevel.minimal: return 'New';
      case TrustLevel.low: return 'Building';
      case TrustLevel.medium: return 'Established';
      case TrustLevel.high: return 'Trusted';
    }
  }

  String get emoji {
    switch (this) {
      case TrustLevel.minimal: return '🌱';
      case TrustLevel.low: return '📈';
      case TrustLevel.medium: return '⭐';
      case TrustLevel.high: return '💎';
    }
  }

  /// Color code (as hex string for easy use)
  int get colorValue {
    switch (this) {
      case TrustLevel.minimal: return 0xFF9CA3AF;  // Gray
      case TrustLevel.low: return 0xFFFBBF24;      // Yellow
      case TrustLevel.medium: return 0xFF3B82F6;  // Blue
      case TrustLevel.high: return 0xFF10B981;    // Green
    }
  }
}

/// QR code payload for sharing identity
class GnsQrPayload {
  final int version;
  final String type;
  final String publicKey;
  final String? handle;
  final String? displayName;
  final DateTime timestamp;
  final String signature;

  GnsQrPayload({
    this.version = 1,
    this.type = 'identity',
    required this.publicKey,
    this.handle,
    this.displayName,
    required this.timestamp,
    required this.signature,
  });

  /// Data to sign (excludes signature itself)
  Map<String, dynamic> get dataToSign => {
    'version': version,
    'type': type,
    'public_key': publicKey,
    if (handle != null) 'handle': handle,
    if (displayName != null) 'display_name': displayName,
    'timestamp': timestamp.toUtc().toIso8601String(),
  };

  Map<String, dynamic> toJson() => {
    ...dataToSign,
    'signature': signature,
  };

  factory GnsQrPayload.fromJson(Map<String, dynamic> json) {
    return GnsQrPayload(
      version: json['version'] as int? ?? 1,
      type: json['type'] as String? ?? 'identity',
      publicKey: json['public_key'] as String,
      handle: json['handle'] as String?,
      displayName: json['display_name'] as String?,
      timestamp: DateTime.parse(json['timestamp'] as String),
      signature: json['signature'] as String,
    );
  }

  /// Check if payload is expired (older than 24 hours)
  bool get isExpired {
    final age = DateTime.now().difference(timestamp);
    return age.inHours > 24;
  }

  /// Format as QR URL
  String toQrUrl(String base64Payload) => 'gns://identity/$base64Payload';
}
