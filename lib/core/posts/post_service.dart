/// Post Service - Globe Posts Phase 2
///
/// Business logic for creating, signing, and managing posts.
/// Integrates with:
/// - PostStorage (local persistence)
/// - IdentityWallet (signing)
/// - GnsApiClient (backend API)
///
/// Philosophy: HUMANS PREVAIL
/// - Every post is cryptographically signed
/// - Trust score provides spam resistance
/// - Signature verification proves authorship
///
/// Location: lib/core/posts/post_service.dart

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'gns_post.dart';
import 'post_storage.dart';
import '../facets/post_payload_types.dart';

// Import these from your existing codebase:
// import '../identity/identity_wallet.dart';
// import '../api/gns_api_client.dart';
// import '../crypto/comm_crypto_service.dart';

/// Result of post creation
class CreatePostResult {
  final bool success;
  final GnsPost? post;
  final String? error;
  final String? errorCode;

  const CreatePostResult._({
    required this.success,
    this.post,
    this.error,
    this.errorCode,
  });

  factory CreatePostResult.success(GnsPost post) => CreatePostResult._(
    success: true,
    post: post,
  );

  factory CreatePostResult.failure(String error, {String? code}) => CreatePostResult._(
    success: false,
    error: error,
    errorCode: code,
  );
}

/// Result of post interaction (like, bookmark, etc.)
class PostInteractionResult {
  final bool success;
  final String? error;

  const PostInteractionResult._({
    required this.success,
    this.error,
  });

  factory PostInteractionResult.success() => const PostInteractionResult._(success: true);
  factory PostInteractionResult.failure(String error) => PostInteractionResult._(
    success: false,
    error: error,
  );
}

/// Service for managing posts
class PostService {
  // Singleton
  static final PostService _instance = PostService._internal();
  factory PostService() => _instance;
  PostService._internal();

  // Dependencies (inject these or use existing singletons)
  final PostStorage _storage = PostStorage();
  // final IdentityWallet _wallet = IdentityWallet();
  // final GnsApiClient _api = GnsApiClient();
  
  final Uuid _uuid = const Uuid();
  
  bool _initialized = false;

  // ============================================================
  // INITIALIZATION
  // ============================================================

  Future<void> initialize() async {
    if (_initialized) return;
    
    await _storage.initialize();
    _initialized = true;
    debugPrint('📝 PostService initialized');
  }

  Future<void> _ensureInitialized() async {
    if (!_initialized) await initialize();
  }

  // ============================================================
  // POST CREATION
  // ============================================================

  /// Create and publish a new post
  /// 
  /// [text] - Post content (max 280 chars for micro-posts)
  /// [facetId] - Facet to post from (e.g., "dix")
  /// [media] - Optional media attachments
  /// [replyToId] - If replying to another post
  /// [quoteOfId] - If quoting another post
  /// [locationH3] - Optional location (H3 cell)
  Future<CreatePostResult> createPost({
    required String text,
    required String facetId,
    List<PostMediaAttachment>? media,
    String? replyToId,
    String? quoteOfId,
    String? locationH3,
    String? locationLabel,
  }) async {
    await _ensureInitialized();

    try {
      // Validate text length
      if (text.isEmpty && (media == null || media.isEmpty)) {
        return CreatePostResult.failure('Post cannot be empty', code: 'EMPTY_POST');
      }
      
      if (text.length > 280) {
        return CreatePostResult.failure(
          'Post exceeds 280 character limit (${text.length} chars)',
          code: 'TEXT_TOO_LONG',
        );
      }

      // Get identity info (replace with actual wallet calls)
      final authorPk = await _getPublicKey();
      final authorHandle = await _getHandle();
      final trustScore = await _getTrustScore();
      final breadcrumbCount = await _getBreadcrumbCount();

      if (authorPk == null) {
        return CreatePostResult.failure('No identity found', code: 'NO_IDENTITY');
      }

      // Build payload
      final payload = PublicPostPayload.fromText(
        text,
        media: media,
        replyToId: replyToId,
        quoteOfId: quoteOfId,
        locationH3: locationH3,
        locationLabel: locationLabel,
      );

      // Generate post ID and timestamp
      final postId = _uuid.v4();
      final createdAt = DateTime.now().toUtc();

      // Get signing bytes
      final signingBytes = GnsPost.getSigningBytes(
        authorPk: authorPk,
        facetId: facetId,
        payloadJson: payload.toJson(),
        createdAt: createdAt,
      );

      // Sign the post (replace with actual signing)
      final signature = await _signBytes(signingBytes);
      
      if (signature == null) {
        return CreatePostResult.failure('Failed to sign post', code: 'SIGN_FAILED');
      }

      // Create post object
      final post = GnsPost(
        id: postId,
        authorPk: authorPk,
        authorHandle: authorHandle,
        facetId: facetId,
        payloadType: payload.type,
        payloadJson: payload.toJson(),
        signature: signature,
        trustScore: trustScore,
        breadcrumbCount: breadcrumbCount,
        replyToId: replyToId,
        quoteOfId: quoteOfId,
        createdAt: createdAt,
      );

      // Save locally first
      await _storage.savePost(post, isOwnPost: true);

      // Publish to server
      final published = await _publishPost(post);
      
      if (!published) {
        // Still saved locally, mark as pending sync
        debugPrint('⚠️ Post saved locally but failed to publish');
        return CreatePostResult.success(post);
      }

      debugPrint('✅ Post created and published: ${post.id}');
      return CreatePostResult.success(post);

    } catch (e, stack) {
      debugPrint('❌ Error creating post: $e\n$stack');
      return CreatePostResult.failure('Failed to create post: $e', code: 'CREATE_ERROR');
    }
  }

  /// Create a reply to a post
  Future<CreatePostResult> createReply({
    required String text,
    required String replyToId,
    required String facetId,
    List<PostMediaAttachment>? media,
  }) async {
    return createPost(
      text: text,
      facetId: facetId,
      media: media,
      replyToId: replyToId,
    );
  }

  /// Create a quote post
  Future<CreatePostResult> createQuote({
    required String text,
    required String quoteOfId,
    required String facetId,
  }) async {
    return createPost(
      text: text,
      facetId: facetId,
      quoteOfId: quoteOfId,
    );
  }

  /// Repost (share without comment)
  Future<CreatePostResult> repost({
    required String postId,
    required String facetId,
  }) async {
    await _ensureInitialized();

    try {
      final authorPk = await _getPublicKey();
      final authorHandle = await _getHandle();
      final trustScore = await _getTrustScore();
      final breadcrumbCount = await _getBreadcrumbCount();

      if (authorPk == null) {
        return CreatePostResult.failure('No identity found', code: 'NO_IDENTITY');
      }

      final repostId = _uuid.v4();
      final createdAt = DateTime.now().toUtc();

      final payloadJson = {
        'type': PostPayloadType.postRepost,
        'original_post_id': postId,
      };

      final signingBytes = GnsPost.getSigningBytes(
        authorPk: authorPk,
        facetId: facetId,
        payloadJson: payloadJson,
        createdAt: createdAt,
      );

      final signature = await _signBytes(signingBytes);
      
      if (signature == null) {
        return CreatePostResult.failure('Failed to sign repost', code: 'SIGN_FAILED');
      }

      final post = GnsPost(
        id: repostId,
        authorPk: authorPk,
        authorHandle: authorHandle,
        facetId: facetId,
        payloadType: PostPayloadType.postRepost,
        payloadJson: payloadJson,
        signature: signature,
        trustScore: trustScore,
        breadcrumbCount: breadcrumbCount,
        quoteOfId: postId,
        createdAt: createdAt,
      );

      await _storage.savePost(post, isOwnPost: true);
      await _publishPost(post);

      return CreatePostResult.success(post);

    } catch (e) {
      return CreatePostResult.failure('Failed to repost: $e', code: 'REPOST_ERROR');
    }
  }

  // ============================================================
  // POST INTERACTIONS
  // ============================================================

  /// Like a post
  Future<PostInteractionResult> likePost(String postId) async {
    await _ensureInitialized();

    try {
      // Mark locally
      await _storage.markLiked(postId);

      // Update local engagement
      final post = await _storage.getPost(postId);
      if (post != null) {
        await _storage.updateEngagement(
          postId,
          post.engagement.copyWith(likeCount: post.engagement.likeCount + 1),
        );
      }

      // Send to server
      await _sendInteraction(PostPayloadType.postLike, postId);

      return PostInteractionResult.success();
    } catch (e) {
      return PostInteractionResult.failure('Failed to like post: $e');
    }
  }

  /// Unlike a post
  Future<PostInteractionResult> unlikePost(String postId) async {
    await _ensureInitialized();

    try {
      await _storage.markUnliked(postId);

      final post = await _storage.getPost(postId);
      if (post != null && post.engagement.likeCount > 0) {
        await _storage.updateEngagement(
          postId,
          post.engagement.copyWith(likeCount: post.engagement.likeCount - 1),
        );
      }

      await _sendInteraction(PostPayloadType.postUnlike, postId);

      return PostInteractionResult.success();
    } catch (e) {
      return PostInteractionResult.failure('Failed to unlike post: $e');
    }
  }

  /// Bookmark a post
  Future<PostInteractionResult> bookmarkPost(String postId) async {
    await _ensureInitialized();

    try {
      await _storage.bookmarkPost(postId);
      return PostInteractionResult.success();
    } catch (e) {
      return PostInteractionResult.failure('Failed to bookmark post: $e');
    }
  }

  /// Remove bookmark
  Future<PostInteractionResult> unbookmarkPost(String postId) async {
    await _ensureInitialized();

    try {
      await _storage.unbookmarkPost(postId);
      return PostInteractionResult.success();
    } catch (e) {
      return PostInteractionResult.failure('Failed to remove bookmark: $e');
    }
  }

  /// Retract (soft-delete) own post
  Future<PostInteractionResult> retractPost(String postId) async {
    await _ensureInitialized();

    try {
      final post = await _storage.getPost(postId);
      if (post == null) {
        return PostInteractionResult.failure('Post not found');
      }

      // Verify ownership
      final authorPk = await _getPublicKey();
      if (post.authorPk != authorPk) {
        return PostInteractionResult.failure('Cannot retract posts you did not create');
      }

      // Update locally
      final retractedPost = post.copyWith(status: PostStatus.retracted);
      await _storage.savePost(retractedPost, isOwnPost: true);

      // Send to server
      // await _api.retractPost(postId);

      return PostInteractionResult.success();
    } catch (e) {
      return PostInteractionResult.failure('Failed to retract post: $e');
    }
  }

  // ============================================================
  // TIMELINE & QUERIES
  // ============================================================

  /// Fetch public timeline from server and cache locally
  Future<List<GnsPost>> fetchTimeline({
    int limit = 20,
    String? beforeId,
  }) async {
    await _ensureInitialized();

    try {
      // Fetch from server
      final posts = await _fetchTimelineFromServer(limit: limit, beforeId: beforeId);
      
      // Cache locally
      await _storage.savePosts(posts);
      
      return posts;
    } catch (e) {
      debugPrint('⚠️ Failed to fetch timeline from server: $e');
      // Fall back to cached
      return _storage.getTimeline(limit: limit);
    }
  }

  /// Get cached timeline (offline mode)
  Future<List<GnsPost>> getCachedTimeline({
    int limit = 20,
    DateTime? beforeTime,
  }) async {
    await _ensureInitialized();
    return _storage.getTimeline(limit: limit, beforeTime: beforeTime);
  }

  /// Fetch posts by handle
  Future<List<GnsPost>> fetchPostsByHandle(
    String handle, {
    String? facetId,
    int limit = 20,
  }) async {
    await _ensureInitialized();

    try {
      // Fetch from server
      final posts = await _fetchPostsByHandleFromServer(
        handle,
        facetId: facetId,
        limit: limit,
      );
      
      // Cache locally
      await _storage.savePosts(posts);
      
      return posts;
    } catch (e) {
      debugPrint('⚠️ Failed to fetch posts by handle: $e');
      return _storage.getPostsByHandle(handle, facetId: facetId, limit: limit);
    }
  }

  /// Get own posts
  Future<List<GnsPost>> getOwnPosts({int limit = 20}) async {
    await _ensureInitialized();
    return _storage.getOwnPosts(limit: limit);
  }

  /// Get bookmarked posts
  Future<List<GnsPost>> getBookmarkedPosts({int limit = 50}) async {
    await _ensureInitialized();
    return _storage.getBookmarkedPosts(limit: limit);
  }

  /// Get replies to a post
  Future<List<GnsPost>> getReplies(String postId, {int limit = 50}) async {
    await _ensureInitialized();

    try {
      final replies = await _fetchRepliesFromServer(postId, limit: limit);
      await _storage.savePosts(replies);
      return replies;
    } catch (e) {
      return _storage.getReplies(postId, limit: limit);
    }
  }

  /// Search posts
  Future<List<GnsPost>> searchPosts(String query, {int limit = 20}) async {
    await _ensureInitialized();
    
    try {
      // Search server first
      final posts = await _searchPostsOnServer(query, limit: limit);
      await _storage.savePosts(posts);
      return posts;
    } catch (e) {
      // Fall back to local search
      return _storage.searchPosts(query, limit: limit);
    }
  }

  // ============================================================
  // DRAFTS
  // ============================================================

  /// Save a draft
  Future<void> saveDraft(PostDraft draft) async {
    await _ensureInitialized();
    await _storage.saveDraft(draft);
  }

  /// Get all drafts
  Future<List<PostDraft>> getDrafts() async {
    await _ensureInitialized();
    return _storage.getDrafts();
  }

  /// Delete a draft
  Future<void> deleteDraft(String id) async {
    await _ensureInitialized();
    await _storage.deleteDraft(id);
  }

  // ============================================================
  // SIGNATURE VERIFICATION
  // ============================================================

  /// Verify a post's signature
  Future<bool> verifyPostSignature(GnsPost post) async {
    try {
      final signingBytes = post.signingBytes;
      return await _verifySignature(
        signingBytes,
        post.signature,
        post.authorPk,
      );
    } catch (e) {
      debugPrint('❌ Signature verification failed: $e');
      return false;
    }
  }

  // ============================================================
  // PRIVATE HELPERS - Replace with actual implementations
  // ============================================================

  /// Get current user's public key
  Future<String?> _getPublicKey() async {
    // TODO: Replace with actual wallet call
    // return _wallet.getPublicKey();
    return 'TODO_REPLACE_WITH_ACTUAL_PK';
  }

  /// Get current user's handle
  Future<String?> _getHandle() async {
    // TODO: Replace with actual call
    // return _wallet.getHandle();
    return null;
  }

  /// Get current trust score
  Future<double> _getTrustScore() async {
    // TODO: Replace with actual call
    return 0.0;
  }

  /// Get current breadcrumb count
  Future<int> _getBreadcrumbCount() async {
    // TODO: Replace with actual call
    return 0;
  }

  /// Sign bytes with identity key
  Future<String?> _signBytes(Uint8List bytes) async {
    // TODO: Replace with actual signing
    // return _wallet.sign(bytes);
    debugPrint('⚠️ TODO: Implement actual signing');
    return '0' * 128; // Placeholder
  }

  /// Verify signature
  Future<bool> _verifySignature(Uint8List message, String signature, String publicKey) async {
    // TODO: Replace with actual verification
    // return CryptoService.verifySignature(message, signature, publicKey);
    debugPrint('⚠️ TODO: Implement actual verification');
    return true; // Placeholder
  }

  /// Publish post to server
  Future<bool> _publishPost(GnsPost post) async {
    // TODO: Replace with actual API call
    // return _api.publishPost(post);
    debugPrint('⚠️ TODO: Implement actual publishing');
    return true; // Placeholder
  }

  /// Send interaction to server
  Future<void> _sendInteraction(String type, String postId) async {
    // TODO: Replace with actual API call
    // await _api.sendInteraction(type, postId);
    debugPrint('⚠️ TODO: Implement interaction API');
  }

  /// Fetch timeline from server
  Future<List<GnsPost>> _fetchTimelineFromServer({int limit = 20, String? beforeId}) async {
    // TODO: Replace with actual API call
    // return _api.getTimeline(limit: limit, beforeId: beforeId);
    debugPrint('⚠️ TODO: Implement timeline fetch');
    return [];
  }

  /// Fetch posts by handle from server
  Future<List<GnsPost>> _fetchPostsByHandleFromServer(
    String handle, {
    String? facetId,
    int limit = 20,
  }) async {
    // TODO: Replace with actual API call
    debugPrint('⚠️ TODO: Implement posts by handle fetch');
    return [];
  }

  /// Fetch replies from server
  Future<List<GnsPost>> _fetchRepliesFromServer(String postId, {int limit = 50}) async {
    // TODO: Replace with actual API call
    debugPrint('⚠️ TODO: Implement replies fetch');
    return [];
  }

  /// Search posts on server
  Future<List<GnsPost>> _searchPostsOnServer(String query, {int limit = 20}) async {
    // TODO: Replace with actual API call
    debugPrint('⚠️ TODO: Implement search');
    return [];
  }
}

/// Extension for convenient post creation
extension PostServiceExtensions on PostService {
  /// Quick create a simple text post
  Future<CreatePostResult> quickPost(String text, {String facetId = 'dix'}) async {
    return createPost(text: text, facetId: facetId);
  }
}
