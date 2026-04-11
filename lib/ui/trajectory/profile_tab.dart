/// Profile Tab
///
/// Avatar, handle, tier, member since. Privacy controls prominent.
/// Identity/wallet/gSite under IDENTITY section.
/// Messages, contacts, advanced features under ADVANCED.
/// Mesh compute teaser.
///
/// Location: lib/ui/trajectory/profile_tab.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/gns/identity_wallet.dart';
import '../../core/profile/profile_service.dart';
import '../../core/profile/identity_view_data.dart';
import '../../core/financial/payment_service.dart';
import '../../core/trajectory/trajectory_service.dart';
import '../../core/theme/theme_service.dart';
import '../widgets/identity_card.dart';
import '../profile/profile_editor_screen.dart';
import '../screens/identity_viewer_screen.dart';
import '../screens/gns_token_screen.dart';
import '../screens/handle_management_screen.dart';
import '../screens/browser_pairing_screen.dart';
import '../screens/debug_screen.dart';
import '../financial/financial_hub_screen.dart';
import '../hive/hive_worker_screen.dart';
import '../messages/unified_inbox_screen.dart';
import '../contacts/contacts_tab.dart';
import '../screens/history_screen.dart';

class ProfileTab extends StatefulWidget {
  final IdentityWallet wallet;
  final ProfileService profileService;
  final PaymentService? paymentService;
  final VoidCallback onIdentityDeleted;

  const ProfileTab({
    super.key,
    required this.wallet,
    required this.profileService,
    this.paymentService,
    required this.onIdentityDeleted,
  });

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab>
    with AutomaticKeepAliveClientMixin {
  final _trajectoryService = TrajectoryService();
  IdentityViewData? _identity;
  TrajectoryStats _stats = TrajectoryStats.empty();
  String? _handle;
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
      final identity = await widget.profileService.getMyIdentity();
      final stats = await _trajectoryService.getStats();
      final handle = await widget.wallet.getCurrentHandle();

      if (mounted) {
        setState(() {
          _identity = identity;
          _stats = stats;
          _handle = handle;
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
          'Profile',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 22),
            onPressed: _editProfile,
            tooltip: 'Edit profile',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  // ── Profile header ──
                  _buildProfileHeader(),
                  const SizedBox(height: 28),

                  // ── Privacy section (prominent) ──
                  _buildSection('PRIVACY', [
                    _buildRow(
                      icon: Icons.hexagon_outlined,
                      label: 'Location tracking',
                      trailing: Text(
                        'H3 cells',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppTheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    _buildRow(
                      icon: Icons.phone_iphone,
                      label: 'Data storage',
                      trailing: Text(
                        'Local only',
                        style: TextStyle(
                          fontSize: 13,
                          color: const Color(0xFF66BB6A),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    _buildRow(
                      icon: Icons.delete_outline,
                      label: 'Delete all breadcrumbs',
                      trailing: const Icon(Icons.chevron_right, size: 20),
                      onTap: _confirmDeleteBreadcrumbs,
                      isDestructive: true,
                    ),
                  ]),
                  const SizedBox(height: 24),

                  // ── Identity section ──
                  _buildSection('IDENTITY', [
                    _buildRow(
                      icon: Icons.vpn_key_outlined,
                      label: 'Your keys',
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Ed25519',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textMuted(context),
                              fontFamily: 'monospace',
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.chevron_right, size: 20),
                        ],
                      ),
                      onTap: _viewKeys,
                    ),
                    if (_handle != null)
                      _buildRow(
                        icon: Icons.alternate_email,
                        label: 'Handle',
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '@$_handle',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: AppTheme.primary,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.chevron_right, size: 20),
                          ],
                        ),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => HandleManagementScreen(wallet: widget.wallet)),
                        ),
                      ),
                    _buildRow(
                      icon: Icons.account_balance_wallet_outlined,
                      label: 'Wallet',
                      trailing: const Icon(Icons.chevron_right, size: 20),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const GnsTokenScreen()),
                      ),
                    ),
                    _buildRow(
                      icon: Icons.language,
                      label: 'gSite',
                      trailing: const Icon(Icons.chevron_right, size: 20),
                      onTap: () {
                        // Navigate to gSite editor
                      },
                    ),
                  ]),
                  const SizedBox(height: 24),

                  // ── Communication ──
                  _buildSection('COMMUNICATION', [
                    _buildRow(
                      icon: Icons.people_outline,
                      label: 'Contacts',
                      trailing: const Icon(Icons.chevron_right, size: 20),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ContactsTab(profileService: widget.profileService),
                        ),
                      ),
                    ),
                    _buildRow(
                      icon: Icons.payments_outlined,
                      label: 'Financial Hub',
                      trailing: const Icon(Icons.chevron_right, size: 20),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const FinancialHubScreen()),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 24),

                  // ── Advanced ──
                  _buildSection('ADVANCED', [
                    _buildRow(
                      icon: Icons.history,
                      label: 'Breadcrumb history',
                      trailing: const Icon(Icons.chevron_right, size: 20),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => HistoryScreen(
                            wallet: widget.wallet,
                            paymentService: widget.paymentService,
                          ),
                        ),
                      ),
                    ),
                    _buildRow(
                      icon: Icons.qr_code_scanner,
                      label: 'Browser pairing',
                      trailing: const Icon(Icons.chevron_right, size: 20),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => BrowserPairingScreen(wallet: widget.wallet)),
                      ),
                    ),
                    _buildRow(
                      icon: Icons.memory,
                      label: 'Mesh compute',
                      trailing: const Icon(Icons.chevron_right, size: 20),
                      subtitle: 'Earn GNS while idle',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => HiveWorkerScreen(wallet: widget.wallet)),
                      ),
                    ),
                    _buildRow(
                      icon: Icons.file_download_outlined,
                      label: 'Export trajectory',
                      trailing: const Icon(Icons.chevron_right, size: 20),
                      onTap: _exportTrajectory,
                    ),
                    _buildRow(
                      icon: Icons.bug_report_outlined,
                      label: 'Debug',
                      trailing: const Icon(Icons.chevron_right, size: 20),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const DebugScreen()),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 24),

                  // ── Danger zone ──
                  _buildSection('', [
                    _buildRow(
                      icon: Icons.logout,
                      label: 'Delete identity',
                      isDestructive: true,
                      trailing: const Icon(Icons.chevron_right, size: 20),
                      onTap: _confirmDeleteIdentity,
                    ),
                  ]),

                  const SizedBox(height: 24),

                  // ── Version ──
                  Center(
                    child: Text(
                      'Globe Crumbs v1.0.0',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textMuted(context).withOpacity(0.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  // ==================== PROFILE HEADER ====================

  Widget _buildProfileHeader() {
    final emoji = TierInfo.tierEmoji(_stats.currentTier);
    final memberSince = _stats.firstBreadcrumbAt != null
        ? _formatDate(_stats.firstBreadcrumbAt!)
        : 'Just joined';

    return Column(
      children: [
        // Avatar circle
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.primary.withOpacity(0.1),
            border: Border.all(color: AppTheme.primary.withOpacity(0.3), width: 2),
          ),
          child: Center(
            child: Text(
              _identity?.displayName?.isNotEmpty == true
                  ? _identity!.displayName![0].toUpperCase()
                  : (_handle?.isNotEmpty == true ? _handle![0].toUpperCase() : '?'),
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w700,
                color: AppTheme.primary,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Handle
        if (_handle != null)
          Text(
            '@$_handle',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary(context),
            ),
          ),
        const SizedBox(height: 4),

        // Tier + crumbs
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 4),
            Text(
              '${_stats.currentTier} — ${_stats.totalBreadcrumbs} crumbs',
              style: TextStyle(
                fontSize: 14,
                color: AppTheme.textSecondary(context),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),

        // Member since
        Text(
          'Since $memberSince',
          style: TextStyle(
            fontSize: 12,
            color: AppTheme.textMuted(context),
          ),
        ),
      ],
    );
  }

  // ==================== SECTION BUILDER ====================

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title.isNotEmpty) ...[
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.5,
              color: AppTheme.textMuted(context),
            ),
          ),
          const SizedBox(height: 10),
        ],
        Container(
          decoration: BoxDecoration(
            color: AppTheme.surface(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.border(context)),
          ),
          child: Column(
            children: [
              for (int i = 0; i < children.length; i++) ...[
                children[i],
                if (i < children.length - 1)
                  Divider(
                    height: 1,
                    indent: 52,
                    color: AppTheme.border(context),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRow({
    required IconData icon,
    required String label,
    Widget? trailing,
    String? subtitle,
    VoidCallback? onTap,
    bool isDestructive = false,
  }) {
    final color = isDestructive
        ? Colors.red
        : AppTheme.textPrimary(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 22, color: color.withOpacity(0.7)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: color,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textMuted(context),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }

  // ==================== ACTIONS ====================

  void _editProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProfileEditorScreen(
          wallet: widget.wallet,
          profileService: widget.profileService,
          onSaved: _loadData,
        ),
      ),
    );
  }

  void _viewKeys() {
    final pk = widget.wallet.publicKey;
    if (pk == null) return;

    showModalBottomSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your Identity Key',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Ed25519 public key',
              style: TextStyle(fontSize: 12, color: AppTheme.textMuted(ctx)),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.surfaceLight(ctx),
                borderRadius: BorderRadius.circular(10),
              ),
              child: SelectableText(
                pk,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: pk));
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Public key copied')),
                  );
                },
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('COPY'),
              ),
            ),
            SizedBox(height: MediaQuery.of(ctx).padding.bottom + 8),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteBreadcrumbs() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete all breadcrumbs?'),
        content: const Text(
          'This will permanently delete your entire trajectory history from this device. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              // TODO: call chain_storage.deleteAll() + refresh
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('DELETE ALL'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteIdentity() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete identity?'),
        content: const Text(
          'This will permanently delete your keypair and all data. You cannot recover this identity.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              widget.onIdentityDeleted();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('DELETE FOREVER'),
          ),
        ],
      ),
    );
  }

  Future<void> _exportTrajectory() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Export coming soon')),
    );
  }

  String _formatDate(DateTime dt) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                     'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[dt.month - 1]} ${dt.year}';
  }
}
