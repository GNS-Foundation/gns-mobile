/// UserTierService — Single Source of Truth for Tier-Based Feature Unlocking
///
/// Tiers are earned through breadcrumb collection (Proof-of-Trajectory).
/// This service drives ALL feature gating across the app.
///
/// Tier thresholds (aligned with Trailblazer milestone labels):
///   🌱 Seedling    0–9      Home, Trailblazer progress, Settings
///   🌿 Explorer    10–99    + @handle reservation & claim (needs 100)
///   🧭 Navigator   100–249  + Messages, Contacts
///   🏔️ Trailblazer 250+     + History, Payments, DIX, gSite, Facets, Org tools
///
/// Location: lib/core/tier/user_tier_service.dart

import 'dart:async';
import 'package:flutter/foundation.dart';
import '../chain/breadcrumb_engine.dart';

// ─────────────────────────────────────────────
// Tier Enum
// ─────────────────────────────────────────────

enum UserTier { seedling, explorer, navigator, trailblazer }

extension UserTierInfo on UserTier {
  String get name {
    switch (this) {
      case UserTier.seedling:    return 'Seedling';
      case UserTier.explorer:    return 'Explorer';
      case UserTier.navigator:   return 'Navigator';
      case UserTier.trailblazer: return 'Trailblazer';
    }
  }

  String get emoji {
    switch (this) {
      case UserTier.seedling:    return '🌱';
      case UserTier.explorer:    return '🌿';
      case UserTier.navigator:   return '🧭';
      case UserTier.trailblazer: return '🏔️';
    }
  }

  String get description {
    switch (this) {
      case UserTier.seedling:
        return 'Drop breadcrumbs to start building your identity.';
      case UserTier.explorer:
        return 'Keep moving! Reserve your @handle at 100 breadcrumbs.';
      case UserTier.navigator:
        return 'Messaging unlocked. Connect with others.';
      case UserTier.trailblazer:
        return 'Full access. Payments, posting, facets, gSite, and org tools.';
    }
  }

  int get minBreadcrumbs {
    switch (this) {
      case UserTier.seedling:    return 0;
      case UserTier.explorer:    return 10;
      case UserTier.navigator:   return 100;
      case UserTier.trailblazer: return 250;
    }
  }

  // ─── Feature flags ──────────────────────────────────────────────────────────

  bool get canSendMessages     => index >= UserTier.navigator.index;
  bool get canViewContacts     => index >= UserTier.navigator.index;
  bool get canViewHistory      => index >= UserTier.trailblazer.index;
  bool get canUsePayments      => index >= UserTier.trailblazer.index;
  bool get canPostDix          => index >= UserTier.trailblazer.index;
  bool get canManageFacets     => index >= UserTier.trailblazer.index;
  bool get canCreateGSite      => index >= UserTier.trailblazer.index;
  bool get canRegisterOrg      => index >= UserTier.trailblazer.index;
  bool get canClaimHandle      => index >= UserTier.explorer.index; // still needs 100 crumbs

  /// How many breadcrumbs until the next tier (null = already max tier)
  int? breadcrumbsUntilNext(int current) {
    switch (this) {
      case UserTier.seedling:    return UserTier.explorer.minBreadcrumbs    - current;
      case UserTier.explorer:    return UserTier.navigator.minBreadcrumbs   - current;
      case UserTier.navigator:   return UserTier.trailblazer.minBreadcrumbs - current;
      case UserTier.trailblazer: return null;
    }
  }
}

// ─────────────────────────────────────────────
// Tier Service
// ─────────────────────────────────────────────

class UserTierService extends ChangeNotifier {
  // Singleton
  static final UserTierService _instance = UserTierService._internal();
  factory UserTierService() => _instance;
  UserTierService._internal();

  UserTier _tier = UserTier.seedling;
  int _breadcrumbCount = 0;
  bool _initialized = false;

  UserTier get tier => _tier;
  int get breadcrumbCount => _breadcrumbCount;
  bool get initialized => _initialized;

  // Convenience passthrough getters
  bool get canSendMessages  => _tier.canSendMessages;
  bool get canViewContacts  => _tier.canViewContacts;
  bool get canViewHistory   => _tier.canViewHistory;
  bool get canUsePayments   => _tier.canUsePayments;
  bool get canPostDix       => _tier.canPostDix;
  bool get canManageFacets  => _tier.canManageFacets;
  bool get canCreateGSite   => _tier.canCreateGSite;
  bool get canRegisterOrg   => _tier.canRegisterOrg;
  int? get breadcrumbsUntilNextTier => _tier.breadcrumbsUntilNext(_breadcrumbCount);

  /// Called once at app startup (from main_navigation or app.dart)
  Future<void> initialize(BreadcrumbEngine engine) async {
    // Attach listener so tier updates live as crumbs are dropped
    engine.onBreadcrumbDropped = (_) => _refresh(engine);
    await _refresh(engine);
  }

  Future<void> _refresh(BreadcrumbEngine engine) async {
    final stats = await engine.getStats();
    final newCount = stats.breadcrumbCount;
    final newTier  = _tierFromCount(newCount);

    if (newCount != _breadcrumbCount || newTier != _tier) {
      final leveledUp = newTier.index > _tier.index;
      _breadcrumbCount = newCount;
      _tier = newTier;
      _initialized = true;
      notifyListeners();
      if (leveledUp) {
        debugPrint('🎉 TIER UP → ${newTier.emoji} ${newTier.name}');
      }
    } else {
      _initialized = true;
    }
  }

  /// Force a manual refresh (e.g. after returning from background)
  Future<void> refresh(BreadcrumbEngine engine) => _refresh(engine);

  static UserTier _tierFromCount(int count) {
    if (count >= UserTier.trailblazer.minBreadcrumbs) return UserTier.trailblazer;
    if (count >= UserTier.navigator.minBreadcrumbs)   return UserTier.navigator;
    if (count >= UserTier.explorer.minBreadcrumbs)    return UserTier.explorer;
    return UserTier.seedling;
  }
}
