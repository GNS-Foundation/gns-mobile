// Profile Module - Phase 3A
//
// Helper class for managing profile data within GnsModule.config.
// Schema: gns.module.profile/v1
//
// Location: lib/core/profile/profile_module.dart

import '../gns/gns_record.dart';

/// A link in the user's profile (website, social, etc.)
class ProfileLink {
  final String type;      // 'website' | 'github' | 'twitter' | 'linkedin' | 'custom'
  final String? label;    // Display label (optional)
  final String url;       // Full URL

  ProfileLink({
    required this.type,
    this.label,
    required this.url,
  });

  Map<String, dynamic> toJson() => {
    'type': type,
    if (label != null) 'label': label,
    'url': url,
  };

  factory ProfileLink.fromJson(Map<String, dynamic> json) {
    return ProfileLink(
      type: json['type'] as String? ?? 'custom',
      label: json['label'] as String?,
      url: json['url'] as String,
    );
  }

  /// Create common link types
  static ProfileLink website(String url, {String? label}) =>
      ProfileLink(type: 'website', url: url, label: label ?? 'Website');
  
  static ProfileLink github(String username) =>
      ProfileLink(type: 'github', url: 'https://github.com/$username', label: 'GitHub');
  
  static ProfileLink twitter(String handle) =>
      ProfileLink(type: 'twitter', url: 'https://twitter.com/$handle', label: 'Twitter');
  
  static ProfileLink linkedin(String username) =>
      ProfileLink(type: 'linkedin', url: 'https://linkedin.com/in/$username', label: 'LinkedIn');

  /// Get icon for link type
  String get icon {
    switch (type) {
      case 'website': return '🌐';
      case 'github': return '🐙';
      case 'twitter': return '🐦';
      case 'linkedin': return '💼';
      default: return '🔗';
    }
  }

  @override
  String toString() => 'ProfileLink($type: $url)';
}

/// Profile data stored in GnsModule.config
class ProfileData {
  final String? displayName;
  final String? bio;
  final String? avatarUrl;
  final List<ProfileLink> links;
  final bool locationPublic;
  final int locationResolution;  // H3 resolution for public location (default: 7 = city)

  ProfileData({
    this.displayName,
    this.bio,
    this.avatarUrl,
    List<ProfileLink>? links,
    this.locationPublic = false,
    this.locationResolution = 7,
  }) : links = links ?? [];

  Map<String, dynamic> toJson() => {
    if (displayName != null) 'display_name': displayName,
    if (bio != null) 'bio': bio,
    if (avatarUrl != null) 'avatar_url': avatarUrl,
    'links': links.map((l) => l.toJson()).toList(),
    'location_public': locationPublic,
    'location_resolution': locationResolution,
  };

  factory ProfileData.fromJson(Map<String, dynamic>? json) {
    if (json == null) return ProfileData();
    
    return ProfileData(
      displayName: json['display_name'] as String?,
      bio: json['bio'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      links: (json['links'] as List?)
          ?.map((l) => ProfileLink.fromJson(l as Map<String, dynamic>))
          .toList() ?? [],
      locationPublic: json['location_public'] as bool? ?? false,
      locationResolution: json['location_resolution'] as int? ?? 7,
    );
  }

  /// Create a copy with updated fields
  ProfileData copyWith({
    String? displayName,
    String? bio,
    String? avatarUrl,
    List<ProfileLink>? links,
    bool? locationPublic,
    int? locationResolution,
  }) {
    return ProfileData(
      displayName: displayName ?? this.displayName,
      bio: bio ?? this.bio,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      links: links ?? this.links,
      locationPublic: locationPublic ?? this.locationPublic,
      locationResolution: locationResolution ?? this.locationResolution,
    );
  }

  /// Check if profile has any content
  bool get isEmpty => 
      displayName == null && 
      bio == null && 
      avatarUrl == null && 
      links.isEmpty;

  bool get isNotEmpty => !isEmpty;

  @override
  String toString() => 'ProfileData(name: $displayName, bio: ${bio?.substring(0, 20)}...)';
}

/// Helper class for creating and extracting profile modules
class ProfileModule {
  static const String moduleId = 'profile';
  static const String schema = GnsModuleSchemas.profile;

  /// Create a GnsModule containing profile data
  static GnsModule create(ProfileData data) {
    return GnsModule(
      id: moduleId,
      schema: schema,
      name: 'Profile',
      isPublic: true,
      config: data.toJson(),
    );
  }

  /// Extract ProfileData from a GnsModule
  static ProfileData? extract(GnsModule module) {
    if (module.id != moduleId || module.schema != schema) {
      return null;
    }
    return ProfileData.fromJson(module.config);
  }

  /// Find and extract profile from a list of modules
  static ProfileData? fromModules(List<GnsModule> modules) {
    try {
      final profileModule = modules.firstWhere(
        (m) => m.id == moduleId && m.schema == schema,
      );
      return extract(profileModule);
    } catch (_) {
      return null;
    }
  }

  /// Update or add profile module in a list
  static List<GnsModule> updateInModules(List<GnsModule> modules, ProfileData data) {
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

  /// Extract profile from a GnsRecord
  static ProfileData? fromRecord(GnsRecord record) {
    return fromModules(record.modules);
  }
}

/// H3 resolution descriptions for location privacy
class LocationPrivacy {
  static const Map<int, String> resolutionLabels = {
    4: 'Country',      // ~1,770 km²
    5: 'Region',       // ~253 km²
    6: 'Metro',        // ~36 km²
    7: 'City',         // ~5 km² (DEFAULT)
    8: 'District',     // ~0.7 km²
    9: 'Neighborhood', // ~0.1 km²
    10: 'Block',       // ~0.015 km²
  };

  static String labelFor(int resolution) {
    return resolutionLabels[resolution] ?? 'Custom ($resolution)';
  }

  static const int defaultPublicResolution = 7;  // City level
  static const int privateResolution = 10;       // Block level (for breadcrumbs)
}
