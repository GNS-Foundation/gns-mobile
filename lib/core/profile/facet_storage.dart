/// Facet Storage - Phase 4c
/// 
/// Persists profile facets to local SQLite database.
/// Integrates with existing profile infrastructure.
/// 
/// Location: lib/core/profile/facet_storage.dart

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'profile_facet.dart';
import 'profile_module.dart';

class FacetStorage {
  static final FacetStorage _instance = FacetStorage._internal();
  factory FacetStorage() => _instance;
  FacetStorage._internal();

  Database? _database;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    final documentsDir = await getApplicationDocumentsDirectory();
    final dbPath = join(documentsDir.path, 'gns_facets.db');

    _database = await openDatabase(
      dbPath,
      version: 1,
      onCreate: _createTables,
    );

    _initialized = true;
    debugPrint('Facet storage initialized: $dbPath');
  }

  Future<void> _createTables(Database db, int version) async {
    await db.execute('''
      CREATE TABLE facets (
        id TEXT PRIMARY KEY,
        label TEXT NOT NULL,
        emoji TEXT NOT NULL,
        display_name TEXT,
        avatar_url TEXT,
        bio TEXT,
        links TEXT,
        is_default INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE facet_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    // Create default facet
    final now = DateTime.now().toIso8601String();
    await db.insert('facets', {
      'id': 'default',
      'label': 'Default',
      'emoji': '👤',
      'is_default': 1,
      'links': '[]',
      'created_at': now,
      'updated_at': now,
    });

    debugPrint('Facet tables created with default facet');
  }

  Future<void> _ensureInitialized() async {
    if (!_initialized) await initialize();
  }

  // ==================== FACET CRUD ====================

  Future<void> saveFacet(ProfileFacet facet) async {
    await _ensureInitialized();

    await _database!.insert(
      'facets',
      {
        'id': facet.id,
        'label': facet.label,
        'emoji': facet.emoji,
        'display_name': facet.displayName,
        'avatar_url': facet.avatarUrl,
        'bio': facet.bio,
        'links': jsonEncode(facet.links.map((l) => l.toJson()).toList()),
        'is_default': facet.isDefault ? 1 : 0,
        'created_at': facet.createdAt.toIso8601String(),
        'updated_at': facet.updatedAt.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    debugPrint('Facet saved: ${facet.id}');
  }

  Future<ProfileFacet?> getFacet(String id) async {
    await _ensureInitialized();

    final results = await _database!.query(
      'facets',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (results.isEmpty) return null;
    return _rowToFacet(results.first);
  }

  Future<List<ProfileFacet>> getAllFacets() async {
    await _ensureInitialized();

    final results = await _database!.query(
      'facets',
      orderBy: 'is_default DESC, created_at ASC',
    );

    return results.map(_rowToFacet).toList();
  }

  Future<ProfileFacet?> getDefaultFacet() async {
    await _ensureInitialized();

    final results = await _database!.query(
      'facets',
      where: 'is_default = 1',
      limit: 1,
    );

    if (results.isEmpty) {
      // Return first facet if no default
      final all = await getAllFacets();
      return all.isNotEmpty ? all.first : null;
    }
    return _rowToFacet(results.first);
  }

  Future<void> deleteFacet(String id) async {
    await _ensureInitialized();

    if (id == 'default') {
      debugPrint('Cannot delete default facet');
      return;
    }

    await _database!.delete(
      'facets',
      where: 'id = ?',
      whereArgs: [id],
    );

    debugPrint('Facet deleted: $id');
  }

  Future<void> setDefaultFacet(String id) async {
    await _ensureInitialized();

    // Clear all defaults
    await _database!.update(
      'facets',
      {'is_default': 0},
    );

    // Set new default
    await _database!.update(
      'facets',
      {'is_default': 1},
      where: 'id = ?',
      whereArgs: [id],
    );

    debugPrint('Default facet set: $id');
  }

  // ==================== SETTINGS ====================

  Future<void> setSetting(String key, String value) async {
    await _ensureInitialized();
    await _database!.insert(
      'facet_settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getSetting(String key) async {
    await _ensureInitialized();
    final results = await _database!.query(
      'facet_settings',
      where: 'key = ?',
      whereArgs: [key],
    );
    if (results.isEmpty) return null;
    return results.first['value'] as String;
  }

  Future<String?> getPrimaryFacetId() async {
    return await getSetting('primary_facet_id');
  }

  Future<void> setPrimaryFacetId(String id) async {
    await setSetting('primary_facet_id', id);
  }

  // ==================== COLLECTION ====================

  Future<FacetCollection> getFacetCollection() async {
    final facets = await getAllFacets();
    final defaultFacet = await getDefaultFacet();
    final primaryId = await getPrimaryFacetId();

    return FacetCollection(
      facets: facets,
      defaultFacetId: defaultFacet?.id,
      primaryFacetId: primaryId,
    );
  }

  Future<void> saveFacetCollection(FacetCollection collection) async {
    for (final facet in collection.facets) {
      await saveFacet(facet);
    }
    if (collection.defaultFacetId != null) {
      await setDefaultFacet(collection.defaultFacetId!);
    }
    if (collection.primaryFacetId != null) {
      await setPrimaryFacetId(collection.primaryFacetId!);
    }
  }

  // ==================== MIGRATION ====================

  /// Migrate from existing ProfileData to facets
  Future<void> migrateFromProfileData(ProfileData? data) async {
    await _ensureInitialized();

    // Check if we already have facets
    final existing = await getAllFacets();
    if (existing.isNotEmpty) {
      debugPrint('Facets already exist, skipping migration');
      return;
    }

    if (data == null || data.isEmpty) {
      debugPrint('No profile data to migrate');
      return;
    }

    // Create default facet from existing profile data
    final facet = ProfileFacet.fromProfileData(data, id: 'default');
    await saveFacet(facet);
    await setDefaultFacet('default');

    debugPrint('Migrated ProfileData to default facet');
  }

  // ==================== HELPERS ====================

  ProfileFacet _rowToFacet(Map<String, dynamic> row) {
    List<ProfileLink> links = [];
    try {
      final linksJson = row['links'] as String?;
      if (linksJson != null && linksJson.isNotEmpty) {
        final decoded = jsonDecode(linksJson) as List;
        links = decoded.map((l) => ProfileLink.fromJson(l as Map<String, dynamic>)).toList();
      }
    } catch (e) {
      debugPrint('Error parsing links: $e');
    }

    return ProfileFacet(
      id: row['id'] as String,
      label: row['label'] as String,
      emoji: row['emoji'] as String? ?? '👤',
      displayName: row['display_name'] as String?,
      avatarUrl: row['avatar_url'] as String?,
      bio: row['bio'] as String?,
      links: links,
      isDefault: (row['is_default'] as int?) == 1,
      createdAt: DateTime.tryParse(row['created_at'] as String? ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(row['updated_at'] as String? ?? '') ?? DateTime.now(),
    );
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
    _initialized = false;
  }

  Future<void> deleteAll() async {
    await _ensureInitialized();
    await _database!.delete('facets');
    await _database!.delete('facet_settings');
    
    // Recreate default facet
    final now = DateTime.now().toIso8601String();
    await _database!.insert('facets', {
      'id': 'default',
      'label': 'Default',
      'emoji': '👤',
      'is_default': 1,
      'links': '[]',
      'created_at': now,
      'updated_at': now,
    });
    
    debugPrint('All facets deleted, default recreated');
  }
}
