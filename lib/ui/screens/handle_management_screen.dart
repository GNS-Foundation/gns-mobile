/// Handle Management Screen - Phase 6 (v2)
/// 
/// Shows handle status, progress toward claiming, and claim button.
/// v2: Fixed mainnet account funding before trustline creation
/// 
/// Location: lib/ui/screens/handle_management_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/gns/identity_wallet.dart';
import '../../core/chain/breadcrumb_engine.dart';
import '../../core/theme/theme_service.dart';
import '../financial/stellar_service.dart';

class HandleManagementScreen extends StatefulWidget {
  final IdentityWallet wallet;
  
  const HandleManagementScreen({super.key, required this.wallet});
  
  @override
  State<HandleManagementScreen> createState() => _HandleManagementScreenState();
}

class _HandleManagementScreenState extends State<HandleManagementScreen> {
  IdentityInfo? _info;
  bool _loading = true;
  bool _claiming = false;
  String? _error;
  Timer? _refreshTimer;
  
  // Requirements
  static const int requiredBreadcrumbs = 100;
  static const double requiredTrust = 20.0;
  
  @override
  void initState() {
    super.initState();
    _loadInfo();
    // Refresh every 10 seconds to show live progress
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) => _loadInfo());
  }
  
  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }
  
  Future<void> _loadInfo() async {
    try {
      final info = await widget.wallet.getIdentityInfo();
      if (mounted) {
        setState(() {
          _info = info;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }
  
  Future<void> _claimHandle() async {
    if (_info?.reservedHandle == null) return;
    
    setState(() => _claiming = true);
    
    final result = await widget.wallet.claimHandle();
    
    if (mounted) {
      if (result.success) {
        // ✅ Set up Stellar wallet on successful claim!
        String walletStatus = '';
        try {
          final stellarService = StellarService();
          final publicKey = widget.wallet.publicKey;
          final privateKeyBytes = widget.wallet.privateKeyBytes;
          
          if (publicKey != null && privateKeyBytes != null) {
            final stellarPublicKey = stellarService.gnsKeyToStellar(publicKey);
            debugPrint('🚀 Setting up Stellar wallet: $stellarPublicKey');
            
            // ==================== STEP 1: Check if account exists ====================
            final exists = await stellarService.accountExists(stellarPublicKey);
            debugPrint('   Account exists: $exists');
            
            if (!exists) {
              // ==================== STEP 2: Fund the account ====================
              debugPrint('💰 Funding Stellar account...');
              
              final fundResult = await stellarService.fundAccount(stellarPublicKey);
              
              if (fundResult.success) {
                debugPrint('✅ Account funded! Hash: ${fundResult.hash}');
                
                // Wait for ledger to update
                await Future.delayed(const Duration(seconds: 3));
              } else {
                debugPrint('❌ Failed to fund account: ${fundResult.error}');
                walletStatus = ' (Wallet funding failed - contact support)';
                
                // Still continue to show success for handle claim
                setState(() => _claiming = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('${result.message ?? '@${result.handle} is yours!'}$walletStatus'),
                    backgroundColor: Colors.orange,
                    duration: const Duration(seconds: 4),
                  ),
                );
                await _loadInfo();
                return;
              }
            }
            
            // ==================== STEP 3: Create GNS trustline ====================
            final hasTrustline = await stellarService.hasGnsTrustline(stellarPublicKey);
            debugPrint('   Has GNS trustline: $hasTrustline');
            
            if (!hasTrustline) {
              debugPrint('📝 Creating GNS trustline...');
              final trustResult = await stellarService.createGnsTrustline(
                stellarPublicKey: stellarPublicKey,
                privateKeyBytes: privateKeyBytes,
              );
              
              if (trustResult.success) {
                debugPrint('✅ GNS trustline created! Hash: ${trustResult.hash}');
                walletStatus = ' GNS wallet ready!';
              } else {
                debugPrint('❌ Trustline error: ${trustResult.error}');
                walletStatus = ' (Trustline pending)';
              }
            } else {
              walletStatus = ' GNS wallet ready!';
            }
          }
        } catch (e) {
          debugPrint('❌ Stellar wallet setup error: $e');
          walletStatus = ' (Wallet setup error)';
          // Don't fail the claim if Stellar setup fails
        }
        
        setState(() => _claiming = false);
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${result.message ?? '@${result.handle} is yours!'}$walletStatus'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
        await _loadInfo();
      } else {
        setState(() => _claiming = false);
        // Show requirements dialog
        _showRequirementsDialog(result);
      }
    } else {
      setState(() => _claiming = false);
    }
  }
  
  void _showRequirementsDialog(HandleClaimResult result) {
    final req = result.requirements;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface(context),
        title: const Text('Requirements Not Met'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(result.error ?? 'You need to collect more breadcrumbs.'),
            if (req != null) ...[
              const SizedBox(height: 16),
              _RequirementRow(
                label: 'Breadcrumbs',
                current: req.breadcrumbsCurrent,
                required: req.breadcrumbsRequired,
                met: req.breadcrumbsMet,
              ),
              const SizedBox(height: 8),
              _RequirementRow(
                label: 'Trust Score',
                current: req.trustCurrent.toInt(),
                required: req.trustRequired.toInt(),
                met: req.trustMet,
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background(context),
      appBar: AppBar(
        backgroundColor: AppTheme.surface(context),
        title: const Text('Handle Management'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : _buildContent(),
    );
  }
  
  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 16),
          Text(_error!, style: TextStyle(color: AppTheme.textSecondary(context))),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadInfo,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
  
  Widget _buildContent() {
    final info = _info!;
    final hasClaimed = info.claimedHandle != null;
    final hasReserved = info.reservedHandle != null;
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status Card
          _buildStatusCard(info, hasClaimed, hasReserved),
          
          const SizedBox(height: 24),
          
          // Progress Card (only if reserved but not claimed)
          if (hasReserved && !hasClaimed)
            _buildProgressCard(info),
          
          const SizedBox(height: 24),
          
          // Identity Info Card
          _buildIdentityCard(info),
          
          const SizedBox(height: 24),
          
          // Actions
          if (hasReserved && !hasClaimed)
            _buildClaimButton(info),
        ],
      ),
    );
  }
  
  Widget _buildStatusCard(IdentityInfo info, bool hasClaimed, bool hasReserved) {
    return Card(
      color: AppTheme.surface(context),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  hasClaimed ? Icons.verified : (hasReserved ? Icons.pending : Icons.help_outline),
                  color: hasClaimed ? Colors.green : (hasReserved ? Colors.orange : Colors.grey),
                  size: 32,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasClaimed
                            ? '@${info.claimedHandle}'
                            : (hasReserved ? '@${info.reservedHandle}' : 'No Handle'),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        hasClaimed
                            ? 'Claimed & Verified'
                            : (hasReserved ? 'Reserved - Collecting breadcrumbs' : 'Reserve a handle to get started'),
                        style: TextStyle(
                          color: AppTheme.textSecondary(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildProgressCard(IdentityInfo info) {
    return Card(
      color: AppTheme.surface(context),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'CLAIM REQUIREMENTS',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 16),
            
            // Hint text
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.blue, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Collect breadcrumbs by moving around with the app open.',
                      style: TextStyle(
                        color: AppTheme.textSecondary(context),
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Breadcrumbs progress
            _ProgressRow(
              icon: Icons.location_on,
              label: 'Breadcrumbs',
              current: info.breadcrumbCount,
              required: requiredBreadcrumbs,
              color: Colors.blue,
            ),
            
            const SizedBox(height: 16),
            
            // Trust score progress
            _ProgressRow(
              icon: Icons.verified_user,
              label: 'Trust Score',
              current: info.trustScore.toInt(),
              required: requiredTrust.toInt(),
              color: Colors.purple,
            ),
            
            const SizedBox(height: 16),
            
            // Days active
            Row(
              children: [
                const Icon(Icons.calendar_today, size: 20, color: Colors.orange),
                const SizedBox(width: 8),
                Text(
                  'Days Active: ${info.daysSinceCreation}',
                  style: TextStyle(color: AppTheme.textSecondary(context)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildIdentityCard(IdentityInfo info) {
    return Card(
      color: AppTheme.surface(context),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'IDENTITY',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 16),
            
            _InfoRow(
              label: 'GNS ID',
              value: info.gnsId ?? 'Unknown',
              copyable: true,
            ),
            const Divider(height: 24),
            _InfoRow(
              label: 'Public Key',
              value: '${info.publicKey?.substring(0, 20)}...',
              copyable: true,
              fullValue: info.publicKey,
            ),
            const Divider(height: 24),
            Row(
              children: [
                Icon(
                  info.networkAvailable ? Icons.cloud_done : Icons.cloud_off,
                  size: 20,
                  color: info.networkAvailable ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                Text(
                  info.networkAvailable ? 'Connected to GNS Network' : 'Offline',
                  style: TextStyle(color: AppTheme.textSecondary(context)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildClaimButton(IdentityInfo info) {
    final canClaim = info.canClaimHandle;
    
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: canClaim && !_claiming ? _claimHandle : null,
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          backgroundColor: canClaim ? Colors.green : Colors.grey,
        ),
        child: _claiming
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(canClaim ? Icons.verified : Icons.lock),
                  const SizedBox(width: 8),
                  Text(
                    canClaim
                        ? 'CLAIM @${info.reservedHandle}'
                        : 'COLLECT MORE BREADCRUMBS',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

// Helper Widgets

class _ProgressRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final int current;
  final int required;
  final Color color;
  
  const _ProgressRow({
    required this.icon,
    required this.label,
    required this.current,
    required this.required,
    required this.color,
  });
  
  @override
  Widget build(BuildContext context) {
    final progress = (current / required).clamp(0.0, 1.0);
    final met = current >= required;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 8),
            Text(label),
            const Spacer(),
            Text(
              '$current / $required',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: met ? Colors.green : AppTheme.textPrimary(context),
              ),
            ),
            if (met) ...[
              const SizedBox(width: 4),
              const Icon(Icons.check_circle, size: 16, color: Colors.green),
            ],
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: progress,
          backgroundColor: Colors.grey.withOpacity(0.2),
          valueColor: AlwaysStoppedAnimation<Color>(met ? Colors.green : color),
        ),
      ],
    );
  }
}

class _RequirementRow extends StatelessWidget {
  final String label;
  final int current;
  final int required;
  final bool met;
  
  const _RequirementRow({
    required this.label,
    required this.current,
    required this.required,
    required this.met,
  });
  
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          met ? Icons.check_circle : Icons.cancel,
          size: 20,
          color: met ? Colors.green : Colors.red,
        ),
        const SizedBox(width: 8),
        Text('$label: $current / $required'),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool copyable;
  final String? fullValue;
  
  const _InfoRow({
    required this.label,
    required this.value,
    this.copyable = false,
    this.fullValue,
  });
  
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label:',
          style: TextStyle(
            color: AppTheme.textSecondary(context),
            fontSize: 14,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 14,
            ),
          ),
        ),
        if (copyable)
          IconButton(
            icon: const Icon(Icons.copy, size: 18),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: fullValue ?? value));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('$label copied!')),
              );
            },
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
      ],
    );
  }
}
