/// Digest Tab
///
/// Weekly trajectory summaries. Scrollable journal of past weeks.
/// Each digest is shareable as a card to Instagram Stories / X.
///
/// Zero protocol language. "Your week in motion."
///
/// Location: lib/ui/trajectory/digest_tab.dart

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import '../../core/trajectory/trajectory_service.dart';
import 'share_card_painter.dart';
import '../../core/theme/theme_service.dart';

class DigestTab extends StatefulWidget {
  const DigestTab({super.key});

  @override
  State<DigestTab> createState() => _DigestTabState();
}

class _DigestTabState extends State<DigestTab>
    with AutomaticKeepAliveClientMixin {
  final _trajectoryService = TrajectoryService();

  WeeklyDigest? _currentDigest;
  List<WeeklyDigest> _history = [];
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
      final current = await _trajectoryService.getCurrentWeekDigest();
      final history = await _trajectoryService.getDigestHistory(weeks: 12);
      if (mounted) {
        setState(() {
          _currentDigest = current;
          _history = history;
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
          'Digest',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: _buildContent(),
            ),
    );
  }

  Widget _buildContent() {
    if (_currentDigest == null && _history.isEmpty) {
      return _buildEmptyState();
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // ── Current week (hero card) ──
        if (_currentDigest != null) ...[
          Text(
            'THIS WEEK',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.5,
              color: AppTheme.textMuted(context),
            ),
          ),
          const SizedBox(height: 12),
          _buildCurrentWeekCard(_currentDigest!),
          const SizedBox(height: 28),
        ],

        // ── Past digests ──
        if (_history.isNotEmpty) ...[
          Text(
            'PAST WEEKS',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.5,
              color: AppTheme.textMuted(context),
            ),
          ),
          const SizedBox(height: 12),
          ..._history.map(_buildHistoryCard),
        ],

        const SizedBox(height: 40),
      ],
    );
  }

  // ==================== CURRENT WEEK (Hero Card) ====================

  Widget _buildCurrentWeekCard(WeeklyDigest digest) {
    final dateRange = _formatDateRange(digest.weekStart, digest.weekEnd);

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A1A2E).withOpacity(0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date range
            Text(
              dateRange,
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withOpacity(0.5),
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 16),

            // Main stat
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${digest.breadcrumbCount}',
                  style: const TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    height: 1,
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    'breadcrumbs',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white.withOpacity(0.6),
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Sub-stats row
            Row(
              children: [
                _digestStat(
                  '${digest.newCells}',
                  'new cells',
                  const Color(0xFF4FC3F7),
                ),
                const SizedBox(width: 24),
                _digestStat(
                  '${digest.neighborhoodCount}',
                  'neighborhoods',
                  const Color(0xFF66BB6A),
                ),
                const SizedBox(width: 24),
                _digestStat(
                  '${digest.cityCount}',
                  'cities',
                  const Color(0xFFFFB74D),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Streak + tier
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      digest.streakWeeks > 0 ? '🔥' : '💤',
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Week ${digest.streakWeeks} streak',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withOpacity(0.7),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Text(
                      TierInfo.tierEmoji(digest.tier),
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      digest.tier,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withOpacity(0.7),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Share button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _shareDigest(digest),
                icon: const Icon(Icons.ios_share, size: 16, color: Colors.white),
                label: const Text(
                  'SHARE TO STORIES',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                    color: Colors.white,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.white.withOpacity(0.3)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),

            // Branding
            const SizedBox(height: 16),
            Center(
              child: Text(
                'GLOBE CRUMBS',
                style: TextStyle(
                  fontSize: 9,
                  color: Colors.white.withOpacity(0.25),
                  letterSpacing: 3,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _digestStat(String value, String label, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.white.withOpacity(0.4),
          ),
        ),
      ],
    );
  }

  // ==================== HISTORY CARDS ====================

  Widget _buildHistoryCard(WeeklyDigest digest) {
    final dateRange = _formatDateRange(digest.weekStart, digest.weekEnd);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border(context)),
      ),
      child: Row(
        children: [
          // Week stat
          SizedBox(
            width: 56,
            child: Column(
              children: [
                Text(
                  '${digest.breadcrumbCount}',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary(context),
                  ),
                ),
                Text(
                  'crumbs',
                  style: TextStyle(
                    fontSize: 10,
                    color: AppTheme.textMuted(context),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),

          // Date + details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dateRange,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${digest.newCells} cells · ${digest.neighborhoodCount} neighborhoods · ${digest.cityCount} cities',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textMuted(context),
                  ),
                ),
              ],
            ),
          ),

          // Share icon
          IconButton(
            icon: Icon(
              Icons.ios_share,
              size: 18,
              color: AppTheme.textMuted(context),
            ),
            onPressed: () => _shareDigest(digest),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  // ==================== EMPTY STATE ====================

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🗺️', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 16),
            Text(
              'No trajectory yet',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary(context),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Drop your first breadcrumb to start building\nyour weekly digest.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: AppTheme.textMuted(context),
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== SHARE ====================

  Future<void> _shareDigest(WeeklyDigest digest) async {
    final dateRange = _formatDateRange(digest.weekStart, digest.weekEnd);
    final text = '${TierInfo.tierEmoji(digest.tier)} '
        '$dateRange — '
        '${digest.breadcrumbCount} breadcrumbs across '
        '${digest.neighborhoodCount} neighborhoods. '
        '${digest.streakWeeks > 0 ? "🔥 Week ${digest.streakWeeks} streak. " : ""}'
        '#TrajectoryMap #GlobeCrumbs';

    await TrajectoryShareService.shareCard(
        context: context,
        data: ShareCardData(
          publicKey: '0042d1dccf036d10f7699892ea3fe621cd7c76218ad89fddab51adad2c90b758',
          handle: 'camiloayerbe',
          breadcrumbs: digest.breadcrumbCount,
          neighborhoods: digest.neighborhoodCount,
          cities: digest.cityCount,
          streakWeeks: digest.streakWeeks,
          tier: digest.tier,
        ),
      );
  }

  // ==================== HELPERS ====================

  String _formatDateRange(DateTime start, DateTime end) {
    final df = DateFormat('MMM d');
    if (start.year == end.year && start.month == end.month) {
      return '${df.format(start)}–${end.day}';
    }
    return '${df.format(start)} – ${df.format(end)}';
  }
}
