/// TierGate — Progressive Feature Unlock Controller
///
/// Central authority for feature gating based on breadcrumb count.
/// Features unlock as users collect more breadcrumbs, creating a
/// natural progression from identity creation to full GNS capabilities.
///
/// Tiers:
///   Seedling:     0+    breadcrumbs — core identity, collection, handle reserve
///   Explorer:     50+   breadcrumbs — handle activation, profile, contacts
///   Navigator:    250+  breadcrumbs — messaging, social feed (read)
///   Trailblazer:  1000+ breadcrumbs — payments, posting, facets, email, GSite
///
/// Location: lib/core/tier_gate.dart

import 'package:flutter/foundation.dart';

// ==================== TIER DEFINITIONS ====================

enum FeatureTier {
  seedling,     // 0+    — always available
  explorer,     // 50+   — handle activation, profile
  navigator,    // 250+  — messaging, social read
  trailblazer,  // 1000+ — payments, posting, full features
}

extension FeatureTierExt on FeatureTier {
  int get threshold {
    switch (this) {
      case FeatureTier.seedling:    return 0;
      case FeatureTier.explorer:    return 50;
      case FeatureTier.navigator:   return 250;
      case FeatureTier.trailblazer: return 1000;
    }
  }

  String get displayName {
    switch (this) {
      case FeatureTier.seedling:    return 'Seedling';
      case FeatureTier.explorer:    return 'Explorer';
      case FeatureTier.navigator:   return 'Navigator';
      case FeatureTier.trailblazer: return 'Trailblazer';
    }
  }

  String get icon {
    switch (this) {
      case FeatureTier.seedling:    return '🌱';
      case FeatureTier.explorer:    return '🧭';
      case FeatureTier.navigator:   return '🗺️';
      case FeatureTier.trailblazer: return '🏔️';
    }
  }

  String get description {
    switch (this) {
      case FeatureTier.seedling:
        return 'Your identity journey begins. Collect breadcrumbs to prove you\'re human.';
      case FeatureTier.explorer:
        return 'Your handle is active. Edit your profile and find other identities.';
      case FeatureTier.navigator:
        return 'Send encrypted messages and browse the decentralized social feed.';
      case FeatureTier.trailblazer:
        return 'Full access. Payments, posting, facets, GSite, and organization tools.';
    }
  }

  int get colorValue {
    switch (this) {
      case FeatureTier.seedling:    return 0xFF4CAF50; // green
      case FeatureTier.explorer:    return 0xFF2196F3; // blue
      case FeatureTier.navigator:   return 0xFF9C27B0; // purple
      case FeatureTier.trailblazer: return 0xFFFF9800; // orange
    }
  }
}

// ==================== FEATURE REGISTRY ====================

enum GnsFeature {
  // Tier 0: Seedling (always available)
  identityCreation,
  breadcrumbCollection,
  handleReservation,
  trustProgress,
  extensionPairing,
  identityCard,

  // Tier 1: Explorer (50+)
  handleActivation,
  profileEditor,
  contactSearch,
  identityBrowser,
  vaultSync,

  // Tier 2: Navigator (250+)
  messaging,
  contactManagement,
  dixFeedRead,

  // Tier 3: Trailblazer (1000+)
  payments,
  dixPosting,
  facetManagement,
  gsiteBuilder,
  emailBridge,
  orgRegistration,
  tokenManagement,
}

extension GnsFeatureExt on GnsFeature {
  FeatureTier get requiredTier {
    switch (this) {
      case GnsFeature.identityCreation:
      case GnsFeature.breadcrumbCollection:
      case GnsFeature.handleReservation:
      case GnsFeature.trustProgress:
      case GnsFeature.extensionPairing:
      case GnsFeature.identityCard:
        return FeatureTier.seedling;

      case GnsFeature.handleActivation:
      case GnsFeature.profileEditor:
      case GnsFeature.contactSearch:
      case GnsFeature.identityBrowser:
      case GnsFeature.vaultSync:
        return FeatureTier.explorer;

      case GnsFeature.messaging:
      case GnsFeature.contactManagement:
      case GnsFeature.dixFeedRead:
        return FeatureTier.navigator;

      case GnsFeature.payments:
      case GnsFeature.dixPosting:
      case GnsFeature.facetManagement:
      case GnsFeature.gsiteBuilder:
      case GnsFeature.emailBridge:
      case GnsFeature.orgRegistration:
      case GnsFeature.tokenManagement:
        return FeatureTier.trailblazer;
    }
  }

  String get displayName {
    switch (this) {
      case GnsFeature.identityCreation:     return 'Identity Creation';
      case GnsFeature.breadcrumbCollection: return 'Breadcrumb Collection';
      case GnsFeature.handleReservation:    return '@Handle Reservation';
      case GnsFeature.trustProgress:        return 'Trust Progress';
      case GnsFeature.extensionPairing:     return 'Vault Extension Pairing';
      case GnsFeature.identityCard:         return 'Identity Card';
      case GnsFeature.handleActivation:     return '@Handle Activation';
      case GnsFeature.profileEditor:        return 'Profile Editor';
      case GnsFeature.contactSearch:        return 'Identity Search';
      case GnsFeature.identityBrowser:      return 'Identity Browser';
      case GnsFeature.vaultSync:            return 'Vault Sync';
      case GnsFeature.messaging:            return 'Encrypted Messaging';
      case GnsFeature.contactManagement:    return 'Contact Management';
      case GnsFeature.dixFeedRead:          return 'Social Feed';
      case GnsFeature.payments:             return 'Stellar Payments';
      case GnsFeature.dixPosting:           return 'Social Posting';
      case GnsFeature.facetManagement:      return 'Identity Facets';
      case GnsFeature.gsiteBuilder:         return 'GSite Builder';
      case GnsFeature.emailBridge:          return 'Email Bridge';
      case GnsFeature.orgRegistration:      return 'Organization Registration';
      case GnsFeature.tokenManagement:      return 'GNS Token Management';
    }
  }

  String get teaser {
    switch (this) {
      case GnsFeature.identityCreation:     return 'Generate your Ed25519 keypair';
      case GnsFeature.breadcrumbCollection: return 'Drop breadcrumbs to prove humanity';
      case GnsFeature.handleReservation:    return 'Reserve your @handle';
      case GnsFeature.trustProgress:        return 'Watch your trust score grow';
      case GnsFeature.extensionPairing:     return 'Pair with Chrome extension';
      case GnsFeature.identityCard:         return 'Your cryptographic identity';
      case GnsFeature.handleActivation:     return 'Activate your @handle on the network';
      case GnsFeature.profileEditor:        return 'Set display name, bio, and avatar';
      case GnsFeature.contactSearch:        return 'Find other GNS identities';
      case GnsFeature.identityBrowser:      return 'Browse and verify identities';
      case GnsFeature.vaultSync:            return 'Sync identity with browser extension';
      case GnsFeature.messaging:            return 'End-to-end encrypted messages';
      case GnsFeature.contactManagement:    return 'Save and organize contacts';
      case GnsFeature.dixFeedRead:          return 'Read the decentralized timeline';
      case GnsFeature.payments:             return 'Send/receive via Stellar network';
      case GnsFeature.dixPosting:           return 'Post to the decentralized timeline';
      case GnsFeature.facetManagement:      return 'Multiple identity contexts';
      case GnsFeature.gsiteBuilder:         return 'Build your personal GNS site';
      case GnsFeature.emailBridge:          return 'Bridge GNS messaging to email';
      case GnsFeature.orgRegistration:      return 'Register an organization namespace';
      case GnsFeature.tokenManagement:      return 'Manage GNS token balance';
    }
  }
}

// ==================== TIER GATE SINGLETON ====================

class TierGate extends ChangeNotifier {
  static final TierGate _instance = TierGate._internal();
  factory TierGate() => _instance;
  TierGate._internal();

  int _breadcrumbCount = 0;
  bool _initialized = false;

  // ==================== Getters ====================

  int get breadcrumbCount => _breadcrumbCount;
  bool get initialized => _initialized;

  FeatureTier get currentTier {
    if (_breadcrumbCount >= 1000) return FeatureTier.trailblazer;
    if (_breadcrumbCount >= 250) return FeatureTier.navigator;
    if (_breadcrumbCount >= 50) return FeatureTier.explorer;
    return FeatureTier.seedling;
  }

  bool canAccess(GnsFeature feature) {
    return currentTier.index >= feature.requiredTier.index;
  }

  bool hasReached(FeatureTier tier) {
    return currentTier.index >= tier.index;
  }

  int breadcrumbsUntil(FeatureTier tier) {
    final needed = tier.threshold - _breadcrumbCount;
    return needed > 0 ? needed : 0;
  }

  double get progressToNextTier {
    if (currentTier == FeatureTier.trailblazer) return 1.0;
    final next = FeatureTier.values[currentTier.index + 1];
    final range = next.threshold - currentTier.threshold;
    if (range <= 0) return 1.0;
    return ((_breadcrumbCount - currentTier.threshold) / range).clamp(0.0, 1.0);
  }

  FeatureTier? get nextTier {
    if (currentTier == FeatureTier.trailblazer) return null;
    return FeatureTier.values[currentTier.index + 1];
  }

  List<GnsFeature> get nextTierFeatures {
    final next = nextTier;
    if (next == null) return [];
    return GnsFeature.values.where((f) => f.requiredTier == next).toList();
  }

  List<GnsFeature> get lockedFeatures {
    return GnsFeature.values.where((f) => !canAccess(f)).toList();
  }

  List<GnsFeature> get unlockedFeatures {
    return GnsFeature.values.where((f) => canAccess(f)).toList();
  }

  // ==================== Lifecycle ====================

  /// Initialize from BreadcrumbStats
  void initializeFromStats(int count) {
    _breadcrumbCount = count;
    _initialized = true;
    debugPrint('[TierGate] Initialized: $_breadcrumbCount breadcrumbs, tier: ${currentTier.displayName}');
    notifyListeners();
  }

  /// Update count (called after dropping a breadcrumb)
  void updateCount(int count) {
    final oldTier = currentTier;
    _breadcrumbCount = count;
    if (currentTier != oldTier) {
      debugPrint('[TierGate] 🎉 TIER UP! ${oldTier.displayName} → ${currentTier.displayName}');
    }
    notifyListeners();
  }

  void incrementCount() => updateCount(_breadcrumbCount + 1);

  // ==================== Milestones ====================

  static const List<Milestone> milestones = [
    Milestone(1,    '🥾', 'First Step',        'You dropped your first breadcrumb!'),
    Milestone(10,   '🌿', 'Getting Started',   '10 breadcrumbs — a real human pattern.'),
    Milestone(25,   '🚶', 'On Your Way',       'Halfway to Explorer tier.'),
    Milestone(50,   '🧭', 'Explorer',          '@handle activated! You have a name.'),
    Milestone(100,  '💯', 'Century',           '100 breadcrumbs — serious trajectory.'),
    Milestone(250,  '🗺️', 'Navigator',         'Messaging unlocked. Connect with others.'),
    Milestone(500,  '⭐', 'Halfway There',     'Halfway to Trailblazer.'),
    Milestone(750,  '🔥', 'Almost There',      'The finish line is in sight.'),
    Milestone(1000, '🏔️', 'Trailblazer',       'Full access. You are a verified human.'),
  ];

  List<Milestone> get achievedMilestones =>
      milestones.where((m) => _breadcrumbCount >= m.threshold).toList();

  Milestone? get nextMilestone {
    for (final m in milestones) {
      if (_breadcrumbCount < m.threshold) return m;
    }
    return null;
  }
}

// ==================== MILESTONE ====================

class Milestone {
  final int threshold;
  final String icon;
  final String title;
  final String description;
  const Milestone(this.threshold, this.icon, this.title, this.description);
}
