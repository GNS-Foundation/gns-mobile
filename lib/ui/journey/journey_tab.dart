/// Journey Tab — Gamified Progression
///
/// Shows tier progress ring, drop breadcrumb button, milestone timeline,
/// stats, and preview of features that unlock next.
///
/// This is the gamification layer that makes breadcrumb collection
/// feel like a game rather than a chore.
///
/// Location: lib/ui/journey/journey_tab.dart

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/gns/identity_wallet.dart';
import '../../core/chain/breadcrumb_engine.dart';
import '../../core/tier_gate.dart';
import '../../core/theme/theme_service.dart';

class JourneyTab extends StatefulWidget {
  final IdentityWallet wallet;

  const JourneyTab({super.key, required this.wallet});

  @override
  State<JourneyTab> createState() => _JourneyTabState();
}

class _JourneyTabState extends State<JourneyTab> with TickerProviderStateMixin {
  final _tierGate = TierGate();
  BreadcrumbStats? _stats;
  bool _isCollecting = false;
  bool _isDropping = false;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _tierGate.addListener(_onTierChanged);
    _loadStats();
    
    widget.wallet.breadcrumbEngine.onBreadcrumbDropped = (_) async {
      await Future.delayed(const Duration(milliseconds: 100));
      _loadStats();
    };
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _tierGate.removeListener(_onTierChanged);
    super.dispose();
  }

  void _onTierChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadStats() async {
    final stats = await widget.wallet.breadcrumbEngine.getStats();
    _isCollecting = widget.wallet.breadcrumbEngine.isCollecting;
    if (mounted) {
      setState(() => _stats = stats);
      _tierGate.updateCount(stats.breadcrumbCount);
    }
  }

  Future<void> _toggleCollection() async {
    HapticFeedback.mediumImpact();
    if (_isCollecting) {
      widget.wallet.breadcrumbEngine.stopCollection();
    } else {
      await widget.wallet.breadcrumbEngine.startCollection();
    }
    setState(() => _isCollecting = widget.wallet.breadcrumbEngine.isCollecting);
  }

  Future<void> _dropBreadcrumb() async {
    if (_isDropping) return;
    setState(() => _isDropping = true);
    HapticFeedback.heavyImpact();
    
    try {
      await widget.wallet.breadcrumbEngine.dropBreadcrumb(manual: true);
      await _loadStats();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not drop breadcrumb: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isDropping = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tier = _tierGate.currentTier;
    final tierColor = Color(tier.colorValue);
    
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0D1117) : const Color(0xFFF6F8FA),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadStats,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            children: [
              // ==================== TIER BADGE ====================
              _buildTierBadge(tier, tierColor, isDark),
              const SizedBox(height: 24),
              
              // ==================== PROGRESS RING ====================
              _buildProgressRing(tierColor, isDark),
              const SizedBox(height: 24),
              
              // ==================== DROP BUTTON ====================
              _buildDropButton(tierColor, isDark),
              const SizedBox(height: 24),
              
              // ==================== STATS GRID ====================
              _buildStatsGrid(isDark),
              const SizedBox(height: 24),
              
              // ==================== MILESTONE TIMELINE ====================
              _buildMilestoneTimeline(tierColor, isDark),
              const SizedBox(height: 24),
              
              // ==================== NEXT UNLOCK ====================
              if (_tierGate.nextTier != null)
                _buildNextUnlock(isDark),
              
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  // ==================== TIER BADGE ====================

  Widget _buildTierBadge(FeatureTier tier, Color tierColor, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [tierColor.withOpacity(0.15), tierColor.withOpacity(0.05)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tierColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Text(tier.icon, style: const TextStyle(fontSize: 28)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tier.displayName.toUpperCase(),
                  style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w800,
                    letterSpacing: 1.5, color: tierColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  tier.description,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==================== PROGRESS RING ====================

  Widget _buildProgressRing(Color tierColor, bool isDark) {
    final progress = _tierGate.progressToNextTier;
    final count = _stats?.breadcrumbCount ?? 0;
    final next = _tierGate.nextTier;
    
    return Center(
      child: SizedBox(
        width: 200,
        height: 200,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Background ring
            SizedBox(
              width: 200, height: 200,
              child: CircularProgressIndicator(
                value: 1.0,
                strokeWidth: 10,
                color: isDark ? Colors.white10 : Colors.black.withOpacity(0.06),
              ),
            ),
            // Progress ring
            SizedBox(
              width: 200, height: 200,
              child: CircularProgressIndicator(
                value: progress,
                strokeWidth: 10,
                color: tierColor,
                backgroundColor: Colors.transparent,
                strokeCap: StrokeCap.round,
              ),
            ),
            // Center content
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 48, fontWeight: FontWeight.w900,
                    color: tierColor,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'breadcrumbs',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                ),
                if (next != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: tierColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_tierGate.breadcrumbsUntil(next)} to ${next.displayName}',
                      style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w600,
                        color: tierColor,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ==================== DROP BUTTON ====================

  Widget _buildDropButton(Color tierColor, bool isDark) {
    return Column(
      children: [
        // Main drop button
        AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            final scale = _isCollecting
                ? 1.0 + (_pulseController.value * 0.05)
                : 1.0;
            return Transform.scale(
              scale: scale,
              child: child,
            );
          },
          child: SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              onPressed: _isDropping ? null : _dropBreadcrumb,
              icon: _isDropping
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.pin_drop, size: 22),
              label: Text(
                _isDropping ? 'Dropping...' : 'Drop Breadcrumb',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: tierColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 3,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        
        // Auto-collection toggle
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF161B22) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border(context)),
          ),
          child: Row(
            children: [
              Icon(
                _isCollecting ? Icons.gps_fixed : Icons.gps_not_fixed,
                size: 18,
                color: _isCollecting ? tierColor : Colors.grey,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Auto-Collection',
                      style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    Text(
                      _isCollecting ? 'Collecting in background' : 'Tap to start',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: _isCollecting,
                onChanged: (_) => _toggleCollection(),
                activeColor: tierColor,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ==================== STATS GRID ====================

  Widget _buildStatsGrid(bool isDark) {
    final stats = _stats;
    return Row(
      children: [
        _buildStatCard(
          'Trust Score',
          '${stats?.trustScore.toStringAsFixed(0) ?? '0'}%',
          Icons.shield_outlined,
          isDark,
        ),
        const SizedBox(width: 12),
        _buildStatCard(
          'Unique Cells',
          '${stats?.uniqueLocations ?? 0}',
          Icons.grid_on,
          isDark,
        ),
        const SizedBox(width: 12),
        _buildStatCard(
          'Days Active',
          '${stats?.daysSinceStart ?? 0}',
          Icons.calendar_today_outlined,
          isDark,
        ),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, bool isDark) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF161B22) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border(context)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: isDark ? Colors.white38 : Colors.black38),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ==================== MILESTONE TIMELINE ====================

  Widget _buildMilestoneTimeline(Color tierColor, bool isDark) {
    final milestones = TierGate.milestones;
    final achieved = _tierGate.achievedMilestones;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161B22) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'MILESTONES',
                style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: isDark ? Colors.white54 : Colors.black45,
                ),
              ),
              const Spacer(),
              Text(
                '${achieved.length}/${milestones.length}',
                style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600,
                  color: tierColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          ...milestones.map((m) {
            final isAchieved = _tierGate.breadcrumbCount >= m.threshold;
            final isNext = !isAchieved && (milestones.indexOf(m) == 0 ||
                _tierGate.breadcrumbCount >= milestones[milestones.indexOf(m) - 1].threshold);
            
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  // Icon
                  Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isAchieved
                          ? tierColor.withOpacity(0.15)
                          : (isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.04)),
                      border: isNext
                          ? Border.all(color: tierColor, width: 2)
                          : null,
                    ),
                    child: Center(
                      child: Text(
                        isAchieved ? m.icon : '🔒',
                        style: TextStyle(fontSize: isAchieved ? 14 : 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  
                  // Content
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          m.title,
                          style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600,
                            color: isAchieved
                                ? (isDark ? Colors.white : Colors.black87)
                                : (isDark ? Colors.white30 : Colors.black26),
                          ),
                        ),
                        Text(
                          isAchieved ? m.description : '${m.threshold} breadcrumbs',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.white30 : Colors.black26,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // Checkmark
                  if (isAchieved)
                    Icon(Icons.check_circle, size: 18, color: tierColor),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ==================== NEXT UNLOCK PREVIEW ====================

  Widget _buildNextUnlock(bool isDark) {
    final next = _tierGate.nextTier!;
    final features = _tierGate.nextTierFeatures;
    final remaining = _tierGate.breadcrumbsUntil(next);
    final nextColor = Color(next.colorValue);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161B22) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: nextColor.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(next.icon, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Text(
                'NEXT: ${next.displayName.toUpperCase()}',
                style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700,
                  letterSpacing: 1, color: nextColor,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: nextColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$remaining to go',
                  style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600,
                    color: nextColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          ...features.take(4).map((f) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Icon(Icons.lock_open, size: 14, color: nextColor.withOpacity(0.6)),
                const SizedBox(width: 8),
                Text(
                  f.displayName,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
                const Spacer(),
                Text(
                  f.teaser.length > 30 ? '${f.teaser.substring(0, 27)}...' : f.teaser,
                  style: TextStyle(
                    fontSize: 10,
                    color: isDark ? Colors.white30 : Colors.black26,
                  ),
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }
}
