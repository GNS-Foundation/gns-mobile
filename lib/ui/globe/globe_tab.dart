/// Globe Tab - Public DIX Timeline
/// 
/// Shows public posts from ALL dix@ users.
/// Fetches from Supabase get_dix_timeline().
/// Users can like, reply, and follow others.
/// 
/// Location: lib/ui/globe/globe_tab.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/gns/identity_wallet.dart';
import '../../core/theme/theme_service.dart';
import '../dix/dix_compose_screen.dart';

class GlobeTab extends StatefulWidget {
  const GlobeTab({super.key});

  @override
  State<GlobeTab> createState() => _GlobeTabState();
}

class _GlobeTabState extends State<GlobeTab> {
  final _wallet = IdentityWallet();
  final _scrollController = ScrollController();
  
  List<DixPost> _posts = [];
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  String? _myPublicKey;
  int _offset = 0;
  bool _hasMore = true;
  
  static const int _pageSize = 20;

  @override
  void initState() {
    super.initState();
    _initialize();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    if (!_wallet.isInitialized) {
      await _wallet.initialize();
    }
    _myPublicKey = _wallet.publicKey;
    await _loadPosts();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= 
        _scrollController.position.maxScrollExtent - 200) {
      _loadMorePosts();
    }
  }

  Future<void> _loadPosts() async {
    setState(() {
      _loading = true;
      _error = null;
      _offset = 0;
    });

    try {
      final response = await Supabase.instance.client
          .rpc('get_dix_timeline', params: {
            'p_limit': _pageSize,
            'p_offset': 0,
          });

      final List<dynamic> data = response as List<dynamic>? ?? [];
      
      setState(() {
        _posts = data.map((json) => DixPost.fromJson(json)).toList();
        _loading = false;
        _hasMore = data.length >= _pageSize;
        _offset = data.length;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadMorePosts() async {
    if (_loadingMore || !_hasMore) return;

    setState(() => _loadingMore = true);

    try {
      final response = await Supabase.instance.client
          .rpc('get_dix_timeline', params: {
            'p_limit': _pageSize,
            'p_offset': _offset,
          });

      final List<dynamic> data = response as List<dynamic>? ?? [];
      
      setState(() {
        _posts.addAll(data.map((json) => DixPost.fromJson(json)));
        _loadingMore = false;
        _hasMore = data.length >= _pageSize;
        _offset += data.length;
      });
    } catch (e) {
      setState(() => _loadingMore = false);
    }
  }

  Future<void> _refresh() async {
    HapticFeedback.mediumImpact();
    await _loadPosts();
  }

  Future<void> _likePost(DixPost post) async {
    if (_myPublicKey == null) return;

    try {
      final isLiked = post.isLikedByMe;
      
      // Optimistic update
      setState(() {
        post.isLikedByMe = !isLiked;
        post.likeCount += isLiked ? -1 : 1;
      });

      // Call RPC
      await Supabase.instance.client.rpc(
        isLiked ? 'unlike_dix_post' : 'like_dix_post',
        params: {
          'p_post_id': post.id,
          'p_user_public_key': _myPublicKey,
        },
      );

      HapticFeedback.lightImpact();
    } catch (e) {
      // Revert on error
      setState(() {
        post.isLikedByMe = !post.isLikedByMe;
        post.likeCount += post.isLikedByMe ? 1 : -1;
      });
    }
  }

  void _openComposer() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const DixComposeScreen(),
      ),
    );

    if (result != null) {
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ThemeService().isDark;
    
    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
      appBar: AppBar(
        backgroundColor: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
        elevation: 0,
        title: Row(
          children: [
            const Text('🌍', style: TextStyle(fontSize: 24)),
            const SizedBox(width: 8),
            Text(
              'Globe',
              style: TextStyle(
                color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
        ],
      ),
      body: _buildBody(isDark),
      floatingActionButton: FloatingActionButton(
        onPressed: _openComposer,
        backgroundColor: const Color(0xFF6366F1),
        child: const Icon(Icons.edit, color: Colors.white),
      ),
    );
  }

  Widget _buildBody(bool isDark) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF6366F1)),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off, size: 64, color: AppTheme.textMuted(context)),
            const SizedBox(height: 16),
            Text(
              'Could not load timeline',
              style: TextStyle(
                color: AppTheme.textSecondary(context),
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(
                color: AppTheme.textMuted(context),
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadPosts,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_posts.isEmpty) {
      return _buildEmptyState(isDark);
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      color: const Color(0xFF6366F1),
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.only(bottom: 80),
        itemCount: _posts.length + (_loadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _posts.length) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          return _buildPostCard(_posts[index], isDark);
        },
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🌍', style: TextStyle(fontSize: 64)),
          const SizedBox(height: 16),
          Text(
            'The Globe is quiet',
            style: TextStyle(
              color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Be the first to broadcast!',
            style: TextStyle(
              color: AppTheme.textMuted(context),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _openComposer,
            icon: const Icon(Icons.edit),
            label: const Text('Create Post'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPostCard(DixPost post, bool isDark) {
    final isMe = post.authorPublicKey == _myPublicKey;
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
        borderRadius: BorderRadius.circular(16),
        border: isMe ? Border.all(
          color: const Color(0xFF6366F1).withValues(alpha: 0.3),
          width: 1,
        ) : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Avatar
                CircleAvatar(
                  radius: 20,
                  backgroundColor: const Color(0xFF6366F1).withValues(alpha: 0.2),
                  child: Text(
                    (post.authorHandle ?? post.authorPublicKey)[0].toUpperCase(),
                    style: const TextStyle(
                      color: Color(0xFF6366F1),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                
                // Name and handle
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            post.authorHandle != null 
                              ? 'dix@${post.authorHandle}'
                              : 'dix@${post.authorPublicKey.substring(0, 8)}',
                            style: TextStyle(
                              color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          if (isMe) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'YOU',
                                style: TextStyle(
                                  color: Color(0xFF6366F1),
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _formatTime(post.createdAt),
                        style: TextStyle(
                          color: AppTheme.textMuted(context),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Location badge
                if (post.locationName != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.location_on, size: 12, color: Color(0xFF10B981)),
                        const SizedBox(width: 4),
                        Text(
                          post.locationName!,
                          style: const TextStyle(
                            color: Color(0xFF10B981),
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          
          // Content
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              post.content,
              style: TextStyle(
                color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                fontSize: 16,
                height: 1.4,
              ),
            ),
          ),
          
          // Tags
          if (post.tags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: post.tags.map((tag) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '#$tag',
                    style: const TextStyle(
                      color: Color(0xFF6366F1),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                )).toList(),
              ),
            ),
          
          // Actions
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Like button
                _buildActionButton(
                  icon: post.isLikedByMe ? Icons.favorite : Icons.favorite_border,
                  label: post.likeCount > 0 ? '${post.likeCount}' : '',
                  color: post.isLikedByMe ? Colors.red : AppTheme.textMuted(context),
                  onTap: () => _likePost(post),
                ),
                const SizedBox(width: 16),
                
                // Reply button
                _buildActionButton(
                  icon: Icons.chat_bubble_outline,
                  label: post.replyCount > 0 ? '${post.replyCount}' : '',
                  color: AppTheme.textMuted(context),
                  onTap: () {
                    // TODO: Open reply screen
                  },
                ),
                const SizedBox(width: 16),
                
                // Views
                Row(
                  children: [
                    Icon(Icons.visibility, size: 16, color: AppTheme.textMuted(context)),
                    const SizedBox(width: 4),
                    Text(
                      '${post.viewCount}',
                      style: TextStyle(
                        color: AppTheme.textMuted(context),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                
                const Spacer(),
                
                // Share button
                IconButton(
                  icon: Icon(Icons.share_outlined, color: AppTheme.textMuted(context), size: 20),
                  onPressed: () {
                    // TODO: Share post
                  },
                  constraints: const BoxConstraints(),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          if (label.isNotEmpty) ...[
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    
    return '${time.day}/${time.month}/${time.year}';
  }
}

// ==================== DATA MODEL ====================

class DixPost {
  final String id;
  final String facetId;
  final String authorPublicKey;
  final String? authorHandle;
  final String content;
  final List<dynamic> media;
  final String? locationName;
  final DateTime createdAt;
  final List<String> tags;
  int viewCount;
  int likeCount;
  int replyCount;
  int repostCount;
  bool isLikedByMe;
  final String? replyToPostId;

  DixPost({
    required this.id,
    required this.facetId,
    required this.authorPublicKey,
    this.authorHandle,
    required this.content,
    required this.media,
    this.locationName,
    required this.createdAt,
    required this.tags,
    required this.viewCount,
    required this.likeCount,
    required this.replyCount,
    required this.repostCount,
    this.isLikedByMe = false,
    this.replyToPostId,
  });

  factory DixPost.fromJson(Map<String, dynamic> json) {
    return DixPost(
      id: json['id'] as String,
      facetId: json['facet_id'] as String? ?? 'dix',
      authorPublicKey: json['author_public_key'] as String,
      authorHandle: json['author_handle'] as String?,
      content: json['content'] as String,
      media: json['media'] as List<dynamic>? ?? [],
      locationName: json['location_name'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      tags: (json['tags'] as List<dynamic>?)?.map((t) => t as String).toList() ?? [],
      viewCount: json['view_count'] as int? ?? 0,
      likeCount: json['like_count'] as int? ?? 0,
      replyCount: json['reply_count'] as int? ?? 0,
      repostCount: json['repost_count'] as int? ?? 0,
      replyToPostId: json['reply_to_post_id'] as String?,
    );
  }
}
