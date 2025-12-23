/// DIX Compose Screen - Create Globe Posts
/// 
/// Full-screen composer for creating public DIX posts.
/// Includes character count, hashtag detection, location tagging.
/// 
/// Location: lib/ui/dix/dix_compose_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:convert/convert.dart';
import '../../core/gns/identity_wallet.dart';
import '../../core/theme/theme_service.dart';

class DixComposeScreen extends StatefulWidget {
  final String? replyToId;
  final String? quoteText;
  final String? quoteAuthor;
  
  const DixComposeScreen({
    super.key,
    this.replyToId,
    this.quoteText,
    this.quoteAuthor,
  });

  @override
  State<DixComposeScreen> createState() => _DixComposeScreenState();
}

class _DixComposeScreenState extends State<DixComposeScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final _wallet = IdentityWallet();
  
  bool _posting = false;
  bool _includeLocation = false;
  String? _locationLabel;
  List<String> _detectedTags = [];
  List<String> _detectedMentions = [];
  String? _handle;
  
  static const int _maxLength = 500;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
    _loadHandle();
    
    // Auto-focus
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  Future<void> _loadHandle() async {
    if (!_wallet.isInitialized) {
      await _wallet.initialize();
    }
    _handle = await _wallet.getCurrentHandle();
    if (_handle == null) {
      final info = await _wallet.getIdentityInfo();
      _handle = info.claimedHandle ?? info.reservedHandle;
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    // Detect hashtags and mentions
    final text = _controller.text;
    final tags = _parseHashtags(text);
    final mentions = _parseMentions(text);
    
    if (tags.join(',') != _detectedTags.join(',') ||
        mentions.join(',') != _detectedMentions.join(',')) {
      setState(() {
        _detectedTags = tags;
        _detectedMentions = mentions;
      });
    } else {
      setState(() {}); // Update character count
    }
  }

  List<String> _parseHashtags(String text) {
    final regex = RegExp(r'#([a-zA-Z][a-zA-Z0-9_]*)');
    return regex.allMatches(text)
        .map((m) => m.group(1)!.toLowerCase())
        .toSet()
        .toList();
  }

  List<String> _parseMentions(String text) {
    final regex = RegExp(r'@([a-zA-Z][a-zA-Z0-9_]*)');
    return regex.allMatches(text)
        .map((m) => m.group(1)!.toLowerCase())
        .toSet()
        .toList();
  }

  Future<void> _post() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _posting) return;
    
    setState(() => _posting = true);
    
    try {
      final publicKey = _wallet.publicKey;
      if (publicKey == null) {
        _showError('No identity found. Please set up your identity first.');
        return;
      }
      
      // Generate post ID
      final postId = const Uuid().v4();
      final createdAt = DateTime.now().toUtc();
      
      // Build canonical payload for signing
      final signedData = {
        'id': postId,
        'facet_id': 'dix',
        'author_public_key': publicKey,
        'content': text,
        'created_at': createdAt.toIso8601String(),
      };
      final canonicalMessage = _canonicalJson(signedData);
      
      // Sign the payload
      final signature = await _wallet.signString(canonicalMessage);
      
      debugPrint('🔏 Creating DIX post...');
      debugPrint('   ID: $postId');
      debugPrint('   Author: $publicKey');
      debugPrint('   Handle: $_handle');
      
      // Call Supabase RPC
      final response = await Supabase.instance.client.rpc('publish_dix_post', params: {
        'p_id': postId,
        'p_facet_id': 'dix',
        'p_author_public_key': publicKey,
        'p_author_handle': _handle,
        'p_content': text,
        'p_media': <dynamic>[],
        'p_location_name': _includeLocation ? _locationLabel : null,
        'p_visibility': 'public',
        'p_created_at': createdAt.toIso8601String(),
        'p_reply_to_post_id': widget.replyToId,
        'p_tags': _detectedTags,
        'p_mentions': _detectedMentions,
        'p_signature': signature,
      });

      final responseMap = response as Map<String, dynamic>;

      if (responseMap['success'] == true) {
        debugPrint('✅ Post created successfully!');
        HapticFeedback.heavyImpact();
        
        if (mounted) {
          Navigator.pop(context);
        }
      } else {
        final error = responseMap['error'] ?? 'Failed to create post';
        debugPrint('❌ Post creation failed: $error');
        _showError(error.toString());
      }
    } catch (e) {
      debugPrint('❌ Failed to create post: $e');
      _showError('Failed to post: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() => _posting = false);
      }
    }
  }

  /// Create canonical JSON with sorted keys (for signing)
  String _canonicalJson(dynamic obj) {
    if (obj == null) return 'null';
    if (obj is bool) return obj.toString();
    if (obj is num) {
      if (obj is int) return obj.toString();
      if (obj == obj.truncateToDouble()) return obj.toInt().toString();
      return obj.toString();
    }
    if (obj is String) return '"${obj.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';
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
    return obj.toString();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
    setState(() => _posting = false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ThemeService().isDark;
    final textLength = _controller.text.length;
    final isOverLimit = textLength > _maxLength;
    final canPost = textLength > 0 && !isOverLimit && !_posting;
    
    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
      appBar: AppBar(
        backgroundColor: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.close,
            color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.replyToId != null ? 'Reply' : 'New Post',
          style: TextStyle(
            color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: ElevatedButton(
              onPressed: canPost ? _post : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                disabledBackgroundColor: const Color(0xFF6366F1).withOpacity(0.4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 20),
              ),
              child: _posting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Post',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Compose area
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Author info
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: const Color(0xFF6366F1).withOpacity(0.2),
                        child: Text(
                          (_handle?.isNotEmpty == true) 
                              ? _handle![0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                            color: Color(0xFF6366F1),
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _handle != null ? 'dix@$_handle' : 'dix@you',
                            style: TextStyle(
                              color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                          Text(
                            'Public post',
                            style: TextStyle(
                              color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Quote preview (if quoting)
                  if (widget.quoteText != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark 
                            ? Colors.white.withOpacity(0.05)
                            : Colors.black.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark 
                              ? Colors.white.withOpacity(0.1)
                              : Colors.black.withOpacity(0.1),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (widget.quoteAuthor != null)
                            Text(
                              '@${widget.quoteAuthor}',
                              style: TextStyle(
                                color: const Color(0xFF6366F1),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          const SizedBox(height: 4),
                          Text(
                            widget.quoteText!,
                            style: TextStyle(
                              color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                              fontSize: 14,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  
                  // Text field
                  TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    maxLines: null,
                    minLines: 5,
                    style: TextStyle(
                      color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                      fontSize: 18,
                      height: 1.4,
                    ),
                    decoration: InputDecoration(
                      hintText: widget.replyToId != null 
                          ? 'Post your reply...'
                          : "What's happening?",
                      hintStyle: TextStyle(
                        color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                        fontSize: 18,
                      ),
                      border: InputBorder.none,
                    ),
                  ),
                  
                  // Detected tags
                  if (_detectedTags.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _detectedTags.map((tag) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6366F1).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          '#$tag',
                          style: const TextStyle(
                            color: Color(0xFF6366F1),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      )).toList(),
                    ),
                  ],
                  
                  // Detected mentions
                  if (_detectedMentions.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _detectedMentions.map((mention) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          '@$mention',
                          style: const TextStyle(
                            color: Color(0xFF10B981),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      )).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),
          
          // Bottom bar
          Container(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 12,
              bottom: MediaQuery.of(context).padding.bottom + 12,
            ),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
              border: Border(
                top: BorderSide(
                  color: isDark 
                      ? Colors.white.withOpacity(0.1)
                      : Colors.black.withOpacity(0.1),
                ),
              ),
            ),
            child: Row(
              children: [
                // Location toggle
                IconButton(
                  onPressed: () {
                    setState(() {
                      _includeLocation = !_includeLocation;
                    });
                    HapticFeedback.lightImpact();
                  },
                  icon: Icon(
                    _includeLocation ? Icons.location_on : Icons.location_off,
                    color: _includeLocation 
                        ? const Color(0xFF10B981)
                        : (isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted),
                  ),
                ),
                
                // Media button (placeholder)
                IconButton(
                  onPressed: () {
                    // TODO: Add media
                    HapticFeedback.lightImpact();
                  },
                  icon: Icon(
                    Icons.image_outlined,
                    color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                  ),
                ),
                
                const Spacer(),
                
                // Character count
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isOverLimit 
                        ? Colors.red.withOpacity(0.1)
                        : (isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05)),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    '$textLength / $_maxLength',
                    style: TextStyle(
                      color: isOverLimit 
                          ? Colors.red
                          : (isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
