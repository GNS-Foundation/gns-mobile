/// Profile Facet - Phase 4c + Meta-Identity Architecture
///
/// Represents a single presentation facet of an identity.
/// One identity can have multiple facets (me, work, friends, family, dix, etc.)
/// 
/// Architecture:
/// - Meta-Identity (@handle) = cryptographic root, hidden from users
/// - Facets (me@, friends@, dix@) = visible personas for communication
/// - me@ is auto-created as the default facet
/// 
/// Uses existing ProfileLink from profile_module.dart
///
/// Location: lib/core/profile/profile_facet.dart

import 'profile_module.dart';  // Uses existing ProfileLink

/// Type of facet - determines behavior and UI
enum FacetType {
  /// Auto-created default personal facet (me@)
  /// Cannot be deleted, can be edited
  defaultPersonal,
  
  /// User-created custom facet (friends@, family@, work@)
  custom,
  
  /// Broadcasting facet for public posts (dix@)
  /// Shows in Messages as a broadcast thread
  broadcast,
  
  /// System facet for protocol communication
  /// Hidden from UI, used for @echo etc.
  system,
}

/// A single facet of an identity profile.
/// 
/// Each facet represents a different presentation of the same identity:
/// - me@cayerbe → Default personal presentation
/// - friends@cayerbe → Casual presentation
/// - family@cayerbe → Private presentation
/// - dix@cayerbe → Public broadcasting
class ProfileFacet {
  final String id;              // "me", "work", "friends", "family", "dix"
  final String label;           // Human-readable label: "Me", "Work", "Friends", etc.
  final String emoji;           // Visual identifier: 👤, 💼, 🎉, 🎵, etc.
  final String? displayName;    // Name shown on this facet
  final String? avatarUrl;      // Avatar for this facet (base64 data URL)
  final String? bio;            // Bio for this facet
  final List<ProfileLink> links;  // Uses existing ProfileLink from profile_module.dart
  final FacetType type;         // NEW: Type of facet (default, custom, broadcast, system)
  final bool isDefault;         // Is this the default facet? (true for me@)
  final DateTime createdAt;
  final DateTime updatedAt;

  ProfileFacet({
    required this.id,
    required this.label,
    required this.emoji,
    this.displayName,
    this.avatarUrl,
    this.bio,
    List<ProfileLink>? links,
    this.type = FacetType.custom,  // NEW: default to custom
    this.isDefault = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : links = links ?? [],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  // ==================== FACTORY CONSTRUCTORS ====================

  /// Create the default "me@" facet (auto-created for new users)
  /// This replaces the old defaultFacet() factory
  factory ProfileFacet.defaultFacet({
    String? displayName,
    String? avatarUrl,
    String? bio,
    List<ProfileLink>? links,
  }) {
    return ProfileFacet(
      id: 'me',  // Changed from 'default' to 'me'
      label: 'Me',
      emoji: '👤',
      displayName: displayName,
      avatarUrl: avatarUrl,
      bio: bio,
      links: links,
      type: FacetType.defaultPersonal,
      isDefault: true,
    );
  }

  /// Create a broadcast facet (DIX-style)
  factory ProfileFacet.createBroadcast({
    required String id,
    required String label,
    String emoji = '📢',
    String? displayName,
    String? avatarUrl,
    String? bio,
  }) {
    return ProfileFacet(
      id: id,
      label: label,
      emoji: emoji,
      displayName: displayName,
      avatarUrl: avatarUrl,
      bio: bio,
      type: FacetType.broadcast,
      isDefault: false,
    );
  }

  /// Create from existing ProfileData (migration helper)
  factory ProfileFacet.fromProfileData(ProfileData data, {String id = 'me'}) {
    final isDefaultPersonal = id == 'me' || id == 'default';
    return ProfileFacet(
      id: isDefaultPersonal ? 'me' : id,  // Normalize 'default' to 'me'
      label: isDefaultPersonal ? 'Me' : id[0].toUpperCase() + id.substring(1),
      emoji: isDefaultPersonal ? '👤' : '📝',
      displayName: data.displayName,
      avatarUrl: data.avatarUrl,
      bio: data.bio,
      links: data.links,
      type: isDefaultPersonal ? FacetType.defaultPersonal : FacetType.custom,
      isDefault: isDefaultPersonal,
    );
  }

  /// Convert to ProfileData (for backward compatibility)
  ProfileData toProfileData() {
    return ProfileData(
      displayName: displayName,
      bio: bio,
      avatarUrl: avatarUrl,
      links: links,
    );
  }

  // ==================== TEMPLATES ====================

  static ProfileFacet workTemplate() => ProfileFacet(
    id: 'work',
    label: 'Work',
    emoji: '💼',
    type: FacetType.custom,
  );

  static ProfileFacet friendsTemplate() => ProfileFacet(
    id: 'friends',
    label: 'Friends',
    emoji: '🎉',
    type: FacetType.custom,
  );

  static ProfileFacet familyTemplate() => ProfileFacet(
    id: 'family',
    label: 'Family',
    emoji: '👨‍👩‍👧',
    type: FacetType.custom,
  );

  static ProfileFacet travelTemplate() => ProfileFacet(
    id: 'travel',
    label: 'Travel',
    emoji: '✈️',
    type: FacetType.custom,
  );

  static ProfileFacet creativeTemplate() => ProfileFacet(
    id: 'creative',
    label: 'Creative',
    emoji: '🎨',
    type: FacetType.custom,
  );

  static ProfileFacet gamingTemplate() => ProfileFacet(
    id: 'gaming',
    label: 'Gaming',
    emoji: '🎮',
    type: FacetType.custom,
  );

  /// DIX template (broadcast)
  static ProfileFacet dixTemplate() => ProfileFacet(
    id: 'dix',
    label: 'DIX',
    emoji: '🎵',
    type: FacetType.broadcast,
  );

  /// All available templates (excluding default "me")
  static List<ProfileFacet> get templates => [
    workTemplate(),
    friendsTemplate(),
    familyTemplate(),
    travelTemplate(),
    creativeTemplate(),
    gamingTemplate(),
    dixTemplate(),  // NEW: DIX broadcast template
  ];

  /// Broadcast templates only
  static List<ProfileFacet> get broadcastTemplates => [
    dixTemplate(),
    ProfileFacet(id: 'blog', label: 'Blog', emoji: '📝', type: FacetType.broadcast),
    ProfileFacet(id: 'news', label: 'News', emoji: '📰', type: FacetType.broadcast),
  ];

  // ==================== HELPERS ====================

  /// Full facet address: me@camiloayerbe
  String address(String handle) => '$id@$handle';

  /// Is this a broadcast facet? (DIX-style)
  bool get isBroadcast => type == FacetType.broadcast;

  /// Is this the default "me" facet?
  bool get isDefaultPersonal => type == FacetType.defaultPersonal;

  /// Is this a system facet?
  bool get isSystem => type == FacetType.system;

  /// Is this a custom user-created facet?
  bool get isCustom => type == FacetType.custom;

  /// Can this facet be deleted?
  bool get canDelete => type != FacetType.defaultPersonal && type != FacetType.system;

  /// For display
  String get displayLabel => '$emoji $label';
  
  String get effectiveDisplayName => displayName ?? label;

  // ==================== COPY WITH ====================

  ProfileFacet copyWith({
    String? id,
    String? label,
    String? emoji,
    String? displayName,
    String? avatarUrl,
    String? bio,
    List<ProfileLink>? links,
    FacetType? type,
    bool? isDefault,
  }) {
    return ProfileFacet(
      id: id ?? this.id,
      label: label ?? this.label,
      emoji: emoji ?? this.emoji,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      bio: bio ?? this.bio,
      links: links ?? this.links,
      type: type ?? this.type,
      isDefault: isDefault ?? this.isDefault,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }

  // ==================== SERIALIZATION ====================

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'emoji': emoji,
    'display_name': displayName,
    'avatar_url': avatarUrl,
    'bio': bio,
    'links': links.map((l) => l.toJson()).toList(),
    'facet_type': type.name,  // NEW: serialize type
    'is_default': isDefault,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  factory ProfileFacet.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String;
    final isDefaultId = id == 'default' || id == 'me';
    
    return ProfileFacet(
      id: isDefaultId ? 'me' : id,  // Normalize 'default' to 'me'
      label: json['label'] as String? ?? (isDefaultId ? 'Me' : id),
      emoji: json['emoji'] as String? ?? '👤',
      displayName: json['display_name'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      bio: json['bio'] as String?,
      links: (json['links'] as List?)
          ?.map((l) => ProfileLink.fromJson(l as Map<String, dynamic>))
          .toList() ?? [],
      type: _parseFacetType(json['facet_type'] as String?, isDefaultId),
      isDefault: json['is_default'] as bool? ?? isDefaultId,
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at'] as String) 
          : DateTime.now(),
      updatedAt: json['updated_at'] != null 
          ? DateTime.parse(json['updated_at'] as String) 
          : DateTime.now(),
    );
  }

  static FacetType _parseFacetType(String? value, bool isDefaultId) {
    if (value != null) {
      switch (value) {
        case 'defaultPersonal':
          return FacetType.defaultPersonal;
        case 'broadcast':
          return FacetType.broadcast;
        case 'system':
          return FacetType.system;
        case 'custom':
          return FacetType.custom;
      }
    }
    // Fallback: infer from isDefault flag
    return isDefaultId ? FacetType.defaultPersonal : FacetType.custom;
  }
  
  @override
  String toString() => 'ProfileFacet($id: $label, type: ${type.name})';
}

// ==================== FACET COLLECTION ====================

/// Container for all facets of an identity
class FacetCollection {
  final List<ProfileFacet> facets;
  final String? defaultFacetId;
  final String? primaryFacetId;  // User's preferred facet

  FacetCollection({
    List<ProfileFacet>? facets,
    this.defaultFacetId,
    this.primaryFacetId,
  }) : facets = facets ?? [ProfileFacet.defaultFacet()];

  /// Get a specific facet by ID
  ProfileFacet? getFacet(String id) {
    // Normalize 'default' to 'me'
    final normalizedId = id == 'default' ? 'me' : id;
    try {
      return facets.firstWhere((f) => f.id == normalizedId);
    } catch (_) {
      return null;
    }
  }

  /// Get facet by label (case-insensitive) - for hashtag lookup
  ProfileFacet? getFacetByLabel(String label) {
    final lower = label.toLowerCase();
    try {
      return facets.firstWhere(
        (f) => f.id.toLowerCase() == lower || f.label.toLowerCase() == lower,
      );
    } catch (_) {
      return null;
    }
  }

  /// Get the default facet (me@)
  ProfileFacet get defaultFacet {
    // First try by type
    try {
      return facets.firstWhere((f) => f.isDefaultPersonal);
    } catch (_) {}
    
    // Then by ID
    if (defaultFacetId != null) {
      final facet = getFacet(defaultFacetId!);
      if (facet != null) return facet;
    }
    
    // Then by isDefault flag
    try {
      return facets.firstWhere((f) => f.isDefault);
    } catch (_) {
      return facets.isNotEmpty ? facets.first : ProfileFacet.defaultFacet();
    }
  }

  /// Get the user's primary facet
  ProfileFacet get primaryFacet {
    if (primaryFacetId != null) {
      final facet = getFacet(primaryFacetId!);
      if (facet != null) return facet;
    }
    return defaultFacet;
  }

  /// Get all broadcast facets (DIX, etc.)
  List<ProfileFacet> get broadcastFacets => 
      facets.where((f) => f.isBroadcast).toList();

  /// Get all custom facets (non-default, non-broadcast)
  List<ProfileFacet> get customFacets => 
      facets.where((f) => f.isCustom).toList();

  /// Check if a facet exists
  bool hasFacet(String id) {
    final normalizedId = id == 'default' ? 'me' : id;
    return facets.any((f) => f.id == normalizedId);
  }

  /// Add a new facet
  FacetCollection addFacet(ProfileFacet facet) {
    final newFacets = List<ProfileFacet>.from(facets);
    // Remove existing with same ID
    newFacets.removeWhere((f) => f.id == facet.id);
    newFacets.add(facet);
    return FacetCollection(
      facets: newFacets,
      defaultFacetId: defaultFacetId,
      primaryFacetId: primaryFacetId,
    );
  }

  /// Update a facet
  FacetCollection updateFacet(ProfileFacet facet) {
    final newFacets = facets.map((f) => f.id == facet.id ? facet : f).toList();
    return FacetCollection(
      facets: newFacets,
      defaultFacetId: defaultFacetId,
      primaryFacetId: primaryFacetId,
    );
  }

  /// Remove a facet (cannot remove default "me")
  FacetCollection removeFacet(String id) {
    final facet = getFacet(id);
    if (facet == null || !facet.canDelete) return this;
    
    final newFacets = facets.where((f) => f.id != id).toList();
    return FacetCollection(
      facets: newFacets,
      defaultFacetId: defaultFacetId == id ? null : defaultFacetId,
      primaryFacetId: primaryFacetId == id ? null : primaryFacetId,
    );
  }

  /// Set the default facet
  FacetCollection setDefaultFacet(String id) {
    final newFacets = facets.map((f) => f.copyWith(isDefault: f.id == id)).toList();
    return FacetCollection(
      facets: newFacets,
      defaultFacetId: id,
      primaryFacetId: primaryFacetId,
    );
  }

  /// Serialization
  Map<String, dynamic> toJson() => {
    'facets': facets.map((f) => f.toJson()).toList(),
    'default_facet_id': defaultFacetId,
    'primary_facet_id': primaryFacetId,
  };

  factory FacetCollection.fromJson(Map<String, dynamic> json) {
    var facets = (json['facets'] as List?)
        ?.map((f) => ProfileFacet.fromJson(f as Map<String, dynamic>))
        .toList() ?? [];
    
    // Ensure default "me" facet exists
    if (!facets.any((f) => f.isDefaultPersonal)) {
      facets.insert(0, ProfileFacet.defaultFacet());
    }
    
    // Normalize defaultFacetId
    var defaultId = json['default_facet_id'] as String?;
    if (defaultId == 'default') defaultId = 'me';
    
    return FacetCollection(
      facets: facets,
      defaultFacetId: defaultId,
      primaryFacetId: json['primary_facet_id'] as String?,
    );
  }

  /// Create with just a default facet
  factory FacetCollection.withDefault({
    String? displayName,
    String? avatarUrl,
    String? bio,
    List<ProfileLink>? links,
  }) {
    return FacetCollection(
      facets: [
        ProfileFacet.defaultFacet(
          displayName: displayName,
          avatarUrl: avatarUrl,
          bio: bio,
          links: links,
        ),
      ],
      defaultFacetId: 'me',
    );
  }

  /// Migrate from existing ProfileData
  factory FacetCollection.migrateFromProfileData(ProfileData? data) {
    if (data == null || data.isEmpty) {
      return FacetCollection(
        facets: [ProfileFacet.defaultFacet()],
        defaultFacetId: 'me',
      );
    }
    
    return FacetCollection(
      facets: [ProfileFacet.fromProfileData(data)],
      defaultFacetId: 'me',
    );
  }
}

// ==================== GNS IDENTITY PAYLOAD ====================

/// GNS Identity payload for QR codes with facet support
class GnsIdentityPayload {
  final String publicKey;
  final String? handle;
  final String? facetId;
  
  GnsIdentityPayload({
    required this.publicKey,
    this.handle,
    this.facetId,
  });
  
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'type': 'gns-identity',
      'version': 2,  // Bumped for facet support
      'pk': publicKey,
    };
    if (handle != null) json['handle'] = handle;
    if (facetId != null && facetId != 'me' && facetId != 'default') {
      json['facet'] = facetId;
    }
    return json;
  }
  
  String toJsonString() => '${toJson()}';
  
  /// Generate URL format: gns://facet@handle or gns://@handle
  String toUrl() {
    if (handle != null) {
      if (facetId != null && facetId != 'me' && facetId != 'default') {
        return 'gns://$facetId@$handle';  // dix@camiloayerbe
      }
      return 'gns://@$handle';  // @camiloayerbe (default facet)
    }
    return 'gns://$publicKey';
  }
  
  factory GnsIdentityPayload.fromJson(Map<String, dynamic> json) {
    return GnsIdentityPayload(
      publicKey: json['pk'] as String,
      handle: json['handle'] as String?,
      facetId: json['facet'] as String?,
    );
  }
}
