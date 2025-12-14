/// GNS Transactions Screen
/// 
/// Transaction history with filters and details.
/// Location: lib/ui/financial/transactions_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/theme_service.dart';
import '../../core/financial/payment_service.dart';
import '../../core/financial/transaction_storage.dart';
import '../../core/gns/identity_wallet.dart';

class TransactionsScreen extends StatefulWidget {
  final TransactionDirection? initialFilter;
  
  const TransactionsScreen({
    super.key,
    this.initialFilter,
  });

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  PaymentService? _paymentService;
  List<GnsTransaction> _allTransactions = [];
  List<GnsTransaction> _filteredTransactions = [];
  bool _isLoading = true;
  
  final _filterTabs = ['All', 'Sent', 'Received', 'Pending'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_onTabChanged);
    
    // Set initial tab based on filter
    if (widget.initialFilter != null) {
      switch (widget.initialFilter!) {
        case TransactionDirection.outgoing:
          _tabController.index = 1;
          break;
        case TransactionDirection.incoming:
          _tabController.index = 2;
          break;
      }
    }
    
    _initAndLoad();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    _applyFilter();
  }

  Future<void> _initAndLoad() async {
    try {
      final wallet = IdentityWallet();
      await wallet.initialize();
      _paymentService = PaymentService.instance(wallet);
      await _paymentService!.initialize();
      await _loadTransactions();
    } catch (e) {
      debugPrint('Error initializing: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadTransactions() async {
    if (_paymentService == null) return;
    
    try {
      final transactions = await _paymentService!.getTransactions(limit: 200);
      
      if (mounted) {
        setState(() {
          _allTransactions = transactions;
          _isLoading = false;
        });
        _applyFilter();
      }
    } catch (e) {
      debugPrint('Error loading transactions: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _applyFilter() {
    List<GnsTransaction> filtered;
    
    switch (_tabController.index) {
      case 1: // Sent
        filtered = _allTransactions
            .where((t) => t.direction == TransactionDirection.outgoing)
            .toList();
        break;
      case 2: // Received
        filtered = _allTransactions
            .where((t) => t.direction == TransactionDirection.incoming)
            .toList();
        break;
      case 3: // Pending
        filtered = _allTransactions
            .where((t) => t.status == TransactionStatus.pending)
            .toList();
        break;
      default: // All
        filtered = _allTransactions;
    }
    
    setState(() => _filteredTransactions = filtered);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transactions'),
        bottom: TabBar(
          controller: _tabController,
          tabs: _filterTabs.map((t) => Tab(text: t)).toList(),
          indicatorColor: AppTheme.primary,
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppTheme.textMuted(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadTransactions,
              child: _filteredTransactions.isEmpty
                  ? _buildEmptyState()
                  : _buildTransactionList(),
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.receipt_long_outlined,
            size: 64,
            color: AppTheme.textMuted(context).withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'No transactions',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppTheme.textSecondary(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _getEmptyMessage(),
            style: TextStyle(color: AppTheme.textMuted(context)),
          ),
        ],
      ),
    );
  }

  String _getEmptyMessage() {
    switch (_tabController.index) {
      case 1: return 'You haven\'t sent any payments yet';
      case 2: return 'You haven\'t received any payments yet';
      case 3: return 'No pending transactions';
      default: return 'No transactions to show';
    }
  }

  Widget _buildTransactionList() {
    // Group by date
    final grouped = _groupByDate(_filteredTransactions);
    
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: grouped.length,
      itemBuilder: (context, index) {
        final group = grouped[index];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date header
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                group.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textMuted(context),
                  letterSpacing: 1,
                ),
              ),
            ),
            // Transactions
            ...group.transactions.map((tx) => _buildTransactionTile(tx)),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }

  List<_DateGroup> _groupByDate(List<GnsTransaction> transactions) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final thisWeek = today.subtract(Duration(days: today.weekday - 1));
    
    final groups = <String, List<GnsTransaction>>{};
    
    for (final tx in transactions) {
      final txDate = DateTime(tx.createdAt.year, tx.createdAt.month, tx.createdAt.day);
      String label;
      
      if (txDate == today) {
        label = 'TODAY';
      } else if (txDate == yesterday) {
        label = 'YESTERDAY';
      } else if (txDate.isAfter(thisWeek)) {
        label = 'THIS WEEK';
      } else if (txDate.month == now.month && txDate.year == now.year) {
        label = 'THIS MONTH';
      } else {
        label = '${_monthName(txDate.month)} ${txDate.year}';
      }
      
      groups.putIfAbsent(label, () => []).add(tx);
    }
    
    return groups.entries
        .map((e) => _DateGroup(label: e.key, transactions: e.value))
        .toList();
  }

  String _monthName(int month) {
    const months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 
                    'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
    return months[month - 1];
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          radius: 20,
          backgroundColor: amountColor.withOpacity(0.15),
          child: Icon(
            isOutgoing ? Icons.arrow_upward : Icons.arrow_downward,
            color: amountColor,
            size: 20,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                tx.counterpartyDisplay,
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textPrimary(context),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              '${isOutgoing ? '-' : '+'}${tx.amountFormatted}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: amountColor,
              ),
            ),
          ],
        ),
        subtitle: Row(
          children: [
            // Status badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _getStatusColor(tx.status).withOpacity(0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                tx.statusDisplay,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: _getStatusColor(tx.status),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _formatTime(tx.createdAt),
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.textMuted(context),
              ),
            ),
            if (tx.memo != null && tx.memo!.isNotEmpty) ...[
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tx.memo!,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textMuted(context),
                    fontStyle: FontStyle.italic,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
        onTap: () => _showTransactionDetails(tx),
      ),
    );
  }

  Color _getStatusColor(TransactionStatus status) {
    switch (status) {
      case TransactionStatus.pending:
        return AppTheme.warning;
      case TransactionStatus.accepted:
      case TransactionStatus.settled:
        return AppTheme.secondary;
      case TransactionStatus.rejected:
      case TransactionStatus.failed:
      case TransactionStatus.expired:
        return AppTheme.error;
    }
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  void _showTransactionDetails(GnsTransaction tx) {
    final isOutgoing = tx.direction == TransactionDirection.outgoing;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.8,
        expand: false,
        builder: (ctx, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(24),
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.border(ctx),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),
            
            // Amount
            Center(
              child: Text(
                '${isOutgoing ? '-' : '+'}${tx.amountFormatted}',
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: isOutgoing ? AppTheme.error : AppTheme.secondary,
                ),
              ),
            ),
            const SizedBox(height: 8),
            
            // Status
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: _getStatusColor(tx.status).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  tx.statusDisplay,
                  style: TextStyle(
                    color: _getStatusColor(tx.status),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            
            // Details
            _buildDetailRow(ctx, isOutgoing ? 'To' : 'From', tx.counterpartyDisplay),
            if (tx.memo != null && tx.memo!.isNotEmpty)
              _buildDetailRow(ctx, 'Memo', tx.memo!),
            _buildDetailRow(ctx, 'Date', '${tx.createdAt.day}/${tx.createdAt.month}/${tx.createdAt.year}'),
            _buildDetailRow(ctx, 'Time', _formatTime(tx.createdAt)),
            _buildDetailRow(ctx, 'Currency', tx.currency.toUpperCase()),
            
            const Divider(height: 32),
            
            // Transaction ID
            _buildDetailRow(ctx, 'Transaction ID', tx.id, copyable: true),
            _buildDetailRow(ctx, 'Counterparty', tx.counterpartyKey, copyable: true),
            
            const SizedBox(height: 24),
            
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(BuildContext ctx, String label, String value, {bool copyable = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(color: AppTheme.textMuted(ctx)),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: AppTheme.textPrimary(ctx),
                fontWeight: FontWeight.w500,
                fontFamily: copyable ? 'monospace' : null,
                fontSize: copyable ? 12 : 14,
              ),
            ),
          ),
          if (copyable)
            IconButton(
              icon: Icon(Icons.copy, size: 16, color: AppTheme.textMuted(ctx)),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: value));
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text('$label copied'), duration: const Duration(seconds: 1)),
                );
              },
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
        ],
      ),
    );
  }
}

class _DateGroup {
  final String label;
  final List<GnsTransaction> transactions;
  
  _DateGroup({required this.label, required this.transactions});
}
