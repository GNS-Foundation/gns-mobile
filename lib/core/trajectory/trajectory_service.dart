/// Trajectory Service
///
/// Computes map data, stats, streaks, and city aggregation
/// from the local breadcrumb chain. Pure read-only queries.
///
/// Location: lib/core/trajectory/trajectory_service.dart

import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import '../chain/chain_storage.dart';
import '../chain/breadcrumb_block.dart';
import '../privacy/h3_quantizer.dart';
import '../gns/gns_api_client.dart';
import 'package:h3_flutter/h3_flutter.dart';

// ==================== DATA MODELS ====================

class TrajectoryStats {
  final int totalBreadcrumbs;
  final int uniqueCells;
  final int uniqueCities;       // H3 Res-4 parents (~1,770 km²)
  final int uniqueNeighborhoods; // H3 Res-7 parents (~5.16 km²)
  final int weeklyStreak;
  final String currentTier;
  final double tierProgress;    // 0.0–1.0 toward next tier
  final int nextTierThreshold;
  final DateTime? firstBreadcrumbAt;
  final DateTime? lastBreadcrumbAt;

  TrajectoryStats({
    required this.totalBreadcrumbs,
    required this.uniqueCells,
    required this.uniqueCities,
    required this.uniqueNeighborhoods,
    required this.weeklyStreak,
    required this.currentTier,
    required this.tierProgress,
    required this.nextTierThreshold,
    this.firstBreadcrumbAt,
    this.lastBreadcrumbAt,
  });

  static TrajectoryStats empty() => TrajectoryStats(
    totalBreadcrumbs: 0,
    uniqueCells: 0,
    uniqueCities: 0,
    uniqueNeighborhoods: 0,
    weeklyStreak: 0,
    currentTier: 'Seedling',
    tierProgress: 0.0,
    nextTierThreshold: 100,
  );
}

class HeatmapCell {
  final String h3Cell;
  final double lat;
  final double lng;
  final int visitCount;
  final double intensity; // 0.0–1.0 normalized
  final List<List<double>> boundary; // polygon vertices [[lat,lng], ...]

  HeatmapCell({
    required this.h3Cell,
    required this.lat,
    required this.lng,
    required this.visitCount,
    required this.intensity,
    required this.boundary,
  });
}

class WeeklyDigest {
  final DateTime weekStart;
  final DateTime weekEnd;
  final int breadcrumbCount;
  final int newCells;
  final int neighborhoodCount;
  final int cityCount;
  final String tier;
  final int streakWeeks;
  final List<String> topCells; // most visited H3 cells that week

  WeeklyDigest({
    required this.weekStart,
    required this.weekEnd,
    required this.breadcrumbCount,
    required this.newCells,
    required this.neighborhoodCount,
    required this.cityCount,
    required this.tier,
    required this.streakWeeks,
    required this.topCells,
  });
}

enum TimeFilter { thisWeek, thisMonth, thisYear, allTime }

// ==================== TIER LOGIC ====================

class TierInfo {
  static const tiers = [
    {'name': 'Seedling',     'min': 0,     'max': 99},
    {'name': 'Explorer',     'min': 100,   'max': 999},
    {'name': 'Navigator',    'min': 1000,  'max': 9999},
    {'name': 'Trailblazer',  'min': 10000, 'max': -1}, // no cap
  ];

  static String tierFor(int breadcrumbs) {
    if (breadcrumbs >= 10000) return 'Trailblazer';
    if (breadcrumbs >= 1000) return 'Navigator';
    if (breadcrumbs >= 100) return 'Explorer';
    return 'Seedling';
  }

  static double progressToNext(int breadcrumbs) {
    if (breadcrumbs >= 10000) return 1.0;
    if (breadcrumbs >= 1000) return (breadcrumbs - 1000) / 9000.0;
    if (breadcrumbs >= 100) return (breadcrumbs - 100) / 900.0;
    return breadcrumbs / 100.0;
  }

  static int nextThreshold(int breadcrumbs) {
    if (breadcrumbs >= 10000) return 10000;
    if (breadcrumbs >= 1000) return 10000;
    if (breadcrumbs >= 100) return 1000;
    return 100;
  }

  static String tierEmoji(String tier) {
    switch (tier) {
      case 'Seedling':    return '🌱';
      case 'Explorer':    return '🧭';
      case 'Navigator':   return '🗺️';
      case 'Trailblazer': return '⚡';
      default:            return '🌱';
    }
  }
}

// ==================== SERVICE ====================

class TrajectoryService {
  static final TrajectoryService _instance = TrajectoryService._internal();
  factory TrajectoryService() => _instance;
  TrajectoryService._internal();

  final _chainStorage = ChainStorage();
  final _h3 = H3Quantizer();
  final _apiClient = GnsApiClient();

  // Backend breadcrumb count cache (survives app container wipes)
  int _backendBreadcrumbCount = 0;
  double _backendTrustScore = 0;
  bool _backendFetched = false;

  /// Fetch breadcrumb count from backend for a given publicKey.
  /// Uses /identities/ endpoint which has breadcrumb_count and trust_score.
  /// This is the authoritative count — local chain may be incomplete
  /// after device change or reinstall.
  Future<void> syncBackendStats(String publicKey) async {
    try {
      final url = '${_apiClient.nodeUrl}/identities/$publicKey';
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
      ));
      final response = await dio.get(url);
      final json = response.data as Map<String, dynamic>;
      
      if (json['success'] == true && json['data'] != null) {
        final data = json['data'] as Map<String, dynamic>;
        _backendBreadcrumbCount = (data['breadcrumb_count'] as num?)?.toInt() ?? 0;
        _backendTrustScore = (data['trust_score'] as num?)?.toDouble() ?? 0;
        _backendFetched = true;
        debugPrint('Backend stats synced: $_backendBreadcrumbCount crumbs, ${_backendTrustScore}% trust');
      }
    } catch (e) {
      debugPrint('Backend stats fetch error: $e');
    }
  }

  /// The effective breadcrumb count: max of local chain and backend record.
  /// This ensures tier is never downgraded by a device change or reinstall.
  int effectiveCount(int localCount) {
    return localCount > _backendBreadcrumbCount ? localCount : _backendBreadcrumbCount;
  }

  // ── Stats ──

  Future<TrajectoryStats> getStats({String? publicKey}) async {
    // Sync backend stats if we have a publicKey and haven't yet
    if (publicKey != null && !_backendFetched) {
      await syncBackendStats(publicKey);
    }

    final localCount = await _chainStorage.getBlockCount();
    final effectiveBreadcrumbs = effectiveCount(localCount);
    final uniqueCells = await _chainStorage.getUniqueCells();
    final uniqueCellCount = uniqueCells.length;

    // Aggregate neighborhoods (Res-7 parents)
    final neighborhoods = <String>{};
    final cities = <String>{};
    for (final cell in uniqueCells) {
      try {
        final hoods = _h3.getParentHex(cell.cell, 7);
        neighborhoods.add(hoods);
        final city = _h3.getParentHex(cell.cell, 4);
        cities.add(city);
      } catch (_) {}
    }

    // Streak
    final streak = await _computeWeeklyStreak();

    // First/last
    final chain = await _chainStorage.getRecentBlocks(limit: 1);
    final fullChain = await _chainStorage.getFullChain();
    final firstAt = fullChain.isNotEmpty ? fullChain.first.timestamp : null;
    final lastAt = chain.isNotEmpty ? chain.first.timestamp : null;

    // Tier uses effective count (max of local + backend)
    final tier = TierInfo.tierFor(effectiveBreadcrumbs);

    return TrajectoryStats(
      totalBreadcrumbs: effectiveBreadcrumbs,
      uniqueCells: uniqueCellCount,
      uniqueCities: cities.length,
      uniqueNeighborhoods: neighborhoods.length,
      weeklyStreak: streak,
      currentTier: tier,
      tierProgress: TierInfo.progressToNext(effectiveBreadcrumbs),
      nextTierThreshold: TierInfo.nextThreshold(effectiveBreadcrumbs),
      firstBreadcrumbAt: firstAt,
      lastBreadcrumbAt: lastAt,
    );
  }

  // ── Heatmap ──

  Future<List<HeatmapCell>> getHeatmapCells({
    TimeFilter filter = TimeFilter.allTime,
  }) async {
    List<UniqueCellInfo> cells;

    if (filter == TimeFilter.allTime) {
      cells = await _chainStorage.getUniqueCells();
    } else {
      // Get blocks in range, then aggregate cells
      final range = _dateRangeFor(filter);
      final blocks = await _chainStorage.getBlocksInRange(range.start, range.end);
      final cellMap = <String, int>{};
      for (final b in blocks) {
        cellMap[b.locationCell] = (cellMap[b.locationCell] ?? 0) + 1;
      }
      cells = cellMap.entries.map((e) => UniqueCellInfo(
        cell: e.key,
        firstVisitedAt: DateTime.now(),
        visitCount: e.value,
      )).toList();
    }

    if (cells.isEmpty) return [];

    final maxVisits = cells.map((c) => c.visitCount).reduce((a, b) => a > b ? a : b);

    return cells.map((cell) {
      try {
        final center = _h3.h3HexToLatLon(cell.cell);
        final boundary = _getCellBoundary(cell.cell);
        return HeatmapCell(
          h3Cell: cell.cell,
          lat: center.lat,
          lng: center.lon,
          visitCount: cell.visitCount,
          intensity: maxVisits > 0 ? cell.visitCount / maxVisits : 0.0,
          boundary: boundary,
        );
      } catch (e) {
        debugPrint('Error converting cell ${cell.cell}: $e');
        return null;
      }
    }).whereType<HeatmapCell>().toList();
  }

  /// Get H3 cell boundary as [[lat, lng], ...] polygon vertices
  List<List<double>> _getCellBoundary(String h3Hex) {
    final h3Index = BigInt.parse(h3Hex, radix: 16);
    final h3Factory = const H3Factory().load();
    final boundary = h3Factory.h3ToGeoBoundary(h3Index);
    // h3_flutter returns GeoCoord(lat, lon) — flutter_map wants LatLng(lat, lng)
    return boundary.map((coord) => [coord.lat, coord.lon]).toList();
  }

  /// Get the center point of all breadcrumbs (for initial map position)
  Future<({double lat, double lng})?> getCenterPoint() async {
    final cells = await _chainStorage.getUniqueCells();
    if (cells.isEmpty) return null;

    double totalLat = 0, totalLng = 0;
    int count = 0;
    for (final cell in cells) {
      try {
        final center = _h3.h3HexToLatLon(cell.cell);
        totalLat += center.lat;
        totalLng += center.lon;
        count++;
      } catch (_) {}
    }
    if (count == 0) return null;
    return (lat: totalLat / count, lng: totalLng / count);
  }

  // ── Weekly Digest ──

  Future<WeeklyDigest> getCurrentWeekDigest() async {
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday % 7));
    final start = DateTime(weekStart.year, weekStart.month, weekStart.day);
    final end = now;

    return _buildDigest(start, end);
  }

  Future<List<WeeklyDigest>> getDigestHistory({int weeks = 12}) async {
    final digests = <WeeklyDigest>[];
    final now = DateTime.now();

    for (int i = 0; i < weeks; i++) {
      final weekEnd = now.subtract(Duration(days: 7 * i));
      final weekStart = weekEnd.subtract(const Duration(days: 7));
      final start = DateTime(weekStart.year, weekStart.month, weekStart.day);
      final end = DateTime(weekEnd.year, weekEnd.month, weekEnd.day, 23, 59, 59);

      final digest = await _buildDigest(start, end);
      if (digest.breadcrumbCount > 0) {
        digests.add(digest);
      }
    }
    return digests;
  }

  Future<WeeklyDigest> _buildDigest(DateTime start, DateTime end) async {
    final blocks = await _chainStorage.getBlocksInRange(start, end);

    final cellCounts = <String, int>{};
    final neighborhoods = <String>{};
    final cities = <String>{};
    for (final b in blocks) {
      cellCounts[b.locationCell] = (cellCounts[b.locationCell] ?? 0) + 1;
      try {
        neighborhoods.add(_h3.getParentHex(b.locationCell, 7));
        cities.add(_h3.getParentHex(b.locationCell, 4));
      } catch (_) {}
    }

    // Sort cells by visit count for "top cells"
    final sorted = cellCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topCells = sorted.take(5).map((e) => e.key).toList();

    final totalCount = await _chainStorage.getBlockCount();
    final tier = TierInfo.tierFor(totalCount);
    final streak = await _computeWeeklyStreak();

    return WeeklyDigest(
      weekStart: start,
      weekEnd: end,
      breadcrumbCount: blocks.length,
      newCells: cellCounts.length,
      neighborhoodCount: neighborhoods.length,
      cityCount: cities.length,
      tier: tier,
      streakWeeks: streak,
      topCells: topCells,
    );
  }

  // ── Streak ──

  Future<int> _computeWeeklyStreak() async {
    final now = DateTime.now();
    int streak = 0;

    for (int i = 0; i < 52; i++) {
      final weekEnd = now.subtract(Duration(days: 7 * i));
      final weekStart = weekEnd.subtract(const Duration(days: 7));
      final start = DateTime(weekStart.year, weekStart.month, weekStart.day);
      final end = DateTime(weekEnd.year, weekEnd.month, weekEnd.day, 23, 59, 59);

      final blocks = await _chainStorage.getBlocksInRange(start, end);
      if (blocks.isNotEmpty) {
        streak++;
      } else {
        break;
      }
    }
    return streak;
  }

  // ── Helpers ──

  ({DateTime start, DateTime end}) _dateRangeFor(TimeFilter filter) {
    final now = DateTime.now();
    switch (filter) {
      case TimeFilter.thisWeek:
        final start = now.subtract(Duration(days: now.weekday));
        return (start: DateTime(start.year, start.month, start.day), end: now);
      case TimeFilter.thisMonth:
        return (start: DateTime(now.year, now.month, 1), end: now);
      case TimeFilter.thisYear:
        return (start: DateTime(now.year, 1, 1), end: now);
      case TimeFilter.allTime:
        return (start: DateTime(2024, 1, 1), end: now);
    }
  }

  // ── Achievements ──

  Future<List<Achievement>> getAchievements() async {
    final stats = await getStats();
    final achievements = <Achievement>[];

    // Multi-city
    achievements.add(Achievement(
      id: 'multi_city',
      name: 'Multi-City',
      description: 'Visit ${stats.uniqueCities >= 3 ? stats.uniqueCities : 3} different cities',
      icon: '🏙️',
      unlocked: stats.uniqueCities >= 3,
      progress: (stats.uniqueCities / 3).clamp(0.0, 1.0),
      value: '${stats.uniqueCities}',
    ));

    // Weekly streak
    achievements.add(Achievement(
      id: 'streak_4',
      name: '4-Week Streak',
      description: 'Drop breadcrumbs for 4 consecutive weeks',
      icon: '🔥',
      unlocked: stats.weeklyStreak >= 4,
      progress: (stats.weeklyStreak / 4).clamp(0.0, 1.0),
      value: '${stats.weeklyStreak}',
    ));

    // Explorer (100 breadcrumbs)
    achievements.add(Achievement(
      id: 'explorer_100',
      name: 'First Hundred',
      description: 'Drop 100 breadcrumbs',
      icon: '🧭',
      unlocked: stats.totalBreadcrumbs >= 100,
      progress: (stats.totalBreadcrumbs / 100).clamp(0.0, 1.0),
      value: '${stats.totalBreadcrumbs}',
    ));

    // Navigator (1000)
    achievements.add(Achievement(
      id: 'navigator_1000',
      name: 'Thousand Steps',
      description: 'Drop 1,000 breadcrumbs',
      icon: '🗺️',
      unlocked: stats.totalBreadcrumbs >= 1000,
      progress: (stats.totalBreadcrumbs / 1000).clamp(0.0, 1.0),
      value: '${stats.totalBreadcrumbs}',
    ));

    // Neighborhood explorer
    achievements.add(Achievement(
      id: 'hoods_10',
      name: 'Neighborhood Explorer',
      description: 'Visit 10 different neighborhoods',
      icon: '🏘️',
      unlocked: stats.uniqueNeighborhoods >= 10,
      progress: (stats.uniqueNeighborhoods / 10).clamp(0.0, 1.0),
      value: '${stats.uniqueNeighborhoods}',
    ));

    // Night Owl — needs time-of-day analysis
    final nightCount = await _countNightBreadcrumbs();
    achievements.add(Achievement(
      id: 'night_owl',
      name: 'Night Owl',
      description: 'Drop 20 breadcrumbs between 10 PM and 5 AM',
      icon: '🦉',
      unlocked: nightCount >= 20,
      progress: (nightCount / 20).clamp(0.0, 1.0),
      value: '$nightCount',
    ));

    // Early Bird
    final earlyCount = await _countEarlyBreadcrumbs();
    achievements.add(Achievement(
      id: 'early_bird',
      name: 'Early Bird',
      description: 'Drop 20 breadcrumbs between 5 AM and 7 AM',
      icon: '🐦',
      unlocked: earlyCount >= 20,
      progress: (earlyCount / 20).clamp(0.0, 1.0),
      value: '$earlyCount',
    ));

    return achievements;
  }

  Future<int> _countNightBreadcrumbs() async {
    final all = await _chainStorage.getFullChain();
    return all.where((b) {
      final hour = b.timestamp.toLocal().hour;
      return hour >= 22 || hour < 5;
    }).length;
  }

  Future<int> _countEarlyBreadcrumbs() async {
    final all = await _chainStorage.getFullChain();
    return all.where((b) {
      final hour = b.timestamp.toLocal().hour;
      return hour >= 5 && hour < 7;
    }).length;
  }
}

// ==================== ACHIEVEMENT MODEL ====================

class Achievement {
  final String id;
  final String name;
  final String description;
  final String icon;
  final bool unlocked;
  final double progress; // 0.0–1.0
  final String value;

  Achievement({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.unlocked,
    required this.progress,
    required this.value,
  });
}
