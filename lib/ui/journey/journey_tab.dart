/// Journey Tab — Breadcrumb Progress & Tier Progression
///
/// Shows the user's current tier, breadcrumb stats, milestones,
/// and a preview of features that unlock at each tier.
///
/// This replaces the old "Trailblazer" tab and is always visible
/// regardless of tier — it IS the unlock screen.
///
/// Location: lib/ui/journey/journey_tab.dart

import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/gns/identity_wallet.dart';
import '../../core/chain/breadcrumb_engine.dart';
import '../../core/tier/tier_gate.dart';
import '../../core/theme/theme_service.dart';

class JourneyTab extends StatefulWidget {
  final IdentityWallet wallet;

  const JourneyTab({super.key, required this.wallet});

  @override
  State<JourneyTab> createState() => _JourneyTabState();
}

class _JourneyTabState extends State<JourneyTab> {
  final _engine = BreadcrumbEngine();
  final _tierGate = TierGate();

  BreadcrumbStats? _stats;
  bool _autoCollecting = false;

  @override
  void initState() {
    super.initState();
    _tierGate.addListener(_onTierChanged);
    _engine.onBreadcrumbDropped = (_) => _loadStats();
    _loadStats();
    _autoCollecting = _engine.isCollecting;
  }

  @override
  void dispose() {
    _tierGate.removeListener(_onTierChanged);
    super.dispose();
  }

  void _onTierChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadStats() async {
    final stats = await _engine.getStats();
    if (mounted) setState(() => _stats = stats);
  }

  Future<void> _dropBreadcrumb() async {
    final result = await _engine.dropBreadcrumb();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message ?? (result.success ? '📍 Breadcrumb dropped!' : 'Drop failed')),
          backgroundColor: result.success ? AppTheme.secondary : AppTheme.error,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
    await _loadStats();
  }

  void _toggleAutoCollection(bool value) {
    if (value) {
      _engine.startCollection();
    } else {
      _engine.stopCollection();
    }
    setState(() => _autoCollecting = value);
  }

  @override
  Widget build(BuildContext context) {
    final tier = _tierGate.currentTier;
    final count = _stats?.breadcrumbCount ?? _tierGate.breadcrumbCount;
    final tierColor = tier.color;

    return Scaffold(
      backgroundColor: AppTheme.background(context),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadStats,
          color: tierColor,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildTierBanner(tier, tierColor),
              const SizedBox(height: 20),
              _buildBreadcrumbCircle(count, tierColor),
              const SizedBox(height: 20),
              _buildDropButton(tierColor),
              const SizedBox(height: 12),
              _buildAutoCollectionToggle(tierColor),
              const SizedBox(height: 16),
              _buildStatsRow(),
              const SizedBox(height: 20),
              _buildMilestones(count),
              const SizedBox(height: 20),
              _buildLockedFeatures(tier, count),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Tier Banner ───────────────────────────────────────────────────────────

  Widget _buildTierBanner(GnsTier tier, Color tierColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: tierColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tierColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Text(tier.emoji, style: const TextStyle(fontSize: 28)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tier.displayName.toUpperCase(),
                  style: TextStyle(
                    color: tierColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  tier.description,
                  style: TextStyle(
                    color: AppTheme.textSecondary(context),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Big breadcrumb circle ─────────────────────────────────────────────────

  Widget _buildBreadcrumbCircle(int count, Color tierColor) {
    return Center(
      child: Container(
        width: 180,
        height: 180,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: tierColor, width: 6),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _formatCount(count),
              style: TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.bold,
                color: tierColor,
              ),
            ),
            Text(
              'breadcrumbs',
              style: TextStyle(
                fontSize: 14,
                color: AppTheme.textSecondary(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatCount(int n) => n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}k' : '$n';

  // ─── Drop Button ───────────────────────────────────────────────────────────

  Widget _buildDropButton(Color tierColor) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: _dropBreadcrumb,
        icon: const Icon(Icons.location_on, color: Colors.white),
        label: const Text(
          'Drop Breadcrumb',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: tierColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
        ),
      ),
    );
  }

  // ─── Auto-Collection Toggle ────────────────────────────────────────────────

  Widget _buildAutoCollectionToggle(Color tierColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border(context)),
      ),
      child: Row(
        children: [
          Icon(Icons.my_location, color: tierColor, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Auto-Collection',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary(context),
                  ),
                ),
                Text(
                  _autoCollecting ? 'Collecting in background' : 'Tap to enable',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary(context),
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: _autoCollecting,
            onChanged: _toggleAutoCollection,
            activeColor: tierColor,
          ),
        ],
      ),
    );
  }

  // ─── Stats Row ─────────────────────────────────────────────────────────────

  Widget _buildStatsRow() {
    final trust = _stats?.trustScore.toStringAsFixed(0) ?? '—';
    final cells = _stats?.uniqueLocations.toString() ?? '—';
    final days  = _stats?.daysSinceStart.toString() ?? '—';

    return Row(
      children: [
        _buildStatCard(Icons.shield_outlined, '$trust%', 'Trust Score'),
        const SizedBox(width: 10),
        _buildStatCard(Icons.grid_view_outlined, cells, 'Unique Cells'),
        const SizedBox(width: 10),
        _buildStatCard(Icons.calendar_today_outlined, days, 'Days Active'),
      ],
    );
  }

  Widget _buildStatCard(IconData icon, String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: AppTheme.surface(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.border(context)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: AppTheme.textSecondary(context)),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: AppTheme.textPrimary(context),
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: AppTheme.textSecondary(context),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ─── Milestones ────────────────────────────────────────────────────────────

  static const _milestones = [
    (count: 1,   emoji: '👟', title: 'First Step',     subtitle: 'You dropped your first breadcrumb!'),
    (count: 10,  emoji: '🌿', title: 'Getting Started', subtitle: '10 breadcrumbs — Explorer unlocked.'),
    (count: 25,  emoji: '🚶', title: 'On Your Way',     subtitle: 'Halfway to Navigator tier.'),
    (count: 50,  emoji: '🧭', title: 'Pathfinder',      subtitle: 'Serious momentum.'),
    (count: 100, emoji: '💯', title: 'Century',         subtitle: '100 breadcrumbs — claim your @handle!'),
    (count: 100, emoji: '🔑', title: 'Navigator',       subtitle: 'Messaging unlocked. Connect with others.'),
    (count: 175, emoji: '⭐', title: 'Halfway There',   subtitle: 'Halfway to Trailblazer.'),
    (count: 200, emoji: '🔥', title: 'Almost There',    subtitle: 'The finish line is in sight.'),
    (count: 250, emoji: '🏔️', title: 'Trailblazer',    subtitle: 'Full access. You are a verified human.'),
  ];

  Widget _buildMilestones(int count) {
    final completed = _milestones.where((m) => count >= m.count).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'MILESTONES',
              style: TextStyle(
                color: AppTheme.textSecondary(context),
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
            Text(
              '$completed/${_milestones.length}',
              style: TextStyle(
                color: _tierGate.currentTier.color,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.surface(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.border(context)),
          ),
          child: Column(
            children: _milestones.map((m) {
              final done = count >= m.count;
              final isLast = _milestones.last == m;
              return Column(
                children: [
                  ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: done
                            ? _tierGate.currentTier.color.withOpacity(0.15)
                            : AppTheme.background(context),
                      ),
                      child: Center(
                        child: Text(m.emoji, style: const TextStyle(fontSize: 20)),
                      ),
                    ),
                    title: Text(
                      m.title,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: done
                            ? AppTheme.textPrimary(context)
                            : AppTheme.textSecondary(context),
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Text(
                      m.subtitle,
                      style: TextStyle(
                        color: AppTheme.textMuted(context),
                        fontSize: 12,
                      ),
                    ),
                    trailing: done
                        ? Icon(Icons.check_circle,
                            color: _tierGate.currentTier.color, size: 22)
                        : Icon(Icons.radio_button_unchecked,
                            color: AppTheme.textMuted(context), size: 22),
                  ),
                  if (!isLast)
                    Divider(height: 1, color: AppTheme.border(context)),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  // ─── Locked Features Preview ───────────────────────────────────────────────

  Widget _buildLockedFeatures(GnsTier tier, int count) {
    // Only show locked features if not yet Trailblazer
    if (tier.id == GnsTier.trailblazer.id) return const SizedBox.shrink();

    final next = tier.next!;
    final needed = next.minBreadcrumbs - count;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'COMING NEXT',
          style: TextStyle(
            color: AppTheme.textSecondary(context),
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.surface(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.border(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(next.emoji, style: const TextStyle(fontSize: 24)),
                  const SizedBox(width: 10),
                  Text(
                    '${next.displayName} — ${next.minBreadcrumbs} breadcrumbs',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary(context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '$needed more breadcrumbs to unlock',
                style: TextStyle(
                  color: next.color,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 12),
              ..._featureListForTier(next).map((f) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Icon(Icons.lock_outline,
                        size: 14, color: AppTheme.textMuted(context)),
                    const SizedBox(width: 8),
                    Text(
                      f,
                      style: TextStyle(
                        color: AppTheme.textSecondary(context),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              )),
            ],
          ),
        ),
      ],
    );
  }

  List<String> _featureListForTier(GnsTier tier) {
    switch (tier.id) {
      case 'explorer':
        return ['Claim your @handle', 'GNS identity visible to others'];
      case 'navigator':
        return ['Encrypted messaging', 'Contacts tab', 'Search users by @handle'];
      case 'trailblazer':
        return [
          'Send & receive payments (USDC/XLM/GNS)',
          'DIX — public posting',
          'Profile facets',
          'Create your gSite',
          'Organization registration',
          'Transaction history',
        ];
      default:
        return [];
    }
  }
}
