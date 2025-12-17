/// DIX Timeline Screen - Globe Posts Feed
/// 
/// Main feed showing public DIX posts with infinite scroll.
/// 
/// Location: lib/ui/dix/dix_timeline_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/theme_service.dart';
import '../../core/dix/dix_post_service.dart';
import 'dix_compose_screen.dart';
import 'dix_post_card.dart';

class DixTimelineScreen extends StatefulWidget {
  const DixTimelineScreen({super.key});

  @override
  State<DixTimelineScreen> createState() => _DixTimelineScreenState();
}

class _DixTimelineScreenState extends State<DixTimelineScreen> {
  final DixPostService _postService = DixPostService();
  final ScrollController _scrollController = ScrollController();
  
  List<DixPost> _posts = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _cursor;
  String? _error;
  
  // Stats
  int _totalPosts = 0;
  int _postsToday = 0;

  @override
  void initState() {
    super.initState();
    _loadPosts();
    _loadStats();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= 
        _scrollController.position.maxScrollExtent - 500) {
      _loadMore();
    }
  }

  Future<void> _loadPosts() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    
    try {
      final posts = await _postService.getTimeline(limit: 20);
      setState(() {
        _posts = posts;
        _loading = false;
        _hasMore = posts.length == 20;
        _cursor = posts.isNotEmpty ? posts.last.createdAt.toIso8601String() : null;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _cursor == null) return;
    
    setState(() => _loadingMore = true);
    
    try {
      final posts = await _postService.getTimeline(limit: 20, cursor: _cursor);
      setState(() {
        _posts.addAll(posts);
        _loadingMore = false;
        _hasMore = posts.length == 20;
        _cursor = posts.isNotEmpty ? posts.last.createdAt.toIso8601String() : null;
      });
    } catch (e) {
      setState(() => _loadingMore = false);
    }
  }

  Future<void> _refresh() async {
    HapticFeedback.mediumImpact();
    await _loadPosts();
    await _loadStats();
  }

  Future<void> _loadStats() async {
    final stats = await _postService.getStats();
    setState(() {
      _totalPosts = stats['totalPosts'] ?? 0;
      _postsToday = stats['postsToday'] ?? 0;
    });
  }

  Future<void> _openCompose() async {
    final result = await Navigator.of(context).push<DixPost>(
      MaterialPageRoute(
        builder: (_) => const DixComposeScreen(),
        fullscreenDialog: true,
      ),
    );
    
    if (result != null) {
      // Add new post to top of feed
      setState(() {
        _posts.insert(0, result);
        _totalPosts++;
        _postsToday++;
      });
      
      // Show success
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Posted! 🌍'),
            backgroundColor: const Color(0xFF6366F1),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ThemeService().isDark;
    
    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
      body: RefreshIndicator(
        onRefresh: _refresh,
        color: const Color(0xFF6366F1),
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            // App Bar
            _buildAppBar(isDark),
            
            // Stats bar
            if (_totalPosts > 0) _buildStatsBar(isDark),
            
            // Content
            if (_loading)
              _buildLoading()
            else if (_error != null)
              _buildError(isDark)
            else if (_posts.isEmpty)
              _buildEmpty(isDark)
            else
              _buildPostsList(isDark),
            
            // Loading more indicator
            if (_loadingMore)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(
                        const Color(0xFF6366F1),
                      ),
                    ),
                  ),
                ),
              ),
            
            // End of feed
            if (!_hasMore && _posts.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: [
                      const Text('🏁', style: TextStyle(fontSize: 32)),
                      const SizedBox(height: 8),
                      Text(
                        "You've reached the end!",
                        style: TextStyle(
                          color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openCompose,
        backgroundColor: const Color(0xFF6366F1),
        child: const Icon(Icons.edit, color: Colors.white),
      ),
    );
  }

  Widget _buildAppBar(bool isDark) {
    return SliverAppBar(
      floating: true,
      snap: true,
      backgroundColor: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
      elevation: 0,
      title: Row(
        children: [
          const Text('🌍', style: TextStyle(fontSize: 24)),
          const SizedBox(width: 8),
          Text(
            'Globe Posts',
            style: TextStyle(
              color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: Icon(
            Icons.refresh,
            color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
          ),
          onPressed: _refresh,
        ),
      ],
    );
  }

  Widget _buildStatsBar(bool isDark) {
    return SliverToBoxAdapter(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: isDark 
          ? AppTheme.darkSurfaceLight.withOpacity(0.5)
          : AppTheme.lightSurfaceLight.withOpacity(0.5),
        child: Row(
          children: [
            _buildStatChip('$_totalPosts posts', isDark),
            const SizedBox(width: 12),
            _buildStatChip('+$_postsToday today', isDark, isHighlight: true),
          ],
        ),
      ),
    );
  }

  Widget _buildStatChip(String text, bool isDark, {bool isHighlight = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isHighlight 
          ? const Color(0xFF22C55E).withOpacity(0.1)
          : (isDark ? AppTheme.darkSurface : AppTheme.lightSurface),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: isHighlight 
            ? const Color(0xFF22C55E)
            : (isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary),
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return SliverFillRemaining(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(const Color(0xFF6366F1)),
            ),
            const SizedBox(height: 16),
            Text(
              'Loading posts...',
              style: TextStyle(
                color: ThemeService().isDark 
                  ? AppTheme.darkTextMuted 
                  : AppTheme.lightTextMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError(bool isDark) {
    return SliverFillRemaining(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('😕', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 16),
            Text(
              'Something went wrong',
              style: TextStyle(
                color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? 'Unknown error',
              style: TextStyle(
                color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loadPosts,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
              ),
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(bool isDark) {
    return SliverFillRemaining(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🌍', style: TextStyle(fontSize: 64)),
            const SizedBox(height: 16),
            Text(
              'No posts yet',
              style: TextStyle(
                color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Be the first to post on DIX!',
              style: TextStyle(
                color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _openCompose,
              icon: const Icon(Icons.edit),
              label: const Text('Create Post'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPostsList(bool isDark) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final post = _posts[index];
          return DixPostCard(
            post: post,
            onTap: () {
              // TODO: Navigate to post detail
            },
            onReply: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DixComposeScreen(replyToId: post.id),
                  fullscreenDialog: true,
                ),
              );
            },
            onLike: () {
              // TODO: Like post
            },
            onRepost: () {
              // TODO: Repost
            },
            onShare: () {
              // TODO: Share
            },
          );
        },
        childCount: _posts.length,
      ),
    );
  }
}
