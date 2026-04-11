/// Trajectory Map Tab
///
/// The new home screen. Full-screen map with H3 hexagonal heatmap
/// overlay showing everywhere the user has been. Stats bar below.
/// Weekly streak. Digest preview. "Share to stories" CTA.
///
/// Zero protocol language. Pure product surface.
///
/// Dependencies: flutter_map, latlong2 (add to pubspec.yaml)
///   flutter_map: ^6.1.0
///   latlong2: ^0.9.1
///
/// Location: lib/ui/trajectory/trajectory_map_tab.dart

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../core/trajectory/trajectory_service.dart';
import '../../core/chain/breadcrumb_engine.dart';
import '../../core/gns/identity_wallet.dart';
import '../../core/privacy/h3_quantizer.dart';
import '../../core/theme/theme_service.dart';

class TrajectoryMapTab extends StatefulWidget {
  final IdentityWallet wallet;

  const TrajectoryMapTab({super.key, required this.wallet});

  @override
  State<TrajectoryMapTab> createState() => _TrajectoryMapTabState();
}

class _TrajectoryMapTabState extends State<TrajectoryMapTab>
    with AutomaticKeepAliveClientMixin {
  final _trajectoryService = TrajectoryService();
  final _mapController = MapController();

  TrajectoryStats _stats = TrajectoryStats.empty();
  List<HeatmapCell> _heatmapCells = [];
  TimeFilter _timeFilter = TimeFilter.allTime;
  bool _isLoading = true;
  LatLng _center = const LatLng(41.8902, 12.4922); // Default: Rome
  double _zoom = 13.0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    widget.wallet.breadcrumbEngine.initialize().then((_) {
      widget.wallet.breadcrumbEngine.startCollection(interval: const Duration(seconds: 30));
    });
    _loadData();
    // Refresh on new breadcrumb
    widget.wallet.breadcrumbEngine.onBreadcrumbDropped = (_) async {
      await Future.delayed(const Duration(milliseconds: 200));
      _loadData();
    };
  }

  Future<void> _loadData() async {
    try {
      final stats = await _trajectoryService.getStats(publicKey: widget.wallet.publicKey);
      final cells = await _trajectoryService.getHeatmapCells(filter: _timeFilter);
      final center = await _trajectoryService.getCenterPoint();

      if (mounted) {
        setState(() {
          _stats = stats;
          _heatmapCells = cells;
          if (center != null) {
            _center = LatLng(center.lat, center.lng);
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Trajectory load error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      body: Stack(
        children: [
          // ── Full-screen map ──
          _buildMap(),

          // ── Top: Time filter chips ──
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 0,
            right: 0,
            child: _buildTimeFilterBar(),
          ),

          // ── Bottom: Stats + streak panel ──
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildBottomPanel(),
          ),

          // ── Loading overlay ──
          if (_isLoading)
            Container(
              color: Colors.black26,
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  // ==================== MAP ====================

  Widget _buildMap() {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _center,
        initialZoom: _zoom,
        minZoom: 3,
        maxZoom: 18,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all,
        ),
        onPositionChanged: (pos, hasGesture) {
          if (hasGesture && pos.zoom != null) {
            _zoom = pos.zoom!;
          }
        },
      ),
      children: [
        // Base tile layer (OpenStreetMap — free, no API key)
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.globecrumbs.app',
          maxZoom: 19,
          // Dark-ish tile option for contrast:
          // urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
          // subdomains: const ['a', 'b', 'c', 'd'],
        ),

        // H3 hexagon heatmap overlay
        if (_heatmapCells.isNotEmpty) _buildHexagonLayer(),

        // Current location marker (latest breadcrumb)
        if (_heatmapCells.isNotEmpty) _buildCurrentLocationMarker(),
      ],
    );
  }

  Widget _buildHexagonLayer() {
    return PolygonLayer(
      polygons: _heatmapCells.map<Polygon<Object>>((cell) {
        final color = _heatColor(cell.intensity);
        return Polygon(
          points: cell.boundary
              .map((coord) => LatLng(coord[0], coord[1]))
              .toList(),
          color: color.withOpacity(0.35 + cell.intensity * 0.45),
          borderColor: color.withOpacity(0.7),
          borderStrokeWidth: 1.0,
        );
      }).toList(),
    );
  }

  Widget _buildCurrentLocationMarker() {
    // Latest cell = first in list (ordered by most recent)
    final latest = _heatmapCells.isNotEmpty ? _heatmapCells.first : null;
    if (latest == null) return const SizedBox.shrink();

    return MarkerLayer(
      markers: [
        Marker(
          point: LatLng(latest.lat, latest.lng),
          width: 20,
          height: 20,
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.9),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primary.withOpacity(0.4),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Intensity 0.0–1.0 → cool blue → warm orange → hot red
  Color _heatColor(double intensity) {
    if (intensity < 0.33) {
      return Color.lerp(
        const Color(0xFF4FC3F7), // light blue
        const Color(0xFF66BB6A), // green
        intensity / 0.33,
      )!;
    } else if (intensity < 0.66) {
      return Color.lerp(
        const Color(0xFF66BB6A), // green
        const Color(0xFFFFB74D), // amber
        (intensity - 0.33) / 0.33,
      )!;
    } else {
      return Color.lerp(
        const Color(0xFFFFB74D), // amber
        const Color(0xFFEF5350), // red
        (intensity - 0.66) / 0.34,
      )!;
    }
  }

  // ==================== TIME FILTER ====================

  Widget _buildTimeFilterBar() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.surface(context).withOpacity(0.92),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: TimeFilter.values.map((f) {
            final selected = f == _timeFilter;
            return GestureDetector(
              onTap: () {
                setState(() => _timeFilter = f);
                _loadData();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: selected ? AppTheme.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _filterLabel(f),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected ? Colors.white : AppTheme.textSecondary(context),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  String _filterLabel(TimeFilter f) {
    switch (f) {
      case TimeFilter.thisWeek:  return 'Week';
      case TimeFilter.thisMonth: return 'Month';
      case TimeFilter.thisYear:  return 'Year';
      case TimeFilter.allTime:   return 'All';
    }
  }

  // ==================== BOTTOM PANEL ====================

  Widget _buildBottomPanel() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.textMuted(context).withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),

            // Stats row
            _buildStatsRow(),
            const SizedBox(height: 16),

            // Streak bar
            _buildStreakBar(),
            const SizedBox(height: 16),

            // Drop breadcrumb button
            _buildDropButton(),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _statItem('${_stats.totalBreadcrumbs}', 'crumbs'),
          _divider(),
          _statItem('${_stats.uniqueNeighborhoods}', 'hoods'),
          _divider(),
          _statItem('${_stats.uniqueCities}', 'cities'),
          _divider(),
          _statItem('${_stats.uniqueCells}', 'cells'),
        ],
      ),
    );
  }

  Widget _statItem(String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary(context),
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w400,
              color: AppTheme.textMuted(context),
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() {
    return Container(
      width: 1,
      height: 28,
      color: AppTheme.border(context),
    );
  }

  Widget _buildStreakBar() {
    final streak = _stats.weeklyStreak;
    final tier = _stats.currentTier;
    final progress = _stats.tierProgress;
    final emoji = TierInfo.tierEmoji(tier);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          // Streak count
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: streak > 0
                  ? const Color(0xFFFF6D00).withOpacity(0.12)
                  : AppTheme.surfaceLight(context),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  streak > 0 ? '🔥' : '💤',
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(width: 4),
                Text(
                  'Week $streak',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: streak > 0
                        ? const Color(0xFFFF6D00)
                        : AppTheme.textMuted(context),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 12),

          // Tier progress bar
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(emoji, style: const TextStyle(fontSize: 14)),
                    const SizedBox(width: 4),
                    Text(
                      tier,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary(context),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 4,
                    backgroundColor: AppTheme.border(context),
                    valueColor: const AlwaysStoppedAnimation(AppTheme.primary),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: SizedBox(
        width: double.infinity,
        height: 48,
        child: ElevatedButton.icon(
          onPressed: _dropBreadcrumb,
          icon: const Icon(Icons.place, size: 20),
          label: const Text(
            'DROP BREADCRUMB',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
              fontSize: 14,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            elevation: 0,
          ),
        ),
      ),
    );
  }

  Future<void> _dropBreadcrumb() async {
    final result = await widget.wallet.breadcrumbEngine.dropBreadcrumb(manual: true);

    if (!mounted) return;

    if (result.success && result.block != null) {
      // Animate to new location
      final cell = result.block!.locationCell;
      try {
        final h3 = H3Quantizer();
        final coord = h3.h3HexToLatLon(cell);
        _mapController.move(LatLng(coord.lat, coord.lon), _zoom);
      } catch (_) {}

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message ?? 'Breadcrumb dropped!'),
          backgroundColor: const Color(0xFF00C853),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message ?? 'Could not drop breadcrumb'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }
}


