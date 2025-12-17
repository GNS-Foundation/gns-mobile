/// DIX Post Card - Individual Post Display
/// 
/// Renders a single DIX post with author info, content, and engagement.
/// 
/// Location: lib/ui/dix/dix_post_card.dart

import 'package:flutter/material.dart';
import '../../core/theme/theme_service.dart';
import '../../core/dix/dix_post_service.dart';

class DixPostCard extends StatelessWidget {
  final DixPost post;
  final VoidCallback? onTap;
  final VoidCallback? onReply;
  final VoidCallback? onLike;
  final VoidCallback? onRepost;
  final VoidCallback? onShare;
  final bool showThread;
  final bool compact;

  const DixPostCard({
    super.key,
    required this.post,
    this.onTap,
    this.onReply,
    this.onLike,
    this.onRepost,
    this.onShare,
    this.showThread = true,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = ThemeService().isDark;
    
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(compact ? 12 : 16),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
          border: Border(
            bottom: BorderSide(
              color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
              width: 0.5,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Author row
            _buildAuthorRow(isDark),
            
            // Content
            Padding(
              padding: const EdgeInsets.only(left: 56, top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Text content
                  _buildTextContent(isDark),
                  
                  // Media (if any)
                  if (post.content.media.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _buildMedia(isDark),
                  ],
                  
                  // Location (if any)
                  if (post.content.locationLabel != null) ...[
                    const SizedBox(height: 8),
                    _buildLocation(isDark),
                  ],
                  
                  // Engagement bar
                  const SizedBox(height: 12),
                  _buildEngagementBar(isDark),
                  
                  // Cryptographic proof (if not compact)
                  if (!compact) ...[
                    const SizedBox(height: 8),
                    _buildProofBar(isDark),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAuthorRow(bool isDark) {
    final displayName = post.authorHandle ?? _truncateKey(post.authorPk);
    final handle = post.authorHandle != null ? '@${post.authorHandle}' : _truncateKey(post.authorPk);
    
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Avatar
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
            ),
          ),
          child: Center(
            child: Text(
              displayName[0].toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        
        // Name and info
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Display name
                  Flexible(
                    child: Text(
                      displayName,
                      style: TextStyle(
                        color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  
                  // Verified badge
                  if (post.authorHandle != null) ...[
                    const SizedBox(width: 4),
                    Icon(
                      Icons.verified,
                      size: 16,
                      color: const Color(0xFF6366F1),
                    ),
                  ],
                ],
              ),
              
              // Handle + time + trust
              Row(
                children: [
                  Text(
                    handle,
                    style: TextStyle(
                      color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    ' · ',
                    style: TextStyle(
                      color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                    ),
                  ),
                  Text(
                    _formatTimeAgo(post.createdAt),
                    style: TextStyle(
                      color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    ' · ',
                    style: TextStyle(
                      color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                    ),
                  ),
                  Text(
                    '${_getTrustEmoji(post.trustScore)} ${post.trustScore}%',
                    style: TextStyle(
                      color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTextContent(bool isDark) {
    return _RichPostText(
      text: post.content.text,
      tags: post.content.tags,
      mentions: post.content.mentions,
      isDark: isDark,
    );
  }

  Widget _buildMedia(bool isDark) {
    final media = post.content.media;
    
    if (media.length == 1) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Container(
            color: isDark ? AppTheme.darkSurfaceLight : AppTheme.lightSurfaceLight,
            child: media[0].type == 'image'
              ? Image.network(
                  media[0].url,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Center(
                    child: Icon(
                      Icons.broken_image,
                      color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                    ),
                  ),
                )
              : Center(
                  child: Icon(
                    Icons.play_circle_outline,
                    size: 48,
                    color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                  ),
                ),
          ),
        ),
      );
    }
    
    // Grid for multiple images
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
        children: media.take(4).map((m) {
          return Container(
            color: isDark ? AppTheme.darkSurfaceLight : AppTheme.lightSurfaceLight,
            child: m.type == 'image'
              ? Image.network(m.url, fit: BoxFit.cover)
              : Center(child: Icon(Icons.play_circle_outline)),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildLocation(bool isDark) {
    return Row(
      children: [
        Icon(
          Icons.location_on,
          size: 14,
          color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
        ),
        const SizedBox(width: 4),
        Text(
          post.content.locationLabel!,
          style: TextStyle(
            color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  Widget _buildEngagementBar(bool isDark) {
    return Row(
      children: [
        _buildEngagementButton(
          icon: Icons.chat_bubble_outline,
          count: post.replyCount,
          onTap: onReply,
          isDark: isDark,
        ),
        const SizedBox(width: 24),
        _buildEngagementButton(
          icon: Icons.repeat,
          count: post.repostCount,
          onTap: onRepost,
          isDark: isDark,
        ),
        const SizedBox(width: 24),
        _buildEngagementButton(
          icon: Icons.favorite_border,
          count: post.likeCount,
          onTap: onLike,
          isDark: isDark,
        ),
        const Spacer(),
        _buildEngagementButton(
          icon: Icons.share_outlined,
          onTap: onShare,
          isDark: isDark,
        ),
      ],
    );
  }

  Widget _buildEngagementButton({
    required IconData icon,
    int? count,
    VoidCallback? onTap,
    required bool isDark,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
          ),
          if (count != null && count > 0) ...[
            const SizedBox(width: 4),
            Text(
              _formatCount(count),
              style: TextStyle(
                color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                fontSize: 13,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProofBar(bool isDark) {
    return Row(
      children: [
        Icon(
          Icons.verified_user_outlined,
          size: 12,
          color: isDark ? AppTheme.darkTextMuted.withOpacity(0.5) : AppTheme.lightTextMuted.withOpacity(0.5),
        ),
        const SizedBox(width: 4),
        Text(
          'Signed · ${post.breadcrumbCount} crumbs at post',
          style: TextStyle(
            color: isDark ? AppTheme.darkTextMuted.withOpacity(0.5) : AppTheme.lightTextMuted.withOpacity(0.5),
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  // ===========================================
  // HELPERS
  // ===========================================

  String _truncateKey(String key) {
    if (key.length <= 12) return key;
    return '${key.substring(0, 6)}...${key.substring(key.length - 4)}';
  }

  String _formatTimeAgo(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    
    if (diff.inSeconds < 60) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    
    return '${date.month}/${date.day}';
  }

  String _formatCount(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return count.toString();
  }

  String _getTrustEmoji(int score) {
    if (score >= 90) return '💎';
    if (score >= 70) return '⭐';
    if (score >= 50) return '🌟';
    if (score >= 20) return '✨';
    return '🌱';
  }
}

// ===========================================
// RICH TEXT WIDGET
// ===========================================

class _RichPostText extends StatelessWidget {
  final String text;
  final List<String> tags;
  final List<String> mentions;
  final bool isDark;

  const _RichPostText({
    required this.text,
    required this.tags,
    required this.mentions,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    // Simple implementation - could be enhanced with proper parsing
    return Text.rich(
      _buildTextSpan(),
      style: TextStyle(
        color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
        fontSize: 16,
        height: 1.4,
      ),
    );
  }

  TextSpan _buildTextSpan() {
    final spans = <InlineSpan>[];
    String remaining = text;
    
    // Pattern to match hashtags and mentions
    final pattern = RegExp(r'(#[a-zA-Z][a-zA-Z0-9_]*|@[a-zA-Z][a-zA-Z0-9_]*)');
    
    while (remaining.isNotEmpty) {
      final match = pattern.firstMatch(remaining);
      
      if (match == null) {
        spans.add(TextSpan(text: remaining));
        break;
      }
      
      // Add text before match
      if (match.start > 0) {
        spans.add(TextSpan(text: remaining.substring(0, match.start)));
      }
      
      // Add highlighted match
      final matchText = match.group(0)!;
      spans.add(TextSpan(
        text: matchText,
        style: const TextStyle(
          color: Color(0xFF6366F1),
          fontWeight: FontWeight.w500,
        ),
      ));
      
      remaining = remaining.substring(match.end);
    }
    
    return TextSpan(children: spans);
  }
}
