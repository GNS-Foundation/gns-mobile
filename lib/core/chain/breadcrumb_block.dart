import 'dart:convert';
import 'dart:typed_data';
import 'package:pointycastle/pointycastle.dart';

class BreadcrumbBlock {
  final int index;
  final String identityPublicKey;
  final DateTime timestamp;
  final String locationCell;
  final int locationResolution;
  final String contextDigest;
  final String? previousHash;
  final Map<String, dynamic> metaFlags;
  final String signature;
  late final String blockHash;

  BreadcrumbBlock({
    required this.index,
    required this.identityPublicKey,
    required this.timestamp,
    required this.locationCell,
    required this.locationResolution,
    required this.contextDigest,
    required this.previousHash,
    required this.metaFlags,
    required this.signature,
  }) {
    blockHash = computeHash();
  }

  factory BreadcrumbBlock.genesis({
    required String identityPublicKey,
    required DateTime timestamp,
    required String locationCell,
    required int locationResolution,
    required String contextDigest,
    required Map<String, dynamic> metaFlags,
    required String signature,
  }) {
    return BreadcrumbBlock(
      index: 0,
      identityPublicKey: identityPublicKey,
      timestamp: timestamp,
      locationCell: locationCell,
      locationResolution: locationResolution,
      contextDigest: contextDigest,
      previousHash: null,
      metaFlags: metaFlags,
      signature: signature,
    );
  }

  String get dataToSign {
    final data = {
      'index': index,
      'identity': identityPublicKey,
      'timestamp': timestamp.toUtc().toIso8601String(),
      'loc_cell': locationCell,
      'loc_res': locationResolution,
      'context': contextDigest,
      'prev_hash': previousHash ?? 'genesis',
      'meta': metaFlags,
    };
    return jsonEncode(data);
  }

  String computeHash() {
    final content = '$dataToSign:$signature';
    final digest = Digest('SHA-256');
    final bytes = digest.process(Uint8List.fromList(utf8.encode(content)));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  bool verifyChainLink(BreadcrumbBlock? previousBlock) {
    if (index == 0) return previousHash == null;
    if (previousBlock == null) return false;
    return previousHash == previousBlock.blockHash;
  }

  Map<String, dynamic> toJson() => {
    'index': index,
    'identity_public_key': identityPublicKey,
    'timestamp': timestamp.toUtc().toIso8601String(),
    'location_cell': locationCell,
    'location_resolution': locationResolution,
    'context_digest': contextDigest,
    'previous_hash': previousHash,
    'meta_flags': metaFlags,
    'signature': signature,
    'block_hash': blockHash,
  };

  factory BreadcrumbBlock.fromJson(Map<String, dynamic> json) {
    return BreadcrumbBlock(
      index: json['index'] as int,
      identityPublicKey: json['identity_public_key'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      locationCell: json['location_cell'] as String,
      locationResolution: json['location_resolution'] as int,
      contextDigest: json['context_digest'] as String,
      previousHash: json['previous_hash'] as String?,
      metaFlags: Map<String, dynamic>.from(json['meta_flags'] as Map),
      signature: json['signature'] as String,
    );
  }

  @override
  String toString() => 'Block[$index] ${blockHash.substring(0, 8)}...';
}

class BreadcrumbBlockBuilder {
  final int index;
  final String identityPublicKey;
  final DateTime timestamp;
  final String locationCell;
  final int locationResolution;
  final String contextDigest;
  final String? previousHash;
  final Map<String, dynamic> metaFlags;

  BreadcrumbBlockBuilder({
    required this.index,
    required this.identityPublicKey,
    required this.timestamp,
    required this.locationCell,
    required this.locationResolution,
    required this.contextDigest,
    this.previousHash,
    Map<String, dynamic>? metaFlags,
  }) : metaFlags = metaFlags ?? {};

  String get dataToSign {
    final data = {
      'index': index,
      'identity': identityPublicKey,
      'timestamp': timestamp.toUtc().toIso8601String(),
      'loc_cell': locationCell,
      'loc_res': locationResolution,
      'context': contextDigest,
      'prev_hash': previousHash ?? 'genesis',
      'meta': metaFlags,
    };
    return jsonEncode(data);
  }

  BreadcrumbBlock build(String signature) {
    return BreadcrumbBlock(
      index: index,
      identityPublicKey: identityPublicKey,
      timestamp: timestamp,
      locationCell: locationCell,
      locationResolution: locationResolution,
      contextDigest: contextDigest,
      previousHash: previousHash,
      metaFlags: metaFlags,
      signature: signature,
    );
  }
}

class BreadcrumbMetaFlags {
  static const batteryLevel = 'battery';
  static const samplingMode = 'sampling';
  static const deviceState = 'state';
  static const networkType = 'network';
  static const gpsAccuracy = 'accuracy';
  static const manualDrop = 'manual';

  static Map<String, dynamic> create({
    int? batteryLevel,
    String samplingMode = 'normal',
    String deviceState = 'unknown',
    String networkType = 'unknown',
    double? gpsAccuracy,
    bool manualDrop = false,
  }) {
    return {
      BreadcrumbMetaFlags.batteryLevel: batteryLevel,
      BreadcrumbMetaFlags.samplingMode: samplingMode,
      BreadcrumbMetaFlags.deviceState: deviceState,
      BreadcrumbMetaFlags.networkType: networkType,
      BreadcrumbMetaFlags.gpsAccuracy: gpsAccuracy,
      BreadcrumbMetaFlags.manualDrop: manualDrop,
    };
  }
}
