/// Home Tab — Phase 1
/// 
/// Simplified: identity card, breadcrumb status, handle progress,
/// and extension pairing CTA. Payments, tokens, and search removed
/// (gated behind TierGate for later phases).
/// 
/// Location: lib/ui/home/home_tab.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/gns/identity_wallet.dart';
import '../../core/chain/breadcrumb_engine.dart';
import '../../core/profile/profile_service.dart';
import '../../core/profile/identity_view_data.dart';
import '../../core/tier/tier_gate.dart';
import '../../core/theme/theme_service.dart';
import '../widgets/identity_card.dart';
import '../screens/handle_management_screen.dart';
import '../screens/browser_pairing_screen.dart';

// ==================== HOME TAB ====================

class HomeTab extends StatefulWidget {
  final IdentityWallet wallet;
  final ProfileService profileService;

  const HomeTab({
    super.key,
    required this.wallet,
    required this.profileService,
  });

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  IdentityViewData? _myIdentity;
  bool _isLoading = true;
  final _tierGate = TierGate();

  @override
  void initState() {
    super.initState();
    _loadData();
    widget.wallet.breadcrumbEngine.onBreadcrumbDropped = (_) async {
      await Future.delayed(const Duration(milliseconds: 100));
      _loadData();
    };
  }

  Future<void> _loadData() async {
    final identity = await widget.profileService.getMyIdentity();
    if (mounted) {
      setState(() {
        _myIdentity = identity;
        _isLoading = false;
      });
      if (identity != null) {
        _tierGate.updateCount(identity.breadcrumbCount);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tierColor = Color(_tierGate.currentTier.colorValue);
    
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0D1117) : const Color(0xFFF6F8FA),
      body: SafeArea(
        child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                children: [
                  // ==================== HEADER ====================
                  _buildHeader(isDark),
                  const SizedBox(height: 20),
                  
                  // ==================== IDENTITY CARD ====================
                  if (_myIdentity != null)
                    IdentityCard(identity: _myIdentity!),
                  const SizedBox(height: 20),
                  
                  // ==================== HANDLE STATUS ====================
                  _buildHandleCard(isDark, tierColor),
                  const SizedBox(height: 16),
                  
                  // ==================== BREADCRUMB STATUS ====================
                  _buildBreadcrumbStatus(isDark, tierColor),
                  const SizedBox(height: 16),
                  
                  // ==================== EXTENSION PAIRING ====================
                  _buildExtensionPairingCard(isDark),
                  const SizedBox(height: 16),
                  
                  // ==================== PUBLIC KEY ====================
                  _buildPublicKeyCard(isDark),
                  
                  const SizedBox(height: 40),
                ],
              ),
            ),
      ),
    );
  }

  // ==================== HEADER ====================

  Widget _buildHeader(bool isDark) {
    final handle = _myIdentity?.handle;
    return Row(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              handle != null ? '@$handle' : 'Globe Crumbs',
              style: TextStyle(
                fontSize: 24, fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            Text(
              'Identity through Presence',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
            ),
          ],
        ),
        const Spacer(),
        // Tier badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Color(_tierGate.currentTier.colorValue).withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_tierGate.currentTier.icon, style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 4),
              Text(
                _tierGate.currentTier.displayName,
                style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700,
                  color: Color(_tierGate.currentTier.colorValue),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ==================== HANDLE STATUS CARD ====================

  Widget _buildHandleCard(bool isDark, Color tierColor) {
    final info = _myIdentity;
    if (info == null) return const SizedBox.shrink();
    
    final hasHandle = info.handle != null;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161B22) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                hasHandle ? Icons.alternate_email : Icons.pending_outlined,
                size: 18,
                color: hasHandle ? tierColor : Colors.amber,
              ),
              const SizedBox(width: 8),
              Text(
                hasHandle ? '@${info.handle}' : '@handle',
                style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const Spacer(),
              if (hasHandle)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: tierColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Reserved',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: tierColor),
                  ),
                ),
            ],
          ),
          
          if (!hasHandle) ...[
            const SizedBox(height: 10),
            Text(
              'Reserve your @handle — it will activate at Explorer tier (50 breadcrumbs)',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  Navigator.push(context,
                    MaterialPageRoute(builder: (_) => HandleManagementScreen(wallet: widget.wallet)),
                  );
                },
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: tierColor),
                  foregroundColor: tierColor,
                ),
                child: const Text('Reserve @Handle'),
              ),
            ),
          ],
          
          if (hasHandle && !_tierGate.hasReached(FeatureTier.explorer)) ...[
            const SizedBox(height: 8),
            // Progress to activation
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: info.breadcrumbCount / 50,
                      backgroundColor: isDark ? Colors.white10 : Colors.black.withOpacity(0.06),
                      color: tierColor,
                      minHeight: 6,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '${info.breadcrumbCount}/50',
                  style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Collect ${50 - info.breadcrumbCount} more breadcrumbs to activate',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white30 : Colors.black26,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ==================== BREADCRUMB STATUS ====================

  Widget _buildBreadcrumbStatus(bool isDark, Color tierColor) {
    final info = _myIdentity;
    if (info == null) return const SizedBox.shrink();
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161B22) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border(context)),
      ),
      child: Column(
        children: [
          _buildStatRow('Breadcrumbs', '${info.breadcrumbCount}', isDark),
          const Divider(height: 20),
          _buildStatRow('Trust Score', '${info.trustScore.toStringAsFixed(0)}%', isDark),
          const Divider(height: 20),
          _buildStatRow('Identity Age', '${info.daysSinceCreation} days', isDark),
          const Divider(height: 20),
          _buildStatRow('Chain Valid', info.chainValid ? '✅ Yes' : '❌ No', isDark),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value, bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(
          fontSize: 14, color: isDark ? Colors.white60 : Colors.black54,
        )),
        Text(value, style: TextStyle(
          fontSize: 14, fontWeight: FontWeight.w700,
          color: isDark ? Colors.white : Colors.black87,
        )),
      ],
    );
  }

  // ==================== EXTENSION PAIRING ====================

  Widget _buildExtensionPairingCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1A3C5E).withOpacity(isDark ? 0.4 : 0.08),
            const Color(0xFF1A3C5E).withOpacity(isDark ? 0.2 : 0.03),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1A3C5E).withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF1A3C5E).withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.extension, color: Color(0xFF1A3C5E), size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'GNS Vault Extension',
                  style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Pair with Chrome to verify sites and auto-fill',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () {
              Navigator.push(context,
                MaterialPageRoute(builder: (_) => BrowserPairingScreen(wallet: widget.wallet)),
              );
            },
            icon: const Icon(Icons.qr_code, color: Color(0xFF1A3C5E)),
          ),
        ],
      ),
    );
  }

  // ==================== PUBLIC KEY ====================

  Widget _buildPublicKeyCard(bool isDark) {
    final pk = widget.wallet.publicKey ?? '';
    if (pk.isEmpty) return const SizedBox.shrink();
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161B22) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PUBLIC KEY',
            style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: pk));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Public key copied'), duration: Duration(seconds: 1)),
              );
            },
            child: Text(
              pk,
              style: TextStyle(
                fontSize: 11, fontFamily: 'monospace',
                color: isDark ? Colors.white54 : Colors.black45,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Tap to copy • Ed25519 (RFC 8032)',
            style: TextStyle(
              fontSize: 10,
              color: isDark ? Colors.white.withValues(alpha: 0.2) : Colors.black.withValues(alpha: 0.2),
            ),
          ),
        ],
      ),
    );
  }
}
