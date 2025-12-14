/// Profile Facet - Phase 4c
///
/// Represents a single presentation facet of an identity.
/// One identity can have multiple facets (work, friends, family, etc.)
/// 
/// Uses existing ProfileLink from profile_module.dart
///
/// Location: lib/core/profile/profile_facet.dart

import 'profile_module.dart';  // Uses existing ProfileLink

/// A single facet of an identity profile.
/// 
/// Each facet represents a different presentation of the same identity:
/// - @cayerbe/work → Professional presentation
/// - @cayerbe/friends → Casual presentation
/// - @cayerbe/family → Private presentation
class ProfileFacet {
  final String id;              // "default", "work", "friends", "family", custom
  final String label;           // Human-readable label: "Work", "Friends", etc.
  final String emoji;           // Visual identifier: 💼, 🎉, 👨‍👩‍👧, etc.
  final String? displayName;    // Name shown on this facet
  final String? avatarUrl;      // Avatar for this facet (base64 data URL)
  final String? bio;            // Bio for this facet
  final List<ProfileLink> links;  // Uses existing ProfileLink from profile_module.dart
  final bool isDefault;         // Is this the default facet for strangers?
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
    this.isDefault = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : links = links ?? [],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// Create the default facet (for strangers)
  factory ProfileFacet.defaultFacet({
    String? displayName,
    String? avatarUrl,
    String? bio,
    List<ProfileLink>? links,
  }) {
    return ProfileFacet(
      id: 'default',
      label: 'Default',
      emoji: '👤',
      displayName: displayName,
      avatarUrl: avatarUrl,
      bio: bio,
      links: links,
      isDefault: true,
    );
  }

  /// Create from existing ProfileData (migration helper)
  factory ProfileFacet.fromProfileData(ProfileData data, {String id = 'default'}) {
    return ProfileFacet(
      id: id,
      label: id == 'default' ? 'Default' : id[0].toUpperCase() + id.substring(1),
      emoji: id == 'default' ? '👤' : '📝',
      displayName: data.displayName,
      avatarUrl: data.avatarUrl,
      bio: data.bio,
      links: data.links,
      isDefault: id == 'default',
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

  /// Predefined facet templates
  static ProfileFacet workTemplate() => ProfileFacet(
    id: 'work',
    label: 'Work',
    emoji: '💼',
  );

  static ProfileFacet friendsTemplate() => ProfileFacet(
    id: 'friends',
    label: 'Friends',
    emoji: '🎉',
  );

  static ProfileFacet familyTemplate() => ProfileFacet(
    id: 'family',
    label: 'Family',
    emoji: '👨‍👩‍👧',
  );

  static ProfileFacet travelTemplate() => ProfileFacet(
    id: 'travel',
    label: 'Travel',
    emoji: '✈️',
  );

  static ProfileFacet creativeTemplate() => ProfileFacet(
    id: 'creative',
    label: 'Creative',
    emoji: '🎨',
  );

  static ProfileFacet gamingTemplate() => ProfileFacet(
    id: 'gaming',
    label: 'Gaming',
    emoji: '🎮',
  );

  /// All available templates
  static List<ProfileFacet> get templates => [
    workTemplate(),
    friendsTemplate(),
    familyTemplate(),
    travelTemplate(),
    creativeTemplate(),
    gamingTemplate(),
  ];

  /// Copy with modifications
  ProfileFacet copyWith({
    String? id,
    String? label,
    String? emoji,
    String? displayName,
    String? avatarUrl,
    String? bio,
    List<ProfileLink>? links,
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
      isDefault: isDefault ?? this.isDefault,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }

  /// Serialization
  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'emoji': emoji,
    'display_name': displayName,
    'avatar_url': avatarUrl,
    'bio': bio,
    'links': links.map((l) => l.toJson()).toList(),
    'is_default': isDefault,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  factory ProfileFacet.fromJson(Map<String, dynamic> json) {
    return ProfileFacet(
      id: json['id'] as String,
      label: json['label'] as String,
      emoji: json['emoji'] as String? ?? '👤',
      displayName: json['display_name'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      bio: json['bio'] as String?,
      links: (json['links'] as List?)
          ?.map((l) => ProfileLink.fromJson(l as Map<String, dynamic>))
          .toList() ?? [],
      isDefault: json['is_default'] as bool? ?? false,
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at'] as String) 
          : DateTime.now(),
      updatedAt: json['updated_at'] != null 
          ? DateTime.parse(json['updated_at'] as String) 
          : DateTime.now(),
    );
  }

  /// For display
  String get displayLabel => '$emoji $label';
  
  String get effectiveDisplayName => displayName ?? label;
  
  @override
  String toString() => 'ProfileFacet($id: $label)';
}

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
    try {
      return facets.firstWhere((f) => f.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Get the default facet (for strangers)
  ProfileFacet get defaultFacet {
    if (defaultFacetId != null) {
      final facet = getFacet(defaultFacetId!);
      if (facet != null) return facet;
    }
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

  /// Remove a facet
  FacetCollection removeFacet(String id) {
    if (id == 'default') return this; // Can't remove default
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
    return FacetCollection(
      facets: (json['facets'] as List?)
          ?.map((f) => ProfileFacet.fromJson(f as Map<String, dynamic>))
          .toList(),
      defaultFacetId: json['default_facet_id'] as String?,
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
      defaultFacetId: 'default',
    );
  }

  /// Migrate from existing ProfileData
  factory FacetCollection.migrateFromProfileData(ProfileData? data) {
    if (data == null || data.isEmpty) {
      return FacetCollection(
        facets: [ProfileFacet.defaultFacet()],
        defaultFacetId: 'default',
      );
    }
    
    return FacetCollection(
      facets: [ProfileFacet.fromProfileData(data)],
      defaultFacetId: 'default',
    );
  }
}

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
      'version': 1,
      'pk': publicKey,
    };
    if (handle != null) json['handle'] = handle;
    if (facetId != null && facetId != 'default') json['facet'] = facetId;
    return json;
  }
  
  String toJsonString() => '${toJson()}';
  
  /// Generate URL format
  String toUrl() {
    if (handle != null) {
      if (facetId != null && facetId != 'default') {
        return 'gns://@$handle/$facetId';
      }
      return 'gns://@$handle';
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
