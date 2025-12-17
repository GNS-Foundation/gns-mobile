/// Breadcrumb Engine - Updated with Location Deduplication
/// 
/// Prevents dropping breadcrumbs in the same location.
/// True Proof-of-Trajectory requires MOVEMENT!
///
/// Location: lib/core/chain/breadcrumb_engine.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../crypto/identity_keypair.dart';
import '../crypto/secure_storage.dart';
import '../privacy/h3_quantizer.dart';
import 'breadcrumb_block.dart';
import 'chain_storage.dart';

enum BreadcrumbEngineState { idle, initializing, collecting, dropping, error }

/// Result of a breadcrumb drop attempt
class BreadcrumbDropResult {
  final bool success;
  final BreadcrumbBlock? block;
  final String? message;
  final BreadcrumbDropRejection? rejection;

  BreadcrumbDropResult({
    required this.success,
    this.block,
    this.message,
    this.rejection,
  });

  factory BreadcrumbDropResult.success(BreadcrumbBlock block) {
    return BreadcrumbDropResult(
      success: true,
      block: block,
      message: 'Breadcrumb #${block.index + 1} dropped!',
    );
  }

  factory BreadcrumbDropResult.rejected(BreadcrumbDropRejection rejection) {
    return BreadcrumbDropResult(
      success: false,
      rejection: rejection,
      message: rejection.userMessage,
    );
  }

  factory BreadcrumbDropResult.error(String error) {
    return BreadcrumbDropResult(
      success: false,
      message: error,
    );
  }
}

/// Reasons why a breadcrumb drop was rejected
enum BreadcrumbDropRejection {
  sameLocation,
  tooClose,
  tooFast,
  noGps,
  notInitialized,
}

extension BreadcrumbDropRejectionExt on BreadcrumbDropRejection {
  String get userMessage {
    switch (this) {
      case BreadcrumbDropRejection.sameLocation:
        return '📍 You\'re still in the same spot!\n\nMove to a new location to drop a breadcrumb. Your identity is built through movement.';
      case BreadcrumbDropRejection.tooClose:
        return '📍 Too close to your last breadcrumb!\n\nWalk at least 50 meters to drop another. Explore your world!';
      case BreadcrumbDropRejection.tooFast:
        return '🚀 Moving too fast!\n\nYour speed seems unrealistic. Please try again.';
      case BreadcrumbDropRejection.noGps:
        return '📍 Can\'t get your location.\n\nMake sure GPS is enabled and you\'re in an area with signal.';
      case BreadcrumbDropRejection.notInitialized:
        return '⚠️ Engine not ready.\n\nPlease wait a moment and try again.';
    }
  }

  String get shortMessage {
    switch (this) {
      case BreadcrumbDropRejection.sameLocation:
        return 'Move to drop!';
      case BreadcrumbDropRejection.tooClose:
        return 'Walk further!';
      case BreadcrumbDropRejection.tooFast:
        return 'Too fast!';
      case BreadcrumbDropRejection.noGps:
        return 'No GPS signal';
      case BreadcrumbDropRejection.notInitialized:
        return 'Not ready';
    }
  }
}

class BreadcrumbEngine {
  static final BreadcrumbEngine _instance = BreadcrumbEngine._internal();
  factory BreadcrumbEngine() => _instance;
  BreadcrumbEngine._internal();

  final _storage = SecureStorageService();
  final _chainStorage = ChainStorage();
  final _h3 = H3Quantizer();

  GnsKeypair? _keypair;
  Timer? _collectionTimer;
  BreadcrumbEngineState _state = BreadcrumbEngineState.idle;

  AccelerometerEvent? _lastAccelerometer;
  GyroscopeEvent? _lastGyroscope;
  StreamSubscription? _accelerometerSubscription;
  StreamSubscription? _gyroscopeSubscription;

  Duration collectionInterval = const Duration(seconds: 30);  // ← TESTING: 30 seconds auto-drop
  int h3Resolution = H3Quantizer.defaultResolution;

  // Location deduplication settings
  bool requireMovement = false;  // ← TESTING: No movement required
  double minimumDistanceMeters = 0.0;  // ← TESTING: No minimum distance
  double maximumSpeedKmh = 200.0;  // Maximum plausible speed
  
  // ⚠️ TESTING CONFIGURATION - CHANGE THESE FOR PRODUCTION!
  // 
  // FOR TESTING (collect 100 at same location):
  int maxSameLocationBreadcrumbs = 999999;  // ← TESTING: No limit
  Duration minTimeBetweenDrops = const Duration(seconds: 10);  // ← TESTING: 10 seconds manual cooldown
  
  // FOR PRODUCTION (genuine movement required):
  // Duration collectionInterval = const Duration(minutes: 10);  // ← PRODUCTION: 10 minutes
  // bool requireMovement = true;  // ← PRODUCTION: Movement required
  // double minimumDistanceMeters = 50.0;  // ← PRODUCTION: 50m minimum
  // int maxSameLocationBreadcrumbs = 10;  // ← PRODUCTION: 10 (home/office limit)
  // Duration minTimeBetweenDrops = const Duration(minutes: 3);  // ← PRODUCTION: 3 minutes

  Function(BreadcrumbBlock)? onBreadcrumbDropped;
  Function(BreadcrumbDropResult)? onDropResult;  // NEW: Callback for any drop attempt
  Function(String)? onError;
  Function(BreadcrumbEngineState)? onStateChanged;

  BreadcrumbEngineState get state => _state;
  bool get isCollecting => _collectionTimer?.isActive ?? false;
  String? get publicKey => _keypair?.publicKeyHex;
  String? get gnsId => _keypair?.gnsId;

  Future<void> initialize() async {
    _setState(BreadcrumbEngineState.initializing);

    try {
      await _chainStorage.initialize();

      // ✅ DUAL-KEY: Load BOTH Ed25519 and X25519 keys
      final ed25519Key = await _storage.readPrivateKey();
      final x25519Key = await _storage.readX25519PrivateKey();
      
      if (ed25519Key != null && ed25519Key.isNotEmpty && 
          x25519Key != null && x25519Key.isNotEmpty) {
        _keypair = await GnsKeypair.fromHex(
          ed25519PrivateKeyHex: ed25519Key,
          x25519PrivateKeyHex: x25519Key,
        );
        debugPrint('Loaded existing dual-key identity: ${_keypair!.gnsId}');
      } else {
        // ✅ DUAL-KEY: Generate BOTH keys
        _keypair = await GnsKeypair.generate();
        
        // ✅ DUAL-KEY: Store BOTH keys
        await _storage.storePrivateKey(_keypair!.privateKeyHex);
        await _storage.writeX25519PrivateKey(_keypair!.encryptionPrivateKeyHex);
        await _storage.storePublicKey(_keypair!.publicKeyHex);
        await _storage.storeGnsId(_keypair!.gnsId);
        
        debugPrint('Created new dual-key identity: ${_keypair!.gnsId}');
        debugPrint('  Ed25519: ${_keypair!.publicKeyHex.substring(0, 16)}...');
        debugPrint('  X25519:  ${_keypair!.encryptionPublicKeyHex.substring(0, 16)}...');
      }

      _startIMUListeners();
      _setState(BreadcrumbEngineState.idle);
      debugPrint('Breadcrumb engine initialized');
    } catch (e) {
      _setState(BreadcrumbEngineState.error);
      debugPrint('Engine init error: $e');
      onError?.call('Initialization failed: $e');
    }
  }

  void _startIMUListeners() {
    _accelerometerSubscription = accelerometerEventStream().listen((event) {
      _lastAccelerometer = event;
    });
    _gyroscopeSubscription = gyroscopeEventStream().listen((event) {
      _lastGyroscope = event;
    });
  }

  Future<void> startCollection({Duration? interval}) async {
    if (_keypair == null) await initialize();

    if (interval != null) collectionInterval = interval;

    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      final requested = await Geolocator.requestPermission();
      if (requested == LocationPermission.denied || requested == LocationPermission.deniedForever) {
        onError?.call('Location permission denied');
        return;
      }
    }

    // Try first drop
    await dropBreadcrumb();

    _collectionTimer = Timer.periodic(collectionInterval, (_) {
      dropBreadcrumb();
    });

    _setState(BreadcrumbEngineState.collecting);
    final intervalStr = collectionInterval.inMinutes > 0 
        ? '${collectionInterval.inMinutes} min' 
        : '${collectionInterval.inSeconds} sec';
    debugPrint('Collection started (every $intervalStr)');
  }

  void stopCollection() {
    _collectionTimer?.cancel();
    _collectionTimer = null;
    _setState(BreadcrumbEngineState.idle);
    debugPrint('Collection stopped');
  }

  void setInterval(Duration interval) {
    collectionInterval = interval;
    if (isCollecting) {
      stopCollection();
      startCollection();
    }
  }

  /// Drop a breadcrumb - now with location deduplication!
  Future<BreadcrumbDropResult> dropBreadcrumb({bool manual = false}) async {
    if (_keypair == null) {
      final result = BreadcrumbDropResult.rejected(BreadcrumbDropRejection.notInitialized);
      onDropResult?.call(result);
      onError?.call('Engine not initialized');
      return result;
    }

    _setState(BreadcrumbEngineState.dropping);

    try {
      // Get current position
      final position = await _getPosition();
      if (position == null) {
        _setState(isCollecting ? BreadcrumbEngineState.collecting : BreadcrumbEngineState.idle);
        final result = BreadcrumbDropResult.rejected(BreadcrumbDropRejection.noGps);
        onDropResult?.call(result);
        return result;
      }

      // Convert to H3 cell
      final h3Cell = _h3.latLonToH3Hex(position.latitude, position.longitude, resolution: h3Resolution);

      // Get previous block for comparison
      final previousBlock = await _chainStorage.getLatestBlock();

      // === SMART LOCATION DEDUPLICATION CHECK ===
      // Rules:
      // 1. If moved 50+ meters → Allow (distance-based)
      // 2. If same location but < maxSameLocationBreadcrumbs → Check time
      // 3. If minTimeBetweenDrops passed → Allow (time fallback)
      // 4. Speed check applies to distance-based drops
      
      if (requireMovement && previousBlock != null) {
        final previousCell = previousBlock.locationCell;
        final timeSinceLastDrop = DateTime.now().difference(previousBlock.timestamp);
        
        // Calculate distance from previous drop
        final previousCenter = _h3.h3HexToLatLon(previousCell);
        final distance = Geolocator.distanceBetween(
          previousCenter.lat,
          previousCenter.lon,
          position.latitude,
          position.longitude,
        );
        
        // ✅ RULE 1: Significant distance moved (50+ meters) → Allow instantly
        if (distance >= minimumDistanceMeters) {
          debugPrint('✅ Distance-based drop: ${distance.toStringAsFixed(0)}m from last');
          // Continue to drop (speed check below)
        }
        
        // ✅ RULE 2: Same/nearby location (< 50m)
        else {
          // Count breadcrumbs at this H3 cell
          final breadcrumbsAtCell = await _countBreadcrumbsAtCell(h3Cell);
          
          // Check if we've hit the limit for this location
          if (breadcrumbsAtCell >= maxSameLocationBreadcrumbs) {
            debugPrint('🚫 Location limit reached ($breadcrumbsAtCell/$maxSameLocationBreadcrumbs) - move to new location!');
            _setState(isCollecting ? BreadcrumbEngineState.collecting : BreadcrumbEngineState.idle);
            final result = BreadcrumbDropResult.rejected(BreadcrumbDropRejection.sameLocation);
            onDropResult?.call(result);
            return result;
          }
          
          // ✅ RULE 3: Under limit, check time fallback
          if (timeSinceLastDrop >= minTimeBetweenDrops) {
            debugPrint('✅ Time-based drop: ${timeSinceLastDrop.inSeconds}s passed (${breadcrumbsAtCell + 1}/$maxSameLocationBreadcrumbs at this location)');
            // Continue to drop
          } else {
            // Not enough time passed
            final remaining = minTimeBetweenDrops - timeSinceLastDrop;
            debugPrint('🚫 Too soon: wait ${remaining.inSeconds}s or move ${(minimumDistanceMeters - distance).toInt()}m more');
            _setState(isCollecting ? BreadcrumbEngineState.collecting : BreadcrumbEngineState.idle);
            final result = BreadcrumbDropResult.rejected(BreadcrumbDropRejection.tooClose);
            onDropResult?.call(result);
            return result;
          }
        }

        // Check 3: Speed plausibility (applies to all drops)
        if (timeSinceLastDrop.inSeconds > 0 && distance >= minimumDistanceMeters) {
          final speedKmh = (distance / 1000) / (timeSinceLastDrop.inSeconds / 3600);
          if (speedKmh > maximumSpeedKmh) {
            debugPrint('🚫 Speed too fast (${speedKmh.toStringAsFixed(0)} km/h) - drop rejected');
            _setState(isCollecting ? BreadcrumbEngineState.collecting : BreadcrumbEngineState.idle);
            final result = BreadcrumbDropResult.rejected(BreadcrumbDropRejection.tooFast);
            onDropResult?.call(result);
            return result;
          }
        }
      }
      // === END DEDUPLICATION CHECK ===

      final contextDigest = _h3.createContextDigest(
        h3Cell: h3Cell,
        imuVector: _getIMUVector(),
        timestamp: DateTime.now(),
      );

      final previousHash = previousBlock?.blockHash;
      final nextIndex = (previousBlock?.index ?? -1) + 1;

      final builder = BreadcrumbBlockBuilder(
        index: nextIndex,
        identityPublicKey: _keypair!.publicKeyHex,
        timestamp: DateTime.now(),
        locationCell: h3Cell,
        locationResolution: h3Resolution,
        contextDigest: contextDigest,
        previousHash: previousHash,
        metaFlags: BreadcrumbMetaFlags.create(
          gpsAccuracy: position.accuracy,
          manualDrop: manual,
          deviceState: _getDeviceState(),
        ),
      );

      final dataToSign = Uint8List.fromList(utf8.encode(builder.dataToSign));
      final signature = await _keypair!.signToHex(dataToSign);

      final block = builder.build(signature);
      await _chainStorage.addBlock(block);
      
      // Increment cell counter for same-location tracking
      _incrementCellCount(h3Cell);

      final count = await _storage.incrementBreadcrumbCount();
      await _storage.storeLastBreadcrumbAt(block.timestamp);
      await _storage.storeChainHead(block.blockHash);

      if (count == 1) await _storage.storeFirstBreadcrumbAt(block.timestamp);

      // Track unique cells for better trust scoring
      await _updateUniqueCells(h3Cell);
      await _updateTrustScore(count);

      _setState(isCollecting ? BreadcrumbEngineState.collecting : BreadcrumbEngineState.idle);
      debugPrint('🍞 Breadcrumb #$count dropped: ${block.blockHash.substring(0, 8)}...');

      final result = BreadcrumbDropResult.success(block);
      onBreadcrumbDropped?.call(block);
      onDropResult?.call(result);
      return result;
    } catch (e) {
      _setState(isCollecting ? BreadcrumbEngineState.collecting : BreadcrumbEngineState.error);
      debugPrint('Breadcrumb error: $e');
      onError?.call('Failed to drop breadcrumb: $e');
      final result = BreadcrumbDropResult.error(e.toString());
      onDropResult?.call(result);
      return result;
    }
  }

  Future<Position?> _getPosition() async {
    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,  // ✅ Changed from high to medium (works better indoors)
      ).timeout(const Duration(seconds: 30));  // ✅ Increased from 15 to 30 seconds
    } catch (e) {
      debugPrint('GPS error: $e');
      return null;
    }
  }

  Map<String, double>? _getIMUVector() {
    if (_lastAccelerometer == null && _lastGyroscope == null) return null;
    return {
      if (_lastAccelerometer != null) ...{
        'acc_x': _lastAccelerometer!.x,
        'acc_y': _lastAccelerometer!.y,
        'acc_z': _lastAccelerometer!.z,
      },
      if (_lastGyroscope != null) ...{
        'gyro_x': _lastGyroscope!.x,
        'gyro_y': _lastGyroscope!.y,
        'gyro_z': _lastGyroscope!.z,
      },
    };
  }

  String _getDeviceState() {
    if (_lastAccelerometer == null) return 'unknown';
    final acc = _lastAccelerometer!;
    final magnitude = (acc.x * acc.x + acc.y * acc.y + acc.z * acc.z);
    if (magnitude < 90 || magnitude > 105) return 'moving';
    return 'stationary';
  }

  /// Track unique H3 cells visited (for trust scoring)
  Future<void> _updateUniqueCells(String h3Cell) async {
    // This could be stored in a separate table or secure storage
    // For now, we'll count from the chain
    // Future enhancement: store Set<String> of unique cells
  }

  /// Count how many breadcrumbs exist at a specific H3 cell
  /// Used to enforce same-location limit (max 10 at home/office)
  /// 
  /// SIMPLIFIED: For testing, we track this with a simple counter
  /// For production, this could query the chain more efficiently
  final Map<String, int> _cellCounts = {};
  
  Future<int> _countBreadcrumbsAtCell(String h3Cell) async {
    try {
      // Simple counter approach - tracks current session
      // Returns how many breadcrumbs were dropped at this cell so far
      return _cellCounts[h3Cell] ?? 0;
    } catch (e) {
      debugPrint('Error counting breadcrumbs at cell: $e');
      return 0; // Safe fallback
    }
  }
  
  /// Increment cell counter after successful drop
  void _incrementCellCount(String h3Cell) {
    _cellCounts[h3Cell] = (_cellCounts[h3Cell] ?? 0) + 1;
  }

  Future<void> _updateTrustScore(int breadcrumbCount) async {
    double score = 0;

    // Get unique cell count for better scoring
    final uniqueCells = await _chainStorage.getUniqueCellCount();
    
    // 40% from breadcrumb count (max at 200)
    score += (breadcrumbCount / 200.0).clamp(0.0, 0.4) * 100;

    // 30% from unique locations (max at 50 unique cells)
    score += (uniqueCells / 50.0).clamp(0.0, 0.3) * 100;

    // 20% from continuity (days since first / 365)
    final firstBreadcrumb = await _storage.readFirstBreadcrumbAt();
    if (firstBreadcrumb != null) {
      final daysSinceFirst = DateTime.now().difference(firstBreadcrumb).inDays;
      score += (daysSinceFirst / 365.0).clamp(0.0, 0.2) * 100;
    }

    // 10% from chain integrity
    final verification = await _chainStorage.verifyChain();
    if (verification.isValid) score += 10;

    await _storage.storeTrustScore(score.clamp(0, 100));
    debugPrint('Trust score updated: ${score.toStringAsFixed(1)}% (${uniqueCells} unique locations)');
  }

  void _setState(BreadcrumbEngineState newState) {
    if (_state != newState) {
      _state = newState;
      onStateChanged?.call(newState);
    }
  }

  Future<BreadcrumbStats> getStats() async {
    final count = await _storage.readBreadcrumbCount();
    final trustScore = await _storage.readTrustScore();
    final firstAt = await _storage.readFirstBreadcrumbAt();
    final lastAt = await _storage.readLastBreadcrumbAt();
    final epochCount = await _storage.readEpochCount();
    final chainVerification = await _chainStorage.verifyChain();
    final uniqueCells = await _chainStorage.getUniqueCellCount();

    return BreadcrumbStats(
      breadcrumbCount: count,
      epochCount: epochCount,
      trustScore: trustScore,
      firstBreadcrumbAt: firstAt,
      lastBreadcrumbAt: lastAt,
      chainValid: chainVerification.isValid,
      chainIssues: chainVerification.issues,
      uniqueLocations: uniqueCells,
    );
  }

  /// Get info about last drop location (for UI)
  Future<LastDropInfo?> getLastDropInfo() async {
    final block = await _chainStorage.getLatestBlock();
    if (block == null) return null;

    return LastDropInfo(
      h3Cell: block.locationCell,
      timestamp: block.timestamp,
      blockIndex: block.index,
    );
  }

  void dispose() {
    stopCollection();
    _accelerometerSubscription?.cancel();
    _gyroscopeSubscription?.cancel();
    _chainStorage.close();
  }
}

class BreadcrumbStats {
  final int breadcrumbCount;
  final int epochCount;
  final double trustScore;
  final DateTime? firstBreadcrumbAt;
  final DateTime? lastBreadcrumbAt;
  final bool chainValid;
  final List<String> chainIssues;
  final int uniqueLocations;

  BreadcrumbStats({
    required this.breadcrumbCount,
    required this.epochCount,
    required this.trustScore,
    this.firstBreadcrumbAt,
    this.lastBreadcrumbAt,
    required this.chainValid,
    required this.chainIssues,
    this.uniqueLocations = 0,
  });

  int get daysSinceStart {
    if (firstBreadcrumbAt == null) return 0;
    return DateTime.now().difference(firstBreadcrumbAt!).inDays;
  }

  // ✅ DEV_MODE: Set to true for testing with fewer breadcrumbs
  static const bool _devMode = false;  // Set to true for testing
  static const int _devBreadcrumbsRequired = 3;  // For testing
  static const double _devTrustRequired = 1.0;   // For testing
  
  bool get canClaimHandle {
    if (_devMode) {
      return breadcrumbCount >= _devBreadcrumbsRequired && trustScore >= _devTrustRequired;
    }
    return breadcrumbCount >= 100 && trustScore >= 20;
  }
  
  double get locationDiversity => uniqueLocations > 0 
      ? (uniqueLocations / breadcrumbCount * 100).clamp(0, 100) 
      : 0;
}

class LastDropInfo {
  final String h3Cell;
  final DateTime timestamp;
  final int blockIndex;

  LastDropInfo({
    required this.h3Cell,
    required this.timestamp,
    required this.blockIndex,
  });

  Duration get timeSinceDrop => DateTime.now().difference(timestamp);
}
