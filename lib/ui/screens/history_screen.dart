/// Globe Crumbs - History Screen
/// 
/// Timeline and Map visualization of breadcrumb trail.
/// Phase 4a: Timeline view
/// Phase 4b: H3 Hexagonal Map view
/// Now with Light/Dark theme support!
/// NEW: Phase 5 - Transactions tab for payments
/// 
/// Location: lib/ui/screens/history_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:h3_flutter/h3_flutter.dart';
import '../../core/chain/breadcrumb_block.dart';
import '../../core/chain/chain_storage.dart';
import '../../core/gns/identity_wallet.dart';
import '../../core/theme/theme_service.dart';
import '../../core/financial/payment_service.dart';
import '../../core/financial/transaction_storage.dart';
import '../financial/send_money_screen.dart';

// ==================== HISTORY SCREEN ====================

class HistoryScreen extends StatefulWidget {
  final IdentityWallet wallet;
  final PaymentService? paymentService;  // NEW: Optional payment service
  
  const HistoryScreen({
    super.key,
    required this.wallet,
    this.paymentService,
  });

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _chainStorage = ChainStorage();
  final _mapController = MapController();
  final _h3 = const H3Factory().load();
  
  List<BreadcrumbBlock> _breadcrumbs = [];
  ChainVerificationResult? _verification;
  bool _isLoading = true;
  
  // Map data
  Map<String, int> _cellCounts = {};
  List<_H3CellData> _cellData = [];
  LatLng? _centerPoint;
  
  // NEW: Transaction data
  List<GnsTransaction> _transactions = [];
  bool _loadingTransactions = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);  // Changed from 2 to 3
    _tabController.addListener(_onTabChanged);
    _loadData();
    widget.wallet.breadcrumbEngine.onBreadcrumbDropped = (_) => _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    // Load transactions when switching to Transactions tab
    if (_tabController.index == 2 && _loadingTransactions) {
      _loadTransactions();
    }
  }

  Future<void> _loadData() async {
    try {
      await _chainStorage.initialize();
      final blocks = await _chainStorage.getRecentBlocks(limit: 500);
      final verification = await _chainStorage.verifyChain();
      
      final cellCounts = <String, int>{};
      final cellBlocks = <String, List<BreadcrumbBlock>>{};
      
      for (final block in blocks) {
        final cell = block.locationCell;
        cellCounts[cell] = (cellCounts[cell] ?? 0) + 1;
        cellBlocks.putIfAbsent(cell, () => []).add(block);
      }
      
      final cellData = <_H3CellData>[];
      LatLng? center;
      
      for (final entry in cellCounts.entries) {
        try {
          final h3Index = BigInt.parse(entry.key, radix: 16);
          final boundary = _h3.h3ToGeoBoundary(h3Index);
          final cellCenter = _h3.h3ToGeo(h3Index);
          
          if (center == null || entry.value > (cellCounts[cellData.firstOrNull?.cellId] ?? 0)) {
            center = LatLng(cellCenter.lat, cellCenter.lon);
          }
          
          final points = boundary.map((coord) => LatLng(coord.lat, coord.lon)).toList();
          
          cellData.add(_H3CellData(
            cellId: entry.key,
            points: points,
            center: LatLng(cellCenter.lat, cellCenter.lon),
            visitCount: entry.value,
            blocks: cellBlocks[entry.key] ?? [],
          ));
        } catch (e) {
          debugPrint('Error processing cell ${entry.key}: $e');
        }
      }
      
      if (mounted) {
        setState(() {
          _breadcrumbs = blocks;
          _verification = verification;
          _cellCounts = cellCounts;
          _cellData = cellData;
          _centerPoint = center;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading history: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // NEW: Load transactions
  Future<void> _loadTransactions() async {
    if (widget.paymentService == null) {
      setState(() => _loadingTransactions = false);
      return;
    }
    
    try {
      final transactions = await widget.paymentService!.getTransactions(limit: 100);
      
      if (mounted) {
        setState(() {
          _transactions = transactions;
          _loadingTransactions = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading transactions: $e');
      if (mounted) setState(() => _loadingTransactions = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.timeline), text: 'Timeline'),
            Tab(icon: Icon(Icons.map_outlined), text: 'Map'),
            Tab(icon: Icon(Icons.receipt_long), text: 'Payments'),  // NEW TAB
          ],
          indicatorColor: AppTheme.primary,
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppTheme.textMuted(context),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildTimelineTab(),
          _buildMapTab(isDark),
          _buildTransactionsTab(),  // NEW TAB CONTENT
        ],
      ),
    );
  }

  // ==================== TIMELINE TAB ====================

  Widget _buildTimelineTab() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildStatsCard(),
          const SizedBox(height: 16),
          if (_breadcrumbs.isEmpty)
            _buildEmptyState()
          else ...[
            _buildSectionHeader('RECENT BREADCRUMBS', '${_breadcrumbs.length}'),
            const SizedBox(height: 8),
            ..._breadcrumbs.map((block) => _buildBreadcrumbCard(block)),
          ],
          const SizedBox(height: 24),
          _buildEpochsSection(),
        ],
      ),
    );
  }

  Widget _buildStatsCard() {
    final isValid = _verification?.isValid ?? true;
    final blockCount = _verification?.blockCount ?? _breadcrumbs.length;
    
    return Container(
      padding: const EdgeInsets.all(20),
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
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(child: Text('🍞', style: TextStyle(fontSize: 32))),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$blockCount',
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary(context),
                  ),
                ),
                Text(
                  'Total Breadcrumbs',
                  style: TextStyle(color: AppTheme.textSecondary(context)),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isValid 
                  ? AppTheme.secondary.withOpacity(0.2)
                  : AppTheme.warning.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isValid ? Icons.check_circle : Icons.warning,
                  size: 16,
                  color: isValid ? AppTheme.secondary : AppTheme.warning,
                ),
                const SizedBox(width: 4),
                Text(
                  isValid ? 'Verified' : 'Issues',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isValid ? AppTheme.secondary : AppTheme.warning,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(40),
      child: Column(
        children: [
          const Text('🚶', style: TextStyle(fontSize: 64)),
          const SizedBox(height: 16),
          Text(
            'No breadcrumbs yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Start collecting to build your trajectory',
            style: TextStyle(color: AppTheme.textSecondary(context)),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, String count) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: AppTheme.textMuted(context),
            letterSpacing: 1,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: AppTheme.surfaceLight(context),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            count,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppTheme.textSecondary(context),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBreadcrumbCard(BreadcrumbBlock block) {
    final timeAgo = _formatTimeAgo(block.timestamp);
    final isManual = block.metaFlags['manual'] == true;
    
    return GestureDetector(
      onTap: () => _showBlockDetails(block),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surface(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border(context)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  '#${block.index}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        timeAgo,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary(context),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (isManual)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.accent.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            '👆 MANUAL',
                            style: TextStyle(fontSize: 10, color: AppTheme.accent),
                          ),
                        )
                      else
                        const Text('🍞', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Cell: ${block.locationCell.substring(0, 12)}...',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textMuted(context),
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  block.blockHash.substring(0, 8),
                  style: const TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: AppTheme.secondary,
                  ),
                ),
                const SizedBox(height: 4),
                Icon(Icons.chevron_right, size: 16, color: AppTheme.textMuted(context)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEpochsSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border(context)),
      ),
      child: Column(
        children: [
          const Text('📦', style: TextStyle(fontSize: 32)),
          const SizedBox(height: 12),
          Text(
            'No epochs published yet',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Epochs compress your breadcrumbs into verifiable commitments',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: AppTheme.textMuted(context)),
          ),
        ],
      ),
    );
  }

  // ==================== MAP TAB ====================

  Widget _buildMapTab(bool isDark) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_cellData.isEmpty) return _buildMapEmptyState();

    final maxVisits = _cellData.map((c) => c.visitCount).reduce((a, b) => a > b ? a : b);
    final tileUrl = isDark
        ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png'
        : 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png';

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _centerPoint ?? const LatLng(41.9028, 12.4964),
            initialZoom: 14,
            minZoom: 3,
            maxZoom: 18,
            onTap: (_, __) {},
          ),
          children: [
            TileLayer(
              urlTemplate: tileUrl,
              subdomains: const ['a', 'b', 'c', 'd'],
              userAgentPackageName: 'com.gns.browser',
              retinaMode: true,
            ),
            PolygonLayer(
              polygons: _cellData.map((cell) {
                final intensity = cell.visitCount / maxVisits;
                return Polygon(
                  points: cell.points,
                  color: _getHeatColor(intensity).withOpacity(0.4),
                  borderColor: _getHeatColor(intensity),
                  borderStrokeWidth: 2,
                );
              }).toList(),
            ),
            MarkerLayer(
              markers: _cellData.map((cell) {
                return Marker(
                  point: cell.center,
                  width: 40,
                  height: 40,
                  child: GestureDetector(
                    onTap: () => _showCellDetails(cell),
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withOpacity(0.9),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          '${cell.visitCount}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
        Positioned(top: 16, right: 16, child: _buildMapLegend(maxVisits)),
        Positioned(bottom: 16, left: 16, right: 16, child: _buildMapStats()),
        Positioned(
          bottom: 100,
          right: 16,
          child: FloatingActionButton.small(
            heroTag: 'center_map',
            backgroundColor: AppTheme.surface(context),
            onPressed: () {
              if (_centerPoint != null) _mapController.move(_centerPoint!, 14);
            },
            child: const Icon(Icons.my_location, color: AppTheme.primary),
          ),
        ),
      ],
    );
  }

  Widget _buildMapEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Center(child: Text('🗺️', style: TextStyle(fontSize: 56))),
            ),
            const SizedBox(height: 24),
            Text(
              'No locations yet',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary(context),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Drop some breadcrumbs to see your trajectory',
              style: TextStyle(fontSize: 16, color: AppTheme.textSecondary(context)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMapLegend(int maxVisits) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface(context).withOpacity(0.95),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'VISITS',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: AppTheme.textMuted(context),
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildLegendItem(AppTheme.secondary, '1'),
              const SizedBox(width: 8),
              _buildLegendItem(AppTheme.warning, '${maxVisits ~/ 2}'),
              const SizedBox(width: 8),
              _buildLegendItem(AppTheme.error, '$maxVisits'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color.withOpacity(0.6),
            border: Border.all(color: color, width: 1),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 10, color: AppTheme.textSecondary(context))),
      ],
    );
  }

  Widget _buildMapStats() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface(context).withOpacity(0.95),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border(context)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildMapStat('⬡', '${_cellData.length}', 'Cells'),
          Container(width: 1, height: 30, color: AppTheme.border(context)),
          _buildMapStat('🍞', '${_breadcrumbs.length}', 'Crumbs'),
          Container(width: 1, height: 30, color: AppTheme.border(context)),
          _buildMapStat('📍', 'H3-10', 'Resolution'),
        ],
      ),
    );
  }

  Widget _buildMapStat(String icon, String value, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(icon, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 4),
            Text(
              value,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.primary),
            ),
          ],
        ),
        Text(label, style: TextStyle(fontSize: 10, color: AppTheme.textMuted(context))),
      ],
    );
  }

  Color _getHeatColor(double intensity) {
    if (intensity < 0.5) {
      return Color.lerp(AppTheme.secondary, AppTheme.warning, intensity * 2)!;
    } else {
      return Color.lerp(AppTheme.warning, AppTheme.error, (intensity - 0.5) * 2)!;
    }
  }

  void _showCellDetails(_H3CellData cell) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.8,
        builder: (ctx, scrollController) => Container(
          decoration: BoxDecoration(
            color: AppTheme.surface(ctx),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(20),
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(color: AppTheme.border(ctx), borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Container(
                    width: 56, height: 56,
                    decoration: BoxDecoration(color: AppTheme.primary.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
                    child: const Center(child: Text('⬡', style: TextStyle(fontSize: 28))),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('H3 Cell', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.textPrimary(ctx))),
                        Text('${cell.visitCount} visit${cell.visitCount == 1 ? '' : 's'}', style: TextStyle(color: AppTheme.textSecondary(ctx))),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: _getHeatColor(cell.visitCount / 10).withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
                    child: Text('${cell.visitCount}x', style: TextStyle(fontWeight: FontWeight.bold, color: _getHeatColor(cell.visitCount / 10))),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _buildDetailItem(ctx, 'Cell ID', cell.cellId, copyable: true),
              _buildDetailItem(ctx, 'Center', '${cell.center.latitude.toStringAsFixed(6)}, ${cell.center.longitude.toStringAsFixed(6)}'),
              const SizedBox(height: 16),
              Text('BREADCRUMBS IN THIS CELL', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textMuted(ctx), letterSpacing: 1)),
              const SizedBox(height: 8),
              ...cell.blocks.take(10).map((block) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(color: AppTheme.primary.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                  child: Center(child: Text('#${block.index}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.primary))),
                ),
                title: Text(_formatTimeAgo(block.timestamp), style: TextStyle(color: AppTheme.textPrimary(ctx))),
                subtitle: Text(block.blockHash.substring(0, 12), style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: AppTheme.secondary)),
                trailing: Text(block.metaFlags['manual'] == true ? '👆' : '🍞', style: const TextStyle(fontSize: 16)),
                onTap: () { Navigator.pop(ctx); _showBlockDetails(block); },
              )),
              if (cell.blocks.length > 10)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('+${cell.blocks.length - 10} more breadcrumbs', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary(ctx))),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTimeAgo(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w ago';
    return '${(diff.inDays / 30).floor()}mo ago';
  }

  void _showBlockDetails(BreadcrumbBlock block) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (ctx, scrollController) => Container(
          decoration: BoxDecoration(
            color: AppTheme.surface(ctx),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(20),
            children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppTheme.border(ctx), borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 20),
              Row(
                children: [
                  Container(
                    width: 56, height: 56,
                    decoration: BoxDecoration(color: AppTheme.primary.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
                    child: Center(child: Text('#${block.index}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primary))),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Breadcrumb Block', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.textPrimary(ctx))),
                        Text(_formatTimeAgo(block.timestamp), style: TextStyle(color: AppTheme.textSecondary(ctx))),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.map, color: AppTheme.primary),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _tabController.animateTo(1);
                      try {
                        final h3Index = BigInt.parse(block.locationCell, radix: 16);
                        final center = _h3.h3ToGeo(h3Index);
                        _mapController.move(LatLng(center.lat, center.lon), 16);
                      } catch (e) { debugPrint('Error centering map: $e'); }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _buildDetailItem(ctx, 'Block Hash', block.blockHash, copyable: true),
              _buildDetailItem(ctx, 'Previous Hash', block.previousHash ?? 'Genesis', copyable: true),
              _buildDetailItem(ctx, 'H3 Cell', block.locationCell, copyable: true),
              _buildDetailItem(ctx, 'Resolution', 'Level ${block.locationResolution}'),
              _buildDetailItem(ctx, 'Context Digest', block.contextDigest, copyable: true),
              _buildDetailItem(ctx, 'Signature', block.signature, copyable: true),
              _buildDetailItem(ctx, 'Timestamp', block.timestamp.toIso8601String()),
              const SizedBox(height: 16),
              Text('METADATA', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textMuted(ctx), letterSpacing: 1)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (block.metaFlags['manual'] == true) _buildMetaChip('👆 Manual', AppTheme.accent),
                  if (block.metaFlags['manual'] != true) _buildMetaChip('🤖 Auto', AppTheme.primary),
                  if (block.metaFlags['state'] != null)
                    _buildMetaChip(block.metaFlags['state'] == 'moving' ? '🚶 Moving' : '🧍 Stationary', AppTheme.secondary),
                  if (block.metaFlags['accuracy'] != null)
                    _buildMetaChip('📍 ${(block.metaFlags['accuracy'] as double).toStringAsFixed(0)}m', AppTheme.warning),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailItem(BuildContext ctx, String label, String value, {bool copyable = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: AppTheme.textMuted(ctx))),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(child: Text(value, style: TextStyle(fontFamily: 'monospace', fontSize: 13, color: AppTheme.textPrimary(ctx)))),
              if (copyable)
                IconButton(
                  icon: Icon(Icons.copy, size: 16, color: AppTheme.textMuted(ctx)),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: value));
                    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('$label copied'), duration: const Duration(seconds: 1)));
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetaChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: color.withOpacity(0.2), borderRadius: BorderRadius.circular(16)),
      child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
    );
  }

  // ==================== TRANSACTIONS TAB ====================

  Widget _buildTransactionsTab() {
    if (_loadingTransactions) {
      return const Center(child: CircularProgressIndicator());
    }
    
    if (widget.paymentService == null) {
      return _buildPaymentsNotAvailable();
    }
    
    if (_transactions.isEmpty) {
      return _buildEmptyTransactions();
    }
    
    return RefreshIndicator(
      onRefresh: _loadTransactions,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _transactions.length + 1,  // +1 for header
        itemBuilder: (context, index) {
          if (index == 0) {
            return _buildTransactionsHeader();
          }
          return _buildTransactionTile(_transactions[index - 1]);
        },
      ),
    );
  }

  Widget _buildPaymentsNotAvailable() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.account_balance_wallet_outlined,
            size: 64,
            color: AppTheme.textMuted(context).withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'Payments Not Available',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppTheme.textSecondary(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Payment service is initializing...',
            style: TextStyle(color: AppTheme.textMuted(context)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyTransactions() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.receipt_long_outlined,
            size: 64,
            color: AppTheme.textMuted(context).withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'No transactions yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppTheme.textSecondary(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Send or receive payments to see them here',
            style: TextStyle(color: AppTheme.textMuted(context)),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SendMoneyScreen()),
              );
            },
            icon: const Icon(Icons.send),
            label: const Text('Send Money'),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionsHeader() {
    final totalSent = _transactions
        .where((t) => t.direction == TransactionDirection.outgoing)
        .fold<double>(0, (sum, t) => sum + (double.tryParse(t.amount) ?? 0));
    
    final totalReceived = _transactions
        .where((t) => t.direction == TransactionDirection.incoming)
        .fold<double>(0, (sum, t) => sum + (double.tryParse(t.amount) ?? 0));
    
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primary.withOpacity(0.1),
            AppTheme.secondary.withOpacity(0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border(context)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.arrow_upward, size: 16, color: AppTheme.error),
                    const SizedBox(width: 4),
                    Text('Sent', style: TextStyle(color: AppTheme.textMuted(context))),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '€${totalSent.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary(context),
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 1,
            height: 40,
            color: AppTheme.border(context),
          ),
          Expanded(
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.arrow_downward, size: 16, color: AppTheme.secondary),
                    const SizedBox(width: 4),
                    Text('Received', style: TextStyle(color: AppTheme.textMuted(context))),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '€${totalReceived.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionTile(GnsTransaction tx) {
    final isOutgoing = tx.direction == TransactionDirection.outgoing;
    final amountColor = isOutgoing ? AppTheme.error : AppTheme.secondary;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          radius: 20,
          backgroundColor: amountColor.withOpacity(0.15),
          child: Icon(
            isOutgoing ? Icons.arrow_upward : Icons.arrow_downward,
            color: amountColor,
            size: 20,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                tx.counterpartyDisplay,
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textPrimary(context),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              '${isOutgoing ? '-' : '+'}${tx.amountFormatted}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: amountColor,
              ),
            ),
          ],
        ),
        subtitle: Row(
          children: [
            Text(
              _formatTransactionTime(tx.createdAt),
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.textMuted(context),
              ),
            ),
            if (tx.memo != null && tx.memo!.isNotEmpty) ...[
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tx.memo!,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textMuted(context),
                    fontStyle: FontStyle.italic,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
        onTap: () => _showTransactionDetails(tx),
      ),
    );
  }

  void _showTransactionDetails(GnsTransaction tx) {
    final isOutgoing = tx.direction == TransactionDirection.outgoing;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.border(ctx),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            
            // Amount
            Text(
              '${isOutgoing ? '-' : '+'}${tx.amountFormatted}',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: isOutgoing ? AppTheme.error : AppTheme.secondary,
              ),
            ),
            const SizedBox(height: 8),
            
            // Status
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _getStatusColor(tx.status).withOpacity(0.15),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                tx.statusDisplay,
                style: TextStyle(
                  color: _getStatusColor(tx.status),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 24),
            
            // Details
            _buildDetailRow(ctx, isOutgoing ? 'To' : 'From', tx.counterpartyDisplay),
            if (tx.memo != null && tx.memo!.isNotEmpty)
              _buildDetailRow(ctx, 'Memo', tx.memo!),
            _buildDetailRow(ctx, 'Date', tx.createdAt.toString().substring(0, 16)),
            _buildDetailRow(ctx, 'ID', '${tx.id.substring(0, 16)}...'),
            
            const SizedBox(height: 24),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(BuildContext ctx, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: AppTheme.textMuted(ctx))),
          Flexible(
            child: Text(
              value,
              style: TextStyle(
                color: AppTheme.textPrimary(ctx),
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(TransactionStatus status) {
    switch (status) {
      case TransactionStatus.pending:
        return AppTheme.warning;
      case TransactionStatus.accepted:
      case TransactionStatus.settled:
        return AppTheme.secondary;
      case TransactionStatus.rejected:
      case TransactionStatus.failed:
      case TransactionStatus.expired:
        return AppTheme.error;
    }
  }

  String _formatTransactionTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

class _H3CellData {
  final String cellId;
  final List<LatLng> points;
  final LatLng center;
  final int visitCount;
  final List<BreadcrumbBlock> blocks;

  _H3CellData({required this.cellId, required this.points, required this.center, required this.visitCount, required this.blocks});
}
