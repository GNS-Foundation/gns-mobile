/// GNS Post Model - Globe Posts Phase 2
///
/// The core data model for public posts on Globe Posts.
/// Posts are SIGNED (not encrypted) - they're public content
/// cryptographically attributed to the author's identity.
///
/// Key difference from messages:
/// - Messages: Encrypted, private, point-to-point
/// - Posts: Signed, public, broadcast to followers
///
/// Philosophy: HUMANS PREVAIL
/// - Every post proves authentic human authorship
/// - Trust score and breadcrumbs provide spam resistance
/// - Cryptographic attribution is permanent and unforgeable
///
/// Location: lib/core/posts/gns_post.dart

import 'dart:convert';
import 'dart:typed_data';
import '../facets/post_payload_types.dart';

/// Verification status of a brand facet
class BrandVerification {
  /// Brand ID (e.g., "google")
  final String brand;
  
  /// Employee's role/title
  final String? role;
  
  /// Department
  final String? department;
  
  /// When verification was granted
  final DateTime verifiedAt;

  const BrandVerification({
    required this.brand,
    this.role,
    this.department,
    required this.verifiedAt,
  });

  Map<String, dynamic> toJson() => {
    'brand': brand,
    if (role != null) 'role': role,
    if (department != null) 'department': department,
    'verified_at': verifiedAt.toIso8601String(),
  };

  factory BrandVerification.fromJson(Map<String, dynamic> json) {
    return BrandVerification(
      brand: json['brand'] as String,
      role: json['role'] as String?,
      department: json['department'] as String?,
      verifiedAt: DateTime.parse(json['verified_at'] as String),
    );
  }
}

/// Engagement metrics for a post
class PostEngagement {
  final int likeCount;
  final int replyCount;
  final int repostCount;
  final int quoteCount;
  final int bookmarkCount;
  final int viewCount;

  const PostEngagement({
    this.likeCount = 0,
    this.replyCount = 0,
    this.repostCount = 0,
    this.quoteCount = 0,
    this.bookmarkCount = 0,
    this.viewCount = 0,
  });

  /// Total engagement score
  int get totalEngagement => likeCount + replyCount + repostCount + quoteCount;

  PostEngagement copyWith({
    int? likeCount,
    int? replyCount,
    int? repostCount,
    int? quoteCount,
    int? bookmarkCount,
    int? viewCount,
  }) {
    return PostEngagement(
      likeCount: likeCount ?? this.likeCount,
      replyCount: replyCount ?? this.replyCount,
      repostCount: repostCount ?? this.repostCount,
      quoteCount: quoteCount ?? this.quoteCount,
      bookmarkCount: bookmarkCount ?? this.bookmarkCount,
      viewCount: viewCount ?? this.viewCount,
    );
  }

  Map<String, dynamic> toJson() => {
    'like_count': likeCount,
    'reply_count': replyCount,
    'repost_count': repostCount,
    'quote_count': quoteCount,
    'bookmark_count': bookmarkCount,
    'view_count': viewCount,
  };

  factory PostEngagement.fromJson(Map<String, dynamic> json) {
    return PostEngagement(
      likeCount: json['like_count'] as int? ?? 0,
      replyCount: json['reply_count'] as int? ?? 0,
      repostCount: json['repost_count'] as int? ?? 0,
      quoteCount: json['quote_count'] as int? ?? 0,
      bookmarkCount: json['bookmark_count'] as int? ?? 0,
      viewCount: json['view_count'] as int? ?? 0,
    );
  }
}

/// Post status
enum PostStatus {
  /// Post is live and visible
  published,
  
  /// Post has been retracted by author (still exists, marked as retracted)
  retracted,
  
  /// Post is hidden due to moderation
  hidden,
  
  /// Post is pending (draft, not yet published)
  draft,
}

/// A public post on Globe Posts
class GnsPost {
  /// Unique post ID (UUID v4)
  final String id;
  
  /// Author's Ed25519 public key (64 hex chars)
  final String authorPk;
  
  /// Author's @handle (if claimed)
  final String? authorHandle;
  
  /// Facet ID this post was made from (e.g., "dix", "blog", "google")
  final String facetId;
  
  /// Payload type (e.g., "gns/post.public", "gns/blog.post")
  final String payloadType;
  
  /// Post content as JSON
  final Map<String, dynamic> payloadJson;
  
  /// Ed25519 signature of the canonical payload (128 hex chars)
  final String signature;
  
  /// Author's trust score at time of posting (0-100)
  final double trustScore;
  
  /// Author's breadcrumb count at time of posting
  final int breadcrumbCount;
  
  /// Brand verification (if posting from a licensed brand facet)
  final BrandVerification? brandVerification;
  
  /// Engagement metrics
  final PostEngagement engagement;
  
  /// Post status
  final PostStatus status;
  
  /// ID of post this is a reply to (if reply)
  final String? replyToId;
  
  /// ID of post this quotes (if quote)
  final String? quoteOfId;
  
  /// When the post was created
  final DateTime createdAt;
  
  /// When the post was last updated (for edits/retractions)
  final DateTime updatedAt;

  GnsPost({
    required this.id,
    required this.authorPk,
    this.authorHandle,
    required this.facetId,
    required this.payloadType,
    required this.payloadJson,
    required this.signature,
    required this.trustScore,
    required this.breadcrumbCount,
    this.brandVerification,
    PostEngagement? engagement,
    this.status = PostStatus.published,
    this.replyToId,
    this.quoteOfId,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : engagement = engagement ?? const PostEngagement(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  // ============================================================
  // PAYLOAD HELPERS
  // ============================================================

  /// Get the post text content
  String get text => payloadJson['text'] as String? ?? '';

  /// Get the post title (for blog posts)
  String? get title => payloadJson['title'] as String?;

  /// Get media attachments
  List<PostMediaAttachment> get media {
    final mediaList = payloadJson['media'] as List?;
    if (mediaList == null) return [];
    return mediaList
        .map((m) => PostMediaAttachment.fromJson(m as Map<String, dynamic>))
        .toList();
  }

  /// Get hashtags
  List<String> get tags {
    final tagList = payloadJson['tags'] as List?;
    if (tagList == null) return [];
    return tagList.map((t) => t as String).toList();
  }

  /// Get @mentions
  List<String> get mentions {
    final mentionList = payloadJson['mentions'] as List?;
    if (mentionList == null) return [];
    return mentionList.map((m) => m as String).toList();
  }

  /// Get location H3 cell
  String? get locationH3 => payloadJson['location_h3'] as String?;

  // ============================================================
  // DISPLAY HELPERS
  // ============================================================

  /// Is this a reply?
  bool get isReply => replyToId != null;

  /// Is this a quote?
  bool get isQuote => quoteOfId != null;

  /// Is this a repost (no additional content)?
  bool get isRepost => payloadType == PostPayloadType.postRepost;

  /// Is this a blog post?
  bool get isBlogPost => payloadType == PostPayloadType.blogPost;

  /// Is this from a verified brand?
  bool get isBrandVerified => brandVerification != null;

  /// Is this post retracted?
  bool get isRetracted => status == PostStatus.retracted;

  /// Get the full facet notation (e.g., "dix@username")
  String get facetNotation {
    if (authorHandle != null) {
      return '$facetId@$authorHandle';
    }
    return '$facetId@${authorPk.substring(0, 8)}...';
  }

  /// Get author display name (handle or truncated pk)
  String get authorDisplay {
    if (authorHandle != null) return '@$authorHandle';
    return '${authorPk.substring(0, 8)}...${authorPk.substring(authorPk.length - 4)}';
  }

  /// Trust level description
  String get trustLevel {
    if (trustScore >= 90) return 'Verified';
    if (trustScore >= 70) return 'Trusted';
    if (trustScore >= 50) return 'Established';
    if (trustScore >= 20) return 'Present';
    return 'Genesis';
  }

  /// Trust level emoji
  String get trustEmoji {
    if (trustScore >= 90) return '💎';
    if (trustScore >= 70) return '⭐';
    if (trustScore >= 50) return '🌟';
    if (trustScore >= 20) return '✨';
    return '🌱';
  }

  // ============================================================
  // SERIALIZATION
  // ============================================================

  Map<String, dynamic> toJson() => {
    'id': id,
    'author_pk': authorPk,
    'author_handle': authorHandle,
    'facet_id': facetId,
    'payload_type': payloadType,
    'payload_json': payloadJson,
    'signature': signature,
    'trust_score': trustScore,
    'breadcrumb_count': breadcrumbCount,
    'brand_verification': brandVerification?.toJson(),
    'engagement': engagement.toJson(),
    'status': status.name,
    'reply_to_id': replyToId,
    'quote_of_id': quoteOfId,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  factory GnsPost.fromJson(Map<String, dynamic> json) {
    return GnsPost(
      id: json['id'] as String,
      authorPk: json['author_pk'] as String,
      authorHandle: json['author_handle'] as String?,
      facetId: json['facet_id'] as String,
      payloadType: json['payload_type'] as String,
      payloadJson: json['payload_json'] as Map<String, dynamic>,
      signature: json['signature'] as String,
      trustScore: (json['trust_score'] as num).toDouble(),
      breadcrumbCount: json['breadcrumb_count'] as int,
      brandVerification: json['brand_verification'] != null
          ? BrandVerification.fromJson(json['brand_verification'] as Map<String, dynamic>)
          : null,
      engagement: json['engagement'] != null
          ? PostEngagement.fromJson(json['engagement'] as Map<String, dynamic>)
          : null,
      status: PostStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => PostStatus.published,
      ),
      replyToId: json['reply_to_id'] as String?,
      quoteOfId: json['quote_of_id'] as String?,
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null 
          ? DateTime.parse(json['updated_at'] as String)
          : null,
    );
  }

  // ============================================================
  // SIGNING
  // ============================================================

  /// Get the canonical bytes to sign
  /// 
  /// The signature covers:
  /// - author_pk
  /// - facet_id
  /// - payload (canonical JSON)
  /// - created_at timestamp
  static Uint8List getSigningBytes({
    required String authorPk,
    required String facetId,
    required Map<String, dynamic> payloadJson,
    required DateTime createdAt,
  }) {
    final signingData = {
      'author_pk': authorPk,
      'facet_id': facetId,
      'payload': _sortedJson(payloadJson),
      'created_at': createdAt.toUtc().toIso8601String(),
    };
    
    final canonicalJson = jsonEncode(_sortedJson(signingData));
    return Uint8List.fromList(utf8.encode(canonicalJson));
  }

  /// Get signing bytes for this post
  Uint8List get signingBytes => getSigningBytes(
    authorPk: authorPk,
    facetId: facetId,
    payloadJson: payloadJson,
    createdAt: createdAt,
  );

  /// Recursively sort JSON keys for canonical representation
  static dynamic _sortedJson(dynamic obj) {
    if (obj is Map) {
      final sorted = Map.fromEntries(
        obj.entries.toList()..sort((a, b) => a.key.toString().compareTo(b.key.toString()))
      );
      return sorted.map((k, v) => MapEntry(k, _sortedJson(v)));
    } else if (obj is List) {
      return obj.map(_sortedJson).toList();
    }
    return obj;
  }

  // ============================================================
  // COPY WITH
  // ============================================================

  GnsPost copyWith({
    String? id,
    String? authorPk,
    String? authorHandle,
    String? facetId,
    String? payloadType,
    Map<String, dynamic>? payloadJson,
    String? signature,
    double? trustScore,
    int? breadcrumbCount,
    BrandVerification? brandVerification,
    PostEngagement? engagement,
    PostStatus? status,
    String? replyToId,
    String? quoteOfId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return GnsPost(
      id: id ?? this.id,
      authorPk: authorPk ?? this.authorPk,
      authorHandle: authorHandle ?? this.authorHandle,
      facetId: facetId ?? this.facetId,
      payloadType: payloadType ?? this.payloadType,
      payloadJson: payloadJson ?? this.payloadJson,
      signature: signature ?? this.signature,
      trustScore: trustScore ?? this.trustScore,
      breadcrumbCount: breadcrumbCount ?? this.breadcrumbCount,
      brandVerification: brandVerification ?? this.brandVerification,
      engagement: engagement ?? this.engagement,
      status: status ?? this.status,
      replyToId: replyToId ?? this.replyToId,
      quoteOfId: quoteOfId ?? this.quoteOfId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  @override
  String toString() => 'GnsPost($id: $facetNotation - "${text.length > 50 ? text.substring(0, 50) + '...' : text}")';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GnsPost && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Builder for creating new posts
class GnsPostBuilder {
  String? _authorPk;
  String? _authorHandle;
  String? _facetId;
  String? _text;
  List<PostMediaAttachment> _media = [];
  String? _replyToId;
  String? _quoteOfId;
  String? _locationH3;
  String? _locationLabel;
  double _trustScore = 0;
  int _breadcrumbCount = 0;
  BrandVerification? _brandVerification;

  GnsPostBuilder();

  GnsPostBuilder author(String pk, {String? handle}) {
    _authorPk = pk;
    _authorHandle = handle;
    return this;
  }

  GnsPostBuilder facet(String facetId) {
    _facetId = facetId;
    return this;
  }

  GnsPostBuilder text(String text) {
    _text = text;
    return this;
  }

  GnsPostBuilder media(List<PostMediaAttachment> media) {
    _media = media;
    return this;
  }

  GnsPostBuilder addMedia(PostMediaAttachment attachment) {
    _media.add(attachment);
    return this;
  }

  GnsPostBuilder replyTo(String postId) {
    _replyToId = postId;
    return this;
  }

  GnsPostBuilder quote(String postId) {
    _quoteOfId = postId;
    return this;
  }

  GnsPostBuilder location(String h3Cell, {String? label}) {
    _locationH3 = h3Cell;
    _locationLabel = label;
    return this;
  }

  GnsPostBuilder trust(double score, int breadcrumbs) {
    _trustScore = score;
    _breadcrumbCount = breadcrumbs;
    return this;
  }

  GnsPostBuilder brand(BrandVerification verification) {
    _brandVerification = verification;
    return this;
  }

  /// Build the payload (call before signing)
  PublicPostPayload buildPayload() {
    if (_text == null || _text!.isEmpty) {
      throw StateError('Post text is required');
    }

    return PublicPostPayload.fromText(
      _text!,
      media: _media.isEmpty ? null : _media,
      replyToId: _replyToId,
      quoteOfId: _quoteOfId,
      locationH3: _locationH3,
      locationLabel: _locationLabel,
    );
  }

  /// Build the post (requires signature from external signing)
  GnsPost build({
    required String id,
    required String signature,
    required DateTime createdAt,
  }) {
    if (_authorPk == null) throw StateError('Author public key is required');
    if (_facetId == null) throw StateError('Facet ID is required');

    final payload = buildPayload();

    return GnsPost(
      id: id,
      authorPk: _authorPk!,
      authorHandle: _authorHandle,
      facetId: _facetId!,
      payloadType: payload.type,
      payloadJson: payload.toJson(),
      signature: signature,
      trustScore: _trustScore,
      breadcrumbCount: _breadcrumbCount,
      brandVerification: _brandVerification,
      replyToId: _replyToId,
      quoteOfId: _quoteOfId,
      createdAt: createdAt,
    );
  }
}
