/// GNS Loyalty & Rewards Screen - Sprint 6
/// 
/// UI for viewing points balance, redeeming rewards, and achievements.
/// 
/// Location: lib/ui/financial/loyalty_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/gns/identity_wallet.dart';
import '../../core/financial/loyalty_service.dart';
import '../../core/theme/theme_service.dart';

class LoyaltyScreen extends StatefulWidget {
  final IdentityWallet wallet;
  
  const LoyaltyScreen({super.key, required this.wallet});
  
  @override
  State<LoyaltyScreen> createState() => _LoyaltyScreenState();
}

class _LoyaltyScreenState extends State<LoyaltyScreen>
    with SingleTickerProviderStateMixin {
  final _loyaltyService = LoyaltyService();
  
  LoyaltyProfile? _profile;
  List<Reward> _rewards = [];
  List<Achievement> _achievements = [];
  List<PointTransaction> _history = [];
  
  bool _loading = true;
  String? _error;
  
  late TabController _tabController;
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _initialize();
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
  
  Future<void> _initialize() async {
    try {
      await _loyaltyService.initialize(widget.wallet);
      await _loadData();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }
  
  Future<void> _loadData() async {
    setState(() => _loading = true);
    
    try {
      final results = await Future.wait([
        _loyaltyService.getProfile(forceRefresh: true),
        _loyaltyService.getAvailableRewards(),
        _loyaltyService.getAchievements(),
        _loyaltyService.getPointsHistory(limit: 20),
      ]);
      
      setState(() {
        _profile = results[0] as LoyaltyProfile?;
        _rewards = results[1] as List<Reward>;
        _achievements = results[2] as List<Achievement>;
        _history = results[3] as List<PointTransaction>;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }
  
  Future<void> _redeemReward(Reward reward) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface(ctx),
        title: const Text('Redeem Reward'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Redeem "${reward.name}" for ${reward.pointsCost} points?'),
            const SizedBox(height: 12),
            Text(
              reward.description,
              style: TextStyle(
                color: AppTheme.textSecondary(ctx),
                fontSize: 14,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Redeem'),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;
    
    HapticFeedback.mediumImpact();
    
    final result = await _loyaltyService.redeemReward(reward.rewardId);
    
    if (result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🎁 Redeemed: ${reward.name}'),
          backgroundColor: AppTheme.secondary,
        ),
      );
      await _loadData();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.error ?? 'Failed to redeem'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }
  
  void _showReferralCode() async {
    final code = await _loyaltyService.getReferralCode();
    
    if (!mounted || code == null) return;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '🤝 Share & Earn',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Both you and your friend get 100 points!',
              style: TextStyle(color: AppTheme.textSecondary(ctx)),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.background(ctx),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    code,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(width: 16),
                  IconButton(
                    icon: const Icon(Icons.copy),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: code));
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('Code copied!')),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  // TODO: Share functionality
                  Navigator.pop(ctx);
                },
                icon: const Icon(Icons.share),
                label: const Text('Share Code'),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background(context),
      appBar: AppBar(
        backgroundColor: AppTheme.surface(context),
        title: const Text('Rewards'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: _showReferralCode,
            tooltip: 'Share & Earn',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Rewards'),
            Tab(text: 'Achievements'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildOverviewTab(),
                    _buildRewardsTab(),
                    _buildAchievementsTab(),
                  ],
                ),
    );
  }
  
  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: AppTheme.error),
          const SizedBox(height: 16),
          Text(_error!, style: TextStyle(color: AppTheme.textSecondary(context))),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadData,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
  
  Widget _buildOverviewTab() {
    if (_profile == null) return const SizedBox.shrink();
    
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Points Card
          _buildPointsCard(),
          
          const SizedBox(height: 16),
          
          // Tier Card
          _buildTierCard(),
          
          const SizedBox(height: 24),
          
          // Recent Activity
          _buildRecentActivity(),
        ],
      ),
    );
  }
  
  Widget _buildPointsCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.primary, AppTheme.primary.withOpacity(0.7)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Available Points',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_profile!.tier.emoji} ${_profile!.tier.displayName}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${_profile!.availablePoints}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 48,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildPointStat('Lifetime', '${_profile!.lifetimePoints}'),
              const SizedBox(width: 24),
              _buildPointStat('Transactions', '${_profile!.totalTransactions}'),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildPointStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white60, fontSize: 12),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
  
  Widget _buildTierCard() {
    final nextTier = _profile!.nextTier;
    final progress = _profile!.tierProgressPercent / 100;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Tier Progress',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary(context),
                ),
              ),
              if (nextTier != null)
                Text(
                  '${_profile!.pointsToNextTier} pts to ${nextTier.displayName}',
                  style: TextStyle(
                    color: AppTheme.textSecondary(context),
                    fontSize: 12,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: AppTheme.divider(context),
              valueColor: AlwaysStoppedAnimation(AppTheme.primary),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _profile!.tier.displayName,
                style: TextStyle(color: AppTheme.textSecondary(context)),
              ),
              if (nextTier != null)
                Text(
                  nextTier.displayName,
                  style: TextStyle(color: AppTheme.textSecondary(context)),
                ),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildRecentActivity() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recent Activity',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary(context),
          ),
        ),
        const SizedBox(height: 12),
        if (_history.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'No activity yet',
                style: TextStyle(color: AppTheme.textMuted(context)),
              ),
            ),
          )
        else
          ...List.generate(
            _history.length.clamp(0, 5),
            (i) => _buildActivityItem(_history[i]),
          ),
      ],
    );
  }
  
  Widget _buildActivityItem(PointTransaction tx) {
    final isPositive = tx.isCredit;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: (isPositive ? AppTheme.secondary : AppTheme.error)
                  .withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isPositive ? Icons.add : Icons.remove,
              color: isPositive ? AppTheme.secondary : AppTheme.error,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tx.description,
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textPrimary(context),
                  ),
                ),
                Text(
                  _formatDate(tx.timestamp),
                  style: TextStyle(
                    color: AppTheme.textMuted(context),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${isPositive ? '+' : ''}${tx.points}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isPositive ? AppTheme.secondary : AppTheme.error,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildRewardsTab() {
    if (_rewards.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🎁', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 16),
            Text(
              'No rewards available',
              style: TextStyle(color: AppTheme.textSecondary(context)),
            ),
          ],
        ),
      );
    }
    
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _rewards.length,
        itemBuilder: (ctx, i) => _buildRewardCard(_rewards[i]),
      ),
    );
  }
  
  Widget _buildRewardCard(Reward reward) {
    final canAfford = (_profile?.availablePoints ?? 0) >= reward.pointsCost;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: canAfford && reward.isAvailable
              ? () => _redeemReward(reward)
              : null,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Icon
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      reward.type == RewardType.discount ? '💸' :
                      reward.type == RewardType.cashback ? '💰' :
                      reward.type == RewardType.gnsTokens ? '🌐' : '🎁',
                      style: const TextStyle(fontSize: 24),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        reward.name,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary(context),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        reward.description,
                        style: TextStyle(
                          color: AppTheme.textSecondary(context),
                          fontSize: 12,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Points
                Column(
                  children: [
                    Text(
                      '${reward.pointsCost}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: canAfford ? AppTheme.primary : AppTheme.textMuted(context),
                      ),
                    ),
                    Text(
                      'pts',
                      style: TextStyle(
                        color: AppTheme.textMuted(context),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildAchievementsTab() {
    final unlocked = _achievements.where((a) => a.isUnlocked).toList();
    final locked = _achievements.where((a) => !a.isUnlocked).toList();
    
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (unlocked.isNotEmpty) ...[
            Text(
              'Unlocked (${unlocked.length})',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary(context),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: unlocked.map(_buildAchievementBadge).toList(),
            ),
            const SizedBox(height: 24),
          ],
          if (locked.isNotEmpty) ...[
            Text(
              'Locked (${locked.length})',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary(context),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: locked.map(_buildAchievementBadge).toList(),
            ),
          ],
          if (_achievements.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(48),
                child: Column(
                  children: [
                    const Text('🏆', style: TextStyle(fontSize: 48)),
                    const SizedBox(height: 16),
                    Text(
                      'Start making payments to unlock achievements!',
                      style: TextStyle(color: AppTheme.textSecondary(context)),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
  
  Widget _buildAchievementBadge(Achievement achievement) {
    return GestureDetector(
      onTap: () => _showAchievementDetails(achievement),
      child: Container(
        width: 100,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.surface(context),
          borderRadius: BorderRadius.circular(12),
          border: achievement.isUnlocked
              ? Border.all(color: AppTheme.secondary, width: 2)
              : null,
        ),
        child: Column(
          children: [
            Text(
              achievement.iconUrl.isNotEmpty ? achievement.iconUrl : '🏆',
              style: TextStyle(
                fontSize: 32,
                color: achievement.isUnlocked ? null : Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              achievement.name,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: achievement.isUnlocked
                    ? AppTheme.textPrimary(context)
                    : AppTheme.textMuted(context),
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (!achievement.isUnlocked && achievement.target != null) ...[
              const SizedBox(height: 4),
              LinearProgressIndicator(
                value: achievement.progressPercent / 100,
                minHeight: 4,
                backgroundColor: AppTheme.divider(context),
              ),
            ],
          ],
        ),
      ),
    );
  }
  
  void _showAchievementDetails(Achievement achievement) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface(ctx),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              achievement.iconUrl.isNotEmpty ? achievement.iconUrl : '🏆',
              style: const TextStyle(fontSize: 48),
            ),
            const SizedBox(height: 16),
            Text(
              achievement.name,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              achievement.description,
              style: TextStyle(color: AppTheme.textSecondary(ctx)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            if (achievement.isUnlocked)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.secondary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '✓ Unlocked',
                  style: TextStyle(
                    color: AppTheme.secondary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            else if (achievement.target != null)
              Text(
                '${achievement.progress?.toInt() ?? 0} / ${achievement.target?.toInt()}',
                style: TextStyle(color: AppTheme.textMuted(ctx)),
              ),
            if (achievement.pointsAwarded > 0) ...[
              const SizedBox(height: 8),
              Text(
                '+${achievement.pointsAwarded} points',
                style: TextStyle(
                  color: AppTheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
  
  String _formatDate(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${date.day}/${date.month}/${date.year}';
  }
}
