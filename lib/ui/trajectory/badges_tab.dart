/// Badges Tab
///
/// 4-tier trajectory progression (Seedling → Trailblazer) with
/// achievement badges and shareable badge cards.
///
/// Zero protocol language. Pure gamification surface.
///
/// Location: lib/ui/trajectory/badges_tab.dart

import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../../core/trajectory/trajectory_service.dart';
import 'share_card_painter.dart';
import '../../core/theme/theme_service.dart';

class BadgesTab extends StatefulWidget {
  const BadgesTab({super.key});

  @override
  State<BadgesTab> createState() => _BadgesTabState();
}

class _BadgesTabState extends State<BadgesTab>
    with AutomaticKeepAliveClientMixin {
  final _trajectoryService = TrajectoryService();
  final _badgeCardKey = GlobalKey();

  TrajectoryStats _stats = TrajectoryStats.empty();
  List<Achievement> _achievements = [];
  bool _isLoading = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final stats = await _trajectoryService.getStats();
      final achievements = await _trajectoryService.getAchievements();
      if (mounted) {
        setState(() {
          _stats = stats;
          _achievements = achievements;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Badges',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share, size: 22),
            onPressed: _shareBadgeCard,
            tooltip: 'Share badge',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  // ── Tier progression ──
                  _buildTierSection(),
                  const SizedBox(height: 28),

                  // ── Achievements ──
                  _buildAchievementsSection(),
                  const SizedBox(height: 28),

                  // ── Shareable badge card (hidden, for screenshot) ──
                  _buildShareButton(),
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  // ==================== TIER PROGRESSION ====================

  Widget _buildTierSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'TRAJECTORY TIERS',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.5,
            color: AppTheme.textMuted(context),
          ),
        ),
        const SizedBox(height: 16),
        ...TierInfo.tiers.map((tier) {
          final tierName = tier['name'] as String;
          final tierMin = tier['min'] as int;
          final tierMax = tier['max'] as int;
          final isCurrent = _stats.currentTier == tierName;
          final isUnlocked = _stats.totalBreadcrumbs >= tierMin;
          final isMaxTier = tierMax == -1;

          double progress;
          if (!isUnlocked) {
            progress = 0.0;
          } else if (isCurrent && !isMaxTier) {
            progress = (_stats.totalBreadcrumbs - tierMin) /
                (tierMax - tierMin + 1);
          } else if (isUnlocked) {
            progress = 1.0;
          } else {
            progress = 0.0;
          }
          progress = progress.clamp(0.0, 1.0);

          return _buildTierRow(
            name: tierName,
            emoji: TierInfo.tierEmoji(tierName),
            progress: progress,
            isCurrent: isCurrent,
            isUnlocked: isUnlocked,
            breadcrumbRange: isMaxTier
                ? '${_formatNum(tierMin)}+'
                : '${_formatNum(tierMin)}–${_formatNum(tierMax)}',
          );
        }),
      ],
    );
  }

  Widget _buildTierRow({
    required String name,
    required String emoji,
    required double progress,
    required bool isCurrent,
    required bool isUnlocked,
    required String breadcrumbRange,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isCurrent
            ? AppTheme.primary.withOpacity(0.06)
            : isUnlocked
                ? AppTheme.surface(context)
                : AppTheme.surfaceLight(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isCurrent
              ? AppTheme.primary.withOpacity(0.3)
              : AppTheme.border(context),
          width: isCurrent ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          // Emoji/icon
          Text(
            isUnlocked ? emoji : '🔒',
            style: TextStyle(
              fontSize: 28,
              color: isUnlocked ? null : Colors.grey,
            ),
          ),
          const SizedBox(width: 14),

          // Name + progress
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                        color: isUnlocked
                            ? AppTheme.textPrimary(context)
                            : AppTheme.textMuted(context),
                      ),
                    ),
                    if (isCurrent) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.primary,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'CURRENT',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  breadcrumbRange,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textMuted(context),
                  ),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 5,
                    backgroundColor: AppTheme.border(context),
                    valueColor: AlwaysStoppedAnimation(
                      isUnlocked
                          ? (isCurrent ? AppTheme.primary : const Color(0xFF66BB6A))
                          : AppTheme.textMuted(context).withOpacity(0.3),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Progress percentage
          const SizedBox(width: 12),
          Text(
            '${(progress * 100).toInt()}%',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isUnlocked
                  ? AppTheme.textPrimary(context)
                  : AppTheme.textMuted(context),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== ACHIEVEMENTS ====================

  Widget _buildAchievementsSection() {
    final unlocked = _achievements.where((a) => a.unlocked).toList();
    final locked = _achievements.where((a) => !a.unlocked).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ACHIEVEMENTS',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.5,
            color: AppTheme.textMuted(context),
          ),
        ),
        const SizedBox(height: 16),

        if (unlocked.isNotEmpty) ...[
          ...unlocked.map(_buildAchievementCard),
        ],
        if (locked.isNotEmpty) ...[
          if (unlocked.isNotEmpty) const SizedBox(height: 8),
          ...locked.map(_buildAchievementCard),
        ],
      ],
    );
  }

  Widget _buildAchievementCard(Achievement achievement) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: achievement.unlocked
            ? const Color(0xFFFFB74D).withOpacity(0.08)
            : AppTheme.surfaceLight(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: achievement.unlocked
              ? const Color(0xFFFFB74D).withOpacity(0.3)
              : AppTheme.border(context),
        ),
      ),
      child: Row(
        children: [
          // Icon
          Text(
            achievement.unlocked ? achievement.icon : '❓',
            style: const TextStyle(fontSize: 28),
          ),
          const SizedBox(width: 12),

          // Name + description
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  achievement.name,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: achievement.unlocked
                        ? AppTheme.textPrimary(context)
                        : AppTheme.textMuted(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  achievement.description,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textMuted(context),
                  ),
                ),
                if (!achievement.unlocked) ...[
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: achievement.progress,
                      minHeight: 3,
                      backgroundColor: AppTheme.border(context),
                      valueColor: const AlwaysStoppedAnimation(Color(0xFFFFB74D)),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Progress value
          const SizedBox(width: 8),
          if (achievement.unlocked)
            const Icon(Icons.check_circle, color: Color(0xFFFFB74D), size: 24)
          else
            Text(
              achievement.value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textMuted(context),
              ),
            ),
        ],
      ),
    );
  }

  // ==================== SHARE ====================

  Widget _buildShareButton() {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton.icon(
        onPressed: _shareBadgeCard,
        icon: const Icon(Icons.ios_share, size: 18),
        label: const Text(
          'SHARE BADGE CARD',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            letterSpacing: 1,
            fontSize: 14,
          ),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.primary,
          side: const BorderSide(color: AppTheme.primary),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

  Future<void> _shareBadgeCard() async {
    try {
      await TrajectoryShareService.shareCard(
        context: context,
        data: ShareCardData(
          publicKey: '0042d1dccf036d10f7699892ea3fe621cd7c76218ad89fddab51adad2c90b758',
          handle: 'camiloayerbe',
          breadcrumbs: _stats.totalBreadcrumbs,
          neighborhoods: _stats.uniqueNeighborhoods,
          cities: _stats.uniqueCities,
          streakWeeks: _stats.weeklyStreak,
          tier: _stats.currentTier,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Share error: $e')),
        );
      }
    }
  }

  /// Badge card layout for image rendering (future: RepaintBoundary capture)
  Widget _buildShareableCard() {
    return RepaintBoundary(
      key: _badgeCardKey,
      child: Container(
        width: 360,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              TierInfo.tierEmoji(_stats.currentTier),
              style: const TextStyle(fontSize: 48),
            ),
            const SizedBox(height: 12),
            Text(
              _stats.currentTier.toUpperCase(),
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: 3,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _shareStatItem('${_stats.totalBreadcrumbs}', 'crumbs'),
                _shareStatItem('${_stats.uniqueNeighborhoods}', 'hoods'),
                _shareStatItem('${_stats.uniqueCities}', 'cities'),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              '🔥 Week ${_stats.weeklyStreak} streak',
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFFFFB74D),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'GLOBE CRUMBS',
              style: TextStyle(
                fontSize: 10,
                color: Colors.white.withOpacity(0.4),
                letterSpacing: 3,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _shareStatItem(String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.white.withOpacity(0.5),
          ),
        ),
      ],
    );
  }

  String _formatNum(int n) {
    if (n >= 10000) return '${(n / 1000).toStringAsFixed(0)}k';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return n.toString();
  }
}
