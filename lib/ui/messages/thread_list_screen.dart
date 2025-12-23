/// Thread List Screen - Conversations List with DIX and Email Tabs
/// 
/// Displays Direct messages, Global posts (DIX), and Email in tabbed interface.
/// 
/// Location: lib/ui/messages/thread_list_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/comm/communication_service.dart';
import '../../core/comm/message_storage.dart';
import '../../core/comm/gns_envelope.dart';
import '../../core/gns/identity_wallet.dart';
import '../../core/theme/theme_service.dart';
import 'conversation_screen.dart';
import 'new_conversation_screen.dart';
import 'email_list_screen.dart';
import '../dix/dix_timeline_screen.dart';
import '../dix/dix_compose_screen.dart';

/// Email gateway public key - messages from this key are emails
const String emailGatewayPublicKey = '007dd9b2c19308dd0e2dfc044da05a522a1d1adbd6f1c84147cc4e0b7a4bd53d';

class ThreadListScreen extends StatefulWidget {
  const ThreadListScreen({super.key});

  @override
  State<ThreadListScreen> createState() => _ThreadListScreenState();
}

class _ThreadListScreenState extends State<ThreadListScreen> with SingleTickerProviderStateMixin {
  final _wallet = IdentityWallet();
  CommunicationService? _commService;
  
  // Tab controller for Direct/Global/Email
  late TabController _tabController;
  
  // Direct messages state
  List<ThreadWithPreview> _threads = [];
  bool _loadingDirect = true;
  String? _directError;
  int _totalUnread = 0;
  
  // Global posts state (DIX)
  List<dynamic> _globalPosts = [];
  bool _loadingGlobal = true;
  String? _globalError;
  
  // Email state
  int _emailUnread = 0;
  
  // User handle (loaded async)
  String? _userHandle;
  
  StreamSubscription? _messageSubscription;
  StreamSubscription? _connectionSubscription;
  CommConnectionState _connectionState = CommConnectionState.disconnected;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});  // Rebuild to update FAB icon
    });
    _initialize();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _messageSubscription?.cancel();
    _connectionSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      if (!_wallet.isInitialized) {
        await _wallet.initialize();
      }
      
      if (!mounted) return;
      
      // Load user handle
      final handle = await _wallet.getCurrentHandle();
      if (mounted) {
        setState(() => _userHandle = handle);
      }
      
      _commService = CommunicationService.instance(_wallet);
      await _commService!.initialize();
      
      if (!mounted) return;
      
      // Listen for new messages
      _messageSubscription = _commService!.incomingMessages.listen((message) {
        if (mounted) _loadThreads();
      });
      
      // Listen for connection state
      _connectionSubscription = _commService!.connectionState.listen((state) {
        if (mounted) setState(() => _connectionState = state);
      });
      
      await _loadThreads();
      await _loadGlobalPosts();
    } catch (e) {
      if (mounted) {
        setState(() {
          _directError = e.toString();
          _loadingDirect = false;
        });
      }
    }
  }

  Future<void> _loadThreads() async {
    if (!mounted) return;
    
    try {
      final threads = await _commService!.getThreads();
      final unread = await _commService!.getTotalUnreadCount();
      
      // Filter out email threads from direct messages
      final directThreads = threads.where((t) {
        final isEmailThread = t.thread.participantKeys.any((k) =>
            k.toLowerCase() == emailGatewayPublicKey.toLowerCase());
        return !isEmailThread;
      }).toList();
      
      if (mounted) {
        setState(() {
          _threads = directThreads;
          _totalUnread = unread;
          _loadingDirect = false;
          _directError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _directError = e.toString();
          _loadingDirect = false;
        });
      }
    }
  }

  Future<void> _loadGlobalPosts() async {
    if (!mounted) return;
    
    try {
      // TODO: Load DIX posts from backend
      // For now, show empty state
      if (mounted) {
        setState(() {
          _globalPosts = [];
          _loadingGlobal = false;
          _globalError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _globalError = e.toString();
          _loadingGlobal = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background(context),
      appBar: AppBar(
        backgroundColor: AppTheme.surface(context),
        title: Row(
          children: [
            const Text(
              'MESSAGES',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
                fontSize: 18,
              ),
            ),
            if (_totalUnread > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$_totalUnread',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _buildConnectionIndicator(),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.primary,
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppTheme.textMuted(context),
          tabs: [
            const Tab(
              icon: Icon(Icons.chat_bubble_outline, size: 20),
              text: 'Direct',
            ),
            const Tab(
              icon: Icon(Icons.public, size: 20),
              text: 'Global',
            ),
            Tab(
              icon: Badge(
                isLabelVisible: _emailUnread > 0,
                label: Text('$_emailUnread'),
                child: const Icon(Icons.mail_outline, size: 20),
              ),
              text: 'Email',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Direct Messages Tab
          _buildDirectTab(),
          // Global Posts Tab (DIX)
          _buildGlobalTab(),
          // Email Tab
          _commService != null
              ? EmailListScreen(
                  commService: _commService!,
                  wallet: _wallet,
                )
              : const Center(child: CircularProgressIndicator()),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _onFabPressed,
        backgroundColor: Theme.of(context).colorScheme.primary,
        child: Icon(
          _getFabIcon(),
          color: AppTheme.textPrimary(context),
        ),
      ),
    );
  }

  IconData _getFabIcon() {
    switch (_tabController.index) {
      case 0:
        return Icons.edit;
      case 1:
        return Icons.add;
      case 2:
        return Icons.mail_outline;
      default:
        return Icons.edit;
    }
  }

  void _onFabPressed() {
    switch (_tabController.index) {
      case 0:
        _startNewConversation();
        break;
      case 1:
        _createNewPost();
        break;
      case 2:
        _showEmailInfo();
        break;
    }
  }

  Widget _buildConnectionIndicator() {
    IconData icon;
    Color color;
    
    switch (_connectionState) {
      case CommConnectionState.connected:
        icon = Icons.wifi;
        color = AppTheme.secondary;
        break;
      case CommConnectionState.connecting:
      case CommConnectionState.reconnecting:
        icon = Icons.sync;
        color = Colors.orange;
        break;
      default:
        icon = Icons.wifi_off;
        color = Colors.red;
    }
    
    return Icon(icon, color: color, size: 20);
  }

  // ==================== DIRECT MESSAGES TAB ====================
  
  Widget _buildDirectTab() {
    if (_loadingDirect) {
      return Center(
        child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary),
      );
    }

    if (_directError != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(_directError!, style: TextStyle(color: AppTheme.textSecondary(context))),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _initialize,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_threads.isEmpty) {
      return _buildDirectEmptyState();
    }

    return RefreshIndicator(
      onRefresh: _loadThreads,
      color: Theme.of(context).colorScheme.primary,
      child: ListView.builder(
        itemCount: _threads.length,
        itemBuilder: (context, index) => _buildThreadTile(_threads[index]),
      ),
    );
  }

  Widget _buildDirectEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 64,
            color: AppTheme.textMuted(context).withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'No messages yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppTheme.textSecondary(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Start a conversation with someone',
            style: TextStyle(color: AppTheme.textMuted(context)),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _startNewConversation,
            icon: const Icon(Icons.add),
            label: const Text('New Message'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
            ),
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
    String displayName = thread.title ?? 'Unknown';
    if (displayName.isEmpty && thread.participantKeys.length > 1) {
      final myKey = _wallet.publicKey?.toLowerCase();
      final otherKey = thread.participantKeys.firstWhere(
        (k) => k.toLowerCase() != myKey,
        orElse: () => thread.participantKeys.first,
      );
      displayName = '${otherKey.substring(0, 8)}...';
    }
    
    // Format time
    String timeText = '';
    if (lastMessage != null) {
      final diff = DateTime.now().difference(lastMessage.timestamp);
      if (diff.inDays > 0) {
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
        color: Colors.red.withOpacity(0.2),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete, color: Colors.red),
      ),
      direction: DismissDirection.endToStart,
      confirmDismiss: (direction) => _confirmDelete(thread),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Stack(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.2),
              child: Text(
                displayName.substring(0, 1).toUpperCase(),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
            if (hasUnread)
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                displayName.startsWith('@') ? displayName : '@$displayName',
                style: TextStyle(
                  fontWeight: hasUnread ? FontWeight.bold : FontWeight.normal,
                  color: AppTheme.textPrimary(context),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              timeText,
              style: TextStyle(
                fontSize: 12,
                color: hasUnread ? Theme.of(context).colorScheme.primary : AppTheme.textMuted(context),
              ),
            ),
          ],
        ),
        subtitle: Row(
          children: [
            if (lastMessage?.isOutgoing == true)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(Icons.done_all, size: 14, color: AppTheme.textMuted(context)),
              ),
            Expanded(
              child: Text(
                lastMessage?.previewText ?? 'No messages',
                style: TextStyle(
                  color: hasUnread ? AppTheme.textSecondary(context) : AppTheme.textMuted(context),
                  fontWeight: hasUnread ? FontWeight.w500 : FontWeight.normal,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (thread.unreadCount > 1)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${thread.unreadCount}',
                  style: TextStyle(fontSize: 10, color: AppTheme.textPrimary(context)),
                ),
              ),
          ],
        ),
        onTap: () => _openConversation(thread),
        onLongPress: () => _showThreadOptions(thread),
      ),
    );
  }

  // ==================== GLOBAL POSTS TAB (DIX) ====================
  
  Widget _buildGlobalTab() {
    // Use the full DIX Timeline Screen
    return const DixTimelineScreen();
  }

  Widget _buildGlobalEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.public,
            size: 64,
            color: AppTheme.textMuted(context).withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'No posts yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppTheme.textSecondary(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Be the first to post on DIX!',
            style: TextStyle(color: AppTheme.textMuted(context)),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _createNewPost,
            icon: const Icon(Icons.edit),
            label: const Text('Create Post'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPostTile(dynamic post) {
    // TODO: Implement DIX post tile
    return const ListTile(
      title: Text('Post'),
      subtitle: Text('Coming soon...'),
    );
  }

  // ==================== ACTIONS ====================

  Future<bool> _confirmDelete(GnsThread thread) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface(context),
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
      if (mounted) _loadThreads();
    }
    
    return false;
  }

  void _showThreadOptions(GnsThread thread) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface(context),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                thread.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                color: AppTheme.textSecondary(context),
              ),
              title: Text(thread.isPinned ? 'Unpin' : 'Pin'),
              onTap: () {
                Navigator.pop(context);
                _commService?.pinThread(thread.id, pinned: !thread.isPinned);
                if (mounted) _loadThreads();
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
                if (mounted) _loadThreads();
              },
            ),
            ListTile(
              leading: Icon(Icons.archive, color: AppTheme.textSecondary(context)),
              title: const Text('Archive'),
              onTap: () {
                Navigator.pop(context);
                _commService?.archiveThread(thread.id);
                if (mounted) _loadThreads();
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
    ).then((_) {
      if (mounted) _loadThreads();
    });
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
    ).then((_) {
      if (mounted) _loadThreads();
    });
  }

  void _createNewPost() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const DixComposeScreen(),
        fullscreenDialog: true,
      ),
    ).then((result) {
      // Refresh if post was created
      if (result != null) {
        setState(() {}); // Triggers rebuild of DixTimelineScreen
      }
    });
  }

  void _showEmailInfo() {
    final handle = _userHandle ?? 'your-handle';
    final emailAddress = '$handle@gcrumbs.com';
    
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface(context),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.mail_outline, size: 48, color: Colors.blue),
              const SizedBox(height: 16),
              const Text(
                'Your GNS Email',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                emailAddress,
                style: TextStyle(
                  fontSize: 20,
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Share this address to receive emails directly in your GNS inbox!',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textMuted(context)),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: emailAddress));
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Copied $emailAddress')),
                  );
                },
                icon: const Icon(Icons.copy),
                label: const Text('Copy Email'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
