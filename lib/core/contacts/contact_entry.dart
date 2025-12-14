/// Contact Entry - Phase 3A
/// 
/// Model for locally stored contacts (known identities).
/// 
/// Location: lib/core/contacts/contact_entry.dart

import 'package:uuid/uuid.dart';

class ContactEntry {
  final String id;
  final String publicKey;        // Ed25519 identity key
  final String? encryptionKey;   // X25519 encryption key (for encrypting TO this contact)
  final String? handle;
  final String? displayName;
  final String? avatarUrl;
  final double? trustScore;
  final String? nickname;      // User's custom label
  final String? notes;         // Private notes
  final DateTime addedAt;
  final DateTime? lastSynced;
  final bool isFavorite;

  ContactEntry({
    String? id,
    required this.publicKey,
    this.encryptionKey,  // Optional for backward compatibility
    this.handle,
    this.displayName,
    this.avatarUrl,
    this.trustScore,
    this.nickname,
    this.notes,
    DateTime? addedAt,
    this.lastSynced,
    this.isFavorite = false,
  }) : id = id ?? const Uuid().v4(),
       addedAt = addedAt ?? DateTime.now();

  /// GNS ID derived from public key
  String get gnsId => 'gns_${publicKey.substring(0, 16)}';

  /// Display title: nickname > handle > gnsId
  String get displayTitle {
    if (nickname != null && nickname!.isNotEmpty) return nickname!;
    if (handle != null) return '@$handle';
    return gnsId;
  }

  /// Subtitle for list display
  String get subtitle {
    if (nickname != null && handle != null) return '@$handle';
    if (displayName != null) return displayName!;
    return gnsId;
  }

  /// Trust score as percentage string
  String get trustLabel => trustScore != null 
      ? '${trustScore!.toStringAsFixed(0)}%' 
      : '--';

  /// Create a copy with updated fields
  ContactEntry copyWith({
    String? handle,
    String? encryptionKey,
    String? displayName,
    String? avatarUrl,
    double? trustScore,
    String? nickname,
    String? notes,
    DateTime? lastSynced,
    bool? isFavorite,
  }) {
    return ContactEntry(
      id: id,
      publicKey: publicKey,
      encryptionKey: encryptionKey ?? this.encryptionKey,
      handle: handle ?? this.handle,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      trustScore: trustScore ?? this.trustScore,
      nickname: nickname ?? this.nickname,
      notes: notes ?? this.notes,
      addedAt: addedAt,
      lastSynced: lastSynced ?? this.lastSynced,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }

  /// Convert to map for SQLite storage
  Map<String, dynamic> toMap() => {
    'id': id,
    'public_key': publicKey,
    'encryption_key': encryptionKey,  // Store X25519 key
    'handle': handle,
    'display_name': displayName,
    'avatar_url': avatarUrl,
    'trust_score': trustScore,
    'nickname': nickname,
    'notes': notes,
    'added_at': addedAt.toIso8601String(),
    'last_synced': lastSynced?.toIso8601String(),
    'is_favorite': isFavorite ? 1 : 0,
  };

  /// Create from SQLite row
  factory ContactEntry.fromMap(Map<String, dynamic> map) {
    return ContactEntry(
      id: map['id'] as String,
      publicKey: map['public_key'] as String,
      encryptionKey: map['encryption_key'] as String?,  // Load X25519 key
      handle: map['handle'] as String?,
      displayName: map['display_name'] as String?,
      avatarUrl: map['avatar_url'] as String?,
      trustScore: map['trust_score'] as double?,
      nickname: map['nickname'] as String?,
      notes: map['notes'] as String?,
      addedAt: DateTime.parse(map['added_at'] as String),
      lastSynced: map['last_synced'] != null 
          ? DateTime.parse(map['last_synced'] as String) 
          : null,
      isFavorite: (map['is_favorite'] as int?) == 1,
    );
  }

  @override
  String toString() => 'ContactEntry($displayTitle, pk: ${publicKey.substring(0, 8)}...)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ContactEntry && publicKey == other.publicKey;

  @override
  int get hashCode => publicKey.hashCode;
}

/// Search history entry
class SearchHistoryEntry {
  final String id;
  final String query;
  final String? resultPublicKey;
  final String? resultHandle;
  final DateTime searchedAt;

  SearchHistoryEntry({
    String? id,
    required this.query,
    this.resultPublicKey,
    this.resultHandle,
    DateTime? searchedAt,
  }) : id = id ?? const Uuid().v4(),
       searchedAt = searchedAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
    'id': id,
    'query': query,
    'result_public_key': resultPublicKey,
    'result_handle': resultHandle,
    'searched_at': searchedAt.toIso8601String(),
  };

  factory SearchHistoryEntry.fromMap(Map<String, dynamic> map) {
    return SearchHistoryEntry(
      id: map['id'] as String,
      query: map['query'] as String,
      resultPublicKey: map['result_public_key'] as String?,
      resultHandle: map['result_handle'] as String?,
      searchedAt: DateTime.parse(map['searched_at'] as String),
    );
  }
}
