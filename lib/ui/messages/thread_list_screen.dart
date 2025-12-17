/// Thread List Screen - Conversations List with Globe Timeline
/// 
/// CHANGES v4 (Globe Integration):
/// - ✅ Segmented control: Direct Messages | 🌍 Globe
/// - ✅ Direct tab: Your conversations + your DIX broadcasts
/// - ✅ Globe tab: Public timeline from all dix@ users
/// - ✅ Fetches public posts from Supabase
/// 
/// Location: lib/ui/messages/thread_list_screen.dart

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/comm/communication_service.dart';
import '../../core/comm/message_storage.dart';
import '../../core/comm/gns_envelope.dart';
import '../../core/gns/identity_wallet.dart';
import '../../core/profile/profile_facet.dart';
import '../../core/profile/facet_storage.dart';
import '../../core/theme/theme_service.dart';
import 'conversation_screen.dart';
import 'new_conversation_screen.dart';
import 'broadcast_screen.dart';
import '../dix/dix_compose_screen.dart';

class ThreadListScreen extends StatefulWidget {
  const ThreadListScreen({super.key});

  @override
  State<ThreadListScreen> createState() => _ThreadListScreenState();
}

class _ThreadListScreenState extends State<ThreadListScreen> {
  final _wallet = IdentityWallet();
  final _facetStorage = FacetStorage();
  CommunicationService? _commService;
  
  // Segment control: 0 = Direct, 1 = Globe
  int _selectedSegment = 0;
  
  // Direct messages state
  List<ThreadWithPreview> _threads = [];
  List<ProfileFacet> _broadcastFacets = [];
  bool _loading = true;
  String? _error;
  int _totalUnread = 0;
  String? _handle;
  
  // Globe state
  List<GlobePost> _globePosts = [];
  bool _loadingGlobe = false;
  String? _globeError;
  int _globeOffset = 0;
  bool _hasMoreGlobe = true;
  final _globeScrollController = ScrollController();
  
  StreamSubscription? _messageSubscription;
  StreamSubscription? _connectionSubscription;
  CommConnectionState _connectionState = CommConnectionState.disconnected;

  /// Get the user's handle
  String get _userHandle => _handle ?? 'you';

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    _connectionSubscription?.cancel();
    _globeScrollController.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      if (!_wallet.isInitialized) {
        await _wallet.initialize();
      }
      
      // Load handle from wallet
      _handle = await _wallet.getCurrentHandle();
      if (_handle == null) {
        final info = await _wallet.getIdentityInfo();
        _handle = info.claimedHandle ?? info.reservedHandle;
      }
      
      _commService = CommunicationService.instance(_wallet);
      await _commService!.initialize();
      
      // Initialize facet storage
      await _facetStorage.initialize();
      
      _messageSubscription = _commService!.incomingMessages.listen((message) {
        _loadThreads();
      });
      
      _connectionSubscription = _commService!.connectionState.listen((state) {
        setState(() => _connectionState = state);
      });
      
      await _loadThreads();
      await _loadBroadcastFacets();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadThreads() async {
    try {
      final threads = await _commService!.getThreads();
      final unread = await _commService!.getTotalUnreadCount();
      
      setState(() {
        _threads = threads;
        _totalUnread = unread;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadBroadcastFacets() async {
    try {
      final facets = await _facetStorage.getBroadcastFacets();
      setState(() {
        _broadcastFacets = facets;
      });
    } catch (e) {
      debugPrint('Error loading broadcast facets: $e');
    }
  }

  Future<void> _refresh() async {
    if (_selectedSegment == 0) {
      await _loadThreads();
      await _loadBroadcastFacets();
    } else {
      await _loadGlobePosts();
    }
  }

  // ==================== GLOBE METHODS ====================

  Future<void> _loadGlobePosts() async {
    setState(() {
      _loadingGlobe = true;
      _globeError = null;
      _globeOffset = 0;
    });

    try {
      final response = await Supabase.instance.client
          .rpc('get_dix_timeline', params: {
            'p_limit': 20,
            'p_offset': 0,
          });

      final List<dynamic> data = response as List<dynamic>? ?? [];
      
      setState(() {
        _globePosts = data.map((json) => GlobePost.fromJson(json)).toList();
        _loadingGlobe = false;
        _hasMoreGlobe = data.length >= 20;
        _globeOffset = data.length;
      });
    } catch (e) {
      setState(() {
        _globeError = e.toString();
        _loadingGlobe = false;
      });
    }
  }

  Future<void> _loadMoreGlobePosts() async {
    if (_loadingGlobe || !_hasMoreGlobe) return;

    setState(() => _loadingGlobe = true);

    try {
      final response = await Supabase.instance.client
          .rpc('get_dix_timeline', params: {
            'p_limit': 20,
            'p_offset': _globeOffset,
          });

      final List<dynamic> data = response as List<dynamic>? ?? [];
      
      setState(() {
        _globePosts.addAll(data.map((json) => GlobePost.fromJson(json)));
        _loadingGlobe = false;
        _hasMoreGlobe = data.length >= 20;
        _globeOffset += data.length;
      });
    } catch (e) {
      setState(() => _loadingGlobe = false);
    }
  }

  Future<void> _likeGlobePost(GlobePost post) async {
    final myPk = _wallet.publicKey;
    if (myPk == null) return;

    try {
      final isLiked = post.isLikedByMe;
      
      // Optimistic update
      setState(() {
        post.isLikedByMe = !isLiked;
        post.likeCount += isLiked ? -1 : 1;
      });

      await Supabase.instance.client.rpc(
        isLiked ? 'unlike_dix_post' : 'like_dix_post',
        params: {
          'p_post_id': post.id,
          'p_user_public_key': myPk,
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
      _loadGlobePosts();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ThemeService().isDark;
    
    return Scaffold(
      backgroundColor: AppTheme.background(context),
      appBar: AppBar(
        backgroundColor: AppTheme.surface(context),
        elevation: 0,
        title: Row(
          children: [
            Text(
              'Messages',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 24,
                color: AppTheme.textPrimary(context),
              ),
            ),
            if (_totalUnread > 0 && _selectedSegment == 0) ...[
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  '$_totalUnread',
                  style: const TextStyle(
                    fontSize: 13, 
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (_selectedSegment == 0)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _buildConnectionIndicator(),
            ),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              // TODO: Search conversations
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Segmented Control
          _buildSegmentedControl(),
          
          // Content based on selected segment
          Expanded(
            child: _selectedSegment == 0 
              ? _buildDirectBody() 
              : _buildGlobeBody(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _selectedSegment == 0 ? _startNewConversation : _openComposer,
        backgroundColor: _selectedSegment == 0 
          ? Theme.of(context).colorScheme.primary 
          : const Color(0xFF6366F1),
        elevation: 4,
        child: const Icon(Icons.edit, color: Colors.white),
      ),
    );
  }

  Widget _buildSegmentedControl() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        border: Border(
          bottom: BorderSide(color: AppTheme.border(context)),
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.background(context),
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.all(4),
        child: Row(
          children: [
            // Direct Messages tab
            Expanded(
              child: GestureDetector(
                onTap: () {
                  if (_selectedSegment != 0) {
                    HapticFeedback.selectionClick();
                    setState(() => _selectedSegment = 0);
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: _selectedSegment == 0 
                      ? AppTheme.surface(context) 
                      : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: _selectedSegment == 0 ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ] : null,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.chat_bubble,
                        size: 18,
                        color: _selectedSegment == 0 
                          ? AppTheme.primary 
                          : AppTheme.textMuted(context),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Direct',
                        style: TextStyle(
                          color: _selectedSegment == 0 
                            ? AppTheme.textPrimary(context) 
                            : AppTheme.textMuted(context),
                          fontWeight: _selectedSegment == 0 
                            ? FontWeight.w600 
                            : FontWeight.normal,
                          fontSize: 14,
                        ),
                      ),
                      if (_totalUnread > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$_totalUnread',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            
            const SizedBox(width: 4),
            
            // Globe tab
            Expanded(
              child: GestureDetector(
                onTap: () {
                  if (_selectedSegment != 1) {
                    HapticFeedback.selectionClick();
                    setState(() => _selectedSegment = 1);
                    if (_globePosts.isEmpty && !_loadingGlobe) {
                      _loadGlobePosts();
                    }
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: _selectedSegment == 1 
                      ? AppTheme.surface(context) 
                      : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: _selectedSegment == 1 ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ] : null,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '🌍',
                        style: TextStyle(
                          fontSize: 16,
                          color: _selectedSegment == 1 
                            ? null 
                            : AppTheme.textMuted(context),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Globe',
                        style: TextStyle(
                          color: _selectedSegment == 1 
                            ? AppTheme.textPrimary(context) 
                            : AppTheme.textMuted(context),
                          fontWeight: _selectedSegment == 1 
                            ? FontWeight.w600 
                            : FontWeight.normal,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionIndicator() {
    IconData icon;
    Color color;
    String tooltip;
    
    switch (_connectionState) {
      case CommConnectionState.connected:
        icon = Icons.wifi;
        color = Colors.green;
        tooltip = 'Connected';
        break;
      case CommConnectionState.connecting:
      case CommConnectionState.reconnecting:
        icon = Icons.sync;
        color = Colors.orange;
        tooltip = 'Connecting...';
        break;
      default:
        icon = Icons.wifi_off;
        color = Colors.red;
        tooltip = 'Disconnected';
    }
    
    return Tooltip(
      message: tooltip,
      child: Icon(icon, color: color, size: 20),
    );
  }

  // ==================== GLOBE BODY ====================

  Widget _buildGlobeBody() {
    if (_loadingGlobe && _globePosts.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF6366F1)),
      );
    }

    if (_globeError != null && _globePosts.isEmpty) {
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
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadGlobePosts,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_globePosts.isEmpty) {
      return _buildGlobeEmptyState();
    }

    return RefreshIndicator(
      onRefresh: _loadGlobePosts,
      color: const Color(0xFF6366F1),
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is ScrollEndNotification &&
              _globeScrollController.position.pixels >= 
              _globeScrollController.position.maxScrollExtent - 200) {
            _loadMoreGlobePosts();
          }
          return false;
        },
        child: ListView.builder(
          controller: _globeScrollController,
          padding: const EdgeInsets.only(bottom: 80),
          itemCount: _globePosts.length + (_loadingGlobe ? 1 : 0),
          itemBuilder: (context, index) {
            if (index >= _globePosts.length) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
            }
            return _buildGlobePostCard(_globePosts[index]);
          },
        ),
      ),
    );
  }

  Widget _buildGlobeEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🌍', style: TextStyle(fontSize: 64)),
          const SizedBox(height: 16),
          Text(
            'The Globe is quiet',
            style: TextStyle(
              color: AppTheme.textPrimary(context),
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

  Widget _buildGlobePostCard(GlobePost post) {
    final isDark = ThemeService().isDark;
    final isMe = post.authorPublicKey == _wallet.publicKey;
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
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
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Avatar
                CircleAvatar(
                  radius: 18,
                  backgroundColor: const Color(0xFF6366F1).withValues(alpha: 0.2),
                  child: Text(
                    (post.authorHandle ?? post.authorPublicKey)[0].toUpperCase(),
                    style: const TextStyle(
                      color: Color(0xFF6366F1),
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                
                // Name and time
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              post.authorHandle != null 
                                ? 'dix@${post.authorHandle}'
                                : 'dix@${post.authorPublicKey.substring(0, 8)}...',
                              style: TextStyle(
                                color: AppTheme.textPrimary(context),
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isMe) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'YOU',
                                style: TextStyle(
                                  color: Color(0xFF6366F1),
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        _formatTime(post.createdAt),
                        style: TextStyle(
                          color: AppTheme.textMuted(context),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Location
                if (post.locationName != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.location_on, size: 10, color: Color(0xFF10B981)),
                        const SizedBox(width: 3),
                        Text(
                          post.locationName!,
                          style: const TextStyle(
                            color: Color(0xFF10B981),
                            fontSize: 9,
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
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              post.content,
              style: TextStyle(
                color: AppTheme.textPrimary(context),
                fontSize: 15,
                height: 1.4,
              ),
            ),
          ),
          
          // Tags
          if (post.tags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                children: post.tags.take(5).map((tag) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '#$tag',
                    style: const TextStyle(
                      color: Color(0xFF6366F1),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                )).toList(),
              ),
            ),
          
          // Actions
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                // Like
                _buildGlobeAction(
                  icon: post.isLikedByMe ? Icons.favorite : Icons.favorite_border,
                  label: post.likeCount > 0 ? '${post.likeCount}' : '',
                  color: post.isLikedByMe ? Colors.red : AppTheme.textMuted(context),
                  onTap: () => _likeGlobePost(post),
                ),
                const SizedBox(width: 16),
                
                // Reply
                _buildGlobeAction(
                  icon: Icons.chat_bubble_outline,
                  label: post.replyCount > 0 ? '${post.replyCount}' : '',
                  color: AppTheme.textMuted(context),
                  onTap: () {
                    // TODO: Open reply
                  },
                ),
                const SizedBox(width: 16),
                
                // Views
                Row(
                  children: [
                    Icon(Icons.visibility, size: 14, color: AppTheme.textMuted(context)),
                    const SizedBox(width: 4),
                    Text(
                      '${post.viewCount}',
                      style: TextStyle(
                        color: AppTheme.textMuted(context),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlobeAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          if (label.isNotEmpty) ...[
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
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
    
    return '${time.day}/${time.month}';
  }

  Widget _buildDirectBody() {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: AppTheme.textSecondary(context))),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _initialize,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final hasBroadcasts = _broadcastFacets.isNotEmpty;
    final hasThreads = _threads.isNotEmpty;

    if (!hasBroadcasts && !hasThreads) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      color: Theme.of(context).colorScheme.primary,
      child: ListView(
        children: [
          // ==================== BROADCAST SECTION ====================
          if (hasBroadcasts) ...[
            _buildSectionHeader(
              'BROADCASTS',
              Icons.campaign,
              const Color(0xFF8B5CF6),
              trailing: TextButton(
                onPressed: () {
                  // TODO: Navigate to create broadcast facet
                },
                child: const Text('+ NEW', style: TextStyle(fontSize: 12)),
              ),
            ),
            ..._broadcastFacets.map((facet) => _buildBroadcastTile(facet)),
            if (hasThreads)
              Divider(
                height: 32,
                indent: 16,
                endIndent: 16,
                color: AppTheme.border(context),
              ),
          ],

          // ==================== MESSAGES SECTION ====================
          if (hasThreads) ...[
            if (hasBroadcasts)
              _buildSectionHeader(
                'DIRECT MESSAGES',
                Icons.chat_bubble_outline,
                AppTheme.primary,
              ),
            ..._threads.asMap().entries.map((entry) {
              final index = entry.key;
              final thread = entry.value;
              return Column(
                children: [
                  _buildThreadTile(thread),
                  if (index < _threads.length - 1)
                    Divider(
                      height: 1,
                      indent: 88,
                      color: AppTheme.border(context).withValues(alpha: 0.5),
                    ),
                ],
              );
            }),
          ],
          
          const SizedBox(height: 80), // Space for FAB
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, Color color, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
              letterSpacing: 1,
            ),
          ),
          const Spacer(),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _buildBroadcastTile(ProfileFacet facet) {
    final handle = _userHandle;
    final avatarImage = _getAvatarImage(facet.avatarUrl);
    
    return InkWell(
      onTap: () => _openBroadcast(facet),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFF8B5CF6).withValues(alpha: 0.1),
              const Color(0xFFEC4899).withValues(alpha: 0.05),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFF8B5CF6).withValues(alpha: 0.2),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Avatar with broadcast indicator
              Stack(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: const Color(0xFF8B5CF6).withValues(alpha: 0.2),
                    backgroundImage: avatarImage,
                    child: avatarImage == null
                        ? Text(facet.emoji, style: const TextStyle(fontSize: 26))
                        : null,
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF8B5CF6), Color(0xFFEC4899)],
                        ),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppTheme.surface(context),
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        Icons.campaign,
                        size: 10,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              
              const SizedBox(width: 16),
              
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '${facet.id}@$handle',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF8B5CF6), Color(0xFFEC4899)],
                            ),
                            borderRadius: BorderRadius.circular(6),
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
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      facet.bio ?? 'Tap to post to your audience',
                      style: TextStyle(
                        color: AppTheme.textSecondary(context),
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    // Stats row (placeholder - connect to real data later)
                    Row(
                      children: [
                        _buildBroadcastStat(Icons.visibility, '0', 'views'),
                        const SizedBox(width: 16),
                        _buildBroadcastStat(Icons.article_outlined, '0', 'posts'),
                      ],
                    ),
                  ],
                ),
              ),
              
              // Action button
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.edit,
                  color: Color(0xFF8B5CF6),
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBroadcastStat(IconData icon, String value, String label) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppTheme.textMuted(context)),
        const SizedBox(width: 4),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12,
            color: AppTheme.textSecondary(context),
          ),
        ),
        const SizedBox(width: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: AppTheme.textMuted(context),
          ),
        ),
      ],
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
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.chat_bubble_outline,
              size: 48,
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'No messages yet',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Start a conversation or create a broadcast channel',
            style: TextStyle(
              color: AppTheme.textMuted(context),
              fontSize: 15,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: _startNewConversation,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New Message'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _createBroadcastFacet,
                icon: const Icon(Icons.campaign, size: 18),
                label: const Text('Broadcast'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF8B5CF6),
                  side: const BorderSide(color: Color(0xFF8B5CF6)),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildThreadTile(ThreadWithPreview threadPreview) {
    final thread = threadPreview.thread;
    final lastMessage = threadPreview.lastMessage;
    final hasUnread = thread.unreadCount > 0;
    
    // Get display name
    String displayName = thread.title ?? '';
    if (displayName.isEmpty && thread.participantKeys.length > 1) {
      final myKey = _wallet.publicKey?.toLowerCase();
      final otherKey = thread.participantKeys.firstWhere(
        (k) => k.toLowerCase() != myKey,
        orElse: () => thread.participantKeys.first,
      );
      displayName = '${otherKey.substring(0, 8)}...';
    }
    if (displayName.isEmpty) {
      displayName = 'Unknown';
    }
    
    // Format time
    String timeText = '';
    if (lastMessage != null) {
      final diff = DateTime.now().difference(lastMessage.timestamp);
      if (diff.inDays > 7) {
        timeText = '${lastMessage.timestamp.day}/${lastMessage.timestamp.month}';
      } else if (diff.inDays > 0) {
        timeText = '${diff.inDays}d';
      } else if (diff.inHours > 0) {
        timeText = '${diff.inHours}h';
      } else if (diff.inMinutes > 0) {
        timeText = '${diff.inMinutes}m';
      } else {
        timeText = 'now';
      }
    }

    return Dismissible(
      key: Key(thread.id),
      background: Container(
        color: Colors.red.withValues(alpha: 0.15),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: const Icon(Icons.delete, color: Colors.red, size: 28),
      ),
      direction: DismissDirection.endToStart,
      confirmDismiss: (direction) => _confirmDelete(thread),
      child: InkWell(
        onTap: () => _openConversation(thread),
        onLongPress: () => _showThreadOptions(thread),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              // Avatar with image support
              Stack(
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: const Color(0xFF64B5F6).withValues(alpha: 0.2),
                    backgroundImage: threadPreview.avatarUrl != null 
                        ? _getAvatarImage(threadPreview.avatarUrl)
                        : null,
                    child: threadPreview.avatarUrl == null
                        ? Text(
                            displayName.replaceAll('@', '').substring(0, 1).toUpperCase(),
                            style: const TextStyle(
                              color: Color(0xFF1976D2),
                              fontWeight: FontWeight.bold,
                              fontSize: 22,
                            ),
                          )
                        : null,
                  ),
                  // Online indicator
                  Positioned(
                    right: 2,
                    bottom: 2,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppTheme.surface(context),
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              
              const SizedBox(width: 16),
              
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name and time row
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            displayName.startsWith('@') ? displayName : '@$displayName',
                            style: TextStyle(
                              fontWeight: hasUnread ? FontWeight.bold : FontWeight.w600,
                              fontSize: 17,
                              color: AppTheme.textPrimary(context),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          timeText,
                          style: TextStyle(
                            fontSize: 13,
                            color: hasUnread 
                                ? Theme.of(context).colorScheme.primary 
                                : AppTheme.textMuted(context),
                            fontWeight: hasUnread ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 6),
                    
                    // Message preview row
                    Row(
                      children: [
                        // Sent/delivered indicator for outgoing
                        if (lastMessage?.isOutgoing == true) ...[
                          Icon(
                            Icons.done_all,
                            size: 16,
                            color: lastMessage?.status == MessageStatus.read
                                ? Theme.of(context).colorScheme.primary
                                : AppTheme.textMuted(context),
                          ),
                          const SizedBox(width: 4),
                        ],
                        
                        // Preview text
                        Expanded(
                          child: Text(
                            lastMessage?.previewText ?? 'No messages yet',
                            style: TextStyle(
                              color: hasUnread 
                                  ? AppTheme.textSecondary(context) 
                                  : AppTheme.textMuted(context),
                              fontWeight: hasUnread ? FontWeight.w500 : FontWeight.normal,
                              fontSize: 15,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        
                        // Unread badge
                        if (thread.unreadCount > 0) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              thread.unreadCount > 99 ? '99+' : '${thread.unreadCount}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                        
                        // Pinned indicator
                        if (thread.isPinned) ...[
                          const SizedBox(width: 8),
                          Icon(
                            Icons.push_pin,
                            size: 16,
                            color: AppTheme.textMuted(context),
                          ),
                        ],
                        
                        // Muted indicator
                        if (thread.isMuted) ...[
                          const SizedBox(width: 4),
                          Icon(
                            Icons.notifications_off,
                            size: 16,
                            color: AppTheme.textMuted(context),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
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

  Future<bool> _confirmDelete(GnsThread thread) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Conversation?'),
        content: const Text('This will delete all messages in this conversation.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    
    if (result == true) {
      await _commService?.deleteThread(thread.id);
      _loadThreads();
    }
    
    return false;
  }

  void _showThreadOptions(GnsThread thread) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(
                color: AppTheme.textMuted(context).withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            
            ListTile(
              leading: Icon(
                thread.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                color: AppTheme.textSecondary(context),
              ),
              title: Text(thread.isPinned ? 'Unpin' : 'Pin'),
              onTap: () {
                Navigator.pop(context);
                _commService?.pinThread(thread.id, pinned: !thread.isPinned);
                _loadThreads();
              },
            ),
            ListTile(
              leading: Icon(
                thread.isMuted ? Icons.notifications : Icons.notifications_off,
                color: AppTheme.textSecondary(context),
              ),
              title: Text(thread.isMuted ? 'Unmute' : 'Mute'),
              onTap: () {
                Navigator.pop(context);
                _commService?.muteThread(thread.id, muted: !thread.isMuted);
                _loadThreads();
              },
            ),
            ListTile(
              leading: Icon(Icons.archive, color: AppTheme.textSecondary(context)),
              title: const Text('Archive'),
              onTap: () {
                Navigator.pop(context);
                _commService?.archiveThread(thread.id);
                _loadThreads();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Delete', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _confirmDelete(thread);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _openConversation(GnsThread thread) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ConversationScreen(
          thread: thread,
          commService: _commService!,
        ),
      ),
    ).then((_) => _loadThreads());
  }

  void _openBroadcast(ProfileFacet facet) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => BroadcastScreen(
          facet: facet,
          wallet: _wallet,
        ),
      ),
    ).then((_) => _refresh());
  }

  void _startNewConversation() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NewConversationScreen(
          commService: _commService!,
          wallet: _wallet,
        ),
      ),
    ).then((_) => _loadThreads());
  }

  void _createBroadcastFacet() {
    // TODO: Navigate to facet creation with broadcast type preselected
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Go to Settings → Profile Facets → Add → DIX to create a broadcast channel'),
        duration: Duration(seconds: 3),
      ),
    );
  }
}

// ==================== GLOBE POST MODEL ====================

class GlobePost {
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

  GlobePost({
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

  factory GlobePost.fromJson(Map<String, dynamic> json) {
    return GlobePost(
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
