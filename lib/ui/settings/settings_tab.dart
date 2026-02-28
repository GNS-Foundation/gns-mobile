/// Settings Tab — Phase 1
/// 
/// Simplified: theme toggle, identity info, locked features preview,
/// debug, and danger zone. Facets, financial settings, org registration
/// hidden behind TierGate.
/// 
/// Location: lib/ui/settings/settings_tab.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/gns/identity_wallet.dart';
import '../../core/tier_gate.dart';
import '../../core/theme/theme_service.dart';
import '../screens/debug_screen.dart';

// ==================== SETTINGS TAB ====================

class SettingsTab extends StatefulWidget {
  final IdentityWallet wallet;
  final VoidCallback onIdentityDeleted;

  const SettingsTab({super.key, required this.wallet, required this.onIdentityDeleted});

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  final _themeService = ThemeService();
  final _tierGate = TierGate();
  String? _handle;

  @override
  void initState() {
    super.initState();
    _themeService.addListener(_onThemeChanged);
    _tierGate.addListener(_onTierChanged);
    _loadHandle();
  }

  @override
  void dispose() {
    _themeService.removeListener(_onThemeChanged);
    _tierGate.removeListener(_onTierChanged);
    super.dispose();
  }

  void _onThemeChanged() { if (mounted) setState(() {}); }
  void _onTierChanged() { if (mounted) setState(() {}); }

  Future<void> _loadHandle() async {
    final handle = await widget.wallet.getCurrentHandle();
    if (mounted) setState(() => _handle = handle);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0D1117) : const Color(0xFFF6F8FA),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          children: [
            // ==================== HEADER ====================
            Text(
              'Settings',
              style: TextStyle(
                fontSize: 28, fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _handle != null ? '@$_handle' : 'Manage your identity',
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
            ),
            const SizedBox(height: 24),

            // ==================== APPEARANCE ====================
            _buildSection('Appearance', isDark, [
              _buildThemeToggle(isDark),
            ]),
            const SizedBox(height: 16),

            // ==================== IDENTITY ====================
            _buildSection('Identity', isDark, [
              _buildInfoRow('Public Key', widget.wallet.publicKey ?? '', isDark, copyable: true),
              if (_handle != null)
                _buildInfoRow('Handle', '@$_handle', isDark),
              _buildInfoRow('Tier', '${_tierGate.currentTier.icon} ${_tierGate.currentTier.displayName}', isDark),
              _buildInfoRow('Breadcrumbs', '${_tierGate.breadcrumbCount}', isDark),
            ]),
            const SizedBox(height: 16),

            // ==================== LOCKED FEATURES ====================
            _buildLockedFeaturesSection(isDark),
            const SizedBox(height: 16),

            // ==================== TOOLS (Trailblazer only) ====================
            if (_tierGate.hasReached(FeatureTier.trailblazer))
            _buildSection('Tools', isDark, [
              _buildNavRow('Debug Console', Icons.bug_report_outlined, isDark, () {
                Navigator.push(context,
                  MaterialPageRoute(builder: (_) => DebugScreen()),
                );
              }),
            ]),
            const SizedBox(height: 16),

            // ==================== DANGER ZONE ====================
            _buildDangerZone(isDark),
            
            const SizedBox(height: 60),
          ],
        ),
      ),
    );
  }

  // ==================== SECTION BUILDER ====================

  Widget _buildSection(String title, bool isDark, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF161B22) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.border(context)),
          ),
          child: Column(
            children: children.asMap().entries.map((entry) {
              final isLast = entry.key == children.length - 1;
              return Column(
                children: [
                  entry.value,
                  if (!isLast) Divider(height: 1, indent: 16, endIndent: 16, color: AppTheme.border(context)),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  // ==================== THEME TOGGLE ====================

  Widget _buildThemeToggle(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(isDark ? Icons.dark_mode : Icons.light_mode,
            size: 20, color: isDark ? Colors.white60 : Colors.black54),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Dark Mode',
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ),
          Switch.adaptive(
            value: _themeService.themeMode == ThemeMode.dark,
            onChanged: (val) {
              _themeService.setThemeMode(val ? ThemeMode.dark : ThemeMode.light);
            },
            activeColor: Color(_tierGate.currentTier.colorValue),
          ),
        ],
      ),
    );
  }

  // ==================== INFO ROW ====================

  Widget _buildInfoRow(String label, String value, bool isDark, {bool copyable = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Text(label, style: TextStyle(
            fontSize: 14, color: isDark ? Colors.white60 : Colors.black54,
          )),
          const Spacer(),
          Flexible(
            child: GestureDetector(
              onTap: copyable ? () {
                Clipboard.setData(ClipboardData(text: value));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('$label copied'), duration: const Duration(seconds: 1)),
                );
              } : null,
              child: Text(
                value.length > 20 ? '${value.substring(0, 8)}...${value.substring(value.length - 8)}' : value,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  fontFamily: copyable ? 'monospace' : null,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          if (copyable) ...[
            const SizedBox(width: 6),
            Icon(Icons.copy, size: 14, color: isDark ? Colors.white30 : Colors.black26),
          ],
        ],
      ),
    );
  }

  // ==================== NAV ROW ====================

  Widget _buildNavRow(String label, IconData icon, bool isDark, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: isDark ? Colors.white60 : Colors.black54),
            const SizedBox(width: 12),
            Text(label, style: TextStyle(
              fontSize: 14, color: isDark ? Colors.white : Colors.black87,
            )),
            const Spacer(),
            Icon(Icons.chevron_right, size: 20, color: isDark ? Colors.white.withValues(alpha: 0.2) : Colors.black.withValues(alpha: 0.2)),
          ],
        ),
      ),
    );
  }

  // ==================== LOCKED FEATURES ====================

  Widget _buildLockedFeaturesSection(bool isDark) {
    final locked = _tierGate.lockedFeatures;
    if (locked.isEmpty) return const SizedBox.shrink();

    // Group by tier
    final byTier = <FeatureTier, List<GnsFeature>>{};
    for (final f in locked) {
      byTier.putIfAbsent(f.requiredTier, () => []).add(f);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'COMING SOON',
            style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ),
        ),
        ...byTier.entries.map((entry) {
          final tier = entry.key;
          final features = entry.value;
          final tierColor = Color(tier.colorValue);
          final remaining = _tierGate.breadcrumbsUntil(tier);
          
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF161B22) : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: tierColor.withOpacity(0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(tier.icon, style: const TextStyle(fontSize: 16)),
                    const SizedBox(width: 6),
                    Text(
                      tier.displayName,
                      style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700,
                        color: tierColor,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '$remaining breadcrumbs to go',
                      style: TextStyle(
                        fontSize: 11, color: isDark ? Colors.white30 : Colors.black26,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: features.map((f) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: tierColor.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock, size: 10, color: tierColor.withOpacity(0.5)),
                        const SizedBox(width: 4),
                        Text(
                          f.displayName,
                          style: TextStyle(fontSize: 11, color: tierColor),
                        ),
                      ],
                    ),
                  )).toList(),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  // ==================== DANGER ZONE ====================

  Widget _buildDangerZone(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'DANGER ZONE',
            style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: Colors.red.shade300,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF161B22) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.red.withOpacity(0.2)),
          ),
          child: InkWell(
            onTap: _confirmDeleteIdentity,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Icon(Icons.delete_forever, size: 20, color: Colors.red.shade400),
                  const SizedBox(width: 12),
                  Text(
                    'Delete Identity',
                    style: TextStyle(fontSize: 14, color: Colors.red.shade400),
                  ),
                  const Spacer(),
                  Icon(Icons.chevron_right, size: 20, color: Colors.red.shade200),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmDeleteIdentity() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Identity?'),
        content: const Text(
          'This will permanently delete your Ed25519 keypair, all breadcrumbs, '
          'and local data. This action cannot be undone.\n\n'
          'Your @handle and on-chain records will remain but become inaccessible.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete Forever'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await widget.wallet.deleteIdentity();
      widget.onIdentityDeleted();
    }
  }
}
