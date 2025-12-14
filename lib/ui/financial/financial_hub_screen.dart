/// GNS Financial Hub Screen
/// 
/// Main payments dashboard with activity summary and quick actions.
/// Location: lib/ui/financial/financial_hub_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme/theme_service.dart';
import '../../core/financial/payment_service.dart';
import '../../core/financial/transaction_storage.dart';
import '../../core/gns/identity_wallet.dart';
import 'send_money_screen.dart';
import 'transactions_screen.dart';
import 'financial_settings_screen.dart';

class FinancialHubScreen extends StatefulWidget {
  const FinancialHubScreen({super.key});

  @override
  State<FinancialHubScreen> createState() => _FinancialHubScreenState();
}

class _FinancialHubScreenState extends State<FinancialHubScreen> {
  PaymentService? _paymentService;
  bool _isLoading = true;
  
  // Stats
  double _todaySent = 0;
  double _todayReceived = 0;
  int _pendingCount = 0;
  List<GnsTransaction> _recentTransactions = [];
  
  StreamSubscription? _transactionSub;

  @override
  void initState() {
    super.initState();
    _initAndLoad();
  }

  @override
  void dispose() {
    _transactionSub?.cancel();
    super.dispose();
  }

  Future<void> _initAndLoad() async {
    try {
      final wallet = IdentityWallet();
      await wallet.initialize();
      _paymentService = PaymentService.instance(wallet);
      await _paymentService!.initialize();
      
      // Listen for updates
      _transactionSub = _paymentService!.transactionUpdates.listen((_) {
        _loadStats();
      });
      
      await _loadStats();
    } catch (e) {
      debugPrint('Error initializing financial hub: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadStats() async {
    if (_paymentService == null) return;
    
    try {
      final sent = await _paymentService!.getTotalSentToday(currency: 'EUR');
      final received = await _paymentService!.getTotalReceivedToday(currency: 'EUR');
      final pending = await _paymentService!.getPendingIncoming();
      final recent = await _paymentService!.getTransactions(limit: 5);
      
      if (mounted) {
        setState(() {
          _todaySent = sent;
          _todayReceived = received;
          _pendingCount = pending.length;
          _recentTransactions = recent;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading stats: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payments'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const FinancialSettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadStats,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Today's Activity Card
                  _buildActivityCard(),
                  const SizedBox(height: 20),
                  
                  // Quick Actions
                  _buildQuickActions(),
                  const SizedBox(height: 24),
                  
                  // Pending Alert
                  if (_pendingCount > 0) ...[
                    _buildPendingAlert(),
                    const SizedBox(height: 24),
                  ],
                  
                  // Recent Transactions
                  _buildRecentSection(),
                ],
              ),
            ),
    );
  }

  Widget _buildActivityCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primary,
            AppTheme.primary.withOpacity(0.8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.today, color: Colors.white70, size: 20),
              const SizedBox(width: 8),
              Text(
                "TODAY'S ACTIVITY",
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Icon(Icons.arrow_upward, color: Colors.white, size: 14),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Sent',
                          style: TextStyle(color: Colors.white.withOpacity(0.7)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '€${_todaySent.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 1,
                height: 50,
                color: Colors.white.withOpacity(0.2),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Icon(Icons.arrow_downward, color: Colors.white, size: 14),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Received',
                            style: TextStyle(color: Colors.white.withOpacity(0.7)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '€${_todayReceived.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    return Row(
      children: [
        Expanded(
          child: _buildActionButton(
            icon: Icons.send,
            label: 'Send',
            color: AppTheme.primary,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SendMoneyScreen()),
              );
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildActionButton(
            icon: Icons.qr_code,
            label: 'Receive',
            color: AppTheme.secondary,
            onTap: _showReceiveQR,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildActionButton(
            icon: Icons.history,
            label: 'History',
            color: AppTheme.accent,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TransactionsScreen()),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPendingAlert() {
    return Container(
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
            child: const Icon(Icons.pending_actions, color: AppTheme.warning, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$_pendingCount Pending Payment${_pendingCount == 1 ? '' : 's'}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.warning,
                  ),
                ),
                Text(
                  'Review and accept incoming payments',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textMuted(context),
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: AppTheme.textMuted(context)),
        ],
      ),
    );
  }

  Widget _buildRecentSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'RECENT TRANSACTIONS',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppTheme.textMuted(context),
                letterSpacing: 1,
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const TransactionsScreen()),
                );
              },
              child: const Text('See All'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_recentTransactions.isEmpty)
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: AppTheme.surface(context),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Column(
                children: [
                  Icon(
                    Icons.receipt_long_outlined,
                    size: 48,
                    color: AppTheme.textMuted(context).withOpacity(0.5),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No transactions yet',
                    style: TextStyle(color: AppTheme.textMuted(context)),
                  ),
                ],
              ),
            ),
          )
        else
          ...(_recentTransactions.map((tx) => _buildTransactionTile(tx))),
      ],
    );
  }

  Widget _buildTransactionTile(GnsTransaction tx) {
    final isOutgoing = tx.direction == TransactionDirection.outgoing;
    final amountColor = isOutgoing ? AppTheme.error : AppTheme.secondary;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: CircleAvatar(
          radius: 18,
          backgroundColor: amountColor.withOpacity(0.15),
          child: Icon(
            isOutgoing ? Icons.arrow_upward : Icons.arrow_downward,
            color: amountColor,
            size: 18,
          ),
        ),
        title: Text(
          tx.counterpartyDisplay,
          style: TextStyle(
            fontWeight: FontWeight.w500,
            color: AppTheme.textPrimary(context),
          ),
        ),
        subtitle: Text(
          _formatTimeAgo(tx.createdAt),
          style: TextStyle(
            fontSize: 12,
            color: AppTheme.textMuted(context),
          ),
        ),
        trailing: Text(
          '${isOutgoing ? '-' : '+'}${tx.amountFormatted}',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: amountColor,
          ),
        ),
      ),
    );
  }

  String _formatTimeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  void _showReceiveQR() {
    // TODO: Implement QR code generation for receiving
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('QR receive coming soon!')),
    );
  }
}
