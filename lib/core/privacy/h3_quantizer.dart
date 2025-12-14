import 'dart:convert';
import 'dart:typed_data';
import 'package:h3_flutter/h3_flutter.dart';
import 'package:pointycastle/pointycastle.dart';

class H3Quantizer {
  static final H3Quantizer _instance = H3Quantizer._internal();
  factory H3Quantizer() => _instance;
  H3Quantizer._internal();

  final h3 = const H3Factory().load();

  static const int defaultResolution = 10;
  static const int publicResolution = 7;
  static const int preciseResolution = 12;

  BigInt latLonToH3(double lat, double lon, {int resolution = defaultResolution}) {
    final coord = GeoCoord(lat: lat, lon: lon);
    return h3.geoToH3(coord, resolution);
  }

  String latLonToH3Hex(double lat, double lon, {int resolution = defaultResolution}) {
    final h3Index = latLonToH3(lat, lon, resolution: resolution);
    return h3Index.toRadixString(16).padLeft(15, '0');
  }

  GeoCoord h3ToLatLon(BigInt h3Index) {
    return h3.h3ToGeo(h3Index);
  }

  GeoCoord h3HexToLatLon(String h3Hex) {
    final h3Index = BigInt.parse(h3Hex, radix: 16);
    return h3ToLatLon(h3Index);
  }

  BigInt getParent(BigInt h3Index, int parentResolution) {
    return h3.h3ToParent(h3Index, parentResolution);
  }

  String getParentHex(String h3Hex, int parentResolution) {
    final h3Index = BigInt.parse(h3Hex, radix: 16);
    final parent = getParent(h3Index, parentResolution);
    return parent.toRadixString(16).padLeft(15, '0');
  }

  List<BigInt> getNeighbors(BigInt h3Index) {
    return h3.kRing(h3Index, 1);
  }

  bool areNeighbors(BigInt cell1, BigInt cell2) {
    final neighbors = getNeighbors(cell1);
    return neighbors.contains(cell2);
  }

  String createContextDigest({
    required String h3Cell,
    List<String>? wifiBssids,
    List<String>? cellTowerIds,
    Map<String, double>? imuVector,
    required DateTime timestamp,
  }) {
    final components = <String>[
      'h3:$h3Cell',
      'ts:${_bucketTimestamp(timestamp)}',
    ];

    if (wifiBssids != null && wifiBssids.isNotEmpty) {
      final wifiSorted = List<String>.from(wifiBssids)..sort();
      final wifiHash = _sha256(wifiSorted.join(','));
      components.add('wifi:${wifiHash.substring(0, 16)}');
    }

    if (cellTowerIds != null && cellTowerIds.isNotEmpty) {
      final cellSorted = List<String>.from(cellTowerIds)..sort();
      final cellHash = _sha256(cellSorted.join(','));
      components.add('cell:${cellHash.substring(0, 16)}');
    }

    if (imuVector != null && imuVector.isNotEmpty) {
      final imuStr = imuVector.entries.map((e) => '${e.key}:${e.value.toStringAsFixed(2)}').join(',');
      final imuHash = _sha256(imuStr);
      components.add('imu:${imuHash.substring(0, 16)}');
    }

    return _sha256(components.join('|'));
  }

  int _bucketTimestamp(DateTime time) {
    final epochMinutes = time.millisecondsSinceEpoch ~/ 60000;
    return (epochMinutes ~/ 5) * 5;
  }

  String _sha256(String input) {
    final digest = Digest('SHA-256');
    final bytes = digest.process(Uint8List.fromList(utf8.encode(input)));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Map<String, dynamic> createLocationProof({
    required String preciseH3Cell,
    required int disclosureLevel,
  }) {
    final preciseIndex = BigInt.parse(preciseH3Cell, radix: 16);
    final disclosedIndex = getParent(preciseIndex, disclosureLevel);

    return {
      'disclosed_cell': disclosedIndex.toRadixString(16).padLeft(15, '0'),
      'disclosure_resolution': disclosureLevel,
      'precise_resolution': h3.h3GetResolution(preciseIndex),
      'approximate_area_km2': _getAreaForResolution(disclosureLevel),
    };
  }

  double _getAreaForResolution(int resolution) {
    const areas = <int, double>{
      0: 4250546.848, 1: 607220.978, 2: 86745.854, 3: 12392.264,
      4: 1770.323, 5: 252.903, 6: 36.129, 7: 5.161, 8: 0.737,
      9: 0.105, 10: 0.015, 11: 0.002, 12: 0.0003, 13: 0.00004,
      14: 0.000006, 15: 0.0000009,
    };
    return areas[resolution] ?? 0.0;
  }

  bool isTrajectoryPlausible(
    String h3Cell1, DateTime time1,
    String h3Cell2, DateTime time2,
    {double maxSpeedKmh = 200}
  ) {
    final index1 = BigInt.parse(h3Cell1, radix: 16);
    final index2 = BigInt.parse(h3Cell2, radix: 16);
    final center1 = h3ToLatLon(index1);
    final center2 = h3ToLatLon(index2);

    final distanceKm = _haversineDistance(center1.lat, center1.lon, center2.lat, center2.lon);
    final timeDiffHours = time2.difference(time1).inMinutes / 60.0;
    if (timeDiffHours <= 0) return false;

    final speedKmh = distanceKm / timeDiffHours;
    return speedKmh <= maxSpeedKmh;
  }

  double _haversineDistance(double lat1, double lon1, double lat2, double lon2) {
    const earthRadiusKm = 6371.0;
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final a = _sin(dLat / 2) * _sin(dLat / 2) +
        _cos(_toRadians(lat1)) * _cos(_toRadians(lat2)) * _sin(dLon / 2) * _sin(dLon / 2);
    final c = 2 * _atan2(_sqrt(a), _sqrt(1 - a));
    return earthRadiusKm * c;
  }

  double _toRadians(double deg) => deg * 3.141592653589793 / 180;
  double _sin(double x) => _taylorSin(x);
  double _cos(double x) => _taylorSin(x + 1.5707963267948966);
  double _sqrt(double x) => x > 0 ? _newtonSqrt(x) : 0;
  double _atan2(double y, double x) {
    if (x > 0) return _taylorAtan(y / x);
    if (x < 0 && y >= 0) return _taylorAtan(y / x) + 3.141592653589793;
    if (x < 0 && y < 0) return _taylorAtan(y / x) - 3.141592653589793;
    if (y > 0) return 1.5707963267948966;
    if (y < 0) return -1.5707963267948966;
    return 0;
  }

  double _taylorSin(double x) {
    x = x % (2 * 3.141592653589793);
    double result = x, term = x;
    for (int i = 1; i < 10; i++) {
      term *= -x * x / ((2 * i) * (2 * i + 1));
      result += term;
    }
    return result;
  }

  double _taylorAtan(double x) {
    if (x.abs() > 1) return (x > 0 ? 1 : -1) * 1.5707963267948966 - _taylorAtan(1 / x);
    double result = x, term = x;
    for (int i = 1; i < 20; i++) {
      term *= -x * x;
      result += term / (2 * i + 1);
    }
    return result;
  }

  double _newtonSqrt(double x) {
    if (x == 0) return 0;
    double guess = x / 2;
    for (int i = 0; i < 20; i++) guess = (guess + x / guess) / 2;
    return guess;
  }
}

class QuantizedLocation {
  final String h3Cell;
  final int resolution;
  final String contextDigest;
  final DateTime timestamp;

  QuantizedLocation({
    required this.h3Cell,
    required this.resolution,
    required this.contextDigest,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'h3_cell': h3Cell,
    'resolution': resolution,
    'context_digest': contextDigest,
    'timestamp': timestamp.toIso8601String(),
  };

  factory QuantizedLocation.fromJson(Map<String, dynamic> json) {
    return QuantizedLocation(
      h3Cell: json['h3_cell'] as String,
      resolution: json['resolution'] as int,
      contextDigest: json['context_digest'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }
}
