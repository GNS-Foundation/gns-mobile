/// Home Tab
/// 
/// Main home screen with identity card, breadcrumb controls, search, 
/// handle progress, GNS tokens, and payments card.
/// 
/// Location: lib/ui/home/home_tab.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/gns/identity_wallet.dart';
import '../../core/chain/breadcrumb_engine.dart';
import '../../core/profile/profile_service.dart';
import '../../core/profile/profile_module.dart';
import '../../core/profile/identity_view_data.dart';
import '../../core/profile/profile_facet.dart';
import '../../core/financial/payment_service.dart';
import '../../core/financial/transaction_storage.dart';
import '../../core/theme/theme_service.dart';
import '../../services/stellar_service.dart';
import '../widgets/identity_card.dart';
import '../widgets/gns_search_bar.dart';
import '../widgets/share_facet_picker.dart';
import '../profile/profile_editor_screen.dart';
import '../profile/identity_viewer_screen.dart';
import '../screens/gns_token_screen.dart';
import '../screens/handle_management_screen.dart';
import '../financial/send_money_screen.dart';
import '../financial/transactions_screen.dart';
import '../financial/financial_hub_screen.dart';

// ==================== HOME TAB ====================

class HomeTab extends StatefulWidget {
  final IdentityWallet wallet;
  final ProfileService profileService;
  final PaymentService? paymentService;

  const HomeTab({
    super.key,
    required this.wallet,
    required this.profileService,
    this.paymentService,
  });

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  IdentityViewData? _myIdentity;
  final _searchController = TextEditingController();
  bool _isLoading = true;
  
  // Payment data
  double _todaySent = 0;
  double _todayReceived = 0;
  int _pendingCount = 0;
  List<GnsTransaction> _recentTransactions = [];
  
  // GNS Token data
  final _stellar = StellarService();
  double _gnsBalance = 0;
  double _gnsClaimable = 0;
  bool _gnsLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadData();
    widget.wallet.breadcrumbEngine.onBreadcrumbDropped = (_) => _loadData();
  }

  Future<void> _loadData() async {
    final identity = await widget.profileService.getMyIdentity();
    
    // Load payment data if available
    if (widget.paymentService != null) {
      try {
        final sent = await widget.paymentService!.getTotalSentToday(currency: 'EUR');
        final received = await widget.paymentService!.getTotalReceivedToday(currency: 'EUR');
        final pending = await widget.paymentService!.getPendingIncoming();
        final txs = await widget.paymentService!.getTransactions(limit: 3);
        
        if (mounted) {
          setState(() {
            _todaySent = sent;
            _todayReceived = received;
            _pendingCount = pending.length;
            _recentTransactions = txs;
          });
        }
      } catch (e) {
        debugPrint('Payment data error: $e');
      }
    }
    
    // Load GNS token balance
    await _loadGnsBalance();
    
    if (mounted) {
      setState(() {
        _myIdentity = identity;
        _isLoading = false;
      });
    }
  }
  
  Future<void> _loadGnsBalance() async {
    try {
      final publicKey = widget.wallet.publicKey;
      if (publicKey == null) return;
      
      final stellarAddress = _stellar.gnsKeyToStellar(publicKey);
      final exists = await _stellar.accountExists(stellarAddress);
      
      if (exists) {
        final balance = await _stellar.getGnsBalance(stellarAddress);
        final claimable = await _stellar.getGnsClaimableBalances(stellarAddress);
        final claimableTotal = claimable.fold<double>(
          0.0, (sum, cb) => sum + (double.tryParse(cb.amount) ?? 0));
        
        if (mounted) {
          setState(() {
            _gnsBalance = balance;
            _gnsClaimable = claimableTotal;
            _gnsLoaded = true;
          });
        }
      } else {
        // Check for claimable even without account
        final claimable = await _stellar.getGnsClaimableBalances(stellarAddress);
        final claimableTotal = claimable.fold<double>(
          0.0, (sum, cb) => sum + (double.tryParse(cb.amount) ?? 0));
        
        if (mounted) {
          setState(() {
            _gnsBalance = 0;
            _gnsClaimable = claimableTotal;
            _gnsLoaded = true;
          });
        }
      }
    } catch (e) {
      debugPrint('GNS balance error: $e');
      if (mounted) {
        setState(() => _gnsLoaded = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'GLOBE CRUMBS',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: _shareIdentity,
            tooltip: 'Share Identity',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // 1. Identity Card
                  if (_myIdentity != null) 
                    IdentityCard(
                      identity: _myIdentity!,
                      onEdit: _editProfile,
                    ),
                  const SizedBox(height: 16),
                  
                  // 2. Breadcrumb Collection (core GNS action - moved up)
                  _buildQuickActions(),
                  const SizedBox(height: 16),
                  
                  // 3. Search Bar
                  GnsSearchBar(
                    controller: _searchController,
                    onSearch: _search,
                  ),
                  const SizedBox(height: 16),
                  
                  // 4. Handle Card (progress/claimed)
                  _buildHandleCard(),
                  const SizedBox(height: 16),
                  
                  // 5. GNS Token Card (NEW!)
                  _buildGnsTokenCard(),
                  const SizedBox(height: 16),
                  
                  // 6. Payments Card (secondary feature - at bottom)
                  _buildPaymentsCard(),
                  
                  const SizedBox(height: 24),
                ],
              ),
      ),
    );
  }

  // ============ GNS TOKEN CARD ============
  Widget _buildGnsTokenCard() {
    final hasClaimable = _gnsClaimable > 0;
    
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF4CAF50).withOpacity(0.15),
            const Color(0xFF2196F3).withOpacity(0.1),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border(context)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const GnsTokenScreen()),
            ).then((_) => _loadGnsBalance());
          },
          borderRadius: BorderRadius.circular(16),
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
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF4CAF50), Color(0xFF2196F3)],
                            ),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Center(
                            child: Text(
                              'G',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'GNS TOKENS',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                            color: AppTheme.textPrimary(context),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        // Claimable badge
                        if (hasClaimable)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              color: Colors.amber,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${_gnsClaimable.toStringAsFixed(0)} claimable',
                              style: const TextStyle(
                                color: Colors.black,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        Icon(Icons.chevron_right, color: AppTheme.textMuted(context)),
                      ],
                    ),
                  ],
                ),
                
                const SizedBox(height: 16),
                
                // Balance Display
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _gnsLoaded ? _gnsBalance.toStringAsFixed(2) : '...',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary(context),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        'GNS',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.textSecondary(context),
                        ),
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 8),
                
                Text(
                  'Tap to view wallet',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textMuted(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ============ PAYMENTS CARD ============
  Widget _buildPaymentsCard() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primary.withOpacity(0.15),
            AppTheme.secondary.withOpacity(0.1),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border(context)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const FinancialHubScreen()),
            );
          },
          borderRadius: BorderRadius.circular(16),
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
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.account_balance_wallet, 
                            color: AppTheme.primary, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'PAYMENTS',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                            color: AppTheme.textPrimary(context),
                          ),
                        ),
                      ],
                    ),
                    // Pending badge
                    if (_pendingCount > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.warning,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '$_pendingCount pending',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    Icon(Icons.chevron_right, color: AppTheme.textMuted(context)),
                  ],
                ),
                
                const SizedBox(height: 16),
                
                // Today's Activity
                Row(
                  children: [
                    Expanded(
                      child: _buildActivityStat(
                        icon: Icons.arrow_upward,
                        iconColor: AppTheme.error,
                        label: 'Sent Today',
                        value: '€${_todaySent.toStringAsFixed(2)}',
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 40,
                      color: AppTheme.border(context),
                    ),
                    Expanded(
                      child: _buildActivityStat(
                        icon: Icons.arrow_downward,
                        iconColor: AppTheme.secondary,
                        label: 'Received',
                        value: '€${_todayReceived.toStringAsFixed(2)}',
                      ),
                    ),
                  ],
                ),
                
                // Quick send button row
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const SendMoneyScreen()),
                          );
                        },
                        icon: const Icon(Icons.send, size: 18),
                        label: const Text('Send'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.primary,
                          side: BorderSide(color: AppTheme.primary.withOpacity(0.5)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const TransactionsScreen()),
                          );
                        },
                        icon: const Icon(Icons.history, size: 18),
                        label: const Text('History'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.primary,
                          side: BorderSide(color: AppTheme.primary.withOpacity(0.5)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
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

  Widget _buildActivityStat({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 16),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: AppTheme.textMuted(context),
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHandleCard() {
    return FutureBuilder<IdentityInfo>(
      future: widget.wallet.getIdentityInfo(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        
        final info = snapshot.data!;
        
        if (info.claimedHandle != null) {
          return Card(
            child: InkWell(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => HandleManagementScreen(wallet: widget.wallet),
                ),
              ),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    const Text('✓', style: TextStyle(fontSize: 24, color: AppTheme.secondary)),
                    const SizedBox(width: 12),
                    Text(
                      '@${info.claimedHandle}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.secondary,
                      ),
                    ),
                    const Spacer(),
                    const Text('CLAIMED', style: TextStyle(color: AppTheme.secondary)),
                    const SizedBox(width: 8),
                    Icon(Icons.chevron_right, color: AppTheme.textMuted(context)),
                  ],
                ),
              ),
            ),
          );
        }
        
        if (info.reservedHandle != null) {
          final remaining = 100 - info.breadcrumbCount;
          return Card(
            child: InkWell(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => HandleManagementScreen(wallet: widget.wallet),
                ),
              ).then((_) => _loadData()),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '@${info.reservedHandle}',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        Icon(Icons.chevron_right, color: AppTheme.textMuted(context)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      remaining > 0 
                          ? 'Reserved • ${info.breadcrumbCount}/100 breadcrumbs'
                          : '✓ Ready to claim!',
                      style: TextStyle(color: AppTheme.textSecondary(context)),
                    ),
                    const SizedBox(height: 12),
                    // Progress bar
                    LinearProgressIndicator(
                      value: info.breadcrumbCount / 100,
                      backgroundColor: Colors.grey.withOpacity(0.2),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        info.canClaimHandle ? AppTheme.secondary : AppTheme.primary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Tap for details',
                      style: TextStyle(fontSize: 12, color: AppTheme.textMuted(context)),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        
        return _HandleReservationCard(
          wallet: widget.wallet,
          onReserved: _loadData,
        );
      },
    );
  }

  Widget _buildQuickActions() {
    final isCollecting = widget.wallet.breadcrumbEngine.isCollecting;
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: isCollecting ? AppTheme.secondary : AppTheme.textMuted(context),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  isCollecting ? 'COLLECTING' : 'PAUSED',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      if (isCollecting) {
                        widget.wallet.stopBreadcrumbCollection();
                      } else {
                        await widget.wallet.startBreadcrumbCollection(
                          interval: const Duration(minutes: 10),
                        );
                      }
                      setState(() {});
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isCollecting ? AppTheme.error : AppTheme.secondary,
                    ),
                    child: Text(isCollecting ? 'STOP' : 'START'),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: () async {
                    final result = await widget.wallet.dropBreadcrumb();
                    _loadData();
                    
                    if (!mounted) return;
                    
                    if (result.rejection != null) {
                      _showMovementRequiredDialog(result.rejection!);
                    } else if (result.success && result.block != null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('🍞 Breadcrumb #${result.block!.index + 1} dropped!'),
                          backgroundColor: AppTheme.secondary,
                        ),
                      );
                    }
                  },
                  child: const Text('DROP NOW'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showMovementRequiredDialog(BreadcrumbDropRejection rejection) {
    String emoji;
    String title;
    String message;
    
    switch (rejection) {
      case BreadcrumbDropRejection.sameLocation:
        emoji = '📍';
        title = 'Already Here!';
        message = "You're still in the same spot.\n\nYour identity is built through movement. Walk to a new location to drop your next breadcrumb.";
      case BreadcrumbDropRejection.tooClose:
        emoji = '📏';
        title = 'Too Close!';
        message = "You haven't moved far enough.\n\nWalk at least 50 meters from your last breadcrumb location.";
      case BreadcrumbDropRejection.tooFast:
        emoji = '🚀';
        title = 'Whoa, Slow Down!';
        message = "That speed seems unrealistic.\n\nYour movement appears faster than possible. Wait a moment and try again.";
      case BreadcrumbDropRejection.noGps:
        emoji = '📡';
        title = 'No GPS Signal';
        message = "Couldn't get your location.\n\nMake sure Location Services are enabled and you have a clear view of the sky.";
      case BreadcrumbDropRejection.notInitialized:
        emoji = '⚠️';
        title = 'Not Ready';
        message = "The breadcrumb engine is still initializing.\n\nPlease wait a moment and try again.";
    }
    
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 64)),
              const SizedBox(height: 16),
              Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: AppTheme.textSecondary(context), height: 1.5),
              ),
              if (rejection == BreadcrumbDropRejection.sameLocation) ...[
                const SizedBox(height: 16),
                Text('🚶 Explore your neighborhood', style: TextStyle(color: AppTheme.textMuted(context))),
                Text('☕ Visit a café', style: TextStyle(color: AppTheme.textMuted(context))),
                Text('🌳 Take a walk in the park', style: TextStyle(color: AppTheme.textMuted(context))),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('GOT IT!', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _shareIdentity() async {
    final result = await ShareFacetPicker.show(
      context,
      publicKey: widget.wallet.publicKey ?? '',
      handle: _myIdentity?.handle,
    );
    
    if (result == null || !mounted) return;
    
    final payload = GnsIdentityPayload(
      publicKey: widget.wallet.publicKey ?? '',
      handle: _myIdentity?.handle,
      facetId: result.facet.id,
    );
    
    if (result.showQr) {
      _showQrDialog(result.facet, payload);
    } else if (result.copyLink) {
      await Clipboard.setData(ClipboardData(text: payload.toUrl()));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Link copied: ${payload.toUrl()}'),
            backgroundColor: AppTheme.secondary,
          ),
        );
      }
    }
  }

  void _showQrDialog(ProfileFacet facet, GnsIdentityPayload payload) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(facet.emoji, style: const TextStyle(fontSize: 32)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          facet.label,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        if (facet.displayName != null)
                          Text(
                            facet.displayName!,
                            style: TextStyle(color: AppTheme.textSecondary(ctx), fontSize: 14),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: QrImageView(
                  data: jsonEncode(payload.toJson()),
                  version: QrVersions.auto,
                  size: 200,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Colors.black,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Colors.black,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceLight(ctx),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  payload.toUrl(),
                  style: TextStyle(color: AppTheme.textMuted(ctx), fontSize: 12, fontFamily: 'monospace'),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Scan to view your ${facet.label.toLowerCase()} profile',
                style: TextStyle(color: AppTheme.textSecondary(ctx), fontSize: 12),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: payload.toUrl()));
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('Link copied!')),
                        );
                      },
                      icon: const Icon(Icons.copy, size: 18),
                      label: const Text('COPY'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('DONE'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _editProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProfileEditorScreen(
          wallet: widget.wallet,
          profileService: widget.profileService,
          onSaved: _loadData,
        ),
      ),
    );
  }

  Future<void> _search(String query) async {
    if (query.isEmpty) return;

    final result = await widget.profileService.search(query);
    
    if (result.success && result.identity != null) {
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => IdentityViewerScreen(
              identity: result.identity!,
              profileService: widget.profileService,
              wallet: widget.wallet,
            ),
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.error ?? 'Not found')),
        );
      }
    }
  }

  void _viewIdentity(String publicKey) async {
    final result = await widget.profileService.lookupByPublicKey(publicKey);
    
    if (result.success && result.identity != null && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => IdentityViewerScreen(
            identity: result.identity!,
            profileService: widget.profileService,
            wallet: widget.wallet,
          ),
        ),
      );
    }
  }
}

// ==================== HANDLE RESERVATION CARD ====================

class _HandleReservationCard extends StatefulWidget {
  final IdentityWallet wallet;
  final VoidCallback? onReserved;

  const _HandleReservationCard({required this.wallet, this.onReserved});

  @override
  State<_HandleReservationCard> createState() => _HandleReservationCardState();
}

class _HandleReservationCardState extends State<_HandleReservationCard> {
  final _controller = TextEditingController();
  bool _isReserving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'RESERVE YOUR @USERNAME',
              style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
            ),
            const SizedBox(height: 8),
            Text(
              'Collect 100 breadcrumbs to claim it permanently',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary(context)),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text(
                  '@',
                  style: TextStyle(
                    fontSize: 24,
                    color: AppTheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      hintText: 'username',
                      isDense: true,
                    ),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _reserve(),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _isReserving ? null : _reserve,
                  child: _isReserving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('RESERVE'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _reserve() async {
    final handle = _controller.text.trim();
    if (handle.isEmpty) return;

    setState(() => _isReserving = true);

    final result = await widget.wallet.reserveHandle(handle);

    setState(() => _isReserving = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message ?? result.error ?? '')),
      );
      if (result.success) {
        widget.onReserved?.call();
      }
    }
  }
}
