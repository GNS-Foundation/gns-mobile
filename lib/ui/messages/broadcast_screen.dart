/// Broadcast Screen - DIX Post Composer and Timeline (with Persistence)
/// 
/// Shows the user's broadcast posts and allows creating new ones.
/// Uses FacetPostStorage for persistence.
/// 
/// Location: lib/ui/messages/broadcast_screen.dart

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../core/gns/identity_wallet.dart';
import '../../core/profile/profile_facet.dart';
import '../../core/posts/facet_post_storage.dart';
import '../../core/theme/theme_service.dart';

class BroadcastScreen extends StatefulWidget {
  final ProfileFacet facet;
  final IdentityWallet wallet;

  const BroadcastScreen({
    super.key,
    required this.facet,
    required this.wallet,
  });

  @override
  State<BroadcastScreen> createState() => _BroadcastScreenState();
}

class _BroadcastScreenState extends State<BroadcastScreen> {
  final _composeController = TextEditingController();
  final _composeFocusNode = FocusNode();
  final _postStorage = FacetPostStorage();
  
  List<FacetPost> _posts = [];
  FacetPostStats? _stats;
  bool _loading = true;
  bool _posting = false;
  bool _showComposer = false;
  String? _handle;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  /// Get the user's handle from wallet
  String get _userHandle => _handle ?? 'you';

  @override
  void dispose() {
    _composeController.dispose();
    _composeFocusNode.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    await _postStorage.initialize();
    
    // Load handle from wallet
    _handle = await widget.wallet.getCurrentHandle();
    if (_handle == null) {
      final info = await widget.wallet.getIdentityInfo();
      _handle = info.claimedHandle ?? info.reservedHandle;
    }
    
    await _loadPosts();
  }

  Future<void> _loadPosts() async {
    setState(() => _loading = true);
    
    try {
      final posts = await _postStorage.getPostsForFacet(widget.facet.id);
      final stats = await _postStorage.getFacetStats(widget.facet.id);
      
      if (mounted) {
        setState(() {
          _posts = posts;
          _stats = stats;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading posts: $e');
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _publishPost() async {
    final content = _composeController.text.trim();
    if (content.isEmpty) return;

    setState(() => _posting = true);

    try {
      // Create post
      final post = FacetPost.create(
        facetId: widget.facet.id,
        authorPublicKey: widget.wallet.publicKey ?? '',
        authorHandle: _userHandle,
        content: content,
        visibility: PostVisibility.public,
      );

      // Save to storage
      await _postStorage.savePost(post);

      // Reload posts
      await _loadPosts();

      setState(() {
        _composeController.clear();
        _showComposer = false;
        _posting = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Text(widget.facet.emoji),
                const SizedBox(width: 8),
                const Text('Posted to your broadcast!'),
              ],
            ),
            backgroundColor: const Color(0xFF8B5CF6),
          ),
        );
      }
      
      // TODO: Trigger network sync
      // _syncPost(post);
      
    } catch (e) {
      setState(() => _posting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to post: $e')),
        );
      }
    }
  }

  Future<void> _deletePost(FacetPost post) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Post?'),
        content: const Text('This will permanently delete this post.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _postStorage.deletePost(post.id);
      await _loadPosts();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Post deleted')),
        );
      }
    }
  }

  Future<void> _toggleLike(FacetPost post) async {
    final updated = await _postStorage.toggleLike(
      post.id, 
      widget.wallet.publicKey ?? '',
    );
    
    if (updated != null) {
      setState(() {
        final index = _posts.indexWhere((p) => p.id == post.id);
        if (index != -1) {
          _posts[index] = updated;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final handle = _userHandle;
    final avatarImage = _getAvatarImage(widget.facet.avatarUrl);

    return Scaffold(
      backgroundColor: AppTheme.background(context),
      appBar: AppBar(
        backgroundColor: AppTheme.surface(context),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: const Color(0xFF8B5CF6).withValues(alpha: 0.2),
              backgroundImage: avatarImage,
              child: avatarImage == null
                  ? Text(widget.facet.emoji, style: const TextStyle(fontSize: 16))
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${widget.facet.id}@$handle',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF8B5CF6), Color(0xFFEC4899)],
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'BROADCAST',
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${_stats?.postCount ?? _posts.length} posts',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.textMuted(context),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          // Stats button
          if (_stats != null && _stats!.totalViews > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Row(
                  children: [
                    Icon(Icons.visibility, size: 14, color: AppTheme.textMuted(context)),
                    const SizedBox(width: 4),
                    Text(
                      _formatCount(_stats!.totalViews),
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textMuted(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {
              // TODO: Open facet settings
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Composer toggle bar
          if (!_showComposer)
            InkWell(
              onTap: () {
                setState(() => _showComposer = true);
                _composeFocusNode.requestFocus();
              },
              child: Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF8B5CF6).withValues(alpha: 0.1),
                      const Color(0xFFEC4899).withValues(alpha: 0.05),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFF8B5CF6).withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: const Color(0xFF8B5CF6).withValues(alpha: 0.2),
                      backgroundImage: avatarImage,
                      child: avatarImage == null
                          ? Text(widget.facet.emoji, style: const TextStyle(fontSize: 16))
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        "What's on your mind?",
                        style: TextStyle(
                          color: AppTheme.textMuted(context),
                          fontSize: 15,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF8B5CF6), Color(0xFFEC4899)],
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.edit, size: 14, color: Colors.white),
                          SizedBox(width: 4),
                          Text(
                            'Post',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Expanded composer
          if (_showComposer)
            _buildComposer(avatarImage),

          // Posts list
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _posts.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                        onRefresh: _loadPosts,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: _posts.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, index) => _buildPostCard(_posts[index]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildComposer(ImageProvider? avatarImage) {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF8B5CF6).withValues(alpha: 0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8B5CF6).withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: const Color(0xFF8B5CF6).withValues(alpha: 0.2),
                backgroundImage: avatarImage,
                child: avatarImage == null
                    ? Text(widget.facet.emoji, style: const TextStyle(fontSize: 18))
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _composeController,
                  focusNode: _composeFocusNode,
                  maxLines: 5,
                  minLines: 3,
                  decoration: InputDecoration(
                    hintText: "What's happening?",
                    hintStyle: TextStyle(color: AppTheme.textMuted(context)),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              // Media buttons
              IconButton(
                icon: Icon(Icons.image_outlined, color: AppTheme.textMuted(context)),
                onPressed: () {
                  // TODO: Add image
                },
              ),
              IconButton(
                icon: Icon(Icons.gif_box_outlined, color: AppTheme.textMuted(context)),
                onPressed: () {
                  // TODO: Add GIF
                },
              ),
              IconButton(
                icon: Icon(Icons.location_on_outlined, color: AppTheme.textMuted(context)),
                onPressed: () {
                  // TODO: Add location
                },
              ),
              
              const Spacer(),
              
              // Cancel button
              TextButton(
                onPressed: () {
                  setState(() => _showComposer = false);
                  _composeController.clear();
                },
                child: Text(
                  'Cancel',
                  style: TextStyle(color: AppTheme.textMuted(context)),
                ),
              ),
              const SizedBox(width: 8),
              
              // Publish button
              ElevatedButton(
                onPressed: _posting ? null : _publishPost,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8B5CF6),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
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
                    : const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.send, size: 16),
                          SizedBox(width: 6),
                          Text('Publish'),
                        ],
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF8B5CF6).withValues(alpha: 0.2),
                  const Color(0xFFEC4899).withValues(alpha: 0.1),
                ],
              ),
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Icon(
                Icons.campaign,
                size: 48,
                color: Color(0xFF8B5CF6),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'No broadcasts yet',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Share your first post with your audience!',
            style: TextStyle(
              color: AppTheme.textMuted(context),
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              setState(() => _showComposer = true);
              _composeFocusNode.requestFocus();
            },
            icon: const Icon(Icons.edit),
            label: const Text('Create Post'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8B5CF6),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPostCard(FacetPost post) {
    final avatarImage = _getAvatarImage(widget.facet.avatarUrl);
    final handle = _userHandle;

    return Card(
      color: AppTheme.surface(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: const Color(0xFF8B5CF6).withValues(alpha: 0.2),
                  backgroundImage: avatarImage,
                  child: avatarImage == null
                      ? Text(widget.facet.emoji, style: const TextStyle(fontSize: 18))
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            '${widget.facet.id}@$handle',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          if (post.isEdited) ...[
                            const SizedBox(width: 6),
                            Text(
                              '(edited)',
                              style: TextStyle(
                                color: AppTheme.textMuted(context),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ],
                      ),
                      Row(
                        children: [
                          Text(
                            post.timeAgo,
                            style: TextStyle(
                              color: AppTheme.textMuted(context),
                              fontSize: 12,
                            ),
                          ),
                          // Sync status indicator
                          if (post.syncStatus != PostSyncStatus.synced) ...[
                            const SizedBox(width: 8),
                            _buildSyncBadge(post.syncStatus),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_horiz, color: AppTheme.textMuted(context)),
                  onSelected: (value) {
                    switch (value) {
                      case 'edit':
                        // TODO: Edit post
                        break;
                      case 'delete':
                        _deletePost(post);
                        break;
                      case 'share':
                        // TODO: Share post
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit, size: 18),
                          SizedBox(width: 8),
                          Text('Edit'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'share',
                      child: Row(
                        children: [
                          Icon(Icons.share, size: 18),
                          SizedBox(width: 8),
                          Text('Share'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete, size: 18, color: Colors.red),
                          SizedBox(width: 8),
                          Text('Delete', style: TextStyle(color: Colors.red)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // Content
            Text(
              post.content,
              style: const TextStyle(fontSize: 16),
            ),
            
            // Media (if any)
            if (post.hasMedia) ...[
              const SizedBox(height: 12),
              _buildMediaGrid(post.media),
            ],
            
            // Location (if any)
            if (post.hasLocation) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.location_on, size: 14, color: AppTheme.textMuted(context)),
                  const SizedBox(width: 4),
                  Text(
                    post.locationName ?? 'Location',
                    style: TextStyle(
                      color: AppTheme.textMuted(context),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
            
            const SizedBox(height: 16),
            
            // Stats and actions
            Row(
              children: [
                _buildStatButton(
                  Icons.visibility_outlined, 
                  _formatCount(post.viewCount),
                  onTap: null,
                ),
                const SizedBox(width: 24),
                _buildStatButton(
                  post.isLikedByMe ? Icons.favorite : Icons.favorite_outline,
                  _formatCount(post.likeCount),
                  color: post.isLikedByMe ? Colors.red : null,
                  onTap: () => _toggleLike(post),
                ),
                const SizedBox(width: 24),
                _buildStatButton(
                  Icons.chat_bubble_outline,
                  _formatCount(post.replyCount),
                  onTap: () {
                    // TODO: Show replies
                  },
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(
                    Icons.share_outlined, 
                    color: AppTheme.textMuted(context), 
                    size: 20,
                  ),
                  onPressed: () {
                    // TODO: Share post
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSyncBadge(PostSyncStatus status) {
    Color color;
    IconData icon;
    String tooltip;
    
    switch (status) {
      case PostSyncStatus.pending:
        color = Colors.orange;
        icon = Icons.cloud_upload_outlined;
        tooltip = 'Pending sync';
        break;
      case PostSyncStatus.syncing:
        color = Colors.blue;
        icon = Icons.sync;
        tooltip = 'Syncing...';
        break;
      case PostSyncStatus.failed:
        color = Colors.red;
        icon = Icons.cloud_off;
        tooltip = 'Sync failed';
        break;
      case PostSyncStatus.localOnly:
        color = Colors.grey;
        icon = Icons.smartphone;
        tooltip = 'Local only';
        break;
      default:
        return const SizedBox.shrink();
    }
    
    return Tooltip(
      message: tooltip,
      child: Icon(icon, size: 14, color: color),
    );
  }

  Widget _buildMediaGrid(List<PostMedia> media) {
    // Simple grid for now - can be enhanced later
    if (media.isEmpty) return const SizedBox.shrink();
    
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Text(
          '${media.length} attachment(s)',
          style: TextStyle(color: AppTheme.textMuted(context)),
        ),
      ),
    );
  }

  Widget _buildStatButton(IconData icon, String count, {Color? color, VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color ?? AppTheme.textMuted(context)),
            const SizedBox(width: 4),
            Text(
              count,
              style: TextStyle(
                color: color ?? AppTheme.textMuted(context),
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K';
    }
    return count.toString();
  }

  ImageProvider? _getAvatarImage(String? avatarUrl) {
    if (avatarUrl == null || avatarUrl.isEmpty) return null;
    
    try {
      String base64Data;
      if (avatarUrl.contains(',')) {
        base64Data = avatarUrl.split(',').last;
      } else {
        base64Data = avatarUrl;
      }
      
      final bytes = base64Decode(base64Data);
      return MemoryImage(Uint8List.fromList(bytes));
    } catch (e) {
      debugPrint('Error decoding avatar: $e');
      return null;
    }
  }
}
