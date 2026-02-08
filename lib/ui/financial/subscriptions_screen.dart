/// GNS Subscriptions Screen - Sprint 7
/// 
/// Manage recurring payments and subscriptions.
/// 
/// Location: lib/ui/financial/subscriptions_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/gns/identity_wallet.dart';
import '../../core/financial/subscription_service.dart';
import '../../core/theme/theme_service.dart';

class SubscriptionsScreen extends StatefulWidget {
  final IdentityWallet wallet;
  
  const SubscriptionsScreen({super.key, required this.wallet});
  
  @override
  State<SubscriptionsScreen> createState() => _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends State<SubscriptionsScreen>
    with SingleTickerProviderStateMixin {
  final _subscriptionService = SubscriptionService();
  
  List<Subscription> _activeSubscriptions = [];
  List<Subscription> _inactiveSubscriptions = [];
  List<Subscription> _upcomingRenewals = [];
  
  bool _loading = true;
  
  late TabController _tabController;
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initialize();
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
  
  Future<void> _initialize() async {
    await _subscriptionService.initialize(widget.wallet.publicKey!);
    await _loadData();
  }
  
  Future<void> _loadData() async {
    setState(() => _loading = true);
    
    try {
      final results = await Future.wait([
        _subscriptionService.getSubscriptions(status: SubscriptionStatus.active),
        _subscriptionService.getSubscriptions(),
        _subscriptionService.getUpcomingRenewals(days: 7),
      ]);
      
      final allSubs = results[1] as List<Subscription>;
      
      setState(() {
        _activeSubscriptions = results[0] as List<Subscription>;
        _inactiveSubscriptions = allSubs
            .where((s) => s.status != SubscriptionStatus.active && 
                         s.status != SubscriptionStatus.trialing)
            .toList();
        _upcomingRenewals = results[2] as List<Subscription>;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background(context),
      appBar: AppBar(
        backgroundColor: AppTheme.surface(context),
        title: const Text('Subscriptions'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'Active (${_activeSubscriptions.length})'),
            Tab(text: 'Past (${_inactiveSubscriptions.length})'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Upcoming renewals banner
                if (_upcomingRenewals.isNotEmpty)
                  _buildUpcomingBanner(),
                
                // Tabs
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildActiveTab(),
                      _buildPastTab(),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
  
  Widget _buildUpcomingBanner() {
    final total = _upcomingRenewals.fold<double>(
      0,
      (sum, s) => sum + s.amount,
    );
    
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.warning.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.warning.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.warning.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.calendar_today,
              color: AppTheme.warning,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_upcomingRenewals.length} renewal(s) this week',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary(context),
                  ),
                ),
                Text(
                  'Total: \$${total.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: AppTheme.textSecondary(context),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildActiveTab() {
    if (_activeSubscriptions.isEmpty) {
      return _buildEmptyState(
        emoji: '🔄',
        title: 'No active subscriptions',
        subtitle: 'Your recurring payments will appear here',
      );
    }
    
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _activeSubscriptions.length,
        itemBuilder: (ctx, i) => _buildSubscriptionCard(_activeSubscriptions[i]),
      ),
    );
  }
  
  Widget _buildPastTab() {
    if (_inactiveSubscriptions.isEmpty) {
      return _buildEmptyState(
        emoji: '📋',
        title: 'No past subscriptions',
        subtitle: 'Cancelled and expired subscriptions will appear here',
      );
    }
    
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _inactiveSubscriptions.length,
        itemBuilder: (ctx, i) => _buildSubscriptionCard(_inactiveSubscriptions[i]),
      ),
    );
  }
  
  Widget _buildEmptyState({
    required String emoji,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 48)),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(color: AppTheme.textSecondary(context)),
          ),
        ],
      ),
    );
  }
  
  Widget _buildSubscriptionCard(Subscription subscription) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showSubscriptionDetails(subscription),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Center(
                        child: Text('🔄', style: TextStyle(fontSize: 24)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            subscription.planName,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary(context),
                            ),
                          ),
                          Text(
                            subscription.merchantName,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    _buildStatusBadge(subscription.status),
                  ],
                ),
                
                const SizedBox(height: 16),
                
                // Price and billing
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          subscription.formattedAmount,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary(context),
                          ),
                        ),
                        Text(
                          subscription.billingCycle.displayName,
                          style: TextStyle(
                            color: AppTheme.textMuted(context),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    if (subscription.isActive && subscription.nextBillingDate != null)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'Next billing',
                            style: TextStyle(
                              color: AppTheme.textMuted(context),
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            _formatDate(subscription.nextBillingDate!),
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              color: AppTheme.textSecondary(context),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                
                // Period progress for active subscriptions
                if (subscription.isActive) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: subscription.periodProgress,
                      minHeight: 4,
                      backgroundColor: AppTheme.divider(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${subscription.daysUntilRenewal} days until renewal',
                    style: TextStyle(
                      color: AppTheme.textMuted(context),
                      fontSize: 10,
                    ),
                  ),
                ],
                
                // Past due warning
                if (subscription.isPastDue) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.error.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning, color: AppTheme.error, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Payment failed. Update your payment method.',
                            style: TextStyle(
                              color: AppTheme.error,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildStatusBadge(SubscriptionStatus status) {
    Color color;
    String text;
    
    switch (status) {
      case SubscriptionStatus.active:
        color = AppTheme.secondary;
        text = 'Active';
        break;
      case SubscriptionStatus.trialing:
        color = AppTheme.primary;
        text = 'Trial';
        break;
      case SubscriptionStatus.paused:
        color = AppTheme.warning;
        text = 'Paused';
        break;
      case SubscriptionStatus.pastDue:
        color = AppTheme.error;
        text = 'Past Due';
        break;
      case SubscriptionStatus.cancelled:
        color = Colors.grey;
        text = 'Cancelled';
        break;
      case SubscriptionStatus.expired:
        color = Colors.grey;
        text = 'Expired';
        break;
      case SubscriptionStatus.pendingActivation:
        color = AppTheme.warning;
        text = 'Pending';
        break;
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
  
  void _showSubscriptionDetails(Subscription subscription) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _SubscriptionDetailsSheet(
        subscription: subscription,
        onCancel: () async {
          Navigator.pop(ctx);
          await _cancelSubscription(subscription);
        },
        onPause: () async {
          Navigator.pop(ctx);
          await _pauseSubscription(subscription);
        },
        onResume: () async {
          Navigator.pop(ctx);
          await _resumeSubscription(subscription);
        },
      ),
    );
  }
  
  Future<void> _cancelSubscription(Subscription subscription) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface(ctx),
        title: const Text('Cancel Subscription?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Are you sure you want to cancel "${subscription.planName}"?'),
            const SizedBox(height: 12),
            Text(
              'Your subscription will remain active until ${_formatDate(subscription.currentPeriodEnd)}.',
              style: TextStyle(
                color: AppTheme.textSecondary(ctx),
                fontSize: 12,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;
    
    HapticFeedback.mediumImpact();
    
    final result = await _subscriptionService.cancel(subscription.subscriptionId);
    
    if (result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Subscription cancelled'),
          backgroundColor: AppTheme.secondary,
        ),
      );
      await _loadData();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.error ?? 'Failed to cancel'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }
  
  Future<void> _pauseSubscription(Subscription subscription) async {
    final result = await _subscriptionService.pause(subscription.subscriptionId);
    
    if (result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Subscription paused')),
      );
      await _loadData();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.error ?? 'Failed to pause'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }
  
  Future<void> _resumeSubscription(Subscription subscription) async {
    final result = await _subscriptionService.resume(subscription.subscriptionId);
    
    if (result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Subscription resumed'),
          backgroundColor: AppTheme.secondary,
        ),
      );
      await _loadData();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.error ?? 'Failed to resume'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }
  
  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}

// Subscription details sheet
class _SubscriptionDetailsSheet extends StatelessWidget {
  final Subscription subscription;
  final VoidCallback onCancel;
  final VoidCallback onPause;
  final VoidCallback onResume;
  
  const _SubscriptionDetailsSheet({
    required this.subscription,
    required this.onCancel,
    required this.onPause,
    required this.onResume,
  });
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.divider(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 24),
          
          // Header
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Text('🔄', style: TextStyle(fontSize: 28)),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      subscription.planName,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      subscription.merchantName,
                      style: TextStyle(
                        color: AppTheme.textSecondary(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 24),
          
          // Details
          _DetailRow(
            label: 'Price',
            value: subscription.formattedAmount,
          ),
          _DetailRow(
            label: 'Status',
            value: '${subscription.status.emoji} ${subscription.status.displayName}',
          ),
          _DetailRow(
            label: 'Started',
            value: _formatDate(subscription.startDate),
          ),
          if (subscription.nextBillingDate != null)
            _DetailRow(
              label: 'Next billing',
              value: _formatDate(subscription.nextBillingDate!),
            ),
          _DetailRow(
            label: 'Auto-renew',
            value: subscription.autoRenew ? 'Yes' : 'No',
          ),
          
          const SizedBox(height: 24),
          
          // Actions
          if (subscription.isActive) ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: onPause,
                child: const Text('Pause Subscription'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onCancel,
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
                child: const Text('Cancel Subscription'),
              ),
            ),
          ] else if (subscription.status == SubscriptionStatus.paused) ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onResume,
                child: const Text('Resume Subscription'),
              ),
            ),
          ],
        ],
      ),
    );
  }
  
  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  
  const _DetailRow({required this.label, required this.value});
  
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: AppTheme.textSecondary(context)),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: AppTheme.textPrimary(context),
            ),
          ),
        ],
      ),
    );
  }
}
