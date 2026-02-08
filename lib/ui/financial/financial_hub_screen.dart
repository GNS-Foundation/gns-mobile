/// GNS Financial Hub Screen (v2)
/// 
/// Main payments dashboard with activity summary and quick actions.
/// v2: Auto-creates USDC + EURC trustlines for existing users
/// 
/// Location: lib/ui/financial/financial_hub_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme/theme_service.dart';
import '../../core/financial/payment_service.dart';
import '../../core/financial/transaction_storage.dart';
import '../../core/gns/identity_wallet.dart';
import 'stellar_service.dart';
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
  IdentityWallet? _wallet;
  bool _isLoading = true;
  
  // Stats
  double _todaySent = 0;
  double _todayReceived = 0;
  int _pendingCount = 0;
  List<GnsTransaction> _recentTransactions = [];
  
  // Stablecoin balances
  double _usdcBalance = 0;
  double _eurcBalance = 0;
  
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
      _wallet = IdentityWallet();
      await _wallet!.initialize();
      _paymentService = PaymentService.instance(_wallet!);
      await _paymentService!.initialize();
      
      // Listen for updates
      _transactionSub = _paymentService!.transactionUpdates.listen((_) {
        _loadStats();
      });
      
      await _loadStats();
      
      // ✅ Auto-create payment trustlines for existing users (silent, no UI)
      _ensurePaymentTrustlines();
      
    } catch (e) {
      debugPrint('Error initializing financial hub: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }
  
  /// Silently ensures USDC + EURC trustlines exist for existing users
  /// This runs in background - no UI, no blocking
  Future<void> _ensurePaymentTrustlines() async {
    try {
      final publicKey = _wallet?.publicKey;
      final privateKeyBytes = _wallet?.privateKeyBytes;
      
      if (publicKey == null || privateKeyBytes == null) {
        debugPrint('⚠️ No wallet keys available for trustline check');
        return;
      }
      
      final stellar = StellarService();
      final stellarAddress = stellar.gnsKeyToStellar(publicKey);
      
      // Check if account exists first
      final accountExists = await stellar.accountExists(stellarAddress);
      if (!accountExists) {
        debugPrint('⚠️ Stellar account does not exist yet - skipping trustlines');
        return;
      }
      
      // Check existing trustlines
      final hasUsdc = await stellar.hasUsdcTrustline(stellarAddress);
      final hasEurc = await stellar.hasEurcTrustline(stellarAddress);
      
      if (hasUsdc && hasEurc) {
        debugPrint('✅ Payment trustlines already exist');
        return;
      }
      
      debugPrint('🔐 Creating missing payment trustlines...');
      debugPrint('   USDC: ${hasUsdc ? "exists" : "MISSING"}');
      debugPrint('   EURC: ${hasEurc ? "exists" : "MISSING"}');
      
      final result = await stellar.createAllPaymentTrustlines(
        stellarPublicKey: stellarAddress,
        privateKeyBytes: privateKeyBytes,
      );
      
      if (result.success) {
        debugPrint('✅ Payment trustlines created! Hash: ${result.hash}');
        
        // Refresh balances after trustline creation
        await _loadStablecoinBalances();
      } else {
        debugPrint('⚠️ Trustline creation failed: ${result.error}');
        // Don't show error to user - this is a background operation
      }
    } catch (e) {
      debugPrint('⚠️ Error ensuring trustlines: $e');
      // Silent failure - don't interrupt user experience
    }
  }
  
  /// Load stablecoin balances for display
  Future<void> _loadStablecoinBalances() async {
    try {
      final publicKey = _wallet?.publicKey;
      if (publicKey == null) return;
      
      final stellar = StellarService();
      final stellarAddress = stellar.gnsKeyToStellar(publicKey);
      
      final balances = await stellar.getAllStablecoinBalances(stellarAddress);
      
      if (mounted) {
        setState(() {
          _usdcBalance = balances[Stablecoin.usdc] ?? 0;
          _eurcBalance = balances[Stablecoin.eurc] ?? 0;
        });
      }
    } catch (e) {
      debugPrint('Error loading stablecoin balances: $e');
    }
  }

  Future<void> _loadStats() async {
    if (_paymentService == null) return;
    
    try {
      final sent = await _paymentService!.getTotalSentToday(currency: 'EUR');
      final received = await _paymentService!.getTotalReceivedToday(currency: 'EUR');
      final pending = await _paymentService!.getPendingIncoming();
      final recent = await _paymentService!.getTransactions(limit: 5);
      
      // Also load stablecoin balances
      await _loadStablecoinBalances();
      
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
                MaterialPageRoute(
                  builder: (context) => const FinancialSettingsScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadStats,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildBalanceCard(),
                    const SizedBox(height: 16),
                    _buildQuickActions(),
                    const SizedBox(height: 16),
                    _buildTodayStats(),
                    const SizedBox(height: 16),
                    _buildRecentTransactions(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildBalanceCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your Balances',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildBalanceItem('€', _eurcBalance, 'EUR'),
                _buildBalanceItem('\$', _usdcBalance, 'USD'),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildBalanceItem(String symbol, double amount, String currency) {
    return Column(
      children: [
        Text(
          '$symbol${amount.toStringAsFixed(2)}',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          currency,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Colors.grey,
          ),
        ),
      ],
    );
  }

  Widget _buildQuickActions() {
    return Row(
      children: [
        Expanded(
          child: _buildActionButton(
            icon: Icons.arrow_upward,
            label: 'Send',
            color: Colors.blue,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SendMoneyScreen(),
                ),
              ).then((_) => _loadStats());
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildActionButton(
            icon: Icons.arrow_downward,
            label: 'Receive',
            color: Colors.green,
            onTap: () {
              // TODO: Show receive screen with QR code
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Receive screen coming soon!')),
              );
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildActionButton(
            icon: Icons.history,
            label: 'History',
            color: Colors.orange,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const TransactionsScreen(),
                ),
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 4),
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
    );
  }

  Widget _buildTodayStats() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Today',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    icon: Icons.arrow_upward,
                    label: 'Sent',
                    value: '€${_todaySent.toStringAsFixed(2)}',
                    color: Colors.red,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    icon: Icons.arrow_downward,
                    label: 'Received',
                    value: '€${_todayReceived.toStringAsFixed(2)}',
                    color: Colors.green,
                  ),
                ),
                if (_pendingCount > 0)
                  Expanded(
                    child: _buildStatItem(
                      icon: Icons.pending,
                      label: 'Pending',
                      value: '$_pendingCount',
                      color: Colors.orange,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: color,
          ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildRecentTransactions() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Recent Activity',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const TransactionsScreen(),
                      ),
                    );
                  },
                  child: const Text('See All'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_recentTransactions.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    'No transactions yet',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              )
            else
              ...List.generate(
                _recentTransactions.length,
                (index) => _buildTransactionItem(_recentTransactions[index]),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionItem(GnsTransaction tx) {
    final isSent = tx.isOutgoing;
    final symbol = tx.currency == 'USD' ? '\$' : '€';
    
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: (isSent ? Colors.red : Colors.green).withOpacity(0.1),
        child: Icon(
          isSent ? Icons.arrow_upward : Icons.arrow_downward,
          color: isSent ? Colors.red : Colors.green,
        ),
      ),
      title: Text(
        isSent 
          ? 'Sent to ${tx.toHandle ?? _shortAddress(tx.toPublicKey)}'
          : 'Received from ${tx.fromHandle ?? _shortAddress(tx.fromPublicKey)}',
      ),
      subtitle: Text(_formatDate(tx.createdAt)),
      trailing: Text(
        '${isSent ? "-" : "+"}$symbol${tx.amountDouble.toStringAsFixed(2)}',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: isSent ? Colors.red : Colors.green,
        ),
      ),
    );
  }
  
  String _shortAddress(String? address) {
    if (address == null || address.length < 12) return address ?? 'Unknown';
    return '${address.substring(0, 6)}...${address.substring(address.length - 4)}';
  }
  
  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    
    return '${date.day}/${date.month}/${date.year}';
  }
}
