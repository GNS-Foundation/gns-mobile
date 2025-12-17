/// DIX Sync Service - Network Broadcasting
/// 
/// Syncs local DIX posts to the GNS network via Supabase RPC.
/// Handles retry logic, signature generation, and status updates.
/// 
/// Location: lib/core/dix/dix_sync_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../gns/identity_wallet.dart';
import '../posts/facet_post_storage.dart';

/// Sync result for a single post
class PostSyncResult {
  final String postId;
  final bool success;
  final String? networkPostId;
  final String? error;

  PostSyncResult({
    required this.postId,
    required this.success,
    this.networkPostId,
    this.error,
  });
}

/// Batch sync result
class BatchSyncResult {
  final int total;
  final int succeeded;
  final int failed;
  final List<PostSyncResult> results;

  BatchSyncResult({
    required this.total,
    required this.succeeded,
    required this.failed,
    required this.results,
  });

  bool get allSucceeded => succeeded == total;
  bool get anyFailed => failed > 0;
}

/// Service for syncing DIX posts to the network
class DixSyncService {
  static final DixSyncService _instance = DixSyncService._internal();
  factory DixSyncService() => _instance;
  DixSyncService._internal();

  final _postStorage = FacetPostStorage();
  final _wallet = IdentityWallet();
  
  // Supabase client
  SupabaseClient get _supabase => Supabase.instance.client;
  
  // Configuration
  static const Duration _syncInterval = Duration(minutes: 5);
  static const int _maxRetries = 3;
  static const Duration _retryDelay = Duration(seconds: 30);
  
  Timer? _syncTimer;
  bool _syncing = false;
  
  // Stream for sync status updates
  final _syncStatusController = StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get syncStatus => _syncStatusController.stream;

  // ==================== INITIALIZATION ====================

  Future<void> initialize() async {
    await _postStorage.initialize();
    
    // Start periodic sync
    _startPeriodicSync();
    
    // Do an initial sync
    syncPendingPosts();
    
    debugPrint('DixSyncService initialized');
  }

  void _startPeriodicSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(_syncInterval, (_) {
      syncPendingPosts();
    });
  }

  void dispose() {
    _syncTimer?.cancel();
    _syncStatusController.close();
  }

  // ==================== SYNC METHODS ====================

  /// Sync all pending posts to the network
  Future<BatchSyncResult> syncPendingPosts() async {
    if (_syncing) {
      debugPrint('Sync already in progress, skipping');
      return BatchSyncResult(total: 0, succeeded: 0, failed: 0, results: []);
    }

    _syncing = true;
    _syncStatusController.add(SyncStatus.syncing);

    try {
      // Get posts that need syncing
      final pendingPosts = await _postStorage.getPendingSyncPosts();
      
      if (pendingPosts.isEmpty) {
        debugPrint('No pending posts to sync');
        _syncStatusController.add(SyncStatus.idle);
        return BatchSyncResult(total: 0, succeeded: 0, failed: 0, results: []);
      }

      debugPrint('Syncing ${pendingPosts.length} pending posts...');

      final results = <PostSyncResult>[];
      int succeeded = 0;
      int failed = 0;

      for (final post in pendingPosts) {
        final result = await _syncPost(post);
        results.add(result);
        
        if (result.success) {
          succeeded++;
        } else {
          failed++;
        }

        // Small delay between posts to avoid rate limiting
        await Future.delayed(const Duration(milliseconds: 100));
      }

      debugPrint('Sync complete: $succeeded succeeded, $failed failed');
      _syncStatusController.add(failed > 0 ? SyncStatus.error : SyncStatus.idle);

      return BatchSyncResult(
        total: pendingPosts.length,
        succeeded: succeeded,
        failed: failed,
        results: results,
      );
    } catch (e) {
      debugPrint('Batch sync error: $e');
      _syncStatusController.add(SyncStatus.error);
      return BatchSyncResult(total: 0, succeeded: 0, failed: 0, results: []);
    } finally {
      _syncing = false;
    }
  }

  /// Sync a single post immediately (called after creating a new post)
  Future<PostSyncResult> syncPost(FacetPost post) async {
    _syncStatusController.add(SyncStatus.syncing);
    
    try {
      final result = await _syncPost(post);
      _syncStatusController.add(result.success ? SyncStatus.idle : SyncStatus.error);
      return result;
    } catch (e) {
      _syncStatusController.add(SyncStatus.error);
      return PostSyncResult(
        postId: post.id,
        success: false,
        error: e.toString(),
      );
    }
  }

  /// Internal: sync a single post with retries
  Future<PostSyncResult> _syncPost(FacetPost post) async {
    // Mark as syncing
    await _postStorage.updateSyncStatus(post.id, PostSyncStatus.syncing);

    for (int attempt = 1; attempt <= _maxRetries; attempt++) {
      try {
        debugPrint('Syncing post ${post.id} (attempt $attempt/$_maxRetries)');
        
        // Build the signed payload
        final signature = await _generateSignature(post);
        if (signature == null) {
          throw Exception('Failed to sign post');
        }

        // Call Supabase RPC
        final response = await _supabase.rpc('publish_dix_post', params: {
          'p_id': post.id,
          'p_facet_id': post.facetId,
          'p_author_public_key': post.authorPublicKey,
          'p_author_handle': post.authorHandle,
          'p_content': post.content,
          'p_media': post.media.map((m) => m.toJson()).toList(),
          'p_location_name': post.locationName,
          'p_visibility': post.visibility.name,
          'p_created_at': post.createdAt.toUtc().toIso8601String(),
          'p_reply_to_post_id': post.replyToPostId,
          'p_tags': _extractTags(post.content),
          'p_mentions': _extractMentions(post.content),
          'p_signature': signature,
        });

        final responseMap = response as Map<String, dynamic>;

        if (responseMap['success'] == true) {
          // Success!
          final networkPostId = responseMap['network_post_id'] as String?;
          
          await _postStorage.updateSyncStatus(
            post.id,
            PostSyncStatus.synced,
            networkPostId: networkPostId,
          );

          debugPrint('✅ Post ${post.id} synced successfully');
          
          return PostSyncResult(
            postId: post.id,
            success: true,
            networkPostId: networkPostId,
          );
        } else {
          // Server returned an error
          final error = responseMap['error'] as String? ?? 'Unknown error';
          throw Exception(error);
        }
      } catch (e) {
        debugPrint('Sync attempt $attempt failed: $e');
        
        if (attempt < _maxRetries) {
          await Future.delayed(_retryDelay);
        } else {
          // All retries exhausted
          await _postStorage.updateSyncStatus(
            post.id,
            PostSyncStatus.failed,
            error: e.toString(),
          );
          
          return PostSyncResult(
            postId: post.id,
            success: false,
            error: e.toString(),
          );
        }
      }
    }

    // Should never reach here
    return PostSyncResult(postId: post.id, success: false, error: 'Unknown error');
  }

  // ==================== SIGNATURE GENERATION ====================

  /// Generate signature for a post
  Future<String?> _generateSignature(FacetPost post) async {
    if (!_wallet.hasIdentity) {
      debugPrint('No identity available for signing');
      return null;
    }

    // Build the data to sign (subset of fields for verification)
    final signedData = {
      'id': post.id,
      'facet_id': post.facetId,
      'author_public_key': post.authorPublicKey,
      'content': post.content,
      'created_at': post.createdAt.toUtc().toIso8601String(),
    };

    // Create canonical JSON for signing
    final canonicalMessage = _canonicalJson(signedData);
    
    // Sign with wallet
    return await _wallet.signString(canonicalMessage);
  }

  /// Create canonical JSON with sorted keys (matches server)
  String _canonicalJson(dynamic obj) {
    if (obj == null) return 'null';
    if (obj is bool) return obj.toString();
    if (obj is num) {
      if (obj is int) return obj.toString();
      if (obj == obj.truncateToDouble()) return obj.toInt().toString();
      return obj.toString();
    }
    if (obj is String) return jsonEncode(obj);
    if (obj is List) {
      return '[${obj.map(_canonicalJson).join(',')}]';
    }
    if (obj is Map) {
      final sortedKeys = obj.keys.map((k) => k.toString()).toList()..sort();
      final pairs = sortedKeys.map((key) {
        return '"$key":${_canonicalJson(obj[key])}';
      });
      return '{${pairs.join(',')}}';
    }
    return jsonEncode(obj);
  }

  /// Extract hashtags from content
  List<String> _extractTags(String text) {
    final regex = RegExp(r'#([a-zA-Z][a-zA-Z0-9_]*)');
    return regex.allMatches(text)
        .map((m) => m.group(1)!.toLowerCase())
        .toSet()
        .toList();
  }

  /// Extract mentions from content
  List<String> _extractMentions(String text) {
    final regex = RegExp(r'@([a-zA-Z][a-zA-Z0-9_]*)');
    return regex.allMatches(text)
        .map((m) => m.group(1)!.toLowerCase())
        .toSet()
        .toList();
  }

  // ==================== UTILITY METHODS ====================

  /// Check if we have posts waiting to sync
  Future<bool> hasPendingPosts() async {
    final pending = await _postStorage.getPendingSyncPosts(limit: 1);
    return pending.isNotEmpty;
  }

  /// Get count of pending posts
  Future<int> getPendingCount() async {
    final pending = await _postStorage.getPendingSyncPosts();
    return pending.length;
  }

  /// Force retry failed posts
  Future<void> retryFailedPosts() async {
    // Get failed posts and reset their status to pending
    final posts = await _postStorage.getPendingSyncPosts();
    for (final post in posts) {
      if (post.syncStatus == PostSyncStatus.failed) {
        await _postStorage.updateSyncStatus(post.id, PostSyncStatus.pending);
      }
    }
    
    // Trigger sync
    syncPendingPosts();
  }

  /// Manual trigger for sync (e.g., pull-to-refresh)
  Future<BatchSyncResult> triggerSync() async {
    return syncPendingPosts();
  }
}

/// Sync status for UI updates
enum SyncStatus {
  idle,
  syncing,
  error,
}
