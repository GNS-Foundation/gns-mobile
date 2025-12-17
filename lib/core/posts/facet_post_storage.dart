/// Facet Post Storage - Broadcast Posts Persistence
/// 
/// Stores broadcast posts (DIX-style) locally with support for:
/// - Creating and editing posts
/// - Media attachments
/// - Engagement metrics (views, likes, replies)
/// - Sync status for GNS network broadcasting
/// 
/// Location: lib/core/posts/facet_post_storage.dart

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Post visibility levels
enum PostVisibility {
  /// Visible to everyone
  public,
  
  /// Visible only to followers of this facet
  followers,
  
  /// Visible only to specific users
  restricted,
  
  /// Draft - not published yet
  draft,
}

/// Sync status for network broadcasting
enum PostSyncStatus {
  /// Not yet synced to network
  pending,
  
  /// Currently syncing
  syncing,
  
  /// Successfully synced
  synced,
  
  /// Sync failed - will retry
  failed,
  
  /// Local only - won't sync
  localOnly,
}

/// Media attachment for a post
class PostMedia {
  final String id;
  final String postId;
  final String type;        // 'image', 'video', 'audio', 'document'
  final String? localPath;  // Local file path
  final String? remoteUrl;  // URL after upload
  final String? thumbnailBase64;
  final String? mimeType;
  final int? sizeBytes;
  final int? width;
  final int? height;
  final int? durationMs;    // For video/audio
  final String? altText;    // Accessibility text

  PostMedia({
    required this.id,
    required this.postId,
    required this.type,
    this.localPath,
    this.remoteUrl,
    this.thumbnailBase64,
    this.mimeType,
    this.sizeBytes,
    this.width,
    this.height,
    this.durationMs,
    this.altText,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'post_id': postId,
    'type': type,
    'local_path': localPath,
    'remote_url': remoteUrl,
    'thumbnail_base64': thumbnailBase64,
    'mime_type': mimeType,
    'size_bytes': sizeBytes,
    'width': width,
    'height': height,
    'duration_ms': durationMs,
    'alt_text': altText,
  };

  factory PostMedia.fromJson(Map<String, dynamic> json) {
    return PostMedia(
      id: json['id'] as String,
      postId: json['post_id'] as String,
      type: json['type'] as String,
      localPath: json['local_path'] as String?,
      remoteUrl: json['remote_url'] as String?,
      thumbnailBase64: json['thumbnail_base64'] as String?,
      mimeType: json['mime_type'] as String?,
      sizeBytes: json['size_bytes'] as int?,
      width: json['width'] as int?,
      height: json['height'] as int?,
      durationMs: json['duration_ms'] as int?,
      altText: json['alt_text'] as String?,
    );
  }

  /// Get display URL (remote if available, else local)
  String? get displayUrl => remoteUrl ?? localPath;

  /// Is this an image?
  bool get isImage => type == 'image';

  /// Is this a video?
  bool get isVideo => type == 'video';
}

/// A broadcast post (DIX-style)
class FacetPost {
  final String id;
  final String facetId;         // Which facet this belongs to (e.g., 'dix')
  final String authorPublicKey;
  final String? authorHandle;
  
  // Content
  final String content;
  final List<PostMedia> media;
  final String? locationName;   // Optional location tag
  final double? locationLat;
  final double? locationLng;
  
  // Metadata
  final PostVisibility visibility;
  final DateTime createdAt;
  final DateTime? editedAt;
  final bool isEdited;
  final bool isDeleted;
  
  // Engagement (local cache - may differ from network)
  final int viewCount;
  final int likeCount;
  final int replyCount;
  final int repostCount;
  final bool isLikedByMe;
  final bool isRepostedByMe;
  
  // Sync status
  final PostSyncStatus syncStatus;
  final String? syncError;
  final DateTime? lastSyncAt;
  final String? networkPostId;  // ID assigned by GNS network
  
  // Reply/thread info
  final String? replyToPostId;
  final String? threadRootId;
  final int threadDepth;

  FacetPost({
    required this.id,
    required this.facetId,
    required this.authorPublicKey,
    this.authorHandle,
    required this.content,
    List<PostMedia>? media,
    this.locationName,
    this.locationLat,
    this.locationLng,
    this.visibility = PostVisibility.public,
    DateTime? createdAt,
    this.editedAt,
    this.isEdited = false,
    this.isDeleted = false,
    this.viewCount = 0,
    this.likeCount = 0,
    this.replyCount = 0,
    this.repostCount = 0,
    this.isLikedByMe = false,
    this.isRepostedByMe = false,
    this.syncStatus = PostSyncStatus.pending,
    this.syncError,
    this.lastSyncAt,
    this.networkPostId,
    this.replyToPostId,
    this.threadRootId,
    this.threadDepth = 0,
  })  : media = media ?? [],
        createdAt = createdAt ?? DateTime.now();

  /// Create a new post
  factory FacetPost.create({
    required String facetId,
    required String authorPublicKey,
    String? authorHandle,
    required String content,
    List<PostMedia>? media,
    PostVisibility visibility = PostVisibility.public,
    String? locationName,
    double? locationLat,
    double? locationLng,
    String? replyToPostId,
    String? threadRootId,
    int threadDepth = 0,
  }) {
    return FacetPost(
      id: const Uuid().v4(),
      facetId: facetId,
      authorPublicKey: authorPublicKey,
      authorHandle: authorHandle,
      content: content,
      media: media,
      visibility: visibility,
      locationName: locationName,
      locationLat: locationLat,
      locationLng: locationLng,
      replyToPostId: replyToPostId,
      threadRootId: threadRootId,
      threadDepth: threadDepth,
    );
  }

  /// Create a draft post
  factory FacetPost.draft({
    required String facetId,
    required String authorPublicKey,
    String? authorHandle,
    String content = '',
    List<PostMedia>? media,
  }) {
    return FacetPost(
      id: const Uuid().v4(),
      facetId: facetId,
      authorPublicKey: authorPublicKey,
      authorHandle: authorHandle,
      content: content,
      media: media,
      visibility: PostVisibility.draft,
      syncStatus: PostSyncStatus.localOnly,
    );
  }

  // ==================== HELPERS ====================

  /// Is this a reply to another post?
  bool get isReply => replyToPostId != null;

  /// Is this a draft?
  bool get isDraft => visibility == PostVisibility.draft;

  /// Is this synced to network?
  bool get isSynced => syncStatus == PostSyncStatus.synced;

  /// Has media attachments?
  bool get hasMedia => media.isNotEmpty;

  /// Has location?
  bool get hasLocation => locationName != null || (locationLat != null && locationLng != null);

  /// Total engagement count
  int get engagementCount => viewCount + likeCount + replyCount + repostCount;

  /// Preview text (truncated content)
  String get previewText {
    if (content.length <= 100) return content;
    return '${content.substring(0, 100)}...';
  }

  /// Formatted time ago
  String get timeAgo {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inDays > 365) {
      return '${(diff.inDays / 365).floor()}y';
    } else if (diff.inDays > 30) {
      return '${(diff.inDays / 30).floor()}mo';
    } else if (diff.inDays > 7) {
      return '${(diff.inDays / 7).floor()}w';
    } else if (diff.inDays > 0) {
      return '${diff.inDays}d';
    } else if (diff.inHours > 0) {
      return '${diff.inHours}h';
    } else if (diff.inMinutes > 0) {
      return '${diff.inMinutes}m';
    } else {
      return 'now';
    }
  }

  // ==================== COPY WITH ====================

  FacetPost copyWith({
    String? content,
    List<PostMedia>? media,
    String? locationName,
    double? locationLat,
    double? locationLng,
    PostVisibility? visibility,
    DateTime? editedAt,
    bool? isEdited,
    bool? isDeleted,
    int? viewCount,
    int? likeCount,
    int? replyCount,
    int? repostCount,
    bool? isLikedByMe,
    bool? isRepostedByMe,
    PostSyncStatus? syncStatus,
    String? syncError,
    DateTime? lastSyncAt,
    String? networkPostId,
  }) {
    return FacetPost(
      id: id,
      facetId: facetId,
      authorPublicKey: authorPublicKey,
      authorHandle: authorHandle,
      content: content ?? this.content,
      media: media ?? this.media,
      locationName: locationName ?? this.locationName,
      locationLat: locationLat ?? this.locationLat,
      locationLng: locationLng ?? this.locationLng,
      visibility: visibility ?? this.visibility,
      createdAt: createdAt,
      editedAt: editedAt ?? this.editedAt,
      isEdited: isEdited ?? this.isEdited,
      isDeleted: isDeleted ?? this.isDeleted,
      viewCount: viewCount ?? this.viewCount,
      likeCount: likeCount ?? this.likeCount,
      replyCount: replyCount ?? this.replyCount,
      repostCount: repostCount ?? this.repostCount,
      isLikedByMe: isLikedByMe ?? this.isLikedByMe,
      isRepostedByMe: isRepostedByMe ?? this.isRepostedByMe,
      syncStatus: syncStatus ?? this.syncStatus,
      syncError: syncError ?? this.syncError,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      networkPostId: networkPostId ?? this.networkPostId,
      replyToPostId: replyToPostId,
      threadRootId: threadRootId,
      threadDepth: threadDepth,
    );
  }

  // ==================== SERIALIZATION ====================

  Map<String, dynamic> toJson() => {
    'id': id,
    'facet_id': facetId,
    'author_public_key': authorPublicKey,
    'author_handle': authorHandle,
    'content': content,
    'media': media.map((m) => m.toJson()).toList(),
    'location_name': locationName,
    'location_lat': locationLat,
    'location_lng': locationLng,
    'visibility': visibility.name,
    'created_at': createdAt.millisecondsSinceEpoch,
    'edited_at': editedAt?.millisecondsSinceEpoch,
    'is_edited': isEdited,
    'is_deleted': isDeleted,
    'view_count': viewCount,
    'like_count': likeCount,
    'reply_count': replyCount,
    'repost_count': repostCount,
    'is_liked_by_me': isLikedByMe,
    'is_reposted_by_me': isRepostedByMe,
    'sync_status': syncStatus.name,
    'sync_error': syncError,
    'last_sync_at': lastSyncAt?.millisecondsSinceEpoch,
    'network_post_id': networkPostId,
    'reply_to_post_id': replyToPostId,
    'thread_root_id': threadRootId,
    'thread_depth': threadDepth,
  };

  factory FacetPost.fromJson(Map<String, dynamic> json) {
    return FacetPost(
      id: json['id'] as String,
      facetId: json['facet_id'] as String,
      authorPublicKey: json['author_public_key'] as String,
      authorHandle: json['author_handle'] as String?,
      content: json['content'] as String,
      media: (json['media'] as List?)
          ?.map((m) => PostMedia.fromJson(m as Map<String, dynamic>))
          .toList() ?? [],
      locationName: json['location_name'] as String?,
      locationLat: json['location_lat'] as double?,
      locationLng: json['location_lng'] as double?,
      visibility: PostVisibility.values.firstWhere(
        (v) => v.name == json['visibility'],
        orElse: () => PostVisibility.public,
      ),
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['created_at'] as int),
      editedAt: json['edited_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['edited_at'] as int)
          : null,
      isEdited: json['is_edited'] as bool? ?? false,
      isDeleted: json['is_deleted'] as bool? ?? false,
      viewCount: json['view_count'] as int? ?? 0,
      likeCount: json['like_count'] as int? ?? 0,
      replyCount: json['reply_count'] as int? ?? 0,
      repostCount: json['repost_count'] as int? ?? 0,
      isLikedByMe: json['is_liked_by_me'] as bool? ?? false,
      isRepostedByMe: json['is_reposted_by_me'] as bool? ?? false,
      syncStatus: PostSyncStatus.values.firstWhere(
        (s) => s.name == json['sync_status'],
        orElse: () => PostSyncStatus.pending,
      ),
      syncError: json['sync_error'] as String?,
      lastSyncAt: json['last_sync_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['last_sync_at'] as int)
          : null,
      networkPostId: json['network_post_id'] as String?,
      replyToPostId: json['reply_to_post_id'] as String?,
      threadRootId: json['thread_root_id'] as String?,
      threadDepth: json['thread_depth'] as int? ?? 0,
    );
  }

  @override
  String toString() => 'FacetPost($id: ${previewText.substring(0, previewText.length.clamp(0, 30))}...)';
}

// ==================== STORAGE ====================

class FacetPostStorage {
  static final FacetPostStorage _instance = FacetPostStorage._internal();
  factory FacetPostStorage() => _instance;
  FacetPostStorage._internal();

  Database? _database;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    final documentsDir = await getApplicationDocumentsDirectory();
    final dbPath = join(documentsDir.path, 'gns_facet_posts.db');

    _database = await openDatabase(
      dbPath,
      version: 1,
      onCreate: _createTables,
    );

    _initialized = true;
    debugPrint('FacetPostStorage initialized: $dbPath');
  }

  Future<void> _createTables(Database db, int version) async {
    // Posts table
    await db.execute('''
      CREATE TABLE posts (
        id TEXT PRIMARY KEY,
        facet_id TEXT NOT NULL,
        author_public_key TEXT NOT NULL,
        author_handle TEXT,
        content TEXT NOT NULL,
        location_name TEXT,
        location_lat REAL,
        location_lng REAL,
        visibility TEXT NOT NULL DEFAULT 'public',
        created_at INTEGER NOT NULL,
        edited_at INTEGER,
        is_edited INTEGER NOT NULL DEFAULT 0,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        view_count INTEGER NOT NULL DEFAULT 0,
        like_count INTEGER NOT NULL DEFAULT 0,
        reply_count INTEGER NOT NULL DEFAULT 0,
        repost_count INTEGER NOT NULL DEFAULT 0,
        is_liked_by_me INTEGER NOT NULL DEFAULT 0,
        is_reposted_by_me INTEGER NOT NULL DEFAULT 0,
        sync_status TEXT NOT NULL DEFAULT 'pending',
        sync_error TEXT,
        last_sync_at INTEGER,
        network_post_id TEXT,
        reply_to_post_id TEXT,
        thread_root_id TEXT,
        thread_depth INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // Media attachments table
    await db.execute('''
      CREATE TABLE post_media (
        id TEXT PRIMARY KEY,
        post_id TEXT NOT NULL,
        type TEXT NOT NULL,
        local_path TEXT,
        remote_url TEXT,
        thumbnail_base64 TEXT,
        mime_type TEXT,
        size_bytes INTEGER,
        width INTEGER,
        height INTEGER,
        duration_ms INTEGER,
        alt_text TEXT,
        FOREIGN KEY (post_id) REFERENCES posts(id) ON DELETE CASCADE
      )
    ''');

    // Likes table (for tracking who liked what)
    await db.execute('''
      CREATE TABLE post_likes (
        post_id TEXT NOT NULL,
        user_public_key TEXT NOT NULL,
        liked_at INTEGER NOT NULL,
        PRIMARY KEY (post_id, user_public_key),
        FOREIGN KEY (post_id) REFERENCES posts(id) ON DELETE CASCADE
      )
    ''');

    // Indexes
    await db.execute('CREATE INDEX idx_posts_facet ON posts(facet_id, created_at DESC)');
    await db.execute('CREATE INDEX idx_posts_author ON posts(author_public_key)');
    await db.execute('CREATE INDEX idx_posts_sync ON posts(sync_status)');
    await db.execute('CREATE INDEX idx_posts_visibility ON posts(visibility)');
    await db.execute('CREATE INDEX idx_posts_reply ON posts(reply_to_post_id)');
    await db.execute('CREATE INDEX idx_post_media ON post_media(post_id)');

    debugPrint('FacetPostStorage tables created');
  }

  Future<void> _ensureInitialized() async {
    if (!_initialized) await initialize();
  }

  // ==================== POST CRUD ====================

  /// Save a post (insert or update)
  Future<void> savePost(FacetPost post) async {
    await _ensureInitialized();

    await _database!.transaction((txn) async {
      // Save post
      await txn.insert(
        'posts',
        {
          'id': post.id,
          'facet_id': post.facetId,
          'author_public_key': post.authorPublicKey,
          'author_handle': post.authorHandle,
          'content': post.content,
          'location_name': post.locationName,
          'location_lat': post.locationLat,
          'location_lng': post.locationLng,
          'visibility': post.visibility.name,
          'created_at': post.createdAt.millisecondsSinceEpoch,
          'edited_at': post.editedAt?.millisecondsSinceEpoch,
          'is_edited': post.isEdited ? 1 : 0,
          'is_deleted': post.isDeleted ? 1 : 0,
          'view_count': post.viewCount,
          'like_count': post.likeCount,
          'reply_count': post.replyCount,
          'repost_count': post.repostCount,
          'is_liked_by_me': post.isLikedByMe ? 1 : 0,
          'is_reposted_by_me': post.isRepostedByMe ? 1 : 0,
          'sync_status': post.syncStatus.name,
          'sync_error': post.syncError,
          'last_sync_at': post.lastSyncAt?.millisecondsSinceEpoch,
          'network_post_id': post.networkPostId,
          'reply_to_post_id': post.replyToPostId,
          'thread_root_id': post.threadRootId,
          'thread_depth': post.threadDepth,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // Save media
      await txn.delete('post_media', where: 'post_id = ?', whereArgs: [post.id]);
      for (final media in post.media) {
        await txn.insert('post_media', {
          'id': media.id,
          'post_id': post.id,
          'type': media.type,
          'local_path': media.localPath,
          'remote_url': media.remoteUrl,
          'thumbnail_base64': media.thumbnailBase64,
          'mime_type': media.mimeType,
          'size_bytes': media.sizeBytes,
          'width': media.width,
          'height': media.height,
          'duration_ms': media.durationMs,
          'alt_text': media.altText,
        });
      }
    });

    debugPrint('Post saved: ${post.id} (${post.syncStatus.name})');
  }

  /// Get a post by ID
  Future<FacetPost?> getPost(String postId) async {
    await _ensureInitialized();

    final rows = await _database!.query(
      'posts',
      where: 'id = ?',
      whereArgs: [postId],
    );

    if (rows.isEmpty) return null;
    return await _postFromRow(rows.first);
  }

  /// Get posts for a facet
  Future<List<FacetPost>> getPostsForFacet(
    String facetId, {
    int limit = 50,
    int offset = 0,
    bool includeDrafts = false,
    bool includeDeleted = false,
  }) async {
    await _ensureInitialized();

    String where = 'facet_id = ?';
    final whereArgs = <dynamic>[facetId];

    if (!includeDrafts) {
      where += " AND visibility != 'draft'";
    }
    if (!includeDeleted) {
      where += ' AND is_deleted = 0';
    }

    final rows = await _database!.query(
      'posts',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'created_at DESC',
      limit: limit,
      offset: offset,
    );

    final posts = <FacetPost>[];
    for (final row in rows) {
      posts.add(await _postFromRow(row));
    }
    return posts;
  }

  /// Get posts by author
  Future<List<FacetPost>> getPostsByAuthor(
    String authorPublicKey, {
    String? facetId,
    int limit = 50,
    int offset = 0,
  }) async {
    await _ensureInitialized();

    String where = 'author_public_key = ? AND is_deleted = 0';
    final whereArgs = <dynamic>[authorPublicKey];

    if (facetId != null) {
      where += ' AND facet_id = ?';
      whereArgs.add(facetId);
    }

    final rows = await _database!.query(
      'posts',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'created_at DESC',
      limit: limit,
      offset: offset,
    );

    final posts = <FacetPost>[];
    for (final row in rows) {
      posts.add(await _postFromRow(row));
    }
    return posts;
  }

  /// Get drafts for a facet
  Future<List<FacetPost>> getDrafts(String facetId) async {
    await _ensureInitialized();

    final rows = await _database!.query(
      'posts',
      where: "facet_id = ? AND visibility = 'draft' AND is_deleted = 0",
      whereArgs: [facetId],
      orderBy: 'created_at DESC',
    );

    final posts = <FacetPost>[];
    for (final row in rows) {
      posts.add(await _postFromRow(row));
    }
    return posts;
  }

  /// Get replies to a post
  Future<List<FacetPost>> getReplies(
    String postId, {
    int limit = 50,
    int offset = 0,
  }) async {
    await _ensureInitialized();

    final rows = await _database!.query(
      'posts',
      where: 'reply_to_post_id = ? AND is_deleted = 0',
      whereArgs: [postId],
      orderBy: 'created_at ASC',
      limit: limit,
      offset: offset,
    );

    final posts = <FacetPost>[];
    for (final row in rows) {
      posts.add(await _postFromRow(row));
    }
    return posts;
  }

  /// Get posts pending sync
  Future<List<FacetPost>> getPendingSyncPosts({int limit = 20}) async {
    await _ensureInitialized();

    final rows = await _database!.query(
      'posts',
      where: "sync_status IN ('pending', 'failed') AND visibility != 'draft'",
      orderBy: 'created_at ASC',
      limit: limit,
    );

    final posts = <FacetPost>[];
    for (final row in rows) {
      posts.add(await _postFromRow(row));
    }
    return posts;
  }

  /// Delete a post (soft delete)
  Future<void> deletePost(String postId) async {
    await _ensureInitialized();

    await _database!.update(
      'posts',
      {'is_deleted': 1},
      where: 'id = ?',
      whereArgs: [postId],
    );

    debugPrint('Post soft-deleted: $postId');
  }

  /// Permanently delete a post
  Future<void> hardDeletePost(String postId) async {
    await _ensureInitialized();

    await _database!.delete(
      'posts',
      where: 'id = ?',
      whereArgs: [postId],
    );

    debugPrint('Post hard-deleted: $postId');
  }

  // ==================== ENGAGEMENT ====================

  /// Toggle like on a post
  Future<FacetPost?> toggleLike(String postId, String userPublicKey) async {
    await _ensureInitialized();

    final post = await getPost(postId);
    if (post == null) return null;

    final isCurrentlyLiked = post.isLikedByMe;
    final newLikeCount = isCurrentlyLiked 
        ? post.likeCount - 1 
        : post.likeCount + 1;

    await _database!.transaction((txn) async {
      // Update post
      await txn.update(
        'posts',
        {
          'like_count': newLikeCount.clamp(0, 999999999),
          'is_liked_by_me': isCurrentlyLiked ? 0 : 1,
        },
        where: 'id = ?',
        whereArgs: [postId],
      );

      // Update likes table
      if (isCurrentlyLiked) {
        await txn.delete(
          'post_likes',
          where: 'post_id = ? AND user_public_key = ?',
          whereArgs: [postId, userPublicKey],
        );
      } else {
        await txn.insert('post_likes', {
          'post_id': postId,
          'user_public_key': userPublicKey,
          'liked_at': DateTime.now().millisecondsSinceEpoch,
        });
      }
    });

    return post.copyWith(
      likeCount: newLikeCount.clamp(0, 999999999),
      isLikedByMe: !isCurrentlyLiked,
    );
  }

  /// Increment view count
  Future<void> incrementViewCount(String postId) async {
    await _ensureInitialized();

    await _database!.rawUpdate(
      'UPDATE posts SET view_count = view_count + 1 WHERE id = ?',
      [postId],
    );
  }

  /// Update reply count
  Future<void> updateReplyCount(String postId, int delta) async {
    await _ensureInitialized();

    await _database!.rawUpdate(
      'UPDATE posts SET reply_count = MAX(0, reply_count + ?) WHERE id = ?',
      [delta, postId],
    );
  }

  // ==================== SYNC STATUS ====================

  /// Update sync status
  Future<void> updateSyncStatus(
    String postId,
    PostSyncStatus status, {
    String? error,
    String? networkPostId,
  }) async {
    await _ensureInitialized();

    final updates = <String, dynamic>{
      'sync_status': status.name,
      'sync_error': error,
      'last_sync_at': DateTime.now().millisecondsSinceEpoch,
    };

    if (networkPostId != null) {
      updates['network_post_id'] = networkPostId;
    }

    await _database!.update(
      'posts',
      updates,
      where: 'id = ?',
      whereArgs: [postId],
    );

    debugPrint('Post sync status updated: $postId -> ${status.name}');
  }

  // ==================== STATISTICS ====================

  /// Get post count for a facet
  Future<int> getPostCount(String facetId, {bool includeDrafts = false}) async {
    await _ensureInitialized();

    String where = 'facet_id = ? AND is_deleted = 0';
    if (!includeDrafts) {
      where += " AND visibility != 'draft'";
    }

    final result = await _database!.rawQuery(
      'SELECT COUNT(*) as count FROM posts WHERE $where',
      [facetId],
    );

    return (result.first['count'] as int?) ?? 0;
  }

  /// Get total views for a facet
  Future<int> getTotalViews(String facetId) async {
    await _ensureInitialized();

    final result = await _database!.rawQuery(
      'SELECT SUM(view_count) as total FROM posts WHERE facet_id = ? AND is_deleted = 0',
      [facetId],
    );

    return (result.first['total'] as int?) ?? 0;
  }

  /// Get facet statistics
  Future<FacetPostStats> getFacetStats(String facetId) async {
    await _ensureInitialized();

    final result = await _database!.rawQuery('''
      SELECT 
        COUNT(*) as post_count,
        COALESCE(SUM(view_count), 0) as total_views,
        COALESCE(SUM(like_count), 0) as total_likes,
        COALESCE(SUM(reply_count), 0) as total_replies
      FROM posts 
      WHERE facet_id = ? AND is_deleted = 0 AND visibility != 'draft'
    ''', [facetId]);

    final row = result.first;
    return FacetPostStats(
      facetId: facetId,
      postCount: (row['post_count'] as int?) ?? 0,
      totalViews: (row['total_views'] as int?) ?? 0,
      totalLikes: (row['total_likes'] as int?) ?? 0,
      totalReplies: (row['total_replies'] as int?) ?? 0,
    );
  }

  // ==================== HELPERS ====================

  Future<FacetPost> _postFromRow(Map<String, dynamic> row) async {
    // Load media for this post
    final mediaRows = await _database!.query(
      'post_media',
      where: 'post_id = ?',
      whereArgs: [row['id']],
    );

    final media = mediaRows.map((m) => PostMedia(
      id: m['id'] as String,
      postId: m['post_id'] as String,
      type: m['type'] as String,
      localPath: m['local_path'] as String?,
      remoteUrl: m['remote_url'] as String?,
      thumbnailBase64: m['thumbnail_base64'] as String?,
      mimeType: m['mime_type'] as String?,
      sizeBytes: m['size_bytes'] as int?,
      width: m['width'] as int?,
      height: m['height'] as int?,
      durationMs: m['duration_ms'] as int?,
      altText: m['alt_text'] as String?,
    )).toList();

    return FacetPost(
      id: row['id'] as String,
      facetId: row['facet_id'] as String,
      authorPublicKey: row['author_public_key'] as String,
      authorHandle: row['author_handle'] as String?,
      content: row['content'] as String,
      media: media,
      locationName: row['location_name'] as String?,
      locationLat: row['location_lat'] as double?,
      locationLng: row['location_lng'] as double?,
      visibility: PostVisibility.values.firstWhere(
        (v) => v.name == row['visibility'],
        orElse: () => PostVisibility.public,
      ),
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      editedAt: row['edited_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(row['edited_at'] as int)
          : null,
      isEdited: (row['is_edited'] as int?) == 1,
      isDeleted: (row['is_deleted'] as int?) == 1,
      viewCount: row['view_count'] as int? ?? 0,
      likeCount: row['like_count'] as int? ?? 0,
      replyCount: row['reply_count'] as int? ?? 0,
      repostCount: row['repost_count'] as int? ?? 0,
      isLikedByMe: (row['is_liked_by_me'] as int?) == 1,
      isRepostedByMe: (row['is_reposted_by_me'] as int?) == 1,
      syncStatus: PostSyncStatus.values.firstWhere(
        (s) => s.name == row['sync_status'],
        orElse: () => PostSyncStatus.pending,
      ),
      syncError: row['sync_error'] as String?,
      lastSyncAt: row['last_sync_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(row['last_sync_at'] as int)
          : null,
      networkPostId: row['network_post_id'] as String?,
      replyToPostId: row['reply_to_post_id'] as String?,
      threadRootId: row['thread_root_id'] as String?,
      threadDepth: row['thread_depth'] as int? ?? 0,
    );
  }

  /// Close database
  Future<void> close() async {
    await _database?.close();
    _database = null;
    _initialized = false;
  }

  /// Delete all posts (for testing/reset)
  Future<void> deleteAll() async {
    await _ensureInitialized();
    await _database!.delete('post_media');
    await _database!.delete('post_likes');
    await _database!.delete('posts');
    debugPrint('All facet posts deleted');
  }
}

/// Statistics for a facet's posts
class FacetPostStats {
  final String facetId;
  final int postCount;
  final int totalViews;
  final int totalLikes;
  final int totalReplies;

  FacetPostStats({
    required this.facetId,
    required this.postCount,
    required this.totalViews,
    required this.totalLikes,
    required this.totalReplies,
  });

  int get totalEngagement => totalViews + totalLikes + totalReplies;
}
