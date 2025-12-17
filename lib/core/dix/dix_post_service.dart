/// DIX Post Service - Globe Posts
/// 
/// Handles creating, signing, and publishing posts to DIX via Supabase.
/// 
/// Location: lib/core/dix/dix_post_service.dart

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:convert/convert.dart';
import 'package:uuid/uuid.dart';
import '../crypto/identity_keypair.dart';

// ===========================================
// POST MODELS
// ===========================================

class DixPost {
  final String id;
  final String authorPk;
  final String? authorHandle;
  final String facetId;
  final DixPostContent content;
  final String signature;
  final int trustScore;
  final int breadcrumbCount;
  final DateTime createdAt;
  
  // Engagement (from server)
  final int likeCount;
  final int replyCount;
  final int repostCount;
  final int viewCount;
  
  // Threading
  final String? replyToId;
  final String? quoteOfId;
  
  DixPost({
    required this.id,
    required this.authorPk,
    this.authorHandle,
    this.facetId = 'dix',
    required this.content,
    required this.signature,
    this.trustScore = 0,
    this.breadcrumbCount = 0,
    required this.createdAt,
    this.likeCount = 0,
    this.replyCount = 0,
    this.repostCount = 0,
    this.viewCount = 0,
    this.replyToId,
    this.quoteOfId,
  });
  
  factory DixPost.fromJson(Map<String, dynamic> json) {
    final contentData = json['content'] ?? json['payload_json'] ?? {};
    return DixPost(
      id: json['id'] ?? json['post_id'] ?? '',
      authorPk: json['author']?['publicKey'] ?? json['author_pk'] ?? json['author_public_key'] ?? '',
      authorHandle: json['author']?['handle'] ?? json['author_handle'],
      facetId: json['facet'] ?? json['facet_id'] ?? 'dix',
      content: DixPostContent.fromJson(contentData is String ? jsonDecode(contentData) : contentData),
      signature: json['meta']?['signature'] ?? json['signature'] ?? '',
      trustScore: json['meta']?['trustScoreAtPost'] ?? json['trust_score'] ?? 0,
      breadcrumbCount: json['meta']?['breadcrumbsAtPost'] ?? json['breadcrumb_count'] ?? 0,
      createdAt: DateTime.parse(json['meta']?['createdAt'] ?? json['created_at'] ?? DateTime.now().toIso8601String()),
      likeCount: json['engagement']?['likes'] ?? json['like_count'] ?? 0,
      replyCount: json['engagement']?['replies'] ?? json['reply_count'] ?? 0,
      repostCount: json['engagement']?['reposts'] ?? json['repost_count'] ?? 0,
      viewCount: json['engagement']?['views'] ?? json['view_count'] ?? 0,
      replyToId: json['thread']?['replyToId'] ?? json['reply_to_id'] ?? json['reply_to_post_id'],
      quoteOfId: json['thread']?['quoteOfId'] ?? json['quote_of_id'],
    );
  }
}

class DixPostContent {
  final String text;
  final List<String> tags;
  final List<String> mentions;
  final List<DixMedia> media;
  final String? locationLabel;
  final String? locationH3;
  
  DixPostContent({
    required this.text,
    this.tags = const [],
    this.mentions = const [],
    this.media = const [],
    this.locationLabel,
    this.locationH3,
  });
  
  factory DixPostContent.fromJson(Map<String, dynamic> json) {
    return DixPostContent(
      text: json['text'] ?? '',
      tags: List<String>.from(json['tags'] ?? []),
      mentions: List<String>.from(json['mentions'] ?? []),
      media: (json['media'] as List?)?.map((m) => DixMedia.fromJson(m)).toList() ?? [],
      locationLabel: json['location_label'],
      locationH3: json['location_h3'],
    );
  }
  
  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'text': text,
    };
    if (tags.isNotEmpty) map['tags'] = tags;
    if (mentions.isNotEmpty) map['mentions'] = mentions;
    if (media.isNotEmpty) map['media'] = media.map((m) => m.toJson()).toList();
    if (locationLabel != null) map['location_label'] = locationLabel;
    if (locationH3 != null) map['location_h3'] = locationH3;
    return map;
  }
}

class DixMedia {
  final String type; // 'image', 'video'
  final String url;
  final String? alt;
  
  DixMedia({
    required this.type,
    required this.url,
    this.alt,
  });
  
  factory DixMedia.fromJson(Map<String, dynamic> json) {
    return DixMedia(
      type: json['type'] ?? 'image',
      url: json['url'] ?? '',
      alt: json['alt'],
    );
  }
  
  Map<String, dynamic> toJson() => {
    'type': type,
    'url': url,
    if (alt != null) 'alt': alt,
  };
}

// ===========================================
// DIX POST SERVICE
// ===========================================

class DixPostService {
  static final DixPostService _instance = DixPostService._internal();
  factory DixPostService() => _instance;
  DixPostService._internal();
  
  final Uuid _uuid = const Uuid();
  
  /// Get Supabase client
  SupabaseClient get _supabase => Supabase.instance.client;
  
  // ===========================================
  // CREATE & PUBLISH POST
  // ===========================================
  
  /// Create and publish a new DIX post via Supabase RPC
  /// 
  /// Returns the created post or throws an exception
  Future<DixPost> createPost({
    required GnsKeypair keypair,
    required String text,
    String? handle,
    List<String>? tags,
    List<DixMedia>? media,
    String? locationLabel,
    String? locationH3,
    String? replyToId,
    String? quoteOfId,
    int trustScore = 0,
    int breadcrumbCount = 0,
  }) async {
    // Generate UUID for post
    final postId = _uuid.v4();
    
    // Parse hashtags from text if not provided
    final parsedTags = tags ?? _parseHashtags(text);
    final parsedMentions = _parseMentions(text);
    
    // Build content
    final content = DixPostContent(
      text: text,
      tags: parsedTags,
      mentions: parsedMentions,
      media: media ?? [],
      locationLabel: locationLabel,
      locationH3: locationH3,
    );
    
    // Create timestamp
    final createdAt = DateTime.now().toUtc();
    
    // Build canonical payload for signing
    final signedData = {
      'id': postId,
      'facet_id': 'dix',
      'author_public_key': keypair.publicKeyHex,
      'content': text,
      'created_at': createdAt.toIso8601String(),
    };
    final canonicalMessage = _canonicalJson(signedData);
    
    // Sign the payload
    final signatureBytes = await keypair.signString(canonicalMessage);
    final signature = hex.encode(signatureBytes);
    
    debugPrint('📝 Creating DIX post via Supabase...');
    debugPrint('   ID: $postId');
    debugPrint('   Text: ${text.substring(0, text.length.clamp(0, 50))}...');
    debugPrint('   Tags: $parsedTags');
    debugPrint('   Signature: ${signature.substring(0, 16)}...');
    
    try {
      // Call Supabase RPC
      final response = await _supabase.rpc('publish_dix_post', params: {
        'p_id': postId,
        'p_facet_id': 'dix',
        'p_author_public_key': keypair.publicKeyHex,
        'p_author_handle': handle,
        'p_content': text,
        'p_media': media?.map((m) => m.toJson()).toList() ?? [],
        'p_location_name': locationLabel,
        'p_visibility': 'public',
        'p_created_at': createdAt.toIso8601String(),
        'p_reply_to_post_id': replyToId,
        'p_tags': parsedTags,
        'p_mentions': parsedMentions,
        'p_signature': signature,
      });

      final responseMap = response as Map<String, dynamic>;

      if (responseMap['success'] == true) {
        debugPrint('✅ Post created successfully!');
        debugPrint('   Post ID: ${responseMap['post_id']}');
        
        // Return the created post
        return DixPost(
          id: postId,
          authorPk: keypair.publicKeyHex,
          authorHandle: handle,
          facetId: 'dix',
          content: content,
          signature: signature,
          trustScore: trustScore,
          breadcrumbCount: breadcrumbCount,
          createdAt: createdAt,
        );
      } else {
        final error = responseMap['error'] ?? 'Failed to create post';
        debugPrint('❌ Post creation failed: $error');
        throw Exception(error);
      }
    } catch (e) {
      debugPrint('❌ Failed to create post: $e');
      rethrow;
    }
  }
  
  // ===========================================
  // FETCH POSTS (via Supabase RPC)
  // ===========================================
  
  /// Get the public DIX timeline
  Future<List<DixPost>> getTimeline({int limit = 20, int offset = 0}) async {
    try {
      final response = await _supabase.rpc('get_dix_timeline', params: {
        'p_limit': limit,
        'p_offset': offset,
      });
      
      final List<dynamic> data = response as List<dynamic>? ?? [];
      return data.map((p) => DixPost.fromJson(p as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('❌ Failed to fetch timeline: $e');
      return [];
    }
  }
  
  /// Get posts by a specific user (by public key)
  Future<List<DixPost>> getUserPosts(String publicKey, {int limit = 20, int offset = 0}) async {
    try {
      final response = await _supabase.rpc('get_dix_timeline', params: {
        'p_limit': limit,
        'p_offset': offset,
        'p_author_public_key': publicKey,
      });
      
      final List<dynamic> data = response as List<dynamic>? ?? [];
      return data.map((p) => DixPost.fromJson(p as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('❌ Failed to fetch user posts: $e');
      return [];
    }
  }
  
  /// Like a post
  Future<bool> likePost(String postId, String userPublicKey) async {
    try {
      final response = await _supabase.rpc('like_dix_post', params: {
        'p_post_id': postId,
        'p_user_public_key': userPublicKey,
      });
      
      final responseMap = response as Map<String, dynamic>;
      return responseMap['success'] == true;
    } catch (e) {
      debugPrint('❌ Failed to like post: $e');
      return false;
    }
  }
  
  /// Unlike a post
  Future<bool> unlikePost(String postId, String userPublicKey) async {
    try {
      final response = await _supabase.rpc('unlike_dix_post', params: {
        'p_post_id': postId,
        'p_user_public_key': userPublicKey,
      });
      
      final responseMap = response as Map<String, dynamic>;
      return responseMap['success'] == true;
    } catch (e) {
      debugPrint('❌ Failed to unlike post: $e');
      return false;
    }
  }
  
  // ===========================================
  // HELPERS
  // ===========================================
  
  /// Create canonical JSON with sorted keys (for signing)
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
  
  /// Parse hashtags from text
  List<String> _parseHashtags(String text) {
    final regex = RegExp(r'#([a-zA-Z][a-zA-Z0-9_]*)');
    return regex.allMatches(text)
        .map((m) => m.group(1)!.toLowerCase())
        .toSet()
        .toList();
  }
  
  /// Parse mentions from text
  List<String> _parseMentions(String text) {
    final regex = RegExp(r'@([a-zA-Z][a-zA-Z0-9_]*)');
    return regex.allMatches(text)
        .map((m) => m.group(1)!.toLowerCase())
        .toSet()
        .toList();
  }
}
