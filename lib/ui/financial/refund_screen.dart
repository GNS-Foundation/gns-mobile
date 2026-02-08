/// GNS Refund Request Screen - Sprint 6
/// 
/// UI for requesting refunds and viewing refund history.
/// 
/// Location: lib/ui/financial/refund_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/gns/identity_wallet.dart';
import '../../core/financial/refund_service.dart';
import '../../core/financial/payment_receipt.dart';
import '../../core/theme/theme_service.dart';

class RefundScreen extends StatefulWidget {
  final IdentityWallet wallet;
  final PaymentReceipt? initialReceipt; // If navigating from receipt
  
  const RefundScreen({
    super.key,
    required this.wallet,
    this.initialReceipt,
  });
  
  @override
  State<RefundScreen> createState() => _RefundScreenState();
}

class _RefundScreenState extends State<RefundScreen>
    with SingleTickerProviderStateMixin {
  final _refundService = RefundService();
  final _receiptStorage = ReceiptStorage();
  
  List<RefundRequest> _refunds = [];
  List<PaymentReceipt> _eligibleReceipts = [];
  
  bool _loading = true;
  String? _error;
  
  late TabController _tabController;
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initialize();
    
    // If initial receipt provided, show refund dialog
    if (widget.initialReceipt != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showRefundDialog(widget.initialReceipt!);
      });
    }
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
  
  Future<void> _initialize() async {
    await _refundService.initialize(widget.wallet);
    await _loadData();
  }
  
  Future<void> _loadData() async {
    setState(() => _loading = true);
    
    try {
      final results = await Future.wait([
        _refundService.getUserRefunds(),
        _receiptStorage.getAllReceipts(),
      ]);
      
      final refunds = results[0] as List<RefundRequest>;
      final receipts = results[1] as List<PaymentReceipt>;
      
      // Filter eligible receipts (not already refunded or has pending refund)
      final refundedReceiptIds = refunds
          .where((r) => r.status != RefundStatus.rejected && r.status != RefundStatus.cancelled)
          .map((r) => r.originalReceiptId)
          .toSet();
      
      final eligible = receipts
          .where((r) => 
            r.status == ReceiptStatus.confirmed && 
            !refundedReceiptIds.contains(r.receiptId) &&
            DateTime.now().difference(r.timestamp).inDays <= 90
          )
          .toList();
      
      setState(() {
        _refunds = refunds;
        _eligibleReceipts = eligible;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }
  
  void _showRefundDialog(PaymentReceipt receipt) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _RefundRequestSheet(
        receipt: receipt,
        onSubmit: (reason, details, amount) async {
          Navigator.pop(ctx);
          await _submitRefund(receipt, reason, details, amount);
        },
      ),
    );
  }
  
  Future<void> _submitRefund(
    PaymentReceipt receipt,
    RefundReason reason,
    String? details,
    double? amount,
  ) async {
    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Submitting refund request...'),
          ],
        ),
      ),
    );
    
    final result = await _refundService.requestRefund(
      receiptId: receipt.receiptId,
      reason: reason,
      reasonDetails: details,
      partialAmount: amount,
    );
    
    Navigator.pop(context); // Close loading
    
    if (result.success) {
      HapticFeedback.heavyImpact();
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Refund request submitted: ${result.refund?.refundId}'),
          backgroundColor: AppTheme.secondary,
        ),
      );
      
      await _loadData();
      _tabController.animateTo(1); // Switch to history tab
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ ${result.error ?? 'Failed to submit refund'}'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }
  
  Future<void> _cancelRefund(RefundRequest refund) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface(ctx),
        title: const Text('Cancel Refund?'),
        content: Text('Cancel refund request ${refund.refundId}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;
    
    final result = await _refundService.cancelRefund(refund.refundId);
    
    if (result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Refund cancelled')),
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
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background(context),
      appBar: AppBar(
        backgroundColor: AppTheme.surface(context),
        title: const Text('Refunds'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'Request (${_eligibleReceipts.length})'),
            Tab(text: 'History (${_refunds.length})'),
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
                    _buildRequestTab(),
                    _buildHistoryTab(),
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
          ElevatedButton(onPressed: _loadData, child: const Text('Retry')),
        ],
      ),
    );
  }
  
  Widget _buildRequestTab() {
    if (_eligibleReceipts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('💳', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 16),
              Text(
                'No eligible transactions',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary(context),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Payments from the last 90 days that haven\'t been refunded will appear here.',
                style: TextStyle(color: AppTheme.textSecondary(context)),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _eligibleReceipts.length,
        itemBuilder: (ctx, i) => _buildReceiptCard(_eligibleReceipts[i]),
      ),
    );
  }
  
  Widget _buildReceiptCard(PaymentReceipt receipt) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showRefundDialog(receipt),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Merchant icon
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Center(
                    child: Icon(Icons.store, color: AppTheme.primary),
                  ),
                ),
                const SizedBox(width: 16),
                // Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        receipt.merchantName,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary(context),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatDate(receipt.timestamp),
                        style: TextStyle(
                          color: AppTheme.textMuted(context),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                // Amount
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      receipt.formattedAmount,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary(context),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Request Refund →',
                      style: TextStyle(
                        color: AppTheme.primary,
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
  
  Widget _buildHistoryTab() {
    if (_refunds.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('📋', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 16),
              Text(
                'No refund history',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary(context),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Your refund requests will appear here.',
                style: TextStyle(color: AppTheme.textSecondary(context)),
              ),
            ],
          ),
        ),
      );
    }
    
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _refunds.length,
        itemBuilder: (ctx, i) => _buildRefundCard(_refunds[i]),
      ),
    );
  }
  
  Widget _buildRefundCard(RefundRequest refund) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  refund.refundId,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary(context),
                  ),
                ),
                _buildStatusChip(refund.status),
              ],
            ),
            const SizedBox(height: 12),
            
            // Merchant and amount
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      refund.merchantName,
                      style: TextStyle(color: AppTheme.textSecondary(context)),
                    ),
                    Text(
                      refund.reason.displayName,
                      style: TextStyle(
                        color: AppTheme.textMuted(context),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      refund.formattedAmount,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: AppTheme.textPrimary(context),
                      ),
                    ),
                    if (refund.isPartialRefund)
                      Text(
                        'of ${refund.formattedOriginalAmount}',
                        style: TextStyle(
                          color: AppTheme.textMuted(context),
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // Date and actions
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatDate(refund.createdAt),
                  style: TextStyle(
                    color: AppTheme.textMuted(context),
                    fontSize: 12,
                  ),
                ),
                if (refund.canCancel)
                  TextButton(
                    onPressed: () => _cancelRefund(refund),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.error,
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 0),
                    ),
                    child: const Text('Cancel'),
                  ),
              ],
            ),
            
            // Rejection reason
            if (refund.status == RefundStatus.rejected && refund.rejectionReason != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.error.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 16, color: AppTheme.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        refund.rejectionReason!,
                        style: const TextStyle(
                          color: AppTheme.error,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            
            // Transaction hash
            if (refund.refundTransactionHash != null) ...[
              const SizedBox(height: 8),
              InkWell(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: refund.refundTransactionHash!));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Transaction hash copied')),
                  );
                },
                child: Row(
                  children: [
                    Icon(
                      Icons.receipt_long,
                      size: 16,
                      color: AppTheme.textMuted(context),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${refund.refundTransactionHash!.substring(0, 20)}...',
                        style: TextStyle(
                          color: AppTheme.primary,
                          fontSize: 12,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    Icon(
                      Icons.copy,
                      size: 14,
                      color: AppTheme.textMuted(context),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
  
  Widget _buildStatusChip(RefundStatus status) {
    Color color;
    String text;
    
    switch (status) {
      case RefundStatus.pending:
        color = AppTheme.warning;
        text = 'Pending';
        break;
      case RefundStatus.approved:
      case RefundStatus.processing:
        color = AppTheme.primary;
        text = 'Processing';
        break;
      case RefundStatus.completed:
        color = AppTheme.secondary;
        text = 'Completed';
        break;
      case RefundStatus.rejected:
        color = AppTheme.error;
        text = 'Rejected';
        break;
      case RefundStatus.failed:
        color = AppTheme.error;
        text = 'Failed';
        break;
      case RefundStatus.cancelled:
        color = Colors.grey;
        text = 'Cancelled';
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
  
  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}

// Refund request sheet
class _RefundRequestSheet extends StatefulWidget {
  final PaymentReceipt receipt;
  final Function(RefundReason, String?, double?) onSubmit;
  
  const _RefundRequestSheet({
    required this.receipt,
    required this.onSubmit,
  });
  
  @override
  State<_RefundRequestSheet> createState() => _RefundRequestSheetState();
}

class _RefundRequestSheetState extends State<_RefundRequestSheet> {
  RefundReason _selectedReason = RefundReason.customerRequest;
  final _detailsController = TextEditingController();
  bool _isPartialRefund = false;
  double _refundAmount = 0;
  
  @override
  void initState() {
    super.initState();
    _refundAmount = widget.receipt.amount;
  }
  
  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
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
            
            // Title
            const Text(
              'Request Refund',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            
            // Transaction summary
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.background(context),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.store, size: 32),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.receipt.merchantName,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          _formatDate(widget.receipt.timestamp),
                          style: TextStyle(
                            color: AppTheme.textMuted(context),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    widget.receipt.formattedAmount,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Reason dropdown
            Text(
              'Reason for refund',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: AppTheme.textSecondary(context),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border.all(color: AppTheme.divider(context)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButton<RefundReason>(
                value: _selectedReason,
                isExpanded: true,
                underline: const SizedBox(),
                items: RefundReason.values.map((reason) {
                  return DropdownMenuItem(
                    value: reason,
                    child: Text(reason.displayName),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _selectedReason = value);
                },
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Additional details
            Text(
              'Additional details (optional)',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: AppTheme.textSecondary(context),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _detailsController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Provide more details...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Partial refund option
            SwitchListTile(
              title: const Text('Request partial refund'),
              value: _isPartialRefund,
              onChanged: (v) => setState(() {
                _isPartialRefund = v;
                if (!v) _refundAmount = widget.receipt.amount;
              }),
              contentPadding: EdgeInsets.zero,
            ),
            
            if (_isPartialRefund) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    '\$',
                    style: TextStyle(
                      fontSize: 24,
                      color: AppTheme.textSecondary(context),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Slider(
                      value: _refundAmount,
                      min: 0.01,
                      max: widget.receipt.amount,
                      onChanged: (v) => setState(() => _refundAmount = v),
                    ),
                  ),
                  SizedBox(
                    width: 80,
                    child: Text(
                      _refundAmount.toStringAsFixed(2),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            
            const SizedBox(height: 24),
            
            // Submit button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  widget.onSubmit(
                    _selectedReason,
                    _detailsController.text.isNotEmpty ? _detailsController.text : null,
                    _isPartialRefund ? _refundAmount : null,
                  );
                },
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: Text(
                  'Submit Refund Request${_isPartialRefund ? ' (\$${_refundAmount.toStringAsFixed(2)})' : ''}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
            
            const SizedBox(height: 8),
            
            Center(
              child: Text(
                'Refunds typically take 3-5 business days',
                style: TextStyle(
                  color: AppTheme.textMuted(context),
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}
