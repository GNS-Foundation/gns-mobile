/// Settings Tab - Updated for Meta-Identity Architecture
/// 
/// Shows me@ as the primary editable facet with user's profile photo.
/// Displays broadcast facets (DIX) with special badges.
/// 
/// Location: lib/ui/settings/settings_tab.dart

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/gns/identity_wallet.dart';
import '../../core/profile/profile_facet.dart';
import '../../core/profile/facet_storage.dart';
import '../../core/profile/profile_module.dart';
import '../../core/financial/payment_service.dart';
import '../../core/theme/theme_service.dart';
import '../screens/facet_list_screen.dart';
import '../screens/facet_editor_screen.dart';
import '../screens/debug_screen.dart';
import '../financial/financial_settings_screen.dart';
import '../financial/transactions_screen.dart';
import '../messages/broadcast_screen.dart';
import '../screens/org_registration_screen.dart';  // 🏢 Organization Registration

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
  ProfileFacet? _defaultFacet;
  final _facetStorage = FacetStorage();
  final _themeService = ThemeService();
  
  int _paymentEndpointCount = 0;
  String? _handle;

  /// Get the user's handle
  String get _userHandle => _handle ?? 'you';

  @override
  void initState() {
    super.initState();
    _themeService.addListener(_onThemeChanged);
    _loadHandle();
    _loadFacets();
    _loadPaymentInfo();
  }

  Future<void> _loadHandle() async {
    final handle = await widget.wallet.getCurrentHandle();
    if (handle == null) {
      // Fall back to getIdentityInfo for reserved handle
      final info = await widget.wallet.getIdentityInfo();
      if (mounted) {
        setState(() {
          _handle = info.claimedHandle ?? info.reservedHandle;
        });
      }
    } else if (mounted) {
      setState(() {
        _handle = handle;
      });
    }
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
      
      // Migrate profile data to me@ facet if needed
      final profileData = widget.wallet.getProfile();
      await _facetStorage.migrateFromProfileData(profileData);
      
      final facets = await _facetStorage.getAllFacets();
      final defaultFacet = await _facetStorage.getDefaultFacet();
      
      if (mounted) {
        setState(() {
          _facets = facets;
          _defaultFacet = defaultFacet;
        });
      }
    } catch (e) {
      debugPrint('Error loading facets: $e');
    }
  }

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
          
          _buildFinancialSection(),
          const SizedBox(height: 24),
          
          _buildThemeSection(),
          const SizedBox(height: 24),

          // 🏢 Organization Registration
          Card(
            child: ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.purple.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.business, color: Colors.purple),
              ),
              title: const Text('Register Organization'),
              subtitle: const Text('Claim your namespace@ with DNS verification'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const OrgRegistrationScreen()),
                );
              },
            ),
          ),
          const SizedBox(height: 16),

          Card(
            color: Colors.deepPurple.withValues(alpha: 0.1),
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

          // 🏠 Home Hub Pairing (Coming Soon - replaces dangerous key export)
          Card(
            child: ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.teal.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.home, color: Colors.teal),
              ),
              title: const Text('Home Hub Pairing'),
              subtitle: const Text('Sync identity to Raspberry Pi, TV, or backup device'),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Coming Soon',
                  style: TextStyle(fontSize: 11, color: Colors.orange, fontWeight: FontWeight.w600),
                ),
              ),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('🏠 Home Hub pairing coming soon! Securely sync your identity to trusted devices.'),
                  ),
                );
              },
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
    // Separate default, custom, and broadcast facets
    final defaultFacet = _defaultFacet;
    final customFacets = _facets.where((f) => f.isCustom).toList();
    final broadcastFacets = _facets.where((f) => f.isBroadcast).toList();
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    // Show user's avatar if available
                    if (defaultFacet?.avatarUrl != null)
                      CircleAvatar(
                        radius: 16,
                        backgroundImage: _getAvatarImage(defaultFacet!.avatarUrl),
                        child: _getAvatarImage(defaultFacet.avatarUrl) == null
                            ? const Text('🎭', style: TextStyle(fontSize: 16))
                            : null,
                      )
                    else
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
            
            // Default "me@" facet - always first and prominent
            if (defaultFacet != null)
              _buildDefaultFacetTile(defaultFacet),
            
            // Broadcast facets (DIX, etc.) - with special styling
            if (broadcastFacets.isNotEmpty) ...[
              const SizedBox(height: 12),
              ...broadcastFacets.map((facet) => _buildBroadcastFacetTile(facet)),
            ],
            
            // Custom facets
            if (customFacets.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...customFacets.take(2).map((facet) => _buildFacetTile(facet)),
            ],
            
            // Show more link
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

  /// Default "me@" facet - primary personal facet
  Widget _buildDefaultFacetTile(ProfileFacet facet) {
    final avatarImage = _getAvatarImage(facet.avatarUrl);
    final handle = _userHandle;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primary.withValues(alpha: 0.1),
            AppTheme.primary.withValues(alpha: 0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        leading: CircleAvatar(
          radius: 26,
          backgroundColor: AppTheme.primary.withValues(alpha: 0.2),
          backgroundImage: avatarImage,
          child: avatarImage == null 
              ? Text(facet.emoji, style: const TextStyle(fontSize: 24))
              : null,
        ),
        title: Row(
          children: [
            Text(
              '#${facet.id}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.primary,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'DEFAULT',
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              facet.displayName ?? 'Your personal facet',
              style: TextStyle(color: AppTheme.textSecondary(context), fontSize: 13),
            ),
            const SizedBox(height: 2),
            Text(
              '${facet.id}@$handle',
              style: TextStyle(
                color: AppTheme.textMuted(context), 
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
        trailing: Icon(Icons.chevron_right, color: AppTheme.primary.withValues(alpha: 0.7)),
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

  /// Broadcast facet tile (DIX-style) with special styling
  Widget _buildBroadcastFacetTile(ProfileFacet facet) {
    final avatarImage = _getAvatarImage(facet.avatarUrl);
    final handle = _userHandle;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF8B5CF6).withValues(alpha: 0.1),
            const Color(0xFFEC4899).withValues(alpha: 0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.3)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: CircleAvatar(
          radius: 24,
          backgroundColor: const Color(0xFF8B5CF6).withValues(alpha: 0.2),
          backgroundImage: avatarImage,
          child: avatarImage == null 
              ? Text(facet.emoji, style: const TextStyle(fontSize: 22))
              : null,
        ),
        title: Row(
          children: [
            Text(
              '#${facet.id}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF8B5CF6), Color(0xFFEC4899)],
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.campaign, size: 10, color: Colors.white),
                  SizedBox(width: 3),
                  Text(
                    'BROADCAST',
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ],
              ),
            ),
          ],
        ),
        subtitle: Text(
          '${facet.id}@$handle',
          style: TextStyle(
            color: AppTheme.textMuted(context), 
            fontSize: 11,
            fontFamily: 'monospace',
          ),
        ),
        trailing: Icon(Icons.chevron_right, color: const Color(0xFF8B5CF6).withValues(alpha: 0.7)),
        onTap: () async {
          // Open BroadcastScreen for DIX facets
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => BroadcastScreen(
                facet: facet,
                wallet: widget.wallet,
              ),
            ),
          );
          _loadFacets();
        },
      ),
    );
  }

  /// Regular custom facet tile
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
          backgroundColor: _getFacetColor(facet.id).withValues(alpha: 0.2),
          backgroundImage: avatarImage,
          child: avatarImage == null 
              ? Text(facet.emoji, style: const TextStyle(fontSize: 20))
              : null,
        ),
        title: Text(
          '#${facet.id}',
          style: const TextStyle(fontWeight: FontWeight.w500),
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
      case 'me': return AppTheme.primary;
      case 'work': return const Color(0xFF3B82F6);
      case 'friends': return const Color(0xFFF97316);
      case 'family': return const Color(0xFFEC4899);
      case 'travel': return AppTheme.secondary;
      case 'creative': return AppTheme.accent;
      case 'gaming': return AppTheme.error;
      case 'dix': return const Color(0xFF8B5CF6);
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
                        color: AppTheme.primary.withValues(alpha: 0.1),
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
                _loadPaymentInfo();
              },
            ),
            
            const Divider(height: 24),
            
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
                            ? AppTheme.primary.withValues(alpha: 0.15)
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
                            ? AppTheme.primary.withValues(alpha: 0.15)
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
            'v0.5.0 • Meta-Identity Architecture',
            style: TextStyle(color: AppTheme.textMuted(context), fontSize: 12),
          ),
        ],
      ),
    );
  }

  // NOTE: Export/Import Identity functions removed for security.
  // Raw key export is dangerous - anyone with the key IS you.
  // Future: Home Hub secure pairing via local network/Bluetooth/NFC

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
