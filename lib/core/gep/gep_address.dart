/// GEP Address Utility
///
/// Computes GeoEpoch Addresses (GEA) from latitude/longitude coordinates
/// using the existing H3Quantizer infrastructure.
///
/// A GEA is the user's identity in GEP space — their permanent geographic
/// address derived from the H3 grid, displayed alongside their @handle.
///
/// Location: lib/core/gep/gep_address.dart

import 'dart:convert';
import 'dart:typed_data';
import 'package:pointycastle/pointycastle.dart';
import '../privacy/h3_quantizer.dart';

class GepAddress {
  /// The H3 cell index at the given resolution (hex string)
  final String cellIndex;

  /// The SHA-256 hash of the cell index
  final String cellHash;

  /// H3 resolution level (0-15)
  final int resolution;

  /// Encoded GEA string: gea:RR:HASH
  final String encoded;

  /// Original coordinates (if available)
  final double? lat;
  final double? lon;

  GepAddress._({
    required this.cellIndex,
    required this.cellHash,
    required this.resolution,
    required this.encoded,
    this.lat,
    this.lon,
  });

  /// GEP protocol version
  static const int protocolVersion = 1;

  /// Default resolution for user-facing GEA (neighborhood level)
  static const int defaultResolution = 7;

  /// Genesis hash — the cryptographic anchor of GEP
  static const String genesisHash =
      '26acb5d998b63d54f2ed92851c5c565db9fe0930fc06b06091d05c0ce4ff8289';

  /// Compute GEA from latitude/longitude
  static GepAddress fromLatLon(
    double lat,
    double lon, {
    int resolution = defaultResolution,
  }) {
    final quantizer = H3Quantizer();
    final cellIndex = quantizer.latLonToH3Hex(lat, lon, resolution: resolution);
    final hash = _sha256(cellIndex);
    final resStr = resolution.toString().padLeft(2, '0');

    return GepAddress._(
      cellIndex: cellIndex,
      cellHash: hash,
      resolution: resolution,
      encoded: 'gea:$resStr:$hash',
      lat: lat,
      lon: lon,
    );
  }

  /// Compute GEA from an existing H3 cell index (hex string)
  static GepAddress fromH3Hex(String h3Hex, int resolution) {
    final hash = _sha256(h3Hex);
    final resStr = resolution.toString().padLeft(2, '0');

    // Get centroid for display
    final quantizer = H3Quantizer();
    final coord = quantizer.h3HexToLatLon(h3Hex);

    return GepAddress._(
      cellIndex: h3Hex,
      cellHash: hash,
      resolution: resolution,
      encoded: 'gea:$resStr:$hash',
      lat: coord.lat,
      lon: coord.lon,
    );
  }

  /// Parse a GEA string back into components
  static GepAddress? parse(String gea) {
    final match = RegExp(r'^gea:(\d{2}):([a-f0-9]{64})$').firstMatch(gea);
    if (match == null) return null;

    final resolution = int.parse(match.group(1)!);
    final hash = match.group(2)!;

    return GepAddress._(
      cellIndex: '', // unknown without reverse lookup
      cellHash: hash,
      resolution: resolution,
      encoded: gea,
    );
  }

  /// Short display form: gea:07:3f8d2a1b...
  String get shortDisplay {
    if (cellHash.length >= 8) {
      final resStr = resolution.toString().padLeft(2, '0');
      return 'gea:$resStr:${cellHash.substring(0, 8)}...';
    }
    return encoded;
  }

  /// Very short form for compact UI: 3f8d2a1b
  String get tinyDisplay => cellHash.length >= 8 ? cellHash.substring(0, 8) : cellHash;

  /// Resolution label
  String get resolutionLabel {
    switch (resolution) {
      case 0: return 'Continent';
      case 1: return 'Subcontinent';
      case 2: return 'Nation';
      case 3: return 'Province';
      case 4: return 'County';
      case 5: return 'City';
      case 6: return 'District';
      case 7: return 'Neighborhood';
      case 8: return 'Block';
      case 9: return 'Building';
      case 10: return 'Room';
      default: return 'R$resolution';
    }
  }

  /// GEP URL form: gep://gea:07:HASH/
  String get gepUrl => 'gep://$encoded/';

  /// SHA-256 of a string
  static String _sha256(String input) {
    final digest = Digest('SHA-256');
    final bytes = digest.process(Uint8List.fromList(utf8.encode(input)));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Compute GEAs at multiple resolutions for the same location
  static List<GepAddress> multiResolution(
    double lat,
    double lon, {
    List<int> resolutions = const [5, 7, 9],
  }) {
    return resolutions.map((r) => fromLatLon(lat, lon, resolution: r)).toList();
  }

  @override
  String toString() => 'GepAddress($encoded)';

  @override
  bool operator ==(Object other) =>
      other is GepAddress && other.encoded == encoded;

  @override
  int get hashCode => encoded.hashCode;
}
