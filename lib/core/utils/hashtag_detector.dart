/// Hashtag Detector - Smart Content Routing
/// 
/// Parses text for hashtags and determines routing:
/// - No hashtag → normal message
/// - #existingfacet → post to that facet
/// - #newfacet → prompt to create facet first
/// 
/// Location: lib/core/utils/hashtag_detector.dart

import 'package:flutter/material.dart';
import '../profile/facet_storage.dart';
import '../profile/profile_facet.dart';

/// Where content should be routed based on hashtag detection
enum ContentRouting {
  /// No hashtag detected - send as normal encrypted message
  message,
  
  /// Hashtag matches existing facet - post to that facet
  facetPost,
  
  /// Hashtag doesn't match any facet - prompt to create
  createFacet,
}

/// Result of parsing text for hashtags
class HashtagParseResult {
  /// All hashtags found (lowercase, without #)
  final List<String> hashtags;
  
  /// Text with hashtags removed
  final String cleanText;
  
  /// Original text
  final String originalText;
  
  /// Determined routing for this content
  final ContentRouting routing;
  
  /// Hashtags that match existing facets
  final List<String> existingFacets;
  
  /// Hashtags that don't match any facet (need creation)
  final List<String> newFacets;
  
  /// Matched facet (if routing == facetPost)
  final ProfileFacet? targetFacet;
  
  /// Spans for rich text display with highlighted hashtags
  final List<HashtagSpan> spans;

  const HashtagParseResult({
    required this.hashtags,
    required this.cleanText,
    required this.originalText,
    required this.routing,
    this.existingFacets = const [],
    this.newFacets = const [],
    this.targetFacet,
    this.spans = const [],
  });

  /// Whether any hashtags were detected
  bool get hasHashtags => hashtags.isNotEmpty;
  
  /// Whether this will post to a facet
  bool get isFacetPost => routing == ContentRouting.facetPost;
  
  /// Whether user needs to create a facet first
  bool get needsNewFacet => routing == ContentRouting.createFacet;
  
  /// Primary hashtag (first one detected)
  String? get primaryHashtag => hashtags.isNotEmpty ? hashtags.first : null;
  
  /// Primary new facet name (for creation prompt)
  String? get primaryNewFacet => newFacets.isNotEmpty ? newFacets.first : null;

  @override
  String toString() => 'HashtagParseResult('
      'routing: $routing, '
      'hashtags: $hashtags, '
      'existing: $existingFacets, '
      'new: $newFacets)';
}

/// A span of text, either plain or a hashtag
class HashtagSpan {
  final String text;
  final bool isHashtag;
  final String? facetId; // If hashtag matches a facet
  final bool isValid;    // If hashtag matches existing facet

  const HashtagSpan({
    required this.text,
    this.isHashtag = false,
    this.facetId,
    this.isValid = false,
  });
}

/// Detects hashtags and determines content routing
class HashtagDetector {
  final FacetStorage _facetStorage;
  
  // Cache facets to avoid repeated DB queries
  List<ProfileFacet>? _cachedFacets;
  DateTime? _cacheTime;
  static const _cacheTimeout = Duration(seconds: 30);

  HashtagDetector([FacetStorage? storage]) 
      : _facetStorage = storage ?? FacetStorage();

  /// Regex for matching hashtags
  /// Matches #word where word is alphanumeric + underscore
  static final _hashtagRegex = RegExp(r'#(\w+)', caseSensitive: false);

  /// Parse text and determine routing
  Future<HashtagParseResult> parse(String text) async {
    if (text.isEmpty) {
      return HashtagParseResult(
        hashtags: [],
        cleanText: '',
        originalText: text,
        routing: ContentRouting.message,
      );
    }

    // Extract all hashtags
    final matches = _hashtagRegex.allMatches(text);
    final hashtags = matches
        .map((m) => m.group(1)!.toLowerCase())
        .toSet() // Remove duplicates
        .toList();

    // No hashtags = normal message
    if (hashtags.isEmpty) {
      return HashtagParseResult(
        hashtags: [],
        cleanText: text,
        originalText: text,
        routing: ContentRouting.message,
        spans: [HashtagSpan(text: text)],
      );
    }

    // Get all facets (with caching)
    final facets = await _getFacets();
    
    // Build lookup sets (both id and label, lowercase)
    final facetLookup = <String, ProfileFacet>{};
    for (final facet in facets) {
      facetLookup[facet.id.toLowerCase()] = facet;
      facetLookup[facet.label.toLowerCase()] = facet;
    }

    // Categorize hashtags
    final existingFacets = <String>[];
    final newFacets = <String>[];
    ProfileFacet? targetFacet;

    for (final hashtag in hashtags) {
      if (facetLookup.containsKey(hashtag)) {
        existingFacets.add(hashtag);
        targetFacet ??= facetLookup[hashtag]; // First match is target
      } else {
        newFacets.add(hashtag);
      }
    }

    // Clean text (remove hashtags)
    final cleanText = text
        .replaceAll(_hashtagRegex, '')
        .replaceAll(RegExp(r'\s+'), ' ') // Normalize whitespace
        .trim();

    // Build rich text spans
    final spans = _buildSpans(text, facetLookup);

    // Determine routing
    ContentRouting routing;
    if (newFacets.isNotEmpty) {
      // Has unknown hashtags - prompt to create
      routing = ContentRouting.createFacet;
    } else if (existingFacets.isNotEmpty) {
      // All hashtags match existing facets
      routing = ContentRouting.facetPost;
    } else {
      // No valid hashtags (shouldn't happen but fallback)
      routing = ContentRouting.message;
    }

    return HashtagParseResult(
      hashtags: hashtags,
      cleanText: cleanText,
      originalText: text,
      routing: routing,
      existingFacets: existingFacets,
      newFacets: newFacets,
      targetFacet: targetFacet,
      spans: spans,
    );
  }

  /// Quick check if text contains any hashtag
  bool hasHashtag(String text) => _hashtagRegex.hasMatch(text);

  /// Extract hashtags without full parsing (fast)
  List<String> extractHashtags(String text) {
    return _hashtagRegex
        .allMatches(text)
        .map((m) => m.group(1)!.toLowerCase())
        .toSet()
        .toList();
  }

  /// Get facet for a specific hashtag
  Future<ProfileFacet?> getFacetForHashtag(String hashtag) async {
    final lower = hashtag.toLowerCase().replaceAll('#', '');
    final facets = await _getFacets();
    
    for (final facet in facets) {
      if (facet.id.toLowerCase() == lower || 
          facet.label.toLowerCase() == lower) {
        return facet;
      }
    }
    return null;
  }

  /// Check if a hashtag matches an existing facet
  Future<bool> isValidFacetHashtag(String hashtag) async {
    return await getFacetForHashtag(hashtag) != null;
  }

  /// Get suggested facet name from hashtag (capitalized)
  String suggestFacetName(String hashtag) {
    final clean = hashtag.replaceAll('#', '').toLowerCase();
    if (clean.isEmpty) return '';
    return clean[0].toUpperCase() + clean.substring(1);
  }

  /// Clear the facet cache (call when facets change)
  void clearCache() {
    _cachedFacets = null;
    _cacheTime = null;
  }

  // ==================== PRIVATE HELPERS ====================

  /// Get facets with caching
  Future<List<ProfileFacet>> _getFacets() async {
    final now = DateTime.now();
    
    if (_cachedFacets != null && 
        _cacheTime != null &&
        now.difference(_cacheTime!) < _cacheTimeout) {
      return _cachedFacets!;
    }
    
    _cachedFacets = await _facetStorage.getAllFacets();
    _cacheTime = now;
    return _cachedFacets!;
  }

  /// Build rich text spans with hashtag highlighting
  List<HashtagSpan> _buildSpans(String text, Map<String, ProfileFacet> facetLookup) {
    final spans = <HashtagSpan>[];
    int lastEnd = 0;

    for (final match in _hashtagRegex.allMatches(text)) {
      // Add text before this hashtag
      if (match.start > lastEnd) {
        spans.add(HashtagSpan(
          text: text.substring(lastEnd, match.start),
        ));
      }

      // Add the hashtag
      final hashtag = match.group(1)!.toLowerCase();
      final facet = facetLookup[hashtag];
      spans.add(HashtagSpan(
        text: match.group(0)!, // Include the #
        isHashtag: true,
        facetId: facet?.id,
        isValid: facet != null,
      ));

      lastEnd = match.end;
    }

    // Add remaining text
    if (lastEnd < text.length) {
      spans.add(HashtagSpan(
        text: text.substring(lastEnd),
      ));
    }

    return spans;
  }
}

/// Extension for building TextSpan widgets from HashtagSpans
extension HashtagSpanWidgets on List<HashtagSpan> {
  /// Convert to Flutter TextSpan for RichText widget
  List<TextSpan> toTextSpans({
    required TextStyle baseStyle,
    required Color validHashtagColor,
    required Color invalidHashtagColor,
  }) {
    return map((span) {
      if (!span.isHashtag) {
        return TextSpan(text: span.text, style: baseStyle);
      }
      
      return TextSpan(
        text: span.text,
        style: baseStyle.copyWith(
          color: span.isValid ? validHashtagColor : invalidHashtagColor,
          fontWeight: FontWeight.w600,
        ),
      );
    }).toList();
  }
}

/// Widget for displaying text with highlighted hashtags
class HashtagText extends StatelessWidget {
  final String text;
  final List<HashtagSpan> spans;
  final TextStyle? style;
  final Color? validHashtagColor;
  final Color? invalidHashtagColor;

  const HashtagText({
    super.key,
    required this.text,
    required this.spans,
    this.style,
    this.validHashtagColor,
    this.invalidHashtagColor,
  });

  @override
  Widget build(BuildContext context) {
    final baseStyle = style ?? DefaultTextStyle.of(context).style;
    final validColor = validHashtagColor ?? Theme.of(context).colorScheme.primary;
    final invalidColor = invalidHashtagColor ?? Colors.orange;

    return RichText(
      text: TextSpan(
        children: spans.toTextSpans(
          baseStyle: baseStyle,
          validHashtagColor: validColor,
          invalidHashtagColor: invalidColor,
        ),
      ),
    );
  }
}
