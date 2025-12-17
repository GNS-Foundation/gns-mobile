/// Protocol Facets Registry - Globe Posts Phase 1
///
/// Defines reserved facet namespaces that unlock special platform features.
/// When a user creates a facet with one of these IDs, the system presents
/// an activation flow with specific terms and behaviors.
///
/// Philosophy: Protocol facets extend user capabilities, they don't restrict them.
/// The identity still belongs to the human - these just unlock new powers.
///
/// Location: lib/core/facets/protocol_facets.dart

import 'package:flutter/foundation.dart';

/// Behavior types for protocol facets
enum FacetBehavior {
  /// Posts are visible on public timeline (Globe Posts)
  publicBroadcast,
  
  /// Listings visible in marketplace/directory
  publicListing,
  
  /// Endpoint for receiving payments
  paymentEndpoint,
  
  /// Programmable API endpoint
  apiEndpoint,
  
  /// Public profile page (link-in-bio style)
  publicProfile,
  
  /// Verified badge display
  verifiedBadge,
}

/// Configuration for a protocol facet
class ProtocolFacetConfig {
  /// Facet ID (e.g., "dix", "store", "pay")
  final String id;
  
  /// Human-readable name
  final String name;
  
  /// Description of what this facet does
  final String description;
  
  /// Icon/emoji for display
  final String icon;
  
  /// The behavior this facet enables
  final FacetBehavior behavior;
  
  /// Module schema identifier
  final String moduleSchema;
  
  /// Whether user must have a claimed @handle to activate
  final bool requiresHandle;
  
  /// Minimum trust score required (null = no minimum)
  final double? minTrustScore;
  
  /// Minimum breadcrumb count required (null = no minimum)
  final int? minBreadcrumbs;
  
  /// Whether content from this facet is publicly visible
  final bool isPublic;
  
  /// Whether content is searchable/indexable
  final bool isSearchable;
  
  /// Whether this facet can receive payments
  final bool supportsPayments;
  
  /// Terms the user must accept to activate
  final List<String> activationTerms;

  const ProtocolFacetConfig({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.behavior,
    required this.moduleSchema,
    this.requiresHandle = true,
    this.minTrustScore,
    this.minBreadcrumbs,
    this.isPublic = true,
    this.isSearchable = true,
    this.supportsPayments = false,
    this.activationTerms = const [],
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'icon': icon,
    'behavior': behavior.name,
    'module_schema': moduleSchema,
    'requires_handle': requiresHandle,
    'min_trust_score': minTrustScore,
    'min_breadcrumbs': minBreadcrumbs,
    'is_public': isPublic,
    'is_searchable': isSearchable,
    'supports_payments': supportsPayments,
    'activation_terms': activationTerms,
  };

  factory ProtocolFacetConfig.fromJson(Map<String, dynamic> json) {
    return ProtocolFacetConfig(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      icon: json['icon'] as String,
      behavior: FacetBehavior.values.firstWhere(
        (b) => b.name == json['behavior'],
        orElse: () => FacetBehavior.publicBroadcast,
      ),
      moduleSchema: json['module_schema'] as String,
      requiresHandle: json['requires_handle'] as bool? ?? true,
      minTrustScore: (json['min_trust_score'] as num?)?.toDouble(),
      minBreadcrumbs: json['min_breadcrumbs'] as int?,
      isPublic: json['is_public'] as bool? ?? true,
      isSearchable: json['is_searchable'] as bool? ?? true,
      supportsPayments: json['supports_payments'] as bool? ?? false,
      activationTerms: (json['activation_terms'] as List?)
          ?.map((e) => e as String)
          .toList() ?? [],
    );
  }
}

/// Registry of all protocol facets
abstract class ProtocolFacets {
  ProtocolFacets._();

  // ============================================================
  // PROTOCOL FACET DEFINITIONS
  // ============================================================

  /// DIX - Public micro-blogging (Globe Posts)
  static const dix = ProtocolFacetConfig(
    id: 'dix',
    name: 'Globe Posts',
    description: 'Public micro-blog visible on the Globe Posts timeline',
    icon: '📢',
    behavior: FacetBehavior.publicBroadcast,
    moduleSchema: 'gns.module.feed/v1',
    requiresHandle: true,
    minBreadcrumbs: 100,
    isPublic: true,
    isSearchable: true,
    supportsPayments: true,
    activationTerms: [
      'Posts from dix@ are PUBLIC and permanently signed',
      'Anyone can view, quote, and respond to your posts',
      'Posts are cryptographically attributed to your identity',
      'Your trust score and breadcrumb count are visible',
      'Posts cannot be deleted from the network (only marked as retracted)',
    ],
  );

  /// BLOG - Long-form public posts
  static const blog = ProtocolFacetConfig(
    id: 'blog',
    name: 'Blog',
    description: 'Long-form public articles and posts',
    icon: '📝',
    behavior: FacetBehavior.publicBroadcast,
    moduleSchema: 'gns.module.blog/v1',
    requiresHandle: true,
    minBreadcrumbs: 100,
    isPublic: true,
    isSearchable: true,
    supportsPayments: true,
    activationTerms: [
      'Blog posts are PUBLIC and permanently signed',
      'Anyone can view and share your articles',
      'Posts are cryptographically attributed to your identity',
    ],
  );

  /// STORE - Marketplace listings
  static const store = ProtocolFacetConfig(
    id: 'store',
    name: 'Marketplace',
    description: 'List products and services for sale',
    icon: '🛒',
    behavior: FacetBehavior.publicListing,
    moduleSchema: 'gns.module.store/v1',
    requiresHandle: true,
    minBreadcrumbs: 100,
    minTrustScore: 30,
    isPublic: true,
    isSearchable: true,
    supportsPayments: true,
    activationTerms: [
      'Store listings are PUBLIC and visible in the marketplace',
      'You are responsible for fulfilling orders',
      'Buyers can leave public reviews',
      'GNS may charge transaction fees',
    ],
  );

  /// PAY - Payment endpoint
  static const pay = ProtocolFacetConfig(
    id: 'pay',
    name: 'Payments',
    description: 'Receive payments and tips',
    icon: '💳',
    behavior: FacetBehavior.paymentEndpoint,
    moduleSchema: 'gns.module.pay/v1',
    requiresHandle: true,
    minBreadcrumbs: 50,
    isPublic: true,
    isSearchable: false,
    supportsPayments: true,
    activationTerms: [
      'Your payment address will be publicly visible',
      'You can receive GNS tokens and supported currencies',
      'Transaction history may be visible on-chain',
    ],
  );

  /// DEV - Developer API endpoint
  static const dev = ProtocolFacetConfig(
    id: 'dev',
    name: 'Developer API',
    description: 'Programmable API endpoint for integrations',
    icon: '🔧',
    behavior: FacetBehavior.apiEndpoint,
    moduleSchema: 'gns.module.api/v1',
    requiresHandle: true,
    minBreadcrumbs: 100,
    minTrustScore: 40,
    isPublic: true,
    isSearchable: false,
    supportsPayments: false,
    activationTerms: [
      'Your API endpoint will be publicly accessible',
      'You are responsible for your API behavior',
      'Rate limits and usage policies apply',
    ],
  );

  /// HIRE - Services directory
  static const hire = ProtocolFacetConfig(
    id: 'hire',
    name: 'Services',
    description: 'Offer professional services for hire',
    icon: '💼',
    behavior: FacetBehavior.publicListing,
    moduleSchema: 'gns.module.hire/v1',
    requiresHandle: true,
    minBreadcrumbs: 100,
    minTrustScore: 30,
    isPublic: true,
    isSearchable: true,
    supportsPayments: true,
    activationTerms: [
      'Your service listing is PUBLIC',
      'Clients can contact you and leave reviews',
      'You are responsible for service delivery',
    ],
  );

  /// EVENTS - Event calendar
  static const events = ProtocolFacetConfig(
    id: 'events',
    name: 'Events',
    description: 'Host and promote events',
    icon: '📅',
    behavior: FacetBehavior.publicListing,
    moduleSchema: 'gns.module.events/v1',
    requiresHandle: true,
    minBreadcrumbs: 50,
    isPublic: true,
    isSearchable: true,
    supportsPayments: true,
    activationTerms: [
      'Events are PUBLIC and visible in the events directory',
      'Attendees can RSVP and leave reviews',
      'You can sell tickets through GNS payments',
    ],
  );

  /// LINKS - Link-in-bio public profile
  static const links = ProtocolFacetConfig(
    id: 'links',
    name: 'Links',
    description: 'Public link-in-bio profile page',
    icon: '🔗',
    behavior: FacetBehavior.publicProfile,
    moduleSchema: 'gns.module.links/v1',
    requiresHandle: true,
    minBreadcrumbs: 50,
    isPublic: true,
    isSearchable: true,
    supportsPayments: false,
    activationTerms: [
      'Your links page is PUBLIC at gns.network/@handle/links',
      'Anyone can view your curated links',
    ],
  );

  // ============================================================
  // REGISTRY
  // ============================================================

  /// All protocol facets
  static const List<ProtocolFacetConfig> all = [
    dix,
    blog,
    store,
    pay,
    dev,
    hire,
    events,
    links,
  ];

  /// Map of facet ID to config
  static final Map<String, ProtocolFacetConfig> registry = {
    for (final config in all) config.id: config,
  };

  /// Set of all protocol facet IDs (for quick lookup)
  static final Set<String> ids = registry.keys.toSet();

  // ============================================================
  // LOOKUP METHODS
  // ============================================================

  /// Check if a facet ID is a protocol facet
  static bool isProtocolFacet(String id) {
    return ids.contains(id.toLowerCase().trim());
  }

  /// Get protocol facet config by ID
  static ProtocolFacetConfig? getConfig(String id) {
    return registry[id.toLowerCase().trim()];
  }

  /// Get all protocol facets with a specific behavior
  static List<ProtocolFacetConfig> getByBehavior(FacetBehavior behavior) {
    return all.where((c) => c.behavior == behavior).toList();
  }

  /// Get all public broadcast facets (for Globe Posts)
  static List<ProtocolFacetConfig> get broadcastFacets {
    return getByBehavior(FacetBehavior.publicBroadcast);
  }

  /// Get all listing facets (marketplace, services, events)
  static List<ProtocolFacetConfig> get listingFacets {
    return getByBehavior(FacetBehavior.publicListing);
  }

  // ============================================================
  // ELIGIBILITY CHECK
  // ============================================================

  /// Check if a user can activate a protocol facet
  static ProtocolFacetEligibility checkEligibility({
    required String facetId,
    required bool hasHandle,
    required int breadcrumbCount,
    required double trustScore,
  }) {
    final config = getConfig(facetId);
    
    if (config == null) {
      return ProtocolFacetEligibility(
        isEligible: false,
        reason: 'Not a protocol facet',
      );
    }

    // Check handle requirement
    if (config.requiresHandle && !hasHandle) {
      return ProtocolFacetEligibility(
        isEligible: false,
        reason: 'You need to claim a @handle first (100 breadcrumbs required)',
        config: config,
      );
    }

    // Check breadcrumb requirement
    if (config.minBreadcrumbs != null && breadcrumbCount < config.minBreadcrumbs!) {
      return ProtocolFacetEligibility(
        isEligible: false,
        reason: 'You need at least ${config.minBreadcrumbs} breadcrumbs (you have $breadcrumbCount)',
        config: config,
      );
    }

    // Check trust score requirement
    if (config.minTrustScore != null && trustScore < config.minTrustScore!) {
      return ProtocolFacetEligibility(
        isEligible: false,
        reason: 'You need at least ${config.minTrustScore}% trust score (you have ${trustScore.toStringAsFixed(1)}%)',
        config: config,
      );
    }

    return ProtocolFacetEligibility(
      isEligible: true,
      config: config,
    );
  }
}

/// Result of eligibility check for protocol facet activation
class ProtocolFacetEligibility {
  final bool isEligible;
  final String? reason;
  final ProtocolFacetConfig? config;

  const ProtocolFacetEligibility({
    required this.isEligible,
    this.reason,
    this.config,
  });

  @override
  String toString() => isEligible 
      ? 'Eligible for ${config?.id}' 
      : 'Not eligible: $reason';
}

/// Extension to add protocol facet display helpers
extension ProtocolFacetConfigDisplay on ProtocolFacetConfig {
  /// Get the full facet notation (e.g., "dix@username")
  String facetNotation(String handle) => '$id@$handle';

  /// Get behavior description
  String get behaviorDescription {
    switch (behavior) {
      case FacetBehavior.publicBroadcast:
        return 'Public posts visible on timeline';
      case FacetBehavior.publicListing:
        return 'Public listing in directory';
      case FacetBehavior.paymentEndpoint:
        return 'Receive payments and tips';
      case FacetBehavior.apiEndpoint:
        return 'Programmable API access';
      case FacetBehavior.publicProfile:
        return 'Public profile page';
      case FacetBehavior.verifiedBadge:
        return 'Verified identity badge';
    }
  }

  /// Get requirements summary
  String get requirementsSummary {
    final reqs = <String>[];
    if (requiresHandle) reqs.add('@handle required');
    if (minBreadcrumbs != null) reqs.add('$minBreadcrumbs+ breadcrumbs');
    if (minTrustScore != null) reqs.add('${minTrustScore}%+ trust');
    return reqs.isEmpty ? 'No requirements' : reqs.join(' · ');
  }
}
