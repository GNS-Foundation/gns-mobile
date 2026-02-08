/// Location: lib/ui/messages/conversation_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/comm/communication_service.dart';
import '../../core/comm/message_storage.dart';
import '../../core/comm/gns_envelope.dart'; 
import '../../core/contacts/contact_storage.dart';
import '../../core/profile/profile_facet.dart';
import '../../core/profile/facet_storage.dart';
import '../../core/theme/theme_service.dart';
import '../../core/calls/call_service.dart';  
import '../../core/calls/call_screen.dart';          
import 'compose_area.dart';  

class ConversationScreen extends StatefulWidget {
  final GnsThread thread;
  final CommunicationService commService;

  const ConversationScreen({
    super.key,
    required this.thread,
    required this.commService,
  });

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  final List<GnsMessage> _messages = [];
  final ScrollController _scrollController = ScrollController();
  
  bool _loading = true;
  String? _error;
  
  // ✅ Reply state
  GnsMessage? _replyingTo;
  
  // ✅ Starred messages (in-memory for now, could persist to DB)
  final Set<String> _starredMessageIds = {};
  
  // ✅ Reactions (messageId -> emoji)
  final Map<String, String> _messageReactions = {};
  
  // ✅ Reply texts (messageId -> original text being replied to)
  final Map<String, String> _replyTexts = {};
  
  // ✅ MULTI-SELECT MODE
  bool _selectionMode = false;
  final Set<String> _selectedMessageIds = {};
  
  // Typing indicator state
  final Map<String, bool> _typingUsers = {};
  Timer? _typingTimer;
  Timer? _autoRefreshTimer;
  
  StreamSubscription? _messageSubscription;
  StreamSubscription? _typingSubscription;
  
  String? _myPublicKey;
  String? _otherPublicKey;
  String? _otherHandle;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    _typingSubscription?.cancel();
    _typingTimer?.cancel();
    _autoRefreshTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    _myPublicKey = widget.commService.myPublicKey;
    
    _otherPublicKey = widget.thread.participantKeys.firstWhere(
      (k) => k.toLowerCase() != _myPublicKey?.toLowerCase(),
      orElse: () => widget.thread.participantKeys.first,
    );
    
    final contactStorage = ContactStorage();
    final contact = await contactStorage.getContact(_otherPublicKey!);
    _otherHandle = contact?.handle;
    
    _messageSubscription = widget.commService.incomingMessages.listen((message) {
      final matchesThread = message.threadId == widget.thread.id;
      final matchesParticipant = message.fromPublicKey.toLowerCase() == _otherPublicKey?.toLowerCase();
      
      if (matchesThread || matchesParticipant) {
        if (!_messages.any((m) => m.id == message.id)) {
          setState(() {
            _messages.add(message);
          });
          _scrollToBottom();
          _markMessagesRead([message.id]);
        }
      }
    });
    
    _typingSubscription = widget.commService.typingEvents.listen((event) {
      if (event.threadId == widget.thread.id) {
        setState(() {
          _typingUsers[event.publicKey] = event.isTyping;
        });
      }
    });
    
    await _loadMessages();
    
    final unreadMessages = _messages.where((m) => !m.isOutgoing).map((m) => m.id).toList();
    if (unreadMessages.isNotEmpty) {
      await widget.commService.markAsRead(
        threadId: widget.thread.id,
        messageIds: unreadMessages,
        toPublicKey: _otherPublicKey!,
      );
    }
    
    // ❌ DISABLED: 3-second polling causes infinite sync loop!
    // WebSocket notifications handle real-time updates.
    // _autoRefreshTimer = Timer.periodic(
    //   const Duration(seconds: 3),
    //   (_) async {
    //     if (mounted) {
    //       await widget.commService.syncMessages();
    //       await _loadMessages();
    //     }
    //   },
    // );
  }

  Future<void> _loadMessages() async {
    try {
      final messages = await widget.commService.getMessages(
        widget.thread.id,
        limit: 50,
      );
      
      setState(() {
        _messages.clear();
        _messages.addAll(messages);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _markMessagesRead(List<String> messageIds) async {
    if (_otherPublicKey == null) return;
    
    await widget.commService.markAsRead(
      threadId: widget.thread.id,
      messageIds: messageIds,
      toPublicKey: _otherPublicKey!,
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ==================== SELECTION MODE ====================

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedMessageIds.clear();
    });
  }

  void _toggleMessageSelection(String messageId) {
    setState(() {
      if (_selectedMessageIds.contains(messageId)) {
        _selectedMessageIds.remove(messageId);
        if (_selectedMessageIds.isEmpty) {
          _selectionMode = false;
        }
      } else {
        _selectedMessageIds.add(messageId);
      }
    });
  }

  void _enterSelectionMode(String messageId) {
    HapticFeedback.mediumImpact();
    setState(() {
      _selectionMode = true;
      _selectedMessageIds.add(messageId);
    });
  }

  // ==================== BUILD ====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _getChatBackground(),
      appBar: _selectionMode ? _buildSelectionAppBar() : _buildAppBar(),
      body: Column(
        children: [
          // Messages list
          Expanded(
            child: _buildMessageList(),
          ),
          
          // Typing indicator (only when not in selection mode)
          if (!_selectionMode && _typingUsers.values.any((t) => t))
            _buildTypingIndicator(),
          
          // ✅ Selection action bar OR ComposeArea (NEW!)
          if (_selectionMode)
            _buildSelectionActionBar()
          else
            ComposeArea(
              // Normal message sending
              onSendText: _sendMessageText,
              
              // ✅ NEW: Post to facet when hashtag detected
              onPostToFacet: _postToFacet,
              
              // ✅ NEW: Create facet when unknown hashtag
              onCreateFacet: _createFacet,
              
              // Typing indicator
              onTypingChanged: _onTypingChanged,
              
              // Reply support
              replyingTo: _replyingTo,
              onCancelReply: () => setState(() => _replyingTo = null),
              
              // Attachments
              onAttachmentPressed: _showAttachmentOptions,
              onCameraPressed: _showAttachmentOptions,
              onLocationPressed: _showAttachmentOptions,
              
              // Enable hashtag detection
              enableHashtagDetection: true,
            ),
        ],
      ),
    );
  }

  Color _getChatBackground() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark 
        ? const Color(0xFF0D1117)
        : const Color(0xFFF0F2F5);
  }

  // ==================== NEW: HASHTAG CALLBACKS ====================

  /// ✅ NEW: Send normal message (called by ComposeArea)
  Future<void> _sendMessageText(String text) async {
    if (text.isEmpty || _otherPublicKey == null) return;

    // Save reply info for local display
    final replyToId = _replyingTo?.id;
    final replyToText = _replyingTo?.textContent;
    
    setState(() => _replyingTo = null);

    final result = await widget.commService.sendText(
      toPublicKey: _otherPublicKey!,
      text: text,
      threadId: widget.thread.id,
      replyToId: replyToId,
    );

    if (result.success && result.message != null) {
      final msg = result.message!;
      
      // Store reply text locally for display
      if (replyToId != null && replyToText != null) {
        _replyTexts[msg.id] = replyToText;
      }
      
      setState(() {
        _messages.add(msg);
      });
      _scrollToBottom();
      
      // Sync for response
      Future.delayed(const Duration(seconds: 2), () async {
        await widget.commService.syncMessages();
        await _loadMessages();
      });
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.error ?? 'Failed to send message')),
        );
      }
    }
  }

  /// ✅ NEW: Post content to a facet (hashtag detected)
  Future<void> _postToFacet(String text, ProfileFacet facet) async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface(context),
        title: Row(
          children: [
            Text(facet.emoji, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Post to ${facet.label}?',
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.surfaceLight(context),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.border(context)),
              ),
              child: Text(
                text,
                style: TextStyle(
                  color: AppTheme.textPrimary(context),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  Icons.public,
                  size: 16,
                  color: AppTheme.textMuted(context),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'This will be visible to your ${facet.label} audience.',
                    style: TextStyle(
                      color: AppTheme.textMuted(context),
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.publish, size: 18),
            label: const Text('Post'),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;
    
    // TODO: Create and save facet post
    // final post = FacetPost(
    //   id: DateTime.now().millisecondsSinceEpoch.toString(),
    //   facetId: facet.id,
    //   content: text,
    //   createdAt: DateTime.now(),
    // );
    // await FacetPostStorage().savePost(post);
    
    // Show success
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Text(facet.emoji, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Text('Posted to ${facet.label}!'),
            ],
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.green[700],
        ),
      );
    }
    
    // TODO: Broadcast to GNS network
    // await widget.commService.broadcastFacetPost(post);
  }

  /// ✅ NEW: Create a new facet from hashtag
  Future<ProfileFacet?> _createFacet(String suggestedName) async {
    final facetStorage = FacetStorage();
    
    // Show creation dialog
    final result = await showDialog<ProfileFacet?>(
      context: context,
      builder: (context) => _CreateFacetDialog(
        suggestedName: suggestedName,
        onSave: (name, emoji) async {
          final facet = ProfileFacet(
            id: name.toLowerCase().replaceAll(' ', '_'),
            label: name,
            emoji: emoji,
            isDefault: false,
          );
          await facetStorage.saveFacet(facet);
          return facet;
        },
      ),
    );
    
    return result;
  }

  /// ✅ NEW: Typing indicator callback
  void _onTypingChanged(bool isTyping) {
    // Note: Typing indicator sending can be implemented when 
    // CommunicationService.sendTypingIndicator is available
    // For now, just update local state
    if (_otherPublicKey == null) return;
    
    // TODO: Uncomment when sendTypingIndicator is implemented
    // widget.commService.sendTypingIndicator(
    //   threadId: widget.thread.id,
    //   toPublicKey: _otherPublicKey!,
    //   isTyping: isTyping,
    // );
  }

  // ==================== SELECTION MODE APP BAR ====================

  PreferredSizeWidget _buildSelectionAppBar() {
    return AppBar(
      backgroundColor: Theme.of(context).colorScheme.primary,
      elevation: 1,
      leading: IconButton(
        icon: const Icon(Icons.close, color: Colors.white),
        onPressed: _exitSelectionMode,
      ),
      title: Text(
        '${_selectedMessageIds.length} Selected',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.select_all, color: Colors.white),
          onPressed: () {
            setState(() {
              if (_selectedMessageIds.length == _messages.length) {
                _selectedMessageIds.clear();
                _selectionMode = false;
              } else {
                _selectedMessageIds.addAll(_messages.map((m) => m.id));
              }
            });
          },
          tooltip: 'Select all',
        ),
        IconButton(
          icon: const Icon(Icons.star_border, color: Colors.white),
          onPressed: _starSelectedMessages,
          tooltip: 'Star',
        ),
      ],
    );
  }

  Widget _buildSelectionActionBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        border: Border(
          top: BorderSide(color: AppTheme.border(context).withOpacity(0.5)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildActionButton(
              icon: Icons.delete,
              label: 'Delete',
              color: Colors.red,
              onTap: _deleteSelectedMessages,
            ),
            _buildActionButton(
              icon: Icons.forward,
              label: 'Forward',
              onTap: _forwardSelectedMessages,
            ),
            _buildActionButton(
              icon: Icons.star_border,
              label: 'Star',
              onTap: _starSelectedMessages,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    Color? color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color ?? AppTheme.textSecondary(context), size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color ?? AppTheme.textSecondary(context),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _deleteSelectedMessages() {
    if (_selectedMessageIds.isEmpty) return;
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface(context),
        title: Text('Delete ${_selectedMessageIds.length} message${_selectedMessageIds.length > 1 ? 's' : ''}?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                _messages.removeWhere((m) => _selectedMessageIds.contains(m.id));
                for (final id in _selectedMessageIds) {
                  _starredMessageIds.remove(id);
                  _messageReactions.remove(id);
                  _replyTexts.remove(id);
                }
              });
              
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('${_selectedMessageIds.length} message${_selectedMessageIds.length > 1 ? 's' : ''} deleted')),
              );
              
              _exitSelectionMode();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _forwardSelectedMessages() {
    if (_selectedMessageIds.isEmpty) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Forward coming soon!')),
    );
    
    _exitSelectionMode();
  }

  void _starSelectedMessages() {
    if (_selectedMessageIds.isEmpty) return;
    
    final allStarred = _selectedMessageIds.every((id) => _starredMessageIds.contains(id));
    
    setState(() {
      if (allStarred) {
        _starredMessageIds.removeAll(_selectedMessageIds);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_selectedMessageIds.length} message${_selectedMessageIds.length > 1 ? 's' : ''} unstarred')),
        );
      } else {
        _starredMessageIds.addAll(_selectedMessageIds);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_selectedMessageIds.length} message${_selectedMessageIds.length > 1 ? 's' : ''} starred ⭐')),
        );
      }
    });
    
    _exitSelectionMode();
  }

  // ==================== NORMAL APP BAR ====================

  AppBar _buildAppBar() {
    String title = widget.thread.title ?? '';
    
    if (title.isEmpty || title == 'Chat') {
      if (_otherHandle != null) {
        title = '@$_otherHandle';
      } else if (_otherPublicKey != null) {
        title = '${_otherPublicKey!.substring(0, 12)}...';
      } else {
        title = 'Unknown';
      }
    }
    
    if (!title.startsWith('@') && !title.contains('...') && !title.contains(' ')) {
      title = '@$title';
    }
    
    return AppBar(
      backgroundColor: AppTheme.surface(context),
      elevation: 1,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => Navigator.pop(context),
      ),
      title: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: const Color(0xFF64B5F6).withOpacity(0.3),
            child: Text(
              title.replaceAll('@', '').substring(0, 1).toUpperCase(),
              style: const TextStyle(
                color: Color(0xFF1976D2),
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (_typingUsers.values.any((typing) => typing))
                  Text(
                    'typing...',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.primary,
                      fontStyle: FontStyle.italic,
                    ),
                  )
                else
                  Text(
                    'Tap for info',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textMuted(context),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        // 📞 Voice call
        IconButton(
          icon: const Icon(Icons.call, size: 22),
          tooltip: 'Voice call',
          onPressed: () => _startCall('voice'),
        ),
        // 📹 Video call
        IconButton(
          icon: const Icon(Icons.videocam, size: 22),
          tooltip: 'Video call',
          onPressed: () => _startCall('video'),
        ),
        IconButton(
          icon: const Icon(Icons.star_outline),
          onPressed: _showStarredMessages,
        ),
        IconButton(
          icon: const Icon(Icons.more_vert),
          onPressed: _showOptions,
        ),
      ],
    );
  }

  // ==================== MESSAGE LIST ====================

  Widget _buildMessageList() {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(
          color: Theme.of(context).colorScheme.primary,
        ),
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
              onPressed: _loadMessages,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_messages.isEmpty) {
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
              style: TextStyle(color: AppTheme.textMuted(context)),
            ),
            const SizedBox(height: 8),
            Text(
              'Say hello! 👋',
              style: TextStyle(color: AppTheme.textMuted(context)),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        final isMe = message.isOutgoing;
        
        bool showDateHeader = false;
        if (index == 0) {
          showDateHeader = true;
        } else {
          final prevMessage = _messages[index - 1];
          final prevDate = DateTime(
            prevMessage.timestamp.year,
            prevMessage.timestamp.month,
            prevMessage.timestamp.day,
          );
          final currDate = DateTime(
            message.timestamp.year,
            message.timestamp.month,
            message.timestamp.day,
          );
          showDateHeader = prevDate != currDate;
        }
        
        return Column(
          children: [
            if (showDateHeader) _buildDateHeader(message.timestamp),
            _buildMessageBubble(message, isMe),
          ],
        );
      },
    );
  }

  Widget _buildDateHeader(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(date.year, date.month, date.day);
    
    String text;
    if (messageDate == today) {
      text = 'Today';
    } else if (messageDate == today.subtract(const Duration(days: 1))) {
      text = 'Yesterday';
    } else {
      text = '${date.day}/${date.month}/${date.year}';
    }
    
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.surface(context).withOpacity(0.8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: AppTheme.textMuted(context),
        ),
      ),
    );
  }

  Widget _buildMessageBubble(GnsMessage message, bool isMe) {
    final isStarred = _starredMessageIds.contains(message.id);
    final reaction = _messageReactions[message.id];
    final isSelected = _selectedMessageIds.contains(message.id);
    final replyToText = _replyTexts[message.id];
    
    return GestureDetector(
      onTap: _selectionMode 
          ? () => _toggleMessageSelection(message.id)
          : null,
      onLongPress: _selectionMode
          ? null
          : () => _showMessageActions(message),
      child: Container(
        color: isSelected 
            ? Theme.of(context).colorScheme.primary.withOpacity(0.15)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            if (_selectionMode) ...[
              Container(
                width: 48,
                alignment: Alignment.center,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected 
                        ? Theme.of(context).colorScheme.primary
                        : Colors.transparent,
                    border: Border.all(
                      color: isSelected 
                          ? Theme.of(context).colorScheme.primary
                          : AppTheme.textMuted(context),
                      width: 2,
                    ),
                  ),
                  child: isSelected
                      ? const Icon(Icons.check, color: Colors.white, size: 16)
                      : null,
                ),
              ),
            ],
            
            Expanded(
              child: Align(
                alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: EdgeInsets.only(
                    top: 4,
                    bottom: reaction != null ? 16 : 4,
                    left: isMe ? 64 : 0,
                    right: isMe ? 0 : 64,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (!isMe) ...[
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: const Color(0xFF64B5F6).withOpacity(0.3),
                          child: Text(
                            (_otherHandle ?? '?')[0].toUpperCase(),
                            style: const TextStyle(
                              color: Color(0xFF1976D2),
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      
                      Flexible(
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: isMe 
                                    ? Theme.of(context).colorScheme.primary
                                    : _getReceivedBubbleColor(),
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(18),
                                  topRight: const Radius.circular(18),
                                  bottomLeft: Radius.circular(isMe ? 18 : 4),
                                  bottomRight: Radius.circular(isMe ? 4 : 18),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.05),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (replyToText != null) ...[
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      margin: const EdgeInsets.only(bottom: 6),
                                      decoration: BoxDecoration(
                                        color: isMe 
                                            ? Colors.white.withOpacity(0.2)
                                            : AppTheme.border(context).withOpacity(0.3),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border(
                                          left: BorderSide(
                                            color: isMe ? Colors.white70 : Theme.of(context).colorScheme.primary,
                                            width: 3,
                                          ),
                                        ),
                                      ),
                                      child: Text(
                                        replyToText,
                                        style: TextStyle(
                                          color: isMe 
                                              ? Colors.white.withOpacity(0.8)
                                              : AppTheme.textSecondary(context),
                                          fontSize: 13,
                                          fontStyle: FontStyle.italic,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                  
                                  Text(
                                    message.textContent ?? '',
                                    style: TextStyle(
                                      color: isMe ? Colors.white : _getReceivedTextColor(),
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (isStarred) ...[
                                        Icon(
                                          Icons.star,
                                          size: 12,
                                          color: isMe 
                                              ? Colors.yellow[300]
                                              : Colors.yellow[700],
                                        ),
                                        const SizedBox(width: 4),
                                      ],
                                      Text(
                                        _formatTime(message.timestamp),
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isMe 
                                              ? Colors.white.withOpacity(0.7)
                                              : AppTheme.textMuted(context),
                                        ),
                                      ),
                                      if (isMe) ...[
                                        const SizedBox(width: 4),
                                        Icon(
                                          message.status == MessageStatus.read 
                                              ? Icons.done_all 
                                              : Icons.done,
                                          size: 14,
                                          color: message.status == MessageStatus.read
                                              ? Colors.lightBlueAccent
                                              : Colors.white.withOpacity(0.7),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            
                            if (reaction != null)
                              Positioned(
                                bottom: -12,
                                right: isMe ? 8 : null,
                                left: isMe ? null : 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppTheme.surface(context),
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.1),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Text(
                                    reaction,
                                    style: const TextStyle(fontSize: 16),
                                  ),
                                ),
                              ),
                          ],
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

  Color _getReceivedBubbleColor() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark 
        ? const Color(0xFF1E2A3A)
        : Colors.white;
  }

  Color _getReceivedTextColor() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? Colors.white : Colors.black87;
  }

  String _formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  Widget _buildTypingIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: const Color(0xFF64B5F6).withOpacity(0.3),
            child: Text(
              (_otherHandle ?? '?')[0].toUpperCase(),
              style: const TextStyle(
                color: Color(0xFF1976D2),
                fontWeight: FontWeight.bold,
                fontSize: 10,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _getReceivedBubbleColor(),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildTypingDot(0),
                const SizedBox(width: 4),
                _buildTypingDot(1),
                const SizedBox(width: 4),
                _buildTypingDot(2),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypingDot(int index) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 600 + (index * 200)),
      builder: (context, value, child) {
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: AppTheme.textMuted(context).withOpacity(0.5 + (0.5 * value)),
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }

  // ==================== MESSAGE ACTIONS ====================

  void _quickReact(GnsMessage message, String emoji) {
    HapticFeedback.lightImpact();
    setState(() {
      if (_messageReactions[message.id] == emoji) {
        _messageReactions.remove(message.id);
      } else {
        _messageReactions[message.id] = emoji;
      }
    });
    
    if (_otherPublicKey != null) {
      widget.commService.sendReaction(
        messageId: message.id,
        threadId: widget.thread.id,
        toPublicKey: _otherPublicKey!,
        emoji: emoji,
      );
    }
  }

  void _showMessageActions(GnsMessage message) {
    HapticFeedback.mediumImpact();
    
    final isStarred = _starredMessageIds.contains(message.id);
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: AppTheme.surface(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 16),
                decoration: BoxDecoration(
                  color: AppTheme.textMuted(context).withOpacity(0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              
              // Emoji reaction bar
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceLight(context),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildReactionButton('👍', message),
                    _buildReactionButton('❤️', message),
                    _buildReactionButton('😂', message),
                    _buildReactionButton('😮', message),
                    _buildReactionButton('😢', message),
                    _buildReactionButton('🙏', message),
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppTheme.border(context),
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.add, size: 20),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _showFullEmojiPicker(message);
                        },
                        padding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 8),
              
              ListTile(
                leading: const Icon(Icons.reply),
                title: const Text('Reply'),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: () {
                  Navigator.pop(ctx);
                  _startReply(message);
                },
              ),
              
              ListTile(
                leading: const Icon(Icons.forward),
                title: const Text('Forward'),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: () {
                  Navigator.pop(ctx);
                  _enterSelectionMode(message.id);
                },
              ),
              
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('Copy'),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: () {
                  Navigator.pop(ctx);
                  Clipboard.setData(ClipboardData(text: message.textContent ?? ''));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copied to clipboard')),
                  );
                },
              ),
              
              if (message.isOutgoing)
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('Info'),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showMessageInfo(message);
                  },
                ),
              
              ListTile(
                leading: Icon(
                  isStarred ? Icons.star : Icons.star_border,
                  color: isStarred ? Colors.yellow[700] : null,
                ),
                title: Text(isStarred ? 'Unstar' : 'Star'),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: () {
                  Navigator.pop(ctx);
                  _toggleStar(message);
                },
              ),
              
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Delete', style: TextStyle(color: Colors.red)),
                trailing: const Icon(Icons.chevron_right, size: 20, color: Colors.red),
                onTap: () {
                  Navigator.pop(ctx);
                  _enterSelectionMode(message.id);
                },
              ),
              
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReactionButton(String emoji, GnsMessage message) {
    final currentReaction = _messageReactions[message.id];
    final isSelected = currentReaction == emoji;
    
    return GestureDetector(
      onTap: () {
        Navigator.pop(context);
        _quickReact(message, emoji);
      },
      child: Container(
        width: 40,
        height: 40,
        decoration: isSelected ? BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
          shape: BoxShape.circle,
        ) : null,
        alignment: Alignment.center,
        child: Text(
          emoji,
          style: const TextStyle(fontSize: 24),
        ),
      ),
    );
  }

  void _startReply(GnsMessage message) {
    setState(() {
      _replyingTo = message;
    });
  }

  void _toggleStar(GnsMessage message) {
    setState(() {
      if (_starredMessageIds.contains(message.id)) {
        _starredMessageIds.remove(message.id);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Message unstarred')),
        );
      } else {
        _starredMessageIds.add(message.id);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Message starred ⭐')),
        );
      }
    });
  }

  void _showStarredMessages() {
    final starredMessages = _messages.where((m) => _starredMessageIds.contains(m.id)).toList();
    
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface(context),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(
                color: AppTheme.textMuted(context).withOpacity(0.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.star, color: Colors.yellow[700]),
                  const SizedBox(width: 8),
                  Text(
                    'Starred Messages (${starredMessages.length})',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            
            const Divider(height: 1),
            
            Expanded(
              child: starredMessages.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.star_border,
                            size: 48,
                            color: AppTheme.textMuted(context),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No starred messages',
                            style: TextStyle(color: AppTheme.textMuted(context)),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: starredMessages.length,
                      itemBuilder: (context, index) {
                        final msg = starredMessages[index];
                        return ListTile(
                          leading: Icon(
                            msg.isOutgoing ? Icons.call_made : Icons.call_received,
                            color: msg.isOutgoing ? Colors.blue : Colors.green,
                          ),
                          title: Text(
                            msg.textContent ?? '',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            _formatTime(msg.timestamp),
                            style: TextStyle(color: AppTheme.textMuted(context)),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.star, color: Colors.yellow),
                            onPressed: () {
                              _toggleStar(msg);
                              Navigator.pop(ctx);
                              _showStarredMessages();
                            },
                          ),
                          onTap: () {
                            Navigator.pop(ctx);
                            final msgIndex = _messages.indexOf(msg);
                            if (msgIndex >= 0) {
                              _scrollController.animateTo(
                                msgIndex * 80.0,
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeOut,
                              );
                            }
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _showFullEmojiPicker(GnsMessage message) {
    final emojis = [
      '👍', '👎', '❤️', '🧡', '💛', '💚', '💙', '💜',
      '😀', '😃', '😄', '😁', '😆', '😅', '🤣', '😂',
      '🙂', '😊', '😇', '🥰', '😍', '🤩', '😘', '😗',
      '😚', '😙', '🥲', '😋', '😛', '😜', '🤪', '😝',
      '🤗', '🤭', '🤫', '🤔', '🤐', '🤨', '😐', '😑',
      '😶', '😏', '😒', '🙄', '😬', '🤥', '😌', '😔',
      '🙏', '👏', '🎉', '🔥', '✨', '💯', '✅', '❌',
    ];
    
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Container(
        height: 300,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppTheme.textMuted(context).withOpacity(0.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 8,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                ),
                itemCount: emojis.length,
                itemBuilder: (context, index) {
                  return GestureDetector(
                    onTap: () {
                      Navigator.pop(ctx);
                      _quickReact(message, emojis[index]);
                    },
                    child: Container(
                      alignment: Alignment.center,
                      child: Text(
                        emojis[index],
                        style: const TextStyle(fontSize: 24),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showMessageInfo(GnsMessage message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface(context),
        title: const Text('Message Info'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _infoRow('Sent', _formatDateTime(message.timestamp)),
            const SizedBox(height: 8),
            _infoRow('Status', message.status.name.toUpperCase()),
            const SizedBox(height: 8),
            _infoRow('ID', '${message.id.substring(0, 12)}...'),
            if (_starredMessageIds.contains(message.id)) ...[
              const SizedBox(height: 8),
              _infoRow('Starred', '⭐ Yes'),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: TextStyle(
              color: AppTheme.textMuted(context),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(value),
        ),
      ],
    );
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} ${_formatTime(dt)}';
  }

  void _showAttachmentOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildAttachmentOption(
                    icon: Icons.photo,
                    label: 'Photo',
                    color: Colors.purple,
                    onTap: () {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Photo sharing coming soon!')),
                      );
                    },
                  ),
                  _buildAttachmentOption(
                    icon: Icons.camera_alt,
                    label: 'Camera',
                    color: Colors.pink,
                    onTap: () => Navigator.pop(ctx),
                  ),
                  _buildAttachmentOption(
                    icon: Icons.insert_drive_file,
                    label: 'Document',
                    color: Colors.blue,
                    onTap: () => Navigator.pop(ctx),
                  ),
                  _buildAttachmentOption(
                    icon: Icons.location_on,
                    label: 'Location',
                    color: Colors.green,
                    onTap: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildAttachmentOption(
                    icon: Icons.person,
                    label: 'Contact',
                    color: Colors.orange,
                    onTap: () => Navigator.pop(ctx),
                  ),
                  _buildAttachmentOption(
                    icon: Icons.poll,
                    label: 'Poll',
                    color: Colors.teal,
                    onTap: () => Navigator.pop(ctx),
                  ),
                  const SizedBox(width: 60),
                  const SizedBox(width: 60),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAttachmentOption({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: AppTheme.textSecondary(context),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  // ==================== CALL ====================

  void _startCall(String callType) {
    if (_otherPublicKey == null) return;

    final type = callType == 'video' ? CallType.video : CallType.voice;

    // Open the CallScreen — it triggers CallService.startCall() internally
    CallScreen.show(
      context,
      remotePublicKey: _otherPublicKey!,
      remoteHandle: _otherHandle,
      callType: type,
    );
  }

  void _showOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(
                color: AppTheme.textMuted(context).withOpacity(0.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.search),
              title: const Text('Search in conversation'),
              onTap: () => Navigator.pop(ctx),
            ),
            ListTile(
              leading: const Icon(Icons.person),
              title: const Text('View profile'),
              onTap: () => Navigator.pop(ctx),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Media, links, and docs'),
              onTap: () => Navigator.pop(ctx),
            ),
            ListTile(
              leading: Icon(
                widget.thread.isMuted ? Icons.notifications : Icons.notifications_off,
              ),
              title: Text(widget.thread.isMuted ? 'Unmute' : 'Mute notifications'),
              onTap: () {
                Navigator.pop(ctx);
                widget.commService.muteThread(widget.thread.id, muted: !widget.thread.isMuted);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Delete conversation', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDeleteConversation();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteConversation() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface(context),
        title: const Text('Delete Conversation?'),
        content: const Text('This will delete all messages in this conversation.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              widget.commService.deleteThread(widget.thread.id);
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

// ==================== CREATE FACET DIALOG ====================

class _CreateFacetDialog extends StatefulWidget {
  final String suggestedName;
  final Future<ProfileFacet> Function(String name, String emoji) onSave;
  
  const _CreateFacetDialog({
    required this.suggestedName,
    required this.onSave,
  });
  
  @override
  State<_CreateFacetDialog> createState() => _CreateFacetDialogState();
}

class _CreateFacetDialogState extends State<_CreateFacetDialog> {
  late TextEditingController _nameController;
  String _selectedEmoji = '📌';
  bool _saving = false;
  
  static const _emojis = [
    '📌', '🎵', '💼', '🎉', '👨‍👩‍👧', '✈️', '🎮', '⚽', 
    '🍕', '💻', '🎨', '📷', '💪', '₿', '📊', '✨',
    '🎬', '📚', '🎸', '🏠', '🚗', '🌍', '☕', '🍺',
  ];
  
  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.suggestedName);
    _selectedEmoji = _suggestEmoji(widget.suggestedName);
  }
  
  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }
  
  String _suggestEmoji(String name) {
    const suggestions = {
      'music': '🎵', 'dix': '🎵',
      'work': '💼', 'business': '💼',
      'friends': '🎉', 'party': '🎉',
      'family': '👨‍👩‍👧',
      'travel': '✈️', 'trip': '✈️',
      'gaming': '🎮', 'games': '🎮',
      'sports': '⚽', 'fitness': '💪',
      'food': '🍕', 'cooking': '🍕',
      'tech': '💻', 'code': '💻',
      'art': '🎨', 'creative': '🎨',
      'photo': '📷', 'photography': '📷',
      'crypto': '₿', 'finance': '📊',
    };
    return suggestions[name.toLowerCase()] ?? '📌';
  }
  
  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    
    setState(() => _saving = true);
    
    try {
      final facet = await widget.onSave(name, _selectedEmoji);
      if (mounted) Navigator.pop(context, facet);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.surface(context),
      title: const Text('Create New Facet'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Emoji selector
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _emojis.map((emoji) {
              final isSelected = emoji == _selectedEmoji;
              return InkWell(
                onTap: () => setState(() => _selectedEmoji = emoji),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isSelected 
                        ? Theme.of(context).colorScheme.primary.withOpacity(0.2)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: isSelected 
                        ? Border.all(color: Theme.of(context).colorScheme.primary)
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: Text(emoji, style: const TextStyle(fontSize: 20)),
                ),
              );
            }).toList(),
          ),
          
          const SizedBox(height: 16),
          
          // Name input
          TextField(
            controller: _nameController,
            decoration: InputDecoration(
              labelText: 'Facet Name',
              prefixText: '$_selectedEmoji  ',
              border: const OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.words,
            autofocus: true,
          ),
          
          const SizedBox(height: 8),
          
          Text(
            'This creates ${_nameController.text.toLowerCase().replaceAll(' ', '')}@yourhandle',
            style: TextStyle(
              color: AppTheme.textMuted(context),
              fontSize: 12,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving 
              ? const SizedBox(
                  width: 16, 
                  height: 16, 
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create'),
        ),
      ],
    );
  }
}
