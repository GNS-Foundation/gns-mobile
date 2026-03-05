/// TierGate — Singleton ChangeNotifier for Tier-Based Feature Gating
///
/// Thresholds:
///   🌱 Seedling    0+
///   🌿 Explorer    10+
///   🧭 Navigator   100+   → Messages, Contacts unlocked
///   🏔️ Trailblazer 250+   → Full access
///
/// Usage:
///   final gate = TierGate();
///   gate.addListener(() => setState((){}));
///   gate.currentTier.displayName  // "Trailblazer"
///   gate.canSendMessages          // true/false
///
/// Initialize once in app.dart AFTER wallet.initialize():
///   await TierGate().initialize();
///
/// Location: lib/core/tier/tier_gate.dart

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../chain/breadcrumb_engine.dart';
import '../gns/identity_wallet.dart';

// ─────────────────────────────────────────────
// Tier Model
// ─────────────────────────────────────────────

class GnsTier {
  final String id;
  final String displayName;
  final String emoji;
  final String description;
  final int minBreadcrumbs;
  final int colorValue;   // as 0xFFRRGGBB int for use in Color()

  const GnsTier._({
    required this.id,
    required this.displayName,
    required this.emoji,
    required this.description,
    required this.minBreadcrumbs,
    required this.colorValue,
  });

  Color get color => Color(colorValue);

  // ── Static tier definitions ──────────────────────────────────────────────

  static const seedling = GnsTier._(
    id: 'seedling',
    displayName: 'Seedling',
    emoji: '🌱',
    description: 'Drop breadcrumbs to start building your identity.',
    minBreadcrumbs: 0,
    colorValue: 0xFF10B981,   // green
  );

  static const explorer = GnsTier._(
    id: 'explorer',
    displayName: 'Explorer',
    emoji: '🌿',
    description: 'Keep moving! Claim your @handle at 100 breadcrumbs.',
    minBreadcrumbs: 10,
    colorValue: 0xFF06B6D4,   // cyan
  );

  static const navigator = GnsTier._(
    id: 'navigator',
    displayName: 'Navigator',
    emoji: '🧭',
    description: 'Messaging unlocked. Connect with others.',
    minBreadcrumbs: 100,
    colorValue: 0xFF3B82F6,   // blue
  );

  static const trailblazer = GnsTier._(
    id: 'trailblazer',
    displayName: 'Trailblazer',
    emoji: '🏔️',
    description: 'Full access. Payments, posting, facets, gSite, and org tools.',
    minBreadcrumbs: 250,
    colorValue: 0xFFF97316,   // orange — matches app screenshots
  );

  static const List<GnsTier> all = [seedling, explorer, navigator, trailblazer];

  static GnsTier fromCount(int count) {
    if (count >= trailblazer.minBreadcrumbs) return trailblazer;
    if (count >= navigator.minBreadcrumbs)   return navigator;
    if (count >= explorer.minBreadcrumbs)    return explorer;
    return seedling;
  }

  // ── Ordering helpers ─────────────────────────────────────────────────────

  int get level => all.indexOf(this);

  bool operator >=(GnsTier other) => level >= other.level;
  bool operator >(GnsTier other)  => level >  other.level;

  /// Next tier, or null if already Trailblazer
  GnsTier? get next {
    final i = level;
    return i < all.length - 1 ? all[i + 1] : null;
  }

  /// Breadcrumbs needed to reach next tier; null if already max
  int? breadcrumbsUntilNext(int current) {
    final n = next;
    return n == null ? null : n.minBreadcrumbs - current;
  }

  // ── Feature flags ─────────────────────────────────────────────────────────

  bool get canClaimHandle   => level >= explorer.level;
  bool get canSendMessages  => level >= navigator.level;
  bool get canViewContacts  => level >= navigator.level;
  bool get canViewHistory   => level >= trailblazer.level;
  bool get canUsePayments   => level >= trailblazer.level;
  bool get canPostDix       => level >= trailblazer.level;
  bool get canManageFacets  => level >= trailblazer.level;
  bool get canCreateGSite   => level >= trailblazer.level;
  bool get canRegisterOrg   => level >= trailblazer.level;
}

// ─────────────────────────────────────────────
// TierGate Singleton
// ─────────────────────────────────────────────

class TierGate extends ChangeNotifier {
  static final TierGate _instance = TierGate._internal();
  factory TierGate() => _instance;
  TierGate._internal();

  GnsTier _currentTier = GnsTier.seedling;
  int _breadcrumbCount = 0;
  bool _initialized = false;

  GnsTier get currentTier       => _currentTier;
  int     get breadcrumbCount   => _breadcrumbCount;
  bool    get initialized       => _initialized;

  // Convenience passthrough
  bool get canSendMessages  => _currentTier.canSendMessages;
  bool get canViewContacts  => _currentTier.canViewContacts;
  bool get canViewHistory   => _currentTier.canViewHistory;
  bool get canUsePayments   => _currentTier.canUsePayments;
  bool get canPostDix       => _currentTier.canPostDix;
  bool get canManageFacets  => _currentTier.canManageFacets;
  bool get canCreateGSite   => _currentTier.canCreateGSite;
  bool get canRegisterOrg   => _currentTier.canRegisterOrg;

  /// Lightweight init from a known count (used when wallet isn't ready yet)
  void initializeFromStats(int breadcrumbCount) {
    _breadcrumbCount = breadcrumbCount;
    _currentTier = GnsTier.fromCount(breadcrumbCount);
    _initialized = true;
    notifyListeners();
  }

  /// Call once in app.dart after wallet.initialize()
  Future<void> initialize() async {
    final engine = IdentityWallet().breadcrumbEngine;

    // Listen for new breadcrumbs in real-time
    final previousCallback = engine.onBreadcrumbDropped;
    engine.onBreadcrumbDropped = (block) {
      previousCallback?.call(block);
      _refresh(engine);
    };

    await _refresh(engine);
  }

  Future<void> _refresh(BreadcrumbEngine engine) async {
    try {
      final stats = await engine.getStats();
      final newCount = stats.breadcrumbCount;
      final newTier  = GnsTier.fromCount(newCount);

      if (newCount != _breadcrumbCount || newTier.id != _currentTier.id) {
        final leveledUp = newTier.level > _currentTier.level;
        _breadcrumbCount = newCount;
        _currentTier    = newTier;
        _initialized    = true;
        notifyListeners();
        if (leveledUp) {
          debugPrint('🎉 TIER UP → ${newTier.emoji} ${newTier.displayName}');
        }
      } else {
        _initialized = true;
      }
    } catch (e) {
      debugPrint('TierGate refresh error: $e');
      _initialized = true;
    }
  }

  /// Check if user has reached a given tier (old API compatibility)
  bool hasReached(GnsTier tier) => _currentTier.level >= tier.level;

  /// Manual refresh (e.g. on app resume)
  Future<void> refresh() => _refresh(IdentityWallet().breadcrumbEngine);
}

// ─────────────────────────────────────────────
// Backwards-compatibility aliases
// home_tab.dart and settings_tab.dart use the old names
// ─────────────────────────────────────────────

/// Alias: FeatureTier == GnsTier
typedef FeatureTier = GnsTier;

/// Lightweight feature descriptor used by settings_tab feature list
class GnsFeature {
  final String id;
  final String displayName;
  final String description;
  final GnsTier requiredTier;
  final IconData? icon;

  const GnsFeature({
    required this.id,
    required this.displayName,
    this.description = '',
    required this.requiredTier,
    this.icon,
  });
}

// ─────────────────────────────────────────────

// ─────────────────────────────────────────────
// Additional compatibility (round 2)
// ─────────────────────────────────────────────

extension GnsTierIconAlias on GnsTier {
  /// Old API used .icon — maps to .emoji
  String get icon => emoji;
}

extension TierGateCompat on TierGate {
  /// Old API: updateCount → initializeFromStats
  void updateCount(int count) => initializeFromStats(count);

  /// Breadcrumbs still needed to reach [tier]; 0 if already there
  int breadcrumbsUntil(GnsTier tier) {
    final needed = tier.minBreadcrumbs - breadcrumbCount;
    return needed < 0 ? 0 : needed;
  }

  /// All features not yet unlocked at current tier
  List<GnsFeature> get lockedFeatures {
    return allGnsFeatures.where((f) => !hasReached(f.requiredTier)).toList();
  }
}

/// Full feature catalogue
final allGnsFeatures = <GnsFeature>[
  GnsFeature(id: 'handle',   displayName: 'Claim @handle',          description: 'Reserve and claim your unique @handle.', requiredTier: GnsTier.explorer,    icon: Icons.alternate_email),
  GnsFeature(id: 'messages', displayName: 'Encrypted messaging',    description: 'Send end-to-end encrypted messages.',     requiredTier: GnsTier.navigator,   icon: Icons.chat_bubble_outline),
  GnsFeature(id: 'contacts', displayName: 'Contacts',               description: 'Manage your contact list.',              requiredTier: GnsTier.navigator,   icon: Icons.people_outline),
  GnsFeature(id: 'payments', displayName: 'Send & receive payments',description: 'Pay anyone with USDC, XLM or GNS.',      requiredTier: GnsTier.trailblazer, icon: Icons.monetization_on_outlined),
  GnsFeature(id: 'dix',      displayName: 'Public posting (DIX)',   description: 'Post publicly to the GNS timeline.',     requiredTier: GnsTier.trailblazer, icon: Icons.public),
  GnsFeature(id: 'facets',   displayName: 'Profile facets',         description: 'Create and manage profile facets.',      requiredTier: GnsTier.trailblazer, icon: Icons.layers_outlined),
  GnsFeature(id: 'gsite',    displayName: 'Create gSite',           description: 'Build your decentralized web presence.', requiredTier: GnsTier.trailblazer, icon: Icons.language),
  GnsFeature(id: 'org',      displayName: 'Organization tools',     description: 'Register and manage an organization.',   requiredTier: GnsTier.trailblazer, icon: Icons.business),
  GnsFeature(id: 'history',  displayName: 'Transaction history',    description: 'View all your past transactions.',       requiredTier: GnsTier.trailblazer, icon: Icons.history),
];
