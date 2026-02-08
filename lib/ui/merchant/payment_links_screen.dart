/// GNS Payment Links Screen - Sprint 8
/// 
/// Merchant UI for creating and managing payment links.
/// 
/// Features:
/// - Create new payment links
/// - View link analytics
/// - Copy/share links
/// - QR code display
/// - Manage link status
/// 
/// Location: lib/screens/merchant/payment_links_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PaymentLinksScreen extends StatefulWidget {
  const PaymentLinksScreen({super.key});

  @override
  State<PaymentLinksScreen> createState() => _PaymentLinksScreenState();
}

class _PaymentLinksScreenState extends State<PaymentLinksScreen> {
  List<PaymentLinkData> _links = [];
  bool _isLoading = true;
  
  @override
  void initState() {
    super.initState();
    _loadLinks();
  }
  
  Future<void> _loadLinks() async {
    setState(() => _isLoading = true);
    
    // Mock data - replace with actual service call
    await Future.delayed(const Duration(milliseconds: 500));
    
    setState(() {
      _links = [
        PaymentLinkData(
          linkId: 'LNK-001',
          shortCode: 'abc123',
          title: 'Premium Subscription',
          type: 'oneTime',
          status: 'active',
          fixedAmount: 29.99,
          currency: 'USDC',
          viewCount: 145,
          paymentCount: 23,
          totalCollected: 689.77,
          createdAt: DateTime.now().subtract(const Duration(days: 7)),
        ),
        PaymentLinkData(
          linkId: 'LNK-002',
          shortCode: 'xyz789',
          title: 'Donation',
          type: 'reusable',
          status: 'active',
          currency: 'USDC',
          viewCount: 89,
          paymentCount: 12,
          totalCollected: 350.00,
          createdAt: DateTime.now().subtract(const Duration(days: 14)),
        ),
        PaymentLinkData(
          linkId: 'LNK-003',
          shortCode: 'def456',
          title: 'Product Purchase',
          type: 'oneTime',
          status: 'completed',
          fixedAmount: 99.00,
          currency: 'USDC',
          viewCount: 45,
          paymentCount: 1,
          totalCollected: 99.00,
          createdAt: DateTime.now().subtract(const Duration(days: 3)),
        ),
      ];
      _isLoading = false;
    });
  }
  
  void _createNewLink() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _CreateLinkSheet(
        onLinkCreated: (link) {
          setState(() => _links.insert(0, link));
        },
      ),
    );
  }
  
  void _showLinkDetails(PaymentLinkData link) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _LinkDetailsSheet(
        link: link,
        onStatusChanged: (newStatus) {
          setState(() {
            final index = _links.indexWhere((l) => l.linkId == link.linkId);
            if (index != -1) {
              _links[index] = PaymentLinkData(
                linkId: link.linkId,
                shortCode: link.shortCode,
                title: link.title,
                type: link.type,
                status: newStatus,
                fixedAmount: link.fixedAmount,
                currency: link.currency,
                viewCount: link.viewCount,
                paymentCount: link.paymentCount,
                totalCollected: link.totalCollected,
                createdAt: link.createdAt,
              );
            }
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payment Links'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadLinks,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _links.isEmpty
              ? _EmptyState(onCreateTap: _createNewLink)
              : RefreshIndicator(
                  onRefresh: _loadLinks,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _links.length,
                    itemBuilder: (context, index) {
                      final link = _links[index];
                      return _PaymentLinkCard(
                        link: link,
                        onTap: () => _showLinkDetails(link),
                        onCopy: () => _copyLink(link),
                        onShare: () => _shareLink(link),
                      );
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createNewLink,
        icon: const Icon(Icons.add),
        label: const Text('Create Link'),
      ),
    );
  }
  
  void _copyLink(PaymentLinkData link) {
    final url = 'https://pay.gns.network/${link.shortCode}';
    Clipboard.setData(ClipboardData(text: url));
    HapticFeedback.lightImpact();
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Link copied to clipboard')),
    );
  }
  
  void _shareLink(PaymentLinkData link) {
    // TODO: Implement share functionality
    final url = 'https://pay.gns.network/${link.shortCode}';
    debugPrint('Share: $url');
  }
}

// Payment link card widget
class _PaymentLinkCard extends StatelessWidget {
  final PaymentLinkData link;
  final VoidCallback onTap;
  final VoidCallback onCopy;
  final VoidCallback onShare;
  
  const _PaymentLinkCard({
    required this.link,
    required this.onTap,
    required this.onCopy,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          link.title ?? 'Untitled',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'pay.gns.network/${link.shortCode}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _StatusBadge(status: link.status),
                ],
              ),
              
              const SizedBox(height: 16),
              
              // Stats row
              Row(
                children: [
                  _StatItem(
                    icon: Icons.visibility,
                    label: 'Views',
                    value: link.viewCount.toString(),
                  ),
                  const SizedBox(width: 24),
                  _StatItem(
                    icon: Icons.payments,
                    label: 'Payments',
                    value: link.paymentCount.toString(),
                  ),
                  const SizedBox(width: 24),
                  _StatItem(
                    icon: Icons.attach_money,
                    label: 'Collected',
                    value: '\$${link.totalCollected.toStringAsFixed(2)}',
                  ),
                ],
              ),
              
              const SizedBox(height: 16),
              
              // Amount and type
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      link.type == 'oneTime' ? 'One-time' : 'Reusable',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (link.fixedAmount != null)
                    Text(
                      '\$${link.fixedAmount!.toStringAsFixed(2)} ${link.currency}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  else
                    Text(
                      'Any amount',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 20),
                    onPressed: onCopy,
                    tooltip: 'Copy link',
                  ),
                  IconButton(
                    icon: const Icon(Icons.share, size: 20),
                    onPressed: onShare,
                    tooltip: 'Share',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Status badge
class _StatusBadge extends StatelessWidget {
  final String status;
  
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    
    switch (status) {
      case 'active':
        color = Colors.green;
        label = 'Active';
        break;
      case 'inactive':
        color = Colors.grey;
        label = 'Inactive';
        break;
      case 'completed':
        color = Colors.blue;
        label = 'Completed';
        break;
      case 'expired':
        color = Colors.red;
        label = 'Expired';
        break;
      default:
        color = Colors.grey;
        label = status;
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

// Stat item widget
class _StatItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  
  const _StatItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Theme.of(context).colorScheme.outline),
        const SizedBox(width: 4),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ],
    );
  }
}

// Empty state
class _EmptyState extends StatelessWidget {
  final VoidCallback onCreateTap;
  
  const _EmptyState({required this.onCreateTap});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.link_off,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'No Payment Links',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Create shareable payment links for customers to pay you instantly.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onCreateTap,
              icon: const Icon(Icons.add),
              label: const Text('Create Payment Link'),
            ),
          ],
        ),
      ),
    );
  }
}

// Create link bottom sheet
class _CreateLinkSheet extends StatefulWidget {
  final ValueChanged<PaymentLinkData> onLinkCreated;
  
  const _CreateLinkSheet({required this.onLinkCreated});

  @override
  State<_CreateLinkSheet> createState() => _CreateLinkSheetState();
}

class _CreateLinkSheetState extends State<_CreateLinkSheet> {
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  
  String _type = 'oneTime';
  String _currency = 'USDC';
  bool _hasFixedAmount = true;
  bool _collectEmail = false;
  bool _isCreating = false;
  
  Future<void> _createLink() async {
    setState(() => _isCreating = true);
    
    // Mock creation - replace with actual service call
    await Future.delayed(const Duration(seconds: 1));
    
    final link = PaymentLinkData(
      linkId: 'LNK-${DateTime.now().millisecondsSinceEpoch}',
      shortCode: DateTime.now().millisecondsSinceEpoch.toRadixString(36),
      title: _titleController.text.isNotEmpty ? _titleController.text : null,
      type: _type,
      status: 'active',
      fixedAmount: _hasFixedAmount ? double.tryParse(_amountController.text) : null,
      currency: _currency,
      viewCount: 0,
      paymentCount: 0,
      totalCollected: 0,
      createdAt: DateTime.now(),
    );
    
    widget.onLinkCreated(link);
    
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment link created!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Create Payment Link',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              
              const SizedBox(height: 16),
              
              // Title
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Title (optional)',
                  hintText: 'e.g., Premium Subscription',
                  border: OutlineInputBorder(),
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Link type
              Text(
                'Link Type',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'oneTime',
                    label: Text('One-time'),
                    icon: Icon(Icons.looks_one),
                  ),
                  ButtonSegment(
                    value: 'reusable',
                    label: Text('Reusable'),
                    icon: Icon(Icons.all_inclusive),
                  ),
                ],
                selected: {_type},
                onSelectionChanged: (values) {
                  setState(() => _type = values.first);
                },
              ),
              
              const SizedBox(height: 16),
              
              // Amount
              SwitchListTile(
                title: const Text('Fixed Amount'),
                subtitle: const Text('Customer pays exact amount'),
                value: _hasFixedAmount,
                onChanged: (value) => setState(() => _hasFixedAmount = value),
                contentPadding: EdgeInsets.zero,
              ),
              
              if (_hasFixedAmount) ...[
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _amountController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Amount',
                          prefixText: '\$ ',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    DropdownButton<String>(
                      value: _currency,
                      items: const [
                        DropdownMenuItem(value: 'USDC', child: Text('USDC')),
                        DropdownMenuItem(value: 'EURC', child: Text('EURC')),
                        DropdownMenuItem(value: 'XLM', child: Text('XLM')),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => _currency = value);
                      },
                    ),
                  ],
                ),
              ],
              
              const SizedBox(height: 16),
              
              // Options
              SwitchListTile(
                title: const Text('Collect Email'),
                subtitle: const Text('Ask customer for email address'),
                value: _collectEmail,
                onChanged: (value) => setState(() => _collectEmail = value),
                contentPadding: EdgeInsets.zero,
              ),
              
              const SizedBox(height: 24),
              
              // Create button
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isCreating ? null : _createLink,
                  child: _isCreating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Create Link'),
                ),
              ),
              
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

// Link details bottom sheet
class _LinkDetailsSheet extends StatelessWidget {
  final PaymentLinkData link;
  final ValueChanged<String> onStatusChanged;
  
  const _LinkDetailsSheet({
    required this.link,
    required this.onStatusChanged,
  });

  @override
  Widget build(BuildContext context) {
    final url = 'https://pay.gns.network/${link.shortCode}';
    
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                link.title ?? 'Payment Link',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              _StatusBadge(status: link.status),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // QR Code placeholder
          Center(
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: const Center(
                child: Icon(Icons.qr_code_2, size: 150),
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // URL
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    url,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: url));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Link copied!')),
                    );
                  },
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Stats
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _StatColumn(label: 'Views', value: link.viewCount.toString()),
              _StatColumn(label: 'Payments', value: link.paymentCount.toString()),
              _StatColumn(label: 'Collected', value: '\$${link.totalCollected.toStringAsFixed(2)}'),
            ],
          ),
          
          const SizedBox(height: 24),
          
          // Actions
          if (link.status == 'active')
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  onStatusChanged('inactive');
                  Navigator.pop(context);
                },
                child: const Text('Deactivate Link'),
              ),
            )
          else if (link.status == 'inactive')
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  onStatusChanged('active');
                  Navigator.pop(context);
                },
                child: const Text('Reactivate Link'),
              ),
            ),
          
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  final String label;
  final String value;
  
  const _StatColumn({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

// Mock data class
class PaymentLinkData {
  final String linkId;
  final String shortCode;
  final String? title;
  final String type;
  final String status;
  final double? fixedAmount;
  final String currency;
  final int viewCount;
  final int paymentCount;
  final double totalCollected;
  final DateTime createdAt;
  
  PaymentLinkData({
    required this.linkId,
    required this.shortCode,
    this.title,
    required this.type,
    required this.status,
    this.fixedAmount,
    required this.currency,
    required this.viewCount,
    required this.paymentCount,
    required this.totalCollected,
    required this.createdAt,
  });
}
