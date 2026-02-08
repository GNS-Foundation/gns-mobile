/// My Organizations Screen - View and manage org registrations
/// 
/// Shows all organization registrations with their status:
/// - Pending: Awaiting DNS verification
/// - Verified: Ready to activate
/// - Active: Fully operational
/// 
/// Location: lib/ui/screens/my_organizations_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/org/org_storage.dart';
import '../../core/org/org_service.dart';
import '../../core/gns/identity_wallet.dart';
import 'org_registration_screen.dart';

class MyOrganizationsScreen extends StatefulWidget {
  final IdentityWallet? wallet;
  
  const MyOrganizationsScreen({super.key, this.wallet});

  @override
  State<MyOrganizationsScreen> createState() => _MyOrganizationsScreenState();
}

class _MyOrganizationsScreenState extends State<MyOrganizationsScreen> {
  final _orgService = OrgService.instance;
  bool _initialized = false;
  bool _syncing = false;
  
  @override
  void initState() {
    super.initState();
    _initialize();
    _orgService.addListener(_onServiceUpdate);
  }
  
  @override
  void dispose() {
    _orgService.removeListener(_onServiceUpdate);
    super.dispose();
  }
  
  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }
  
  Future<void> _initialize() async {
    await _orgService.initialize();
    setState(() => _initialized = true);
    _syncWithServer();
  }
  
  Future<void> _syncWithServer() async {
    setState(() => _syncing = true);
    await _orgService.syncWithServer();
    if (mounted) setState(() => _syncing = false);
  }
  
  Future<void> _verifyDns(OrgRegistration reg) async {
    final result = await _orgService.verifyDns(reg.namespace);
    if (mounted) {
      if (result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ ${reg.namespace}@ verified!'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.error ?? 'Verification failed'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }
  
  Future<void> _activate(OrgRegistration reg) async {
    if (widget.wallet == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No identity loaded'), backgroundColor: Colors.red),
      );
      return;
    }
    
    final pk = widget.wallet!.publicKey;
    if (pk == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Identity not fully initialized'), backgroundColor: Colors.red),
      );
      return;
    }
    final result = await _orgService.activate(reg.namespace, pk);
    
    if (mounted) {
      if (result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🎉 ${reg.namespace}@ activated!'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.error ?? 'Activation failed'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copied!'), backgroundColor: Colors.green),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Organizations'),
        actions: [
          if (_syncing)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _syncWithServer,
              tooltip: 'Sync with server',
            ),
        ],
      ),
      body: !_initialized
          ? const Center(child: CircularProgressIndicator())
          : _orgService.registrations.isEmpty
              ? _buildEmptyState()
              : _buildRegistrationsList(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const OrgRegistrationScreen()),
          ).then((_) => _syncWithServer());
        },
        icon: const Icon(Icons.add),
        label: const Text('Register Org'),
        backgroundColor: Colors.purple,
        foregroundColor: Colors.white,
      ),
    );
  }
  
  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.purple.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.business, size: 64, color: Colors.purple),
            ),
            const SizedBox(height: 24),
            const Text(
              'No Organizations Yet',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Register your organization to claim a namespace like company@',
              style: TextStyle(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const OrgRegistrationScreen()),
                ).then((_) => _syncWithServer());
              },
              icon: const Icon(Icons.add),
              label: const Text('Register Organization'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildRegistrationsList() {
    final regs = _orgService.registrations;
    
    // Sort: active first, then verified, then pending
    regs.sort((a, b) {
      final order = {OrgStatus.active: 0, OrgStatus.verified: 1, OrgStatus.pending: 2, OrgStatus.suspended: 3};
      return (order[a.status] ?? 4).compareTo(order[b.status] ?? 4);
    });
    
    return RefreshIndicator(
      onRefresh: _syncWithServer,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: regs.length,
        itemBuilder: (context, index) => _buildRegistrationCard(regs[index]),
      ),
    );
  }
  
  Widget _buildRegistrationCard(OrgRegistration reg) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _getStatusColor(reg.status).withOpacity(0.1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _getStatusColor(reg.status).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    _getStatusIcon(reg.status),
                    color: _getStatusColor(reg.status),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        reg.organizationName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                      Text(
                        '${reg.namespace}@',
                        style: TextStyle(
                          color: Colors.purple[700],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                _buildStatusBadge(reg.status),
              ],
            ),
          ),
          
          // Details
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDetailRow(Icons.language, 'Domain', reg.domain),
                const SizedBox(height: 8),
                _buildDetailRow(Icons.email, 'Email', reg.email),
                const SizedBox(height: 8),
                _buildDetailRow(Icons.workspace_premium, 'Tier', reg.tier.toUpperCase()),
                
                // Show DNS instructions for pending
                if (reg.isPending) ...[
                  const Divider(height: 24),
                  _buildDnsInstructions(reg),
                ],
                
                // Actions
                const SizedBox(height: 16),
                _buildActions(reg),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildStatusBadge(OrgStatus status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _getStatusColor(status),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _getStatusLabel(status),
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }
  
  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Text('$label: ', style: TextStyle(color: Colors.grey[600])),
        Expanded(
          child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ),
      ],
    );
  }
  
  Widget _buildDnsInstructions(OrgRegistration reg) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.dns, color: Colors.orange[700]),
              const SizedBox(width: 8),
              Text(
                'DNS Verification Required',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.orange[800],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Add this TXT record to your DNS:',
            style: TextStyle(color: Colors.orange[700], fontSize: 13),
          ),
          const SizedBox(height: 8),
          _buildCopyField('Host', reg.txtRecordHost),
          const SizedBox(height: 8),
          _buildCopyField('Type', 'TXT'),
          const SizedBox(height: 8),
          _buildCopyField('Value', reg.txtRecordValue),
        ],
      ),
    );
  }
  
  Widget _buildCopyField(String label, String value) {
    return Row(
      children: [
        SizedBox(
          width: 60,
          child: Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
        ),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                GestureDetector(
                  onTap: () => _copyToClipboard(value, label),
                  child: Icon(Icons.copy, size: 16, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
  
  Widget _buildActions(OrgRegistration reg) {
    switch (reg.status) {
      case OrgStatus.pending:
        return Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _orgService.isLoading ? null : () => _verifyDns(reg),
                icon: _orgService.isLoading 
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.verified),
                label: const Text('Check DNS'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: () => _showDeleteConfirm(reg),
              icon: const Icon(Icons.delete_outline, color: Colors.red),
            ),
          ],
        );
        
      case OrgStatus.verified:
        return Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _orgService.isLoading ? null : () => _activate(reg),
                icon: _orgService.isLoading 
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.rocket_launch),
                label: const Text('Activate Namespace'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        );
        
      case OrgStatus.active:
        return Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  // TODO: Navigate to org management screen
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Org management coming soon!')),
                  );
                },
                icon: const Icon(Icons.settings),
                label: const Text('Manage'),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () {
                // TODO: Add member flow
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Add members coming soon!')),
                );
              },
              icon: const Icon(Icons.person_add),
              label: const Text('Add Members'),
            ),
          ],
        );
        
      case OrgStatus.suspended:
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.red[50],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.warning, color: Colors.red[700]),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'This namespace has been suspended. Contact support.',
                  style: TextStyle(color: Colors.red[700]),
                ),
              ),
            ],
          ),
        );
    }
  }
  
  void _showDeleteConfirm(OrgRegistration reg) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Registration?'),
        content: Text('Remove ${reg.namespace}@ from your local list? This won\'t affect any server-side registration.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _orgService.deleteRegistration(reg.namespace);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
  }
  
  Color _getStatusColor(OrgStatus status) {
    switch (status) {
      case OrgStatus.pending:
        return Colors.orange;
      case OrgStatus.verified:
        return Colors.blue;
      case OrgStatus.active:
        return Colors.green;
      case OrgStatus.suspended:
        return Colors.red;
    }
  }
  
  IconData _getStatusIcon(OrgStatus status) {
    switch (status) {
      case OrgStatus.pending:
        return Icons.hourglass_empty;
      case OrgStatus.verified:
        return Icons.verified;
      case OrgStatus.active:
        return Icons.check_circle;
      case OrgStatus.suspended:
        return Icons.block;
    }
  }
  
  String _getStatusLabel(OrgStatus status) {
    switch (status) {
      case OrgStatus.pending:
        return 'PENDING';
      case OrgStatus.verified:
        return 'VERIFIED';
      case OrgStatus.active:
        return 'ACTIVE';
      case OrgStatus.suspended:
        return 'SUSPENDED';
    }
  }
}
