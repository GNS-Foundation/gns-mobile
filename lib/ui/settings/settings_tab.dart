/// Settings Tab
/// 
/// App settings including facets, payments, theme, identity management.
/// 
/// Location: lib/ui/settings/settings_tab.dart

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/gns/identity_wallet.dart';
import '../../core/profile/profile_facet.dart';
import '../../core/profile/facet_storage.dart';
import '../../core/financial/payment_service.dart';
import '../../core/theme/theme_service.dart';
import '../screens/facet_list_screen.dart';
import '../screens/facet_editor_screen.dart';
import '../screens/debug_screen.dart';
import '../financial/financial_settings_screen.dart';
import '../financial/transactions_screen.dart';

// ==================== SETTINGS TAB ====================

class SettingsTab extends StatefulWidget {
  final IdentityWallet wallet;
  final VoidCallback onIdentityDeleted;

  const SettingsTab({super.key, required this.wallet, required this.onIdentityDeleted});

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  List<ProfileFacet> _facets = [];
  final _facetStorage = FacetStorage();
  final _themeService = ThemeService();
  
  // NEW: Payment service for displaying endpoint count
  int _paymentEndpointCount = 0;

  @override
  void initState() {
    super.initState();
    _themeService.addListener(_onThemeChanged);
    _loadFacets();
    _loadPaymentInfo();  // NEW
  }

  @override
  void dispose() {
    _themeService.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadFacets() async {
    try {
      await _facetStorage.initialize();
      final facets = await _facetStorage.getAllFacets();
      if (mounted) {
        setState(() => _facets = facets);
      }
    } catch (e) {
      debugPrint('Error loading facets: $e');
    }
  }

  // NEW: Load payment endpoint count
  Future<void> _loadPaymentInfo() async {
    try {
      final paymentService = PaymentService.instance(widget.wallet);
      await paymentService.initialize();
      
      final financialData = paymentService.myFinancialData;
      if (mounted && financialData != null) {
        setState(() {
          _paymentEndpointCount = financialData.paymentEndpoints.length;
        });
      }
    } catch (e) {
      debugPrint('Error loading payment info: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildFacetsSection(),
          const SizedBox(height: 24),
          
          // ============ FINANCIAL SETTINGS ============
          _buildFinancialSection(),
          const SizedBox(height: 24),
          
          _buildThemeSection(),
          const SizedBox(height: 24),

          // 👇 ADD THIS DEBUG BUTTON HERE:
          Card(
            color: Colors.deepPurple.withOpacity(0.1),
            child: ListTile(
              leading: const Icon(Icons.bug_report, color: Colors.deepPurple),
              title: const Text('Developer Tools'),
              subtitle: const Text('Debug & publish GNS record'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const DebugScreen()),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          // 👆 END OF NEW CODE

          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.key),
                  title: const Text('Export Identity'),
                  subtitle: const Text('Backup your identity to another device'),
                  onTap: () => _exportIdentity(context),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.download),
                  title: const Text('Import Identity'),
                  subtitle: const Text('Restore from backup'),
                  onTap: () => _importIdentity(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.delete_forever, color: AppTheme.error),
              title: const Text('Delete Identity', style: TextStyle(color: AppTheme.error)),
              subtitle: const Text('This cannot be undone'),
              onTap: () => _deleteIdentity(context),
            ),
          ),
          const SizedBox(height: 24),
          _buildAboutSection(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildFacetsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Text('🎭', style: TextStyle(fontSize: 24)),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'PROFILE FACETS',
                          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
                        ),
                        Text(
                          'One identity, many faces',
                          style: TextStyle(color: AppTheme.textSecondary(context), fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
                TextButton(
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const FacetListScreen()),
                    );
                    _loadFacets();
                  },
                  child: const Text('MANAGE'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_facets.isEmpty)
              _buildEmptyFacetsState()
            else
              ..._facets.take(3).map((facet) => _buildFacetTile(facet)),
            if (_facets.length > 3)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Center(
                  child: TextButton(
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const FacetListScreen()),
                      );
                      _loadFacets();
                    },
                    child: Text(
                      '+${_facets.length - 3} more facets',
                      style: const TextStyle(color: AppTheme.primary),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyFacetsState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppTheme.surfaceLight(context),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Center(child: Text('👤', style: TextStyle(fontSize: 24))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Default Profile', style: TextStyle(fontWeight: FontWeight.w500)),
                Text(
                  'Tap MANAGE to create facets',
                  style: TextStyle(color: AppTheme.textSecondary(context), fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFacetTile(ProfileFacet facet) {
    final avatarImage = _getAvatarImage(facet.avatarUrl);
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.border(context)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: CircleAvatar(
          radius: 22,
          backgroundColor: _getFacetColor(facet.id).withOpacity(0.2),
          backgroundImage: avatarImage,
          child: avatarImage == null 
              ? Text(facet.emoji, style: const TextStyle(fontSize: 20))
              : null,
        ),
        title: Row(
          children: [
            Text(facet.label, style: const TextStyle(fontWeight: FontWeight.w500)),
            if (facet.isDefault) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.secondary,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'DEFAULT',
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
            ],
          ],
        ),
        subtitle: Text(
          facet.displayName ?? facet.label,
          style: TextStyle(color: AppTheme.textSecondary(context), fontSize: 12),
        ),
        trailing: Icon(Icons.chevron_right, color: AppTheme.textMuted(context)),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => FacetEditorScreen(existingFacet: facet),
            ),
          );
          _loadFacets();
        },
      ),
    );
  }

  ImageProvider? _getAvatarImage(String? avatarUrl) {
    if (avatarUrl == null || avatarUrl.isEmpty) return null;
    
    try {
      String base64Data;
      if (avatarUrl.contains(',')) {
        base64Data = avatarUrl.split(',').last;
      } else {
        base64Data = avatarUrl;
      }
      
      final bytes = base64Decode(base64Data);
      return MemoryImage(Uint8List.fromList(bytes));
    } catch (e) {
      debugPrint('Error decoding avatar: $e');
      return null;
    }
  }

  Color _getFacetColor(String id) {
    switch (id) {
      case 'work': return AppTheme.primary;
      case 'friends': return const Color(0xFFF97316);
      case 'family': return const Color(0xFFEC4899);
      case 'travel': return AppTheme.secondary;
      case 'creative': return AppTheme.accent;
      case 'gaming': return AppTheme.error;
      default: return AppTheme.textMuted(context);
    }
  }

  // ============ FINANCIAL SECTION ============
  Widget _buildFinancialSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.account_balance_wallet,
                        color: AppTheme.primary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'PAYMENTS',
                          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
                        ),
                        Text(
                          'Financial identity settings',
                          style: TextStyle(color: AppTheme.textSecondary(context), fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Payment endpoints tile
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceLight(context),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.credit_card,
                  color: AppTheme.textSecondary(context),
                  size: 20,
                ),
              ),
              title: const Text('Payment Methods'),
              subtitle: Text(
                _paymentEndpointCount == 0 
                    ? 'No endpoints configured'
                    : '$_paymentEndpointCount endpoint${_paymentEndpointCount == 1 ? '' : 's'} configured',
                style: TextStyle(
                  color: _paymentEndpointCount == 0 
                      ? AppTheme.warning 
                      : AppTheme.textMuted(context),
                  fontSize: 12,
                ),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const FinancialSettingsScreen()),
                );
                _loadPaymentInfo();  // Reload after returning
              },
            ),
            
            const Divider(height: 24),
            
            // Limits tile
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceLight(context),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.speed,
                  color: AppTheme.textSecondary(context),
                  size: 20,
                ),
              ),
              title: const Text('Limits & Preferences'),
              subtitle: Text(
                'Daily limits, auto-accept settings',
                style: TextStyle(color: AppTheme.textMuted(context), fontSize: 12),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const FinancialSettingsScreen()),
                );
              },
            ),
            
            const Divider(height: 24),
            
            // Transaction History tile
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceLight(context),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.receipt_long,
                  color: AppTheme.textSecondary(context),
                  size: 20,
                ),
              ),
              title: const Text('Transaction History'),
              subtitle: Text(
                'View all payments',
                style: TextStyle(color: AppTheme.textMuted(context), fontSize: 12),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const TransactionsScreen()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThemeSection() {
    final isDark = _themeService.isDark;
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isDark ? Icons.dark_mode : Icons.light_mode,
                  size: 24,
                  color: isDark ? Colors.amber : Colors.orange,
                ),
                const SizedBox(width: 12),
                const Text(
                  'APPEARANCE',
                  style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => _themeService.setThemeMode(ThemeMode.light),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: !isDark 
                            ? AppTheme.primary.withOpacity(0.15)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: !isDark ? AppTheme.primary : AppTheme.border(context),
                          width: !isDark ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.light_mode,
                            size: 32,
                            color: !isDark ? AppTheme.primary : AppTheme.textMuted(context),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Light',
                            style: TextStyle(
                              fontWeight: !isDark ? FontWeight.bold : FontWeight.normal,
                              color: !isDark ? AppTheme.primary : AppTheme.textSecondary(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () => _themeService.setThemeMode(ThemeMode.dark),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: isDark 
                            ? AppTheme.primary.withOpacity(0.15)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark ? AppTheme.primary : AppTheme.border(context),
                          width: isDark ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.dark_mode,
                            size: 32,
                            color: isDark ? AppTheme.primary : AppTheme.textMuted(context),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Dark',
                            style: TextStyle(
                              fontWeight: isDark ? FontWeight.bold : FontWeight.normal,
                              color: isDark ? AppTheme.primary : AppTheme.textSecondary(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAboutSection() {
    return Center(
      child: Column(
        children: [
          const Text('🌍', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 8),
          const Text(
            'Globe Crumbs',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          Text(
            'Identity through Presence',
            style: TextStyle(color: AppTheme.textSecondary(context)),
          ),
          const SizedBox(height: 4),
          Text(
            'v0.4.1 • Light/Dark Mode',
            style: TextStyle(color: AppTheme.textMuted(context), fontSize: 12),
          ),
        ],
      ),
    );
  }

  void _exportIdentity(BuildContext context) async {
    try {
      final data = await widget.wallet.exportIdentity();
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Export Identity'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Copy this code and save it securely:'),
              const SizedBox(height: 8),
              SelectableText(
                data,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 10),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: data));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Copied to clipboard')),
                );
              },
              child: const Text('COPY'),
            ),
          ],
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e')),
      );
    }
  }

  void _importIdentity(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import Identity'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Paste your backup code',
          ),
          maxLines: 4,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () async {
              try {
                await widget.wallet.importIdentity(controller.text.trim());
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Identity imported!')),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Import failed: $e')),
                );
              }
            },
            child: const Text('IMPORT'),
          ),
        ],
      ),
    );
  }

  void _deleteIdentity(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Identity?'),
        content: const Text(
          'This will permanently delete your identity, all breadcrumbs, and any claimed handles. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () async {
              await widget.wallet.deleteIdentity();
              Navigator.pop(dialogContext);
              widget.onIdentityDeleted();
            },
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
  }
}
