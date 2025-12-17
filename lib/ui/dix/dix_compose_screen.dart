/// DIX Compose Screen - Create Globe Posts
/// 
/// Full-screen composer for creating public DIX posts.
/// Includes character count, hashtag detection, location tagging.
/// 
/// Location: lib/ui/dix/dix_compose_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/gns/identity_wallet.dart';
import '../../core/theme/theme_service.dart';
import '../../core/dix/dix_post_service.dart';

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
  final DixPostService _postService = DixPostService();
  
  bool _posting = false;
  bool _includeLocation = false;
  String? _locationLabel;
  List<String> _detectedTags = [];
  List<String> _detectedMentions = [];
  
  static const int _maxLength = 500;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
    
    // Auto-focus
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
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
      // Get identity
      final wallet = IdentityWallet();
      if (!wallet.hasIdentity) {
        _showError('No identity found');
        return;
      }
      
      // Get handle and trust info
      final info = await wallet.getIdentityInfo();
      final handle = info.claimedHandle ?? info.reservedHandle;
      final trustScore = info.trustScore;
      final breadcrumbCount = info.breadcrumbCount;
      
      // Create post
      final post = await _postService.createPost(
        keypair: wallet.keypair!,
        text: text,
        handle: handle,
        tags: _detectedTags,
        locationLabel: _includeLocation ? _locationLabel : null,
        replyToId: widget.replyToId,
        trustScore: trustScore.toInt(),
        breadcrumbCount: breadcrumbCount.toInt(),
      );
      
      // Success!
      HapticFeedback.mediumImpact();
      
      if (mounted) {
        Navigator.of(context).pop(post);
      }
    } catch (e) {
      _showError('Failed to post: $e');
    } finally {
      if (mounted) {
        setState(() => _posting = false);
      }
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ThemeService().isDark;
    final textLength = _controller.text.length;
    final canPost = textLength > 0 && textLength <= _maxLength && !_posting;
    
    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
      appBar: _buildAppBar(isDark, canPost),
      body: SafeArea(
        child: Column(
          children: [
            // Quote preview (if quoting)
            if (widget.quoteText != null) _buildQuotePreview(isDark),
            
            // Compose area
            Expanded(
              child: _buildComposeArea(isDark),
            ),
            
            // Bottom bar
            _buildBottomBar(isDark, textLength),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(bool isDark, bool canPost) {
    return AppBar(
      backgroundColor: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
      elevation: 0,
      leading: IconButton(
        icon: Icon(
          Icons.close,
          color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
        ),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: Text(
        widget.replyToId != null ? 'Reply' : 'New Post',
        style: TextStyle(
          color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: _buildPostButton(isDark, canPost),
        ),
      ],
    );
  }

  Widget _buildPostButton(bool isDark, bool canPost) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      child: ElevatedButton(
        onPressed: canPost ? _post : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: canPost 
            ? const Color(0xFF6366F1) // Indigo
            : (isDark ? AppTheme.darkSurfaceLight : AppTheme.lightSurfaceLight),
          foregroundColor: canPost 
            ? Colors.white 
            : (isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        child: _posting
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
          : const Text(
              'Post',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
      ),
    );
  }

  Widget _buildQuotePreview(bool isDark) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurfaceLight : AppTheme.lightSurfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.format_quote,
                size: 16,
                color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
              ),
              const SizedBox(width: 8),
              Text(
                'Quoting ${widget.quoteAuthor ?? 'post'}',
                style: TextStyle(
                  color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            widget.quoteText!,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComposeArea(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // User info row
          _buildUserRow(isDark),
          const SizedBox(height: 16),
          
          // Text input
          TextField(
            controller: _controller,
            focusNode: _focusNode,
            maxLines: null,
            minLines: 5,
            maxLength: _maxLength,
            maxLengthEnforcement: MaxLengthEnforcement.enforced,
            style: TextStyle(
              color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
              fontSize: 18,
              height: 1.4,
            ),
            decoration: InputDecoration(
              hintText: widget.replyToId != null 
                ? "Write your reply..."
                : "What's happening? 🌍",
              hintStyle: TextStyle(
                color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                fontSize: 18,
              ),
              border: InputBorder.none,
              counterText: '', // Hide default counter
            ),
          ),
          
          // Detected tags preview
          if (_detectedTags.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildTagsPreview(isDark),
          ],
        ],
      ),
    );
  }

  Widget _buildUserRow(bool isDark) {
    final wallet = IdentityWallet();
    
    return FutureBuilder<IdentityInfo>(
      future: wallet.getIdentityInfo(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }
        
        final info = snapshot.data!;
        final handle = info.claimedHandle ?? info.reservedHandle;
        final displayName = info.displayName;
        
        return Row(
          children: [
            // Avatar
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                ),
              ),
              child: Center(
                child: Text(
                  (displayName)[0].toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            
            // Name and handle
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: TextStyle(
                    color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                if (handle != null)
                  Text(
                    '@$handle',
                    style: const TextStyle(
                      color: Color(0xFF6366F1),
                      fontSize: 14,
                    ),
                  ),
              ],
            ),
            
            const Spacer(),
            
            // Globe icon
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('🌍', style: TextStyle(fontSize: 14)),
                  SizedBox(width: 4),
                  Text(
                    'Public',
                    style: TextStyle(
                      color: Color(0xFF6366F1),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTagsPreview(bool isDark) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _detectedTags.map((tag) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF6366F1).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '#$tag',
            style: const TextStyle(
              color: Color(0xFF6366F1),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildBottomBar(bool isDark, int textLength) {
    final remaining = _maxLength - textLength;
    final isNearLimit = remaining <= 50;
    final isOverLimit = remaining < 0;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
        border: Border(
          top: BorderSide(
            color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
          ),
        ),
      ),
      child: Row(
        children: [
          // Action buttons
          _buildActionButton(
            icon: Icons.image_outlined,
            onTap: () {
              // TODO: Image picker
              _showError('Image upload coming soon!');
            },
            isDark: isDark,
          ),
          const SizedBox(width: 8),
          _buildActionButton(
            icon: Icons.gif_box_outlined,
            onTap: () {
              // TODO: GIF picker
              _showError('GIF picker coming soon!');
            },
            isDark: isDark,
          ),
          const SizedBox(width: 8),
          _buildActionButton(
            icon: _includeLocation ? Icons.location_on : Icons.location_on_outlined,
            onTap: () {
              setState(() {
                _includeLocation = !_includeLocation;
                if (_includeLocation) {
                  _locationLabel = 'Rome, Italy'; // TODO: Get actual location
                }
              });
            },
            isDark: isDark,
            isActive: _includeLocation,
          ),
          
          const Spacer(),
          
          // Character count
          _buildCharacterCount(remaining, isNearLimit, isOverLimit, isDark),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required VoidCallback onTap,
    required bool isDark,
    bool isActive = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isActive 
            ? const Color(0xFF6366F1).withValues(alpha: 0.1)
            : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Icon(
          icon,
          color: isActive 
            ? const Color(0xFF6366F1)
            : (isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted),
          size: 22,
        ),
      ),
    );
  }

  Widget _buildCharacterCount(int remaining, bool isNearLimit, bool isOverLimit, bool isDark) {
    Color countColor;
    if (isOverLimit) {
      countColor = Colors.red;
    } else if (isNearLimit) {
      countColor = Colors.orange;
    } else {
      countColor = isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted;
    }
    
    return Row(
      children: [
        // Circular progress
        SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            value: (_controller.text.length / _maxLength).clamp(0.0, 1.0),
            strokeWidth: 2.5,
            backgroundColor: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
            valueColor: AlwaysStoppedAnimation<Color>(
              isOverLimit ? Colors.red : const Color(0xFF6366F1),
            ),
          ),
        ),
        const SizedBox(width: 8),
        
        // Count text
        Text(
          '$remaining',
          style: TextStyle(
            color: countColor,
            fontSize: 14,
            fontWeight: isNearLimit ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ],
    );
  }
}
