/// Post Storage - Globe Posts Phase 2
///
/// Persists posts to local SQLite database.
/// Follows the same patterns as message_storage.dart but for public posts.
///
/// Posts are stored locally for:
/// - Offline access to own posts
/// - Caching timeline posts
/// - Draft posts before publishing
/// - Bookmarked posts
///
/// Location: lib/core/posts/post_storage.dart

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'gns_post.dart';

/// Storage for posts
class PostStorage {
  static final PostStorage _instance = PostStorage._internal();
  factory PostStorage() => _instance;
  PostStorage._internal();

  Database? _database;
  bool _initialized = false;

  static const String _dbName = 'gns_posts.db';
  static const int _dbVersion = 1;

  // Table names
  static const String _tablePosts = 'posts';
  static const String _tableBookmarks = 'bookmarks';
  static const String _tableLikes = 'likes';
  static const String _tableDrafts = 'drafts';

  // ============================================================
  // INITIALIZATION
  // ============================================================

  Future<void> initialize() async {
    if (_initialized) return;

    final documentsDir = await getApplicationDocumentsDirectory();
    final dbPath = join(documentsDir.path, _dbName);

    _database = await openDatabase(
      dbPath,
      version: _dbVersion,
      onCreate: _createTables,
      onUpgrade: _upgradeTables,
    );

    _initialized = true;
    debugPrint('📝 Post storage initialized: $dbPath');
  }

  Future<void> _createTables(Database db, int version) async {
    // Main posts table
    await db.execute('''
      CREATE TABLE $_tablePosts (
        id TEXT PRIMARY KEY,
        author_pk TEXT NOT NULL,
        author_handle TEXT,
        facet_id TEXT NOT NULL,
        payload_type TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        signature TEXT NOT NULL,
        trust_score REAL NOT NULL,
        breadcrumb_count INTEGER NOT NULL,
        brand_verification TEXT,
        engagement TEXT,
        status TEXT NOT NULL DEFAULT 'published',
        reply_to_id TEXT,
        quote_of_id TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        cached_at TEXT NOT NULL,
        is_own_post INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // Indexes for efficient queries
    await db.execute('CREATE INDEX idx_posts_author ON $_tablePosts(author_pk)');
    await db.execute('CREATE INDEX idx_posts_handle ON $_tablePosts(author_handle)');
    await db.execute('CREATE INDEX idx_posts_facet ON $_tablePosts(facet_id)');
    await db.execute('CREATE INDEX idx_posts_created ON $_tablePosts(created_at DESC)');
    await db.execute('CREATE INDEX idx_posts_reply ON $_tablePosts(reply_to_id)');
    await db.execute('CREATE INDEX idx_posts_own ON $_tablePosts(is_own_post, created_at DESC)');

    // Bookmarks table
    await db.execute('''
      CREATE TABLE $_tableBookmarks (
        post_id TEXT PRIMARY KEY,
        bookmarked_at TEXT NOT NULL,
        FOREIGN KEY (post_id) REFERENCES $_tablePosts(id) ON DELETE CASCADE
      )
    ''');

    // Likes table (tracks own likes)
    await db.execute('''
      CREATE TABLE $_tableLikes (
        post_id TEXT PRIMARY KEY,
        liked_at TEXT NOT NULL
      )
    ''');

    // Drafts table
    await db.execute('''
      CREATE TABLE $_tableDrafts (
        id TEXT PRIMARY KEY,
        facet_id TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        reply_to_id TEXT,
        quote_of_id TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    debugPrint('📝 Post tables created');
  }

  Future<void> _upgradeTables(Database db, int oldVersion, int newVersion) async {
    // Handle future migrations here
    debugPrint('📝 Upgrading post database from v$oldVersion to v$newVersion');
  }

  Future<void> _ensureInitialized() async {
    if (!_initialized) await initialize();
  }

  // ============================================================
  // POST CRUD
  // ============================================================

  /// Save a post to local storage
  Future<void> savePost(GnsPost post, {bool isOwnPost = false}) async {
    await _ensureInitialized();

    await _database!.insert(
      _tablePosts,
      {
        'id': post.id,
        'author_pk': post.authorPk,
        'author_handle': post.authorHandle,
        'facet_id': post.facetId,
        'payload_type': post.payloadType,
        'payload_json': jsonEncode(post.payloadJson),
        'signature': post.signature,
        'trust_score': post.trustScore,
        'breadcrumb_count': post.breadcrumbCount,
        'brand_verification': post.brandVerification != null 
            ? jsonEncode(post.brandVerification!.toJson()) 
            : null,
        'engagement': jsonEncode(post.engagement.toJson()),
        'status': post.status.name,
        'reply_to_id': post.replyToId,
        'quote_of_id': post.quoteOfId,
        'created_at': post.createdAt.toIso8601String(),
        'updated_at': post.updatedAt.toIso8601String(),
        'cached_at': DateTime.now().toIso8601String(),
        'is_own_post': isOwnPost ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Save multiple posts (batch insert)
  Future<void> savePosts(List<GnsPost> posts, {bool isOwnPost = false}) async {
    await _ensureInitialized();

    final batch = _database!.batch();
    for (final post in posts) {
      batch.insert(
        _tablePosts,
        {
          'id': post.id,
          'author_pk': post.authorPk,
          'author_handle': post.authorHandle,
          'facet_id': post.facetId,
          'payload_type': post.payloadType,
          'payload_json': jsonEncode(post.payloadJson),
          'signature': post.signature,
          'trust_score': post.trustScore,
          'breadcrumb_count': post.breadcrumbCount,
          'brand_verification': post.brandVerification != null 
              ? jsonEncode(post.brandVerification!.toJson()) 
              : null,
          'engagement': jsonEncode(post.engagement.toJson()),
          'status': post.status.name,
          'reply_to_id': post.replyToId,
          'quote_of_id': post.quoteOfId,
          'created_at': post.createdAt.toIso8601String(),
          'updated_at': post.updatedAt.toIso8601String(),
          'cached_at': DateTime.now().toIso8601String(),
          'is_own_post': isOwnPost ? 1 : 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// Get a single post by ID
  Future<GnsPost?> getPost(String id) async {
    await _ensureInitialized();

    final results = await _database!.query(
      _tablePosts,
      where: 'id = ?',
      whereArgs: [id],
    );

    if (results.isEmpty) return null;
    return _rowToPost(results.first);
  }

  /// Get multiple posts by IDs
  Future<List<GnsPost>> getPosts(List<String> ids) async {
    if (ids.isEmpty) return [];
    await _ensureInitialized();

    final placeholders = List.filled(ids.length, '?').join(',');
    final results = await _database!.query(
      _tablePosts,
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );

    return results.map(_rowToPost).toList();
  }

  /// Delete a post
  Future<void> deletePost(String id) async {
    await _ensureInitialized();
    await _database!.delete(_tablePosts, where: 'id = ?', whereArgs: [id]);
  }

  /// Update post engagement
  Future<void> updateEngagement(String postId, PostEngagement engagement) async {
    await _ensureInitialized();
    await _database!.update(
      _tablePosts,
      {'engagement': jsonEncode(engagement.toJson())},
      where: 'id = ?',
      whereArgs: [postId],
    );
  }

  // ============================================================
  // TIMELINE QUERIES
  // ============================================================

  /// Get timeline posts (paginated)
  Future<List<GnsPost>> getTimeline({
    int limit = 20,
    String? beforeId,
    DateTime? beforeTime,
  }) async {
    await _ensureInitialized();

    String whereClause = "status = 'published'";
    List<dynamic> whereArgs = [];

    if (beforeTime != null) {
      whereClause += ' AND created_at < ?';
      whereArgs.add(beforeTime.toIso8601String());
    }

    final results = await _database!.query(
      _tablePosts,
      where: whereClause,
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: 'created_at DESC',
      limit: limit,
    );

    return results.map(_rowToPost).toList();
  }

  /// Get posts by author
  Future<List<GnsPost>> getPostsByAuthor(
    String authorPk, {
    String? facetId,
    int limit = 20,
    DateTime? beforeTime,
  }) async {
    await _ensureInitialized();

    String whereClause = 'author_pk = ? AND status = ?';
    List<dynamic> whereArgs = [authorPk, 'published'];

    if (facetId != null) {
      whereClause += ' AND facet_id = ?';
      whereArgs.add(facetId);
    }

    if (beforeTime != null) {
      whereClause += ' AND created_at < ?';
      whereArgs.add(beforeTime.toIso8601String());
    }

    final results = await _database!.query(
      _tablePosts,
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'created_at DESC',
      limit: limit,
    );

    return results.map(_rowToPost).toList();
  }

  /// Get posts by handle
  Future<List<GnsPost>> getPostsByHandle(
    String handle, {
    String? facetId,
    int limit = 20,
    DateTime? beforeTime,
  }) async {
    await _ensureInitialized();

    String whereClause = 'author_handle = ? AND status = ?';
    List<dynamic> whereArgs = [handle.toLowerCase(), 'published'];

    if (facetId != null) {
      whereClause += ' AND facet_id = ?';
      whereArgs.add(facetId);
    }

    if (beforeTime != null) {
      whereClause += ' AND created_at < ?';
      whereArgs.add(beforeTime.toIso8601String());
    }

    final results = await _database!.query(
      _tablePosts,
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'created_at DESC',
      limit: limit,
    );

    return results.map(_rowToPost).toList();
  }

  /// Get own posts
  Future<List<GnsPost>> getOwnPosts({
    int limit = 20,
    DateTime? beforeTime,
  }) async {
    await _ensureInitialized();

    String whereClause = 'is_own_post = 1';
    List<dynamic> whereArgs = [];

    if (beforeTime != null) {
      whereClause += ' AND created_at < ?';
      whereArgs.add(beforeTime.toIso8601String());
    }

    final results = await _database!.query(
      _tablePosts,
      where: whereClause,
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: 'created_at DESC',
      limit: limit,
    );

    return results.map(_rowToPost).toList();
  }

  /// Get replies to a post
  Future<List<GnsPost>> getReplies(
    String postId, {
    int limit = 50,
  }) async {
    await _ensureInitialized();

    final results = await _database!.query(
      _tablePosts,
      where: 'reply_to_id = ? AND status = ?',
      whereArgs: [postId, 'published'],
      orderBy: 'created_at ASC',
      limit: limit,
    );

    return results.map(_rowToPost).toList();
  }

  // ============================================================
  // SEARCH
  // ============================================================

  /// Search posts by text content
  Future<List<GnsPost>> searchPosts(
    String query, {
    int limit = 20,
  }) async {
    await _ensureInitialized();

    // Simple LIKE search (could be enhanced with FTS5)
    final results = await _database!.query(
      _tablePosts,
      where: "payload_json LIKE ? AND status = 'published'",
      whereArgs: ['%$query%'],
      orderBy: 'created_at DESC',
      limit: limit,
    );

    return results.map(_rowToPost).toList();
  }

  /// Search posts by hashtag
  Future<List<GnsPost>> searchByTag(
    String tag, {
    int limit = 20,
  }) async {
    await _ensureInitialized();

    final normalizedTag = tag.toLowerCase().replaceAll('#', '');
    
    final results = await _database!.query(
      _tablePosts,
      where: "payload_json LIKE ? AND status = 'published'",
      whereArgs: ['%"$normalizedTag"%'],
      orderBy: 'created_at DESC',
      limit: limit,
    );

    // Filter to only posts that actually have this tag
    return results
        .map(_rowToPost)
        .where((p) => p.tags.contains(normalizedTag))
        .toList();
  }

  // ============================================================
  // BOOKMARKS
  // ============================================================

  /// Bookmark a post
  Future<void> bookmarkPost(String postId) async {
    await _ensureInitialized();
    await _database!.insert(
      _tableBookmarks,
      {
        'post_id': postId,
        'bookmarked_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Remove bookmark
  Future<void> unbookmarkPost(String postId) async {
    await _ensureInitialized();
    await _database!.delete(
      _tableBookmarks,
      where: 'post_id = ?',
      whereArgs: [postId],
    );
  }

  /// Check if post is bookmarked
  Future<bool> isBookmarked(String postId) async {
    await _ensureInitialized();
    final result = await _database!.query(
      _tableBookmarks,
      where: 'post_id = ?',
      whereArgs: [postId],
    );
    return result.isNotEmpty;
  }

  /// Get bookmarked posts
  Future<List<GnsPost>> getBookmarkedPosts({int limit = 50}) async {
    await _ensureInitialized();

    final results = await _database!.rawQuery('''
      SELECT p.* FROM $_tablePosts p
      INNER JOIN $_tableBookmarks b ON p.id = b.post_id
      ORDER BY b.bookmarked_at DESC
      LIMIT ?
    ''', [limit]);

    return results.map(_rowToPost).toList();
  }

  // ============================================================
  // LIKES (LOCAL TRACKING)
  // ============================================================

  /// Mark post as liked locally
  Future<void> markLiked(String postId) async {
    await _ensureInitialized();
    await _database!.insert(
      _tableLikes,
      {
        'post_id': postId,
        'liked_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Mark post as unliked locally
  Future<void> markUnliked(String postId) async {
    await _ensureInitialized();
    await _database!.delete(
      _tableLikes,
      where: 'post_id = ?',
      whereArgs: [postId],
    );
  }

  /// Check if post is liked locally
  Future<bool> isLiked(String postId) async {
    await _ensureInitialized();
    final result = await _database!.query(
      _tableLikes,
      where: 'post_id = ?',
      whereArgs: [postId],
    );
    return result.isNotEmpty;
  }

  /// Get liked post IDs
  Future<Set<String>> getLikedPostIds() async {
    await _ensureInitialized();
    final results = await _database!.query(_tableLikes);
    return results.map((r) => r['post_id'] as String).toSet();
  }

  // ============================================================
  // DRAFTS
  // ============================================================

  /// Save a draft
  Future<void> saveDraft(PostDraft draft) async {
    await _ensureInitialized();
    await _database!.insert(
      _tableDrafts,
      {
        'id': draft.id,
        'facet_id': draft.facetId,
        'payload_json': jsonEncode(draft.payloadJson),
        'reply_to_id': draft.replyToId,
        'quote_of_id': draft.quoteOfId,
        'created_at': draft.createdAt.toIso8601String(),
        'updated_at': draft.updatedAt.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Get all drafts
  Future<List<PostDraft>> getDrafts() async {
    await _ensureInitialized();
    final results = await _database!.query(
      _tableDrafts,
      orderBy: 'updated_at DESC',
    );
    return results.map(_rowToDraft).toList();
  }

  /// Delete a draft
  Future<void> deleteDraft(String id) async {
    await _ensureInitialized();
    await _database!.delete(_tableDrafts, where: 'id = ?', whereArgs: [id]);
  }

  // ============================================================
  // CACHE MANAGEMENT
  // ============================================================

  /// Clear cached posts older than duration
  Future<int> clearOldCache(Duration maxAge) async {
    await _ensureInitialized();
    
    final cutoff = DateTime.now().subtract(maxAge);
    final result = await _database!.delete(
      _tablePosts,
      where: 'cached_at < ? AND is_own_post = 0',
      whereArgs: [cutoff.toIso8601String()],
    );
    
    debugPrint('📝 Cleared $result old cached posts');
    return result;
  }

  /// Get cache statistics
  Future<Map<String, int>> getCacheStats() async {
    await _ensureInitialized();

    final totalPosts = Sqflite.firstIntValue(
      await _database!.rawQuery('SELECT COUNT(*) FROM $_tablePosts')
    ) ?? 0;

    final ownPosts = Sqflite.firstIntValue(
      await _database!.rawQuery('SELECT COUNT(*) FROM $_tablePosts WHERE is_own_post = 1')
    ) ?? 0;

    final bookmarks = Sqflite.firstIntValue(
      await _database!.rawQuery('SELECT COUNT(*) FROM $_tableBookmarks')
    ) ?? 0;

    final likes = Sqflite.firstIntValue(
      await _database!.rawQuery('SELECT COUNT(*) FROM $_tableLikes')
    ) ?? 0;

    final drafts = Sqflite.firstIntValue(
      await _database!.rawQuery('SELECT COUNT(*) FROM $_tableDrafts')
    ) ?? 0;

    return {
      'total_posts': totalPosts,
      'own_posts': ownPosts,
      'bookmarks': bookmarks,
      'likes': likes,
      'drafts': drafts,
    };
  }

  /// Clear all cached posts (keeps own posts, bookmarks)
  Future<void> clearCache() async {
    await _ensureInitialized();
    await _database!.delete(
      _tablePosts,
      where: 'is_own_post = 0',
    );
    debugPrint('📝 Cache cleared');
  }

  // ============================================================
  // HELPERS
  // ============================================================

  GnsPost _rowToPost(Map<String, dynamic> row) {
    return GnsPost(
      id: row['id'] as String,
      authorPk: row['author_pk'] as String,
      authorHandle: row['author_handle'] as String?,
      facetId: row['facet_id'] as String,
      payloadType: row['payload_type'] as String,
      payloadJson: jsonDecode(row['payload_json'] as String) as Map<String, dynamic>,
      signature: row['signature'] as String,
      trustScore: (row['trust_score'] as num).toDouble(),
      breadcrumbCount: row['breadcrumb_count'] as int,
      brandVerification: row['brand_verification'] != null
          ? BrandVerification.fromJson(
              jsonDecode(row['brand_verification'] as String) as Map<String, dynamic>
            )
          : null,
      engagement: row['engagement'] != null
          ? PostEngagement.fromJson(
              jsonDecode(row['engagement'] as String) as Map<String, dynamic>
            )
          : null,
      status: PostStatus.values.firstWhere(
        (s) => s.name == row['status'],
        orElse: () => PostStatus.published,
      ),
      replyToId: row['reply_to_id'] as String?,
      quoteOfId: row['quote_of_id'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }

  PostDraft _rowToDraft(Map<String, dynamic> row) {
    return PostDraft(
      id: row['id'] as String,
      facetId: row['facet_id'] as String,
      payloadJson: jsonDecode(row['payload_json'] as String) as Map<String, dynamic>,
      replyToId: row['reply_to_id'] as String?,
      quoteOfId: row['quote_of_id'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }

  /// Close the database
  Future<void> close() async {
    await _database?.close();
    _database = null;
    _initialized = false;
  }

  /// Delete all data (for testing/reset)
  Future<void> deleteAll() async {
    await _ensureInitialized();
    await _database!.delete(_tablePosts);
    await _database!.delete(_tableBookmarks);
    await _database!.delete(_tableLikes);
    await _database!.delete(_tableDrafts);
    debugPrint('📝 All post data deleted');
  }
}

/// Draft post (not yet published)
class PostDraft {
  final String id;
  final String facetId;
  final Map<String, dynamic> payloadJson;
  final String? replyToId;
  final String? quoteOfId;
  final DateTime createdAt;
  final DateTime updatedAt;

  PostDraft({
    required this.id,
    required this.facetId,
    required this.payloadJson,
    this.replyToId,
    this.quoteOfId,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  String get text => payloadJson['text'] as String? ?? '';

  Map<String, dynamic> toJson() => {
    'id': id,
    'facet_id': facetId,
    'payload_json': payloadJson,
    'reply_to_id': replyToId,
    'quote_of_id': quoteOfId,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };
}
