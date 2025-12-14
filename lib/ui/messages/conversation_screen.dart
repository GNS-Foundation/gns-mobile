/// Conversation Screen - Chat View (flutter_chat_ui INTEGRATED)
/// 
/// CHANGES:
/// - ✅ Integrated flutter_chat_ui for professional UI
/// - ✅ Keeps all your backend (GnsMessage, CommunicationService)
/// - ✅ Ready to use in 2 minutes!
/// 
/// Location: lib/ui/messages/conversation_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:flutter_chat_types/flutter_chat_types.dart' as types;
import '../../core/comm/communication_service.dart';
import '../../core/comm/message_storage.dart';
import '../../core/comm/gns_envelope.dart';
import '../../core/comm/payload_types.dart';
import '../../core/contacts/contact_storage.dart';
import '../../core/theme/theme_service.dart';
import 'chat_ui_adapter.dart';

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
  late ChatUIAdapter _adapter;  // ✅ ADDED
  
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;
  
  // Typing indicator state
  Map<String, bool> _typingUsers = {};
  Timer? _typingTimer;
  Timer? _autoRefreshTimer;
  
  StreamSubscription? _messageSubscription;
  StreamSubscription? _typingSubscription;
  
  String? _myPublicKey;
  String? _otherPublicKey;
  String? _otherEncryptionKey;
  String? _otherHandle;

  @override
  void initState() {
    super.initState();
    _adapter = ChatUIAdapter(widget.commService);  // ✅ ADDED
    _initialize();
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    _typingSubscription?.cancel();
    _typingTimer?.cancel();
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _initialize() async {
    // Get my public key
    _myPublicKey = widget.commService.myPublicKey;
    
    // Find the other participant
    _otherPublicKey = widget.thread.participantKeys.firstWhere(
      (k) => k.toLowerCase() != _myPublicKey?.toLowerCase(),
      orElse: () => widget.thread.participantKeys.first,
    );
    
    // Fetch contact info including handle
    final contactStorage = ContactStorage();
    final contact = await contactStorage.getContact(_otherPublicKey!);
    _otherEncryptionKey = contact?.encryptionKey;
    _otherHandle = contact?.handle;
    
    // Listen for new messages
    _messageSubscription = widget.commService.incomingMessages.listen((message) {
      // Check threadId OR if message is from the other participant
      final matchesThread = message.threadId == widget.thread.id;
      final matchesParticipant = message.fromPublicKey.toLowerCase() == _otherPublicKey?.toLowerCase();
      
      if (matchesThread || matchesParticipant) {
        // Avoid duplicates
        if (!_messages.any((m) => m.id == message.id)) {
          setState(() {
            _messages.add(message);
          });
          
          // Mark as read
          _markMessagesRead([message.id]);
        }
      }
    });
    
    // Listen for typing indicators
    _typingSubscription = widget.commService.typingEvents.listen((event) {
      if (event.threadId == widget.thread.id) {
        setState(() {
          _typingUsers[event.publicKey] = event.isTyping;
        });
      }
    });
    
    await _loadMessages();
    
    // Mark thread as read
    final unreadMessages = _messages.where((m) => !m.isOutgoing).map((m) => m.id).toList();
    if (unreadMessages.isNotEmpty) {
      await widget.commService.markAsRead(
        threadId: widget.thread.id,
        messageIds: unreadMessages,
        toPublicKey: _otherPublicKey!,
      );
    }
    
    _autoRefreshTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) async {
        if (mounted) {
          await widget.commService.syncMessages();
          await _loadMessages();
        }
      },
    );
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
        _hasMore = messages.length >= 50;
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: AppTheme.background(context),
        appBar: _buildAppBar(),
        body: Center(
          child: CircularProgressIndicator(
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: AppTheme.background(context),
        appBar: _buildAppBar(),
        body: Center(
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
        ),
      );
    }

    // ✅ Convert GnsMessages to flutter_chat_ui format
    final chatMessages = _messages
        .map((m) => _adapter.toFlutterMessage(m))
        .toList()
        .reversed  // flutter_chat_ui expects newest first
        .toList();
    
    return Scaffold(
      backgroundColor: AppTheme.background(context),
      appBar: _buildAppBar(),
      body: Chat(
        messages: chatMessages,
        onSendPressed: _handleSendPressed,
        user: _adapter.currentUser,
        theme: _buildChatTheme(),
        showUserAvatars: true,
        showUserNames: false,
        // ✅ Enable typing indicator
        typingIndicatorOptions: TypingIndicatorOptions(
          typingUsers: _typingUsers.entries
              .where((e) => e.value && e.key != _myPublicKey)
              .map((e) => types.User(id: e.key))
              .toList(),
        ),
      ),
    );
  }

  // ✅ ADDED: Handle send message
  void _handleSendPressed(types.PartialText message) {
    _sendTextMessage(message.text);
  }

  // ✅ ADDED: Build chat theme matching your app
  DefaultChatTheme _buildChatTheme() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return DefaultChatTheme(
      primaryColor: const Color(0xFF3B82F6),
      secondaryColor: isDark ? const Color(0xFF2D2D2D) : const Color(0xFFF0F0F0),
      backgroundColor: AppTheme.background(context),
      inputBackgroundColor: AppTheme.surface(context),
      inputTextColor: AppTheme.textPrimary(context),
      receivedMessageBodyTextStyle: TextStyle(
        color: AppTheme.textPrimary(context),
        fontSize: 16,
      ),
      sentMessageBodyTextStyle: const TextStyle(
        color: Colors.white,
        fontSize: 16,
      ),
    );
  }

  AppBar _buildAppBar() {
    // Get title
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
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => Navigator.pop(context),
      ),
      title: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.2),
            child: Text(
              title.replaceAll('@', '').substring(0, 1).toUpperCase(),
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
                fontSize: 14,
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
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                // Show typing indicator in subtitle
                if (_typingUsers.values.any((typing) => typing))
                  Text(
                    'typing...',
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.primary,
                      fontStyle: FontStyle.italic,
                    ),
                  )
                else
                  Text(
                    'Tap for info',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.textMuted(context),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.more_vert),
          onPressed: _showOptions,
        ),
      ],
    );
  }

  Future<void> _sendTextMessage(String text) async {
    if (_otherPublicKey == null) return;

    // Send typing stopped
    widget.commService.sendTyping(
      threadId: widget.thread.id,
      toPublicKey: _otherPublicKey!,
      isTyping: false,
    );

    final result = await widget.commService.sendText(
      toPublicKey: _otherPublicKey!,
      text: text,
      threadId: widget.thread.id,
    );

    if (result.success && result.message != null) {
      setState(() {
        _messages.add(result.message!);
      });
      
      // ✅ ADD THIS: Sync after 2 seconds to get @echo response
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

  void _showOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface(context),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.search, color: Colors.white70),
              title: const Text('Search in conversation'),
              onTap: () {
                Navigator.pop(context);
                // TODO: Implement search
              },
            ),
            ListTile(
              leading: const Icon(Icons.person, color: Colors.white70),
              title: const Text('View profile'),
              onTap: () {
                Navigator.pop(context);
                // TODO: Open profile
              },
            ),
            ListTile(
              leading: Icon(
                widget.thread.isMuted ? Icons.notifications : Icons.notifications_off,
                color: Colors.white70,
              ),
              title: Text(widget.thread.isMuted ? 'Unmute' : 'Mute notifications'),
              onTap: () {
                Navigator.pop(context);
                widget.commService.muteThread(widget.thread.id, muted: !widget.thread.isMuted);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Delete conversation', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _confirmDeleteConversation();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteConversation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface(context),
        title: const Text('Delete Conversation?'),
        content: const Text('This will delete all messages in this conversation.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              widget.commService.deleteThread(widget.thread.id);
              Navigator.pop(context);  // Go back to thread list
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
