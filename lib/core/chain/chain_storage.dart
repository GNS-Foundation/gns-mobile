/// Chain Storage - Updated with Unique Location Tracking
/// 
/// Now tracks unique H3 cells for better trust scoring.
/// Location diversity matters!
///
/// Location: lib/core/chain/chain_storage.dart

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'breadcrumb_block.dart';

class ChainStorage {
  static final ChainStorage _instance = ChainStorage._internal();
  factory ChainStorage() => _instance;
  ChainStorage._internal();

  Database? _database;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    final documentsDir = await getApplicationDocumentsDirectory();
    final dbPath = join(documentsDir.path, 'gns_chain.db');

    _database = await openDatabase(
      dbPath,
      version: 2,  // Bumped version for migration
      onCreate: _createTables,
      onUpgrade: _onUpgrade,
    );

    _initialized = true;
    debugPrint('Chain storage initialized: $dbPath');
  }

  Future<void> _createTables(Database db, int version) async {
    await db.execute('''
      CREATE TABLE breadcrumbs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        block_index INTEGER NOT NULL UNIQUE,
        identity_public_key TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        location_cell TEXT NOT NULL,
        location_resolution INTEGER NOT NULL,
        context_digest TEXT NOT NULL,
        previous_hash TEXT,
        meta_flags TEXT NOT NULL,
        signature TEXT NOT NULL,
        block_hash TEXT NOT NULL UNIQUE,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    await db.execute('''
      CREATE TABLE epochs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        epoch_index INTEGER NOT NULL UNIQUE,
        start_time TEXT NOT NULL,
        end_time TEXT NOT NULL,
        start_block_index INTEGER NOT NULL,
        end_block_index INTEGER NOT NULL,
        merkle_root TEXT NOT NULL,
        block_count INTEGER NOT NULL,
        previous_epoch_hash TEXT,
        signature TEXT NOT NULL,
        epoch_hash TEXT NOT NULL UNIQUE,
        published_at TEXT,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    // NEW: Track unique locations visited
    await db.execute('''
      CREATE TABLE unique_cells (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        location_cell TEXT NOT NULL UNIQUE,
        first_visited_at TEXT NOT NULL,
        visit_count INTEGER NOT NULL DEFAULT 1
      )
    ''');

    await db.execute('CREATE INDEX idx_breadcrumbs_timestamp ON breadcrumbs(timestamp)');
    await db.execute('CREATE INDEX idx_breadcrumbs_location ON breadcrumbs(location_cell)');
    await db.execute('CREATE INDEX idx_breadcrumbs_hash ON breadcrumbs(block_hash)');
    await db.execute('CREATE INDEX idx_unique_cells_cell ON unique_cells(location_cell)');

    debugPrint('Database tables created');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Add unique_cells table if upgrading from v1
      await db.execute('''
        CREATE TABLE IF NOT EXISTS unique_cells (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          location_cell TEXT NOT NULL UNIQUE,
          first_visited_at TEXT NOT NULL,
          visit_count INTEGER NOT NULL DEFAULT 1
        )
      ''');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_unique_cells_cell ON unique_cells(location_cell)');
      
      // Populate from existing breadcrumbs
      await _rebuildUniqueCells(db);
      debugPrint('Database upgraded to v2 with unique_cells tracking');
    }
  }

  Future<void> _rebuildUniqueCells(Database db) async {
    final blocks = await db.query('breadcrumbs', orderBy: 'block_index ASC');
    for (final row in blocks) {
      final cell = row['location_cell'] as String;
      final timestamp = row['timestamp'] as String;
      await db.insert(
        'unique_cells',
        {
          'location_cell': cell,
          'first_visited_at': timestamp,
          'visit_count': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  Future<void> _ensureInitialized() async {
    if (!_initialized) await initialize();
  }

  Future<int> addBlock(BreadcrumbBlock block) async {
    await _ensureInitialized();

    final result = await _database!.insert(
      'breadcrumbs',
      {
        'block_index': block.index,
        'identity_public_key': block.identityPublicKey,
        'timestamp': block.timestamp.toUtc().toIso8601String(),
        'location_cell': block.locationCell,
        'location_resolution': block.locationResolution,
        'context_digest': block.contextDigest,
        'previous_hash': block.previousHash,
        'meta_flags': jsonEncode(block.metaFlags),
        'signature': block.signature,
        'block_hash': block.blockHash,
      },
      conflictAlgorithm: ConflictAlgorithm.abort,
    );

    // Track unique cell
    await _trackUniqueCell(block.locationCell, block.timestamp);

    debugPrint('Block ${block.index} stored: ${block.blockHash.substring(0, 8)}...');
    return result;
  }

  /// Track a unique H3 cell visit
  Future<void> _trackUniqueCell(String cell, DateTime timestamp) async {
    try {
      // Try to insert new cell
      await _database!.insert(
        'unique_cells',
        {
          'location_cell': cell,
          'first_visited_at': timestamp.toUtc().toIso8601String(),
          'visit_count': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      
      // If already exists, increment visit count
      await _database!.rawUpdate('''
        UPDATE unique_cells 
        SET visit_count = visit_count + 1 
        WHERE location_cell = ?
      ''', [cell]);
    } catch (e) {
      debugPrint('Error tracking unique cell: $e');
    }
  }

  /// Get count of unique H3 cells visited
  Future<int> getUniqueCellCount() async {
    await _ensureInitialized();
    final result = await _database!.rawQuery('SELECT COUNT(*) as count FROM unique_cells');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Get all unique cells with their visit counts
  Future<List<UniqueCellInfo>> getUniqueCells() async {
    await _ensureInitialized();
    final results = await _database!.query(
      'unique_cells',
      orderBy: 'first_visited_at DESC',
    );
    return results.map((row) => UniqueCellInfo(
      cell: row['location_cell'] as String,
      firstVisitedAt: DateTime.parse(row['first_visited_at'] as String),
      visitCount: row['visit_count'] as int,
    )).toList();
  }

  /// Check if a cell has been visited before
  Future<bool> hasVisitedCell(String cell) async {
    await _ensureInitialized();
    final result = await _database!.query(
      'unique_cells',
      where: 'location_cell = ?',
      whereArgs: [cell],
    );
    return result.isNotEmpty;
  }

  Future<BreadcrumbBlock?> getLatestBlock() async {
    await _ensureInitialized();

    final results = await _database!.query(
      'breadcrumbs',
      orderBy: 'block_index DESC',
      limit: 1,
    );

    if (results.isEmpty) return null;
    return _rowToBlock(results.first);
  }

  Future<BreadcrumbBlock?> getBlockByIndex(int index) async {
    await _ensureInitialized();

    final results = await _database!.query(
      'breadcrumbs',
      where: 'block_index = ?',
      whereArgs: [index],
    );

    if (results.isEmpty) return null;
    return _rowToBlock(results.first);
  }

  Future<BreadcrumbBlock?> getBlockByHash(String hash) async {
    await _ensureInitialized();

    final results = await _database!.query(
      'breadcrumbs',
      where: 'block_hash = ?',
      whereArgs: [hash],
    );

    if (results.isEmpty) return null;
    return _rowToBlock(results.first);
  }

  Future<List<BreadcrumbBlock>> getBlocksInRange(DateTime start, DateTime end) async {
    await _ensureInitialized();

    final results = await _database!.query(
      'breadcrumbs',
      where: 'timestamp >= ? AND timestamp <= ?',
      whereArgs: [start.toUtc().toIso8601String(), end.toUtc().toIso8601String()],
      orderBy: 'block_index ASC',
    );

    return results.map(_rowToBlock).toList();
  }

  Future<int> getBlockCount() async {
    await _ensureInitialized();
    final result = await _database!.rawQuery('SELECT COUNT(*) as count FROM breadcrumbs');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<List<BreadcrumbBlock>> getFullChain() async {
    await _ensureInitialized();
    final results = await _database!.query('breadcrumbs', orderBy: 'block_index ASC');
    return results.map(_rowToBlock).toList();
  }

  Future<List<BreadcrumbBlock>> getRecentBlocks({int limit = 50}) async {
    await _ensureInitialized();
    final results = await _database!.query('breadcrumbs', orderBy: 'block_index DESC', limit: limit);
    return results.map(_rowToBlock).toList();
  }

  /// Get blocks at a specific location cell
  Future<List<BreadcrumbBlock>> getBlocksAtCell(String cell) async {
    await _ensureInitialized();
    final results = await _database!.query(
      'breadcrumbs',
      where: 'location_cell = ?',
      whereArgs: [cell],
      orderBy: 'block_index ASC',
    );
    return results.map(_rowToBlock).toList();
  }

  Future<ChainVerificationResult> verifyChain() async {
    await _ensureInitialized();

    final blocks = await getFullChain();
    if (blocks.isEmpty) {
      return ChainVerificationResult(isValid: true, blockCount: 0, issues: []);
    }

    final issues = <String>[];
    BreadcrumbBlock? previousBlock;

    for (final block in blocks) {
      if (previousBlock != null && block.index != previousBlock.index + 1) {
        issues.add('Block ${block.index}: Index gap');
      }
      if (!block.verifyChainLink(previousBlock)) {
        issues.add('Block ${block.index}: Invalid chain link');
      }
      if (block.computeHash() != block.blockHash) {
        issues.add('Block ${block.index}: Hash mismatch');
      }
      if (previousBlock != null && block.timestamp.isBefore(previousBlock.timestamp)) {
        issues.add('Block ${block.index}: Timestamp before previous');
      }
      previousBlock = block;
    }

    return ChainVerificationResult(isValid: issues.isEmpty, blockCount: blocks.length, issues: issues);
  }

  BreadcrumbBlock _rowToBlock(Map<String, dynamic> row) {
    return BreadcrumbBlock(
      index: row['block_index'] as int,
      identityPublicKey: row['identity_public_key'] as String,
      timestamp: DateTime.parse(row['timestamp'] as String),
      locationCell: row['location_cell'] as String,
      locationResolution: row['location_resolution'] as int,
      contextDigest: row['context_digest'] as String,
      previousHash: row['previous_hash'] as String?,
      metaFlags: jsonDecode(row['meta_flags'] as String) as Map<String, dynamic>,
      signature: row['signature'] as String,
    );
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
    _initialized = false;
  }

  Future<void> deleteAll() async {
    await _ensureInitialized();
    await _database!.delete('breadcrumbs');
    await _database!.delete('epochs');
    await _database!.delete('unique_cells');
    debugPrint('All chain data deleted');
  }
}

/// Information about a unique location cell
class UniqueCellInfo {
  final String cell;
  final DateTime firstVisitedAt;
  final int visitCount;

  UniqueCellInfo({
    required this.cell,
    required this.firstVisitedAt,
    required this.visitCount,
  });
}

class EpochSummary {
  final int epochIndex;
  final DateTime startTime;
  final DateTime endTime;
  final int startBlockIndex;
  final int endBlockIndex;
  final String merkleRoot;
  final int blockCount;
  final String? previousEpochHash;
  final String signature;
  final String epochHash;
  final DateTime? publishedAt;

  EpochSummary({
    required this.epochIndex,
    required this.startTime,
    required this.endTime,
    required this.startBlockIndex,
    required this.endBlockIndex,
    required this.merkleRoot,
    required this.blockCount,
    this.previousEpochHash,
    required this.signature,
    required this.epochHash,
    this.publishedAt,
  });
}

class ChainVerificationResult {
  final bool isValid;
  final int blockCount;
  final List<String> issues;

  ChainVerificationResult({required this.isValid, required this.blockCount, required this.issues});
}
