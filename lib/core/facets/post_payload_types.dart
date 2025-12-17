/// GNS Payload Types - Extended for Globe Posts
/// 
/// Adds public post payload types to the existing registry.
/// These are for PUBLIC content (signed but not encrypted).
/// 
/// Key difference from messages:
/// - Messages: Encrypted, private, between specific parties
/// - Posts: Signed, public, broadcast to all followers
///
/// Location: lib/core/comm/payload_types.dart (additions)

// Add these to the existing PayloadType abstract class:

/*
  // =======================================================
  // PUBLIC POSTS (Globe Posts)
  // =======================================================
  
  /// Public micro-post (max 280 chars)
  static const postPublic = 'gns/post.public';
  
  /// Reply to a public post
  static const postReply = 'gns/post.reply';
  
  /// Repost (share without comment)
  static const postRepost = 'gns/post.repost';
  
  /// Quote post (share with comment)
  static const postQuote = 'gns/post.quote';
  
  /// Long-form blog post
  static const blogPost = 'gns/blog.post';
  
  // =======================================================
  // POST INTERACTIONS
  // =======================================================
  
  /// Like a post
  static const postLike = 'gns/post.like';
  
  /// Unlike a post
  static const postUnlike = 'gns/post.unlike';
  
  /// Bookmark a post
  static const postBookmark = 'gns/post.bookmark';
  
  /// Report a post
  static const postReport = 'gns/post.report';
  
  // =======================================================
  // BRAND VERIFICATION
  // =======================================================
  
  /// Brand employee verification request
  static const brandVerifyRequest = 'gns/brand.verify_request';
  
  /// Brand employee verification approval
  static const brandVerifyApprove = 'gns/brand.verify_approve';
  
  /// Brand employee verification revocation
  static const brandVerifyRevoke = 'gns/brand.verify_revoke';
*/

// =======================================================
// POST PAYLOAD DATA STRUCTURES
// =======================================================

import 'dart:convert';
import 'dart:typed_data';

/// Extended payload type constants for posts
abstract class PostPayloadType {
  // Public posts
  static const postPublic = 'gns/post.public';
  static const postReply = 'gns/post.reply';
  static const postRepost = 'gns/post.repost';
  static const postQuote = 'gns/post.quote';
  static const blogPost = 'gns/blog.post';
  
  // Post interactions
  static const postLike = 'gns/post.like';
  static const postUnlike = 'gns/post.unlike';
  static const postBookmark = 'gns/post.bookmark';
  static const postReport = 'gns/post.report';
  
  // Brand verification
  static const brandVerifyRequest = 'gns/brand.verify_request';
  static const brandVerifyApprove = 'gns/brand.verify_approve';
  static const brandVerifyRevoke = 'gns/brand.verify_revoke';
}

/// Media attachment for posts
class PostMediaAttachment {
  /// Type: image, video, gif, audio
  final String type;
  
  /// URL or base64 data
  final String url;
  
  /// MIME type
  final String mimeType;
  
  /// Alt text for accessibility
  final String? altText;
  
  /// Width in pixels (for images/video)
  final int? width;
  
  /// Height in pixels (for images/video)
  final int? height;
  
  /// Duration in seconds (for video/audio)
  final int? durationSeconds;
  
  /// Thumbnail URL (for video)
  final String? thumbnailUrl;
  
  /// Blurhash for placeholder
  final String? blurhash;

  PostMediaAttachment({
    required this.type,
    required this.url,
    required this.mimeType,
    this.altText,
    this.width,
    this.height,
    this.durationSeconds,
    this.thumbnailUrl,
    this.blurhash,
  });

  Map<String, dynamic> toJson() => {
    'type': type,
    'url': url,
    'mime_type': mimeType,
    if (altText != null) 'alt_text': altText,
    if (width != null) 'width': width,
    if (height != null) 'height': height,
    if (durationSeconds != null) 'duration_seconds': durationSeconds,
    if (thumbnailUrl != null) 'thumbnail_url': thumbnailUrl,
    if (blurhash != null) 'blurhash': blurhash,
  };

  factory PostMediaAttachment.fromJson(Map<String, dynamic> json) {
    return PostMediaAttachment(
      type: json['type'] as String,
      url: json['url'] as String,
      mimeType: json['mime_type'] as String,
      altText: json['alt_text'] as String?,
      width: json['width'] as int?,
      height: json['height'] as int?,
      durationSeconds: json['duration_seconds'] as int?,
      thumbnailUrl: json['thumbnail_url'] as String?,
      blurhash: json['blurhash'] as String?,
    );
  }

  bool get isImage => type == 'image';
  bool get isVideo => type == 'video';
  bool get isGif => type == 'gif';
  bool get isAudio => type == 'audio';
}

/// Link preview for URLs in posts
class PostLinkPreview {
  final String url;
  final String? title;
  final String? description;
  final String? imageUrl;
  final String? siteName;
  final String? faviconUrl;

  PostLinkPreview({
    required this.url,
    this.title,
    this.description,
    this.imageUrl,
    this.siteName,
    this.faviconUrl,
  });

  Map<String, dynamic> toJson() => {
    'url': url,
    if (title != null) 'title': title,
    if (description != null) 'description': description,
    if (imageUrl != null) 'image_url': imageUrl,
    if (siteName != null) 'site_name': siteName,
    if (faviconUrl != null) 'favicon_url': faviconUrl,
  };

  factory PostLinkPreview.fromJson(Map<String, dynamic> json) {
    return PostLinkPreview(
      url: json['url'] as String,
      title: json['title'] as String?,
      description: json['description'] as String?,
      imageUrl: json['image_url'] as String?,
      siteName: json['site_name'] as String?,
      faviconUrl: json['favicon_url'] as String?,
    );
  }
}

/// Public post payload (for Globe Posts dix@ facet)
class PublicPostPayload {
  /// Payload type identifier
  String get type => PostPayloadType.postPublic;
  
  /// Post text content (max 280 chars for micro-posts)
  final String text;
  
  /// Optional media attachments
  final List<PostMediaAttachment> media;
  
  /// Optional link previews (auto-generated)
  final List<PostLinkPreview> links;
  
  /// Reply to post ID (if this is a reply)
  final String? replyToId;
  
  /// Quote of post ID (if this is a quote)
  final String? quoteOfId;
  
  /// Hashtags extracted from text
  final List<String> tags;
  
  /// @mentions extracted from text
  final List<String> mentions;
  
  /// Privacy-preserving location (H3 cell, resolution 4-6)
  final String? locationH3;
  
  /// Optional location label
  final String? locationLabel;

  PublicPostPayload({
    required this.text,
    this.media = const [],
    this.links = const [],
    this.replyToId,
    this.quoteOfId,
    this.tags = const [],
    this.mentions = const [],
    this.locationH3,
    this.locationLabel,
  });

  /// Create from plain text (auto-extracts tags and mentions)
  factory PublicPostPayload.fromText(
    String text, {
    List<PostMediaAttachment>? media,
    String? replyToId,
    String? quoteOfId,
    String? locationH3,
    String? locationLabel,
  }) {
    return PublicPostPayload(
      text: text,
      media: media ?? [],
      replyToId: replyToId,
      quoteOfId: quoteOfId,
      tags: _extractTags(text),
      mentions: _extractMentions(text),
      locationH3: locationH3,
      locationLabel: locationLabel,
    );
  }

  /// Extract #hashtags from text
  static List<String> _extractTags(String text) {
    final regex = RegExp(r'#(\w+)');
    return regex
        .allMatches(text)
        .map((m) => m.group(1)!.toLowerCase())
        .toSet()
        .toList();
  }

  /// Extract @mentions from text
  static List<String> _extractMentions(String text) {
    final regex = RegExp(r'@(\w+)');
    return regex
        .allMatches(text)
        .map((m) => m.group(1)!.toLowerCase())
        .toSet()
        .toList();
  }

  /// Validate post constraints
  bool get isValid {
    if (text.isEmpty && media.isEmpty) return false;
    if (text.length > 280) return false; // Micro-post limit
    return true;
  }

  /// Character count remaining
  int get charactersRemaining => 280 - text.length;

  Map<String, dynamic> toJson() => {
    'type': type,
    'text': text,
    if (media.isNotEmpty) 'media': media.map((m) => m.toJson()).toList(),
    if (links.isNotEmpty) 'links': links.map((l) => l.toJson()).toList(),
    if (replyToId != null) 'reply_to': replyToId,
    if (quoteOfId != null) 'quote_of': quoteOfId,
    if (tags.isNotEmpty) 'tags': tags,
    if (mentions.isNotEmpty) 'mentions': mentions,
    if (locationH3 != null) 'location_h3': locationH3,
    if (locationLabel != null) 'location_label': locationLabel,
  };

  factory PublicPostPayload.fromJson(Map<String, dynamic> json) {
    return PublicPostPayload(
      text: json['text'] as String,
      media: (json['media'] as List?)
          ?.map((m) => PostMediaAttachment.fromJson(m as Map<String, dynamic>))
          .toList() ?? [],
      links: (json['links'] as List?)
          ?.map((l) => PostLinkPreview.fromJson(l as Map<String, dynamic>))
          .toList() ?? [],
      replyToId: json['reply_to'] as String?,
      quoteOfId: json['quote_of'] as String?,
      tags: (json['tags'] as List?)?.map((t) => t as String).toList() ?? [],
      mentions: (json['mentions'] as List?)?.map((m) => m as String).toList() ?? [],
      locationH3: json['location_h3'] as String?,
      locationLabel: json['location_label'] as String?,
    );
  }

  Uint8List toBytes() => Uint8List.fromList(utf8.encode(jsonEncode(toJson())));

  /// Canonical JSON string for signing (sorted keys, no whitespace)
  String toCanonicalJson() {
    final sorted = _sortedJson(toJson());
    return jsonEncode(sorted);
  }

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
}

/// Blog post payload (for longer content)
class BlogPostPayload {
  String get type => PostPayloadType.blogPost;
  
  /// Post title
  final String title;
  
  /// Post content (markdown supported)
  final String content;
  
  /// Summary/excerpt
  final String? summary;
  
  /// Cover image
  final PostMediaAttachment? coverImage;
  
  /// Tags
  final List<String> tags;
  
  /// Estimated read time in minutes
  final int? readTimeMinutes;

  BlogPostPayload({
    required this.title,
    required this.content,
    this.summary,
    this.coverImage,
    this.tags = const [],
    this.readTimeMinutes,
  });

  /// Calculate estimated read time (avg 200 words/min)
  int get estimatedReadTime {
    if (readTimeMinutes != null) return readTimeMinutes!;
    final wordCount = content.split(RegExp(r'\s+')).length;
    return (wordCount / 200).ceil().clamp(1, 60);
  }

  Map<String, dynamic> toJson() => {
    'type': type,
    'title': title,
    'content': content,
    if (summary != null) 'summary': summary,
    if (coverImage != null) 'cover_image': coverImage!.toJson(),
    if (tags.isNotEmpty) 'tags': tags,
    'read_time_minutes': estimatedReadTime,
  };

  factory BlogPostPayload.fromJson(Map<String, dynamic> json) {
    return BlogPostPayload(
      title: json['title'] as String,
      content: json['content'] as String,
      summary: json['summary'] as String?,
      coverImage: json['cover_image'] != null
          ? PostMediaAttachment.fromJson(json['cover_image'] as Map<String, dynamic>)
          : null,
      tags: (json['tags'] as List?)?.map((t) => t as String).toList() ?? [],
      readTimeMinutes: json['read_time_minutes'] as int?,
    );
  }
}

/// Post interaction payload (like, bookmark, etc.)
class PostInteractionPayload {
  final String type;
  
  /// ID of the post being interacted with
  final String postId;
  
  /// Optional: emoji for reactions
  final String? emoji;

  PostInteractionPayload({
    required this.type,
    required this.postId,
    this.emoji,
  });

  factory PostInteractionPayload.like(String postId) => PostInteractionPayload(
    type: PostPayloadType.postLike,
    postId: postId,
  );

  factory PostInteractionPayload.unlike(String postId) => PostInteractionPayload(
    type: PostPayloadType.postUnlike,
    postId: postId,
  );

  factory PostInteractionPayload.bookmark(String postId) => PostInteractionPayload(
    type: PostPayloadType.postBookmark,
    postId: postId,
  );

  Map<String, dynamic> toJson() => {
    'type': type,
    'post_id': postId,
    if (emoji != null) 'emoji': emoji,
  };

  factory PostInteractionPayload.fromJson(Map<String, dynamic> json) {
    return PostInteractionPayload(
      type: json['type'] as String,
      postId: json['post_id'] as String,
      emoji: json['emoji'] as String?,
    );
  }
}

/// Brand verification payload
class BrandVerificationPayload {
  final String type;
  
  /// Brand ID (e.g., "google")
  final String brandId;
  
  /// Public key of the employee
  final String employeePk;
  
  /// Employee's @handle (if claimed)
  final String? employeeHandle;
  
  /// Role/title
  final String? role;
  
  /// Department
  final String? department;
  
  /// Verification proof (for requests)
  final String? verificationProof;
  
  /// Reason (for revocations)
  final String? reason;

  BrandVerificationPayload({
    required this.type,
    required this.brandId,
    required this.employeePk,
    this.employeeHandle,
    this.role,
    this.department,
    this.verificationProof,
    this.reason,
  });

  factory BrandVerificationPayload.request({
    required String brandId,
    required String employeePk,
    String? employeeHandle,
    String? role,
    String? department,
    String? verificationProof,
  }) => BrandVerificationPayload(
    type: PostPayloadType.brandVerifyRequest,
    brandId: brandId,
    employeePk: employeePk,
    employeeHandle: employeeHandle,
    role: role,
    department: department,
    verificationProof: verificationProof,
  );

  factory BrandVerificationPayload.approve({
    required String brandId,
    required String employeePk,
    String? employeeHandle,
    String? role,
    String? department,
  }) => BrandVerificationPayload(
    type: PostPayloadType.brandVerifyApprove,
    brandId: brandId,
    employeePk: employeePk,
    employeeHandle: employeeHandle,
    role: role,
    department: department,
  );

  factory BrandVerificationPayload.revoke({
    required String brandId,
    required String employeePk,
    String? reason,
  }) => BrandVerificationPayload(
    type: PostPayloadType.brandVerifyRevoke,
    brandId: brandId,
    employeePk: employeePk,
    reason: reason,
  );

  Map<String, dynamic> toJson() => {
    'type': type,
    'brand_id': brandId,
    'employee_pk': employeePk,
    if (employeeHandle != null) 'employee_handle': employeeHandle,
    if (role != null) 'role': role,
    if (department != null) 'department': department,
    if (verificationProof != null) 'verification_proof': verificationProof,
    if (reason != null) 'reason': reason,
  };

  factory BrandVerificationPayload.fromJson(Map<String, dynamic> json) {
    return BrandVerificationPayload(
      type: json['type'] as String,
      brandId: json['brand_id'] as String,
      employeePk: json['employee_pk'] as String,
      employeeHandle: json['employee_handle'] as String?,
      role: json['role'] as String?,
      department: json['department'] as String?,
      verificationProof: json['verification_proof'] as String?,
      reason: json['reason'] as String?,
    );
  }
}
