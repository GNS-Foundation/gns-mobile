/// Facet Storage - Phase 4c + Meta-Identity Architecture
/// 
/// Persists profile facets to local SQLite database.
/// 
/// Key features:
/// - Auto-creates me@ facet on initialization
/// - Migrates existing 'default' facet to 'me'
/// - Supports FacetType (default, custom, broadcast)
/// - Cannot delete default me@ facet
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
      version: 2,  // Bumped for facet_type column
      onCreate: _createTables,
      onUpgrade: _upgradeTables,
    );

    _initialized = true;
    
    // Ensure default "me" facet exists
    await _ensureDefaultFacet();
    
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
        facet_type TEXT NOT NULL DEFAULT 'custom',
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

    // Create default "me" facet
    final now = DateTime.now().toIso8601String();
    await db.insert('facets', {
      'id': 'me',
      'label': 'Me',
      'emoji': '👤',
      'facet_type': 'defaultPersonal',
      'is_default': 1,
      'links': '[]',
      'created_at': now,
      'updated_at': now,
    });

    debugPrint('Facet tables created with default "me" facet');
  }

  Future<void> _upgradeTables(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Add facet_type column if upgrading from v1
      try {
        await db.execute('ALTER TABLE facets ADD COLUMN facet_type TEXT DEFAULT "custom"');
        debugPrint('Added facet_type column');
      } catch (e) {
        debugPrint('Column facet_type might already exist: $e');
      }
      
      // Migrate 'default' facet to 'me' with correct type
      final existing = await db.query('facets', where: 'id = ?', whereArgs: ['default']);
      if (existing.isNotEmpty) {
        final row = existing.first;
        
        // Insert new 'me' facet with migrated data
        await db.insert('facets', {
          'id': 'me',
          'label': 'Me',
          'emoji': row['emoji'] ?? '👤',
          'display_name': row['display_name'],
          'avatar_url': row['avatar_url'],
          'bio': row['bio'],
          'links': row['links'] ?? '[]',
          'facet_type': 'defaultPersonal',
          'is_default': 1,
          'created_at': row['created_at'] ?? DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        
        // Delete old 'default' facet
        await db.delete('facets', where: 'id = ?', whereArgs: ['default']);
        
        debugPrint('Migrated "default" facet to "me"');
      } else {
        // No 'default' facet, just update any existing default
        await db.execute('''
          UPDATE facets 
          SET facet_type = 'defaultPersonal'
          WHERE is_default = 1
        ''');
      }
      
      debugPrint('Upgraded facets table to version 2');
    }
  }

  Future<void> _ensureInitialized() async {
    if (!_initialized) await initialize();
  }

  /// Ensure the default "me" facet exists
  Future<void> _ensureDefaultFacet() async {
    // Check for 'me' facet
    final meResults = await _database!.query(
      'facets',
      where: 'id = ?',
      whereArgs: ['me'],
    );
    
    if (meResults.isEmpty) {
      // Check for old 'default' facet to migrate
      final defaultResults = await _database!.query(
        'facets',
        where: 'id = ?',
        whereArgs: ['default'],
      );
      
      if (defaultResults.isNotEmpty) {
        // Migrate 'default' to 'me'
        final row = defaultResults.first;
        await _database!.insert('facets', {
          'id': 'me',
          'label': 'Me',
          'emoji': row['emoji'] ?? '👤',
          'display_name': row['display_name'],
          'avatar_url': row['avatar_url'],
          'bio': row['bio'],
          'links': row['links'] ?? '[]',
          'facet_type': 'defaultPersonal',
          'is_default': 1,
          'created_at': row['created_at'] ?? DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        
        await _database!.delete('facets', where: 'id = ?', whereArgs: ['default']);
        debugPrint('Migrated "default" facet to "me"');
      } else {
        // Create new 'me' facet
        final now = DateTime.now().toIso8601String();
        await _database!.insert('facets', {
          'id': 'me',
          'label': 'Me',
          'emoji': '👤',
          'facet_type': 'defaultPersonal',
          'is_default': 1,
          'links': '[]',
          'created_at': now,
          'updated_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        debugPrint('Created default "me" facet');
      }
    }
  }

  // ==================== FACET CRUD ====================

  Future<void> saveFacet(ProfileFacet facet) async {
    await _ensureInitialized();

    // Normalize 'default' to 'me'
    final id = facet.id == 'default' ? 'me' : facet.id;
    final label = id == 'me' && facet.label == 'Default' ? 'Me' : facet.label;

    await _database!.insert(
      'facets',
      {
        'id': id,
        'label': label,
        'emoji': facet.emoji,
        'display_name': facet.displayName,
        'avatar_url': facet.avatarUrl,
        'bio': facet.bio,
        'links': jsonEncode(facet.links.map((l) => l.toJson()).toList()),
        'facet_type': facet.type.name,
        'is_default': facet.isDefault ? 1 : 0,
        'created_at': facet.createdAt.toIso8601String(),
        'updated_at': facet.updatedAt.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    debugPrint('Facet saved: $id (${facet.type.name})');
    
    // NOTE: Profile sync is now handled by the UI layer (FacetEditorScreen)
    // to avoid circular dependencies between FacetStorage and ProfileService.
    // When saving the default facet, FacetEditorScreen calls 
    // ProfileService().syncDefaultFacetToProfile() after this method returns.
  }

  Future<ProfileFacet?> getFacet(String id) async {
    await _ensureInitialized();

    // Normalize 'default' to 'me'
    final normalizedId = id == 'default' ? 'me' : id;

    final results = await _database!.query(
      'facets',
      where: 'id = ?',
      whereArgs: [normalizedId],
    );

    if (results.isEmpty) return null;
    return _rowToFacet(results.first);
  }

  /// Get facet by label or ID (case-insensitive) - for hashtag lookup
  Future<ProfileFacet?> getFacetByLabel(String label) async {
    await _ensureInitialized();
    
    final lowerLabel = label.toLowerCase();
    
    // Normalize 'default' to 'me'
    final searchLabel = lowerLabel == 'default' ? 'me' : lowerLabel;
    
    final results = await _database!.query(
      'facets',
      where: 'LOWER(label) = ? OR LOWER(id) = ?',
      whereArgs: [searchLabel, searchLabel],
      limit: 1,
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

    final facets = results.map(_rowToFacet).toList();
    
    // Ensure "me" is always first, then custom, then broadcast
    facets.sort((a, b) {
      if (a.isDefaultPersonal) return -1;
      if (b.isDefaultPersonal) return 1;
      if (a.isBroadcast && !b.isBroadcast) return 1;
      if (!a.isBroadcast && b.isBroadcast) return -1;
      return a.createdAt.compareTo(b.createdAt);
    });
    
    return facets;
  }

  /// Get the default "me" facet
  Future<ProfileFacet> getDefaultFacet() async {
    await _ensureInitialized();

    // First try by type
    var results = await _database!.query(
      'facets',
      where: 'facet_type = ?',
      whereArgs: ['defaultPersonal'],
      limit: 1,
    );

    // Fallback to 'me' id
    if (results.isEmpty) {
      results = await _database!.query(
        'facets',
        where: 'id = ?',
        whereArgs: ['me'],
        limit: 1,
      );
    }

    // Fallback to is_default flag
    if (results.isEmpty) {
      results = await _database!.query(
        'facets',
        where: 'is_default = 1',
        limit: 1,
      );
    }

    if (results.isEmpty) {
      // This shouldn't happen, but create if missing
      await _ensureDefaultFacet();
      return ProfileFacet.defaultFacet();
    }
    
    return _rowToFacet(results.first);
  }

  /// Get all broadcast facets (DIX, etc.)
  Future<List<ProfileFacet>> getBroadcastFacets() async {
    await _ensureInitialized();

    final results = await _database!.query(
      'facets',
      where: 'facet_type = ?',
      whereArgs: ['broadcast'],
      orderBy: 'created_at ASC',
    );

    return results.map(_rowToFacet).toList();
  }

  /// Get all custom facets (excluding default and broadcast)
  Future<List<ProfileFacet>> getCustomFacets() async {
    await _ensureInitialized();

    final results = await _database!.query(
      'facets',
      where: 'facet_type = ?',
      whereArgs: ['custom'],
      orderBy: 'created_at ASC',
    );

    return results.map(_rowToFacet).toList();
  }

  Future<void> deleteFacet(String id) async {
    await _ensureInitialized();

    // Normalize 'default' to 'me'
    final normalizedId = id == 'default' ? 'me' : id;

    // Cannot delete the default "me" facet
    final facet = await getFacet(normalizedId);
    if (facet == null) return;
    
    if (!facet.canDelete) {
      debugPrint('Cannot delete facet: ${facet.id} (${facet.type.name})');
      return;
    }

    await _database!.delete(
      'facets',
      where: 'id = ?',
      whereArgs: [normalizedId],
    );

    debugPrint('Facet deleted: $normalizedId');
  }

  Future<void> setDefaultFacet(String id) async {
    await _ensureInitialized();

    // Normalize 'default' to 'me'
    final normalizedId = id == 'default' ? 'me' : id;

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
      whereArgs: [normalizedId],
    );

    debugPrint('Default facet set: $normalizedId');
  }

  /// Check if a facet exists
  Future<bool> facetExists(String labelOrId) async {
    final facet = await getFacetByLabel(labelOrId);
    return facet != null;
  }

  /// Get all facet labels for quick validation
  Future<Set<String>> getAllFacetLabels() async {
    await _ensureInitialized();
    
    final results = await _database!.query(
      'facets',
      columns: ['id', 'label'],
    );
    
    final labels = <String>{};
    for (final row in results) {
      labels.add((row['id'] as String).toLowerCase());
      labels.add((row['label'] as String).toLowerCase());
    }
    return labels;
  }

  /// Create facet from hashtag (quick creation)
  Future<ProfileFacet> createFacetFromHashtag(String hashtag, {
    String? emoji,
    FacetType type = FacetType.custom,
  }) async {
    final cleanName = hashtag.replaceAll('#', '').toLowerCase();
    final displayLabel = cleanName[0].toUpperCase() + cleanName.substring(1);
    
    final facet = ProfileFacet(
      id: cleanName,
      label: displayLabel,
      emoji: emoji ?? _suggestEmoji(cleanName),
      type: type,
      isDefault: false,
    );
    
    await saveFacet(facet);
    return facet;
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
    // Normalize 'default' to 'me'
    final normalizedId = id == 'default' ? 'me' : id;
    await setSetting('primary_facet_id', normalizedId);
  }

  // ==================== COLLECTION ====================

  Future<FacetCollection> getFacetCollection() async {
    final facets = await getAllFacets();
    final defaultFacet = await getDefaultFacet();
    final primaryId = await getPrimaryFacetId();

    return FacetCollection(
      facets: facets,
      defaultFacetId: defaultFacet.id,
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

  /// Migrate from existing ProfileData to me@ facet
  Future<void> migrateFromProfileData(ProfileData? data) async {
    await _ensureInitialized();

    // Get existing default facet
    final existing = await getDefaultFacet();
    
    // If profile data exists and default facet is empty, migrate
    if (data != null && !data.isEmpty) {
      // Only migrate if me@ doesn't have this data yet
      if (existing.displayName == null && data.displayName != null ||
          existing.avatarUrl == null && data.avatarUrl != null ||
          existing.bio == null && data.bio != null) {
        
        final updated = existing.copyWith(
          displayName: existing.displayName ?? data.displayName,
          avatarUrl: existing.avatarUrl ?? data.avatarUrl,
          bio: existing.bio ?? data.bio,
          links: existing.links.isEmpty ? data.links : existing.links,
        );
        await saveFacet(updated);
        debugPrint('Migrated ProfileData to "me" facet');
      }
    }
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

    final id = row['id'] as String;
    final isDefaultId = id == 'default' || id == 'me';
    
    return ProfileFacet(
      id: isDefaultId ? 'me' : id,  // Normalize 'default' to 'me'
      label: row['label'] as String? ?? (isDefaultId ? 'Me' : id),
      emoji: row['emoji'] as String? ?? '👤',
      displayName: row['display_name'] as String?,
      avatarUrl: row['avatar_url'] as String?,
      bio: row['bio'] as String?,
      links: links,
      type: _parseFacetType(row['facet_type'] as String?, isDefaultId),
      isDefault: (row['is_default'] as int?) == 1 || isDefaultId,
      createdAt: DateTime.tryParse(row['created_at'] as String? ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(row['updated_at'] as String? ?? '') ?? DateTime.now(),
    );
  }

  FacetType _parseFacetType(String? value, bool isDefaultId) {
    if (value != null) {
      switch (value) {
        case 'defaultPersonal':
          return FacetType.defaultPersonal;
        case 'broadcast':
          return FacetType.broadcast;
        case 'system':
          return FacetType.system;
        case 'custom':
          return FacetType.custom;
      }
    }
    // Fallback: infer from ID
    return isDefaultId ? FacetType.defaultPersonal : FacetType.custom;
  }

  String _suggestEmoji(String name) {
    const suggestions = {
      'work': '💼',
      'friends': '🎉',
      'family': '👨‍👩‍👧',
      'travel': '✈️',
      'music': '🎵',
      'dix': '🎵',
      'gaming': '🎮',
      'sports': '⚽',
      'food': '🍕',
      'tech': '💻',
      'art': '🎨',
      'photo': '📷',
      'fitness': '💪',
      'crypto': '₿',
      'business': '📊',
      'creative': '✨',
      'blog': '📝',
      'news': '📰',
      'email': '📧',
    };
    
    return suggestions[name.toLowerCase()] ?? '📌';
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
    
    // Recreate default "me" facet
    await _ensureDefaultFacet();
    
    debugPrint('All facets deleted, "me" facet recreated');
  }
}
