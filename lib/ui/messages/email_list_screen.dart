/// Email List Screen - Enhanced Email Inbox Tab
/// 
/// Displays emails received via the gcrumbs.com gateway.
/// Features:
/// - Unread indicators  
/// - Swipe to delete
/// - Pull to refresh
/// - Multi-select
/// 
/// Location: lib/ui/messages/email_list_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/comm/communication_service.dart';
import '../../core/comm/message_storage.dart';
import '../../core/comm/payload_types.dart';
import '../../core/email/email_service.dart';
import '../../core/gns/identity_wallet.dart';
import '../../core/theme/theme_service.dart';
import 'email_conversation_screen.dart';
import 'email_compose_screen.dart';

/// Email gateway public key - messages from this key are emails
const String EMAIL_GATEWAY_PUBLIC_KEY = '007dd9b2c19308dd0e2dfc044da05a522a1d1adbd6f1c84147cc4e0b7a4bd53d';

/// Email thread grouping (by subject)
class EmailThread {
  final String subject;  // ✅ Thread by subject, not sender
  final List<GnsMessage> messages;
  final DateTime lastMessageTime;
  final int unreadCount;
  
  EmailThread({
    required this.subject,
    required this.messages,
    required this.lastMessageTime,
    this.unreadCount = 0,
  });
  
  GnsMessage get lastMessage => messages.last;
  
  // For backward compatibility (used as unique key)
  String get externalEmail => subject;
  
  // Extract sender email from the first message
  String get senderEmail {
    if (messages.isEmpty) return 'unknown@email.com';
    final msg = messages.first;
    if (msg.payload is EmailPayload) {
      final emailPayload = msg.payload as EmailPayload;
      return emailPayload.from ?? 'unknown@email.com';
    }
    return 'unknown@email.com';
  }
  
  String get lastSubject => subject;
  
  String get previewText {
    final msg = lastMessage;
    if (msg.payload is EmailPayload) {
      final body = (msg.payload as EmailPayload).body;
      return body.length > 80 ? '${body.substring(0, 80)}...' : body;
    }
    // Try payload JSON
    try {
      final json = msg.payload.toJson();
      if (json.containsKey('body')) {
        final body = json['body'] as String? ?? '';
        return body.length > 80 ? '${body.substring(0, 80)}...' : body;
      }
    } catch (_) {}
    return msg.previewText;
  }
  
  String get senderName {
    // Extract email before @
    return senderEmail.split('@').first;
  }
  
  String get senderDomain {
    if (senderEmail.contains('@')) {
      return senderEmail.split('@').last;
    }
    return '';
  }
}

class EmailListScreen extends StatefulWidget {
  final CommunicationService commService;
  final IdentityWallet wallet;
  
  const EmailListScreen({
    super.key,
    required this.commService,
    required this.wallet,
  });

  @override
  State<EmailListScreen> createState() => _EmailListScreenState();
}

class _EmailListScreenState extends State<EmailListScreen> {
  final EmailService _emailService = EmailService();
  
  List<EmailThread> _emailThreads = [];
  Set<String> _selectedEmails = {};
  bool _selectionMode = false;
  bool _loading = true;
  String? _error;
  String? _userHandle;
  
  StreamSubscription? _messageSubscription;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await _emailService.initialize(widget.wallet);
    await _loadEmails();
    await _loadUserHandle();
    
    // Listen for new messages
    _messageSubscription = widget.commService.incomingMessages.listen((message) {
      debugPrint('📨 EmailListScreen: New message received');
      debugPrint('   PayloadType: ${message.payloadType}');
      debugPrint('   From: ${message.fromPublicKey.substring(0, 16)}...');
      
      // Check if it's an email
      final isEmailType = message.payloadType == PayloadType.email;
      final isFromGateway = message.fromPublicKey.toLowerCase() == EMAIL_GATEWAY_PUBLIC_KEY.toLowerCase();
      
      debugPrint('   isEmailType: $isEmailType');
      debugPrint('   isFromGateway: $isFromGateway');
      
      if (isEmailType || isFromGateway) {
        debugPrint('   ✅ Identified as email, reloading...');
        _loadEmails();
      } else {
        debugPrint('   ❌ NOT identified as email');
      }
    });
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    super.dispose();
  }
  
  Future<void> _loadUserHandle() async {
    final handle = await widget.wallet.getCurrentHandle();
    if (mounted) {
      setState(() => _userHandle = handle);
    }
  }

  Future<void> _loadEmails() async {
    try {
      setState(() => _loading = true);
      
      debugPrint('📧 _loadEmails: Starting email load...');
      
      // Get all threads
      final allThreads = await widget.commService.getThreads();
      debugPrint('   Found ${allThreads.length} total threads');
      
      // ✅ Filter for email messages in ANY thread (not just gateway threads)
      final emailMessages = <GnsMessage>[];
      
      for (final threadPreview in allThreads) {
        final thread = threadPreview.thread;
        
        // Load messages for this thread
        final messages = await widget.commService.getMessages(thread.id);
        
        // ✅ Filter for email payloadType (includes both incoming AND outgoing)
        final emailsInThread = messages.where((m) => 
          m.payloadType == PayloadType.email
        ).where((m) => !m.isDeleted).toList();
        
        if (emailsInThread.isNotEmpty) {
          debugPrint('   Thread ${thread.id.substring(0, 8)}: Found ${emailsInThread.length} emails');
          for (final email in emailsInThread) {
            debugPrint('      - ${email.id.substring(0, 8)}: from=${email.fromPublicKey.substring(0, 8)}, direction=${email.fromPublicKey == widget.wallet.publicKey ? "SENT" : "RECEIVED"}');
          }
          emailMessages.addAll(emailsInThread);
        }
      }
      
      // ✅ Group by subject (email threading based on subject line)
      final threadMap = <String, List<GnsMessage>>{};
      
      for (final msg in emailMessages) {
        String subject = '(No Subject)';
        
        // Extract subject from payload
        if (msg.payload is EmailPayload) {
          final emailPayload = msg.payload as EmailPayload;
          subject = emailPayload.subject;
        }
        
        // ✅ Normalize subject: strip Re:, Fwd:, etc. for proper threading
        final normalizedSubject = subject
          .replaceAll(RegExp(r'^(re|fw|fwd):\s*', caseSensitive: false), '')
          .trim()
          .toLowerCase();
        
        threadMap.putIfAbsent(normalizedSubject, () => []);
        threadMap[normalizedSubject]!.add(msg);
      }
      
      // Create EmailThread objects
      final threads = threadMap.entries.map((entry) {
        final messages = entry.value..sort((a, b) => a.timestamp.compareTo(b.timestamp));
        final unreadCount = messages.where((m) => m.status != MessageStatus.read).length;
        return EmailThread(
          subject: entry.key,  // ✅ Now using subject as identifier
          messages: messages,
          lastMessageTime: messages.last.timestamp,
          unreadCount: unreadCount,
        );
      }).toList();
      
      // Sort by most recent
      threads.sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));
      
      setState(() {
        _emailThreads = threads;
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

  @override
  Widget build(BuildContext context) {
    final isDark = ThemeService().isDark;
    
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
            Text(_error!, style: TextStyle(color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadEmails,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Email address banner
        _buildEmailAddressBanner(isDark),
        
        // Selection bar
        if (_selectionMode)
          _buildSelectionBar(isDark),
        
        // Email list or empty state
        Expanded(
          child: _emailThreads.isEmpty
              ? _buildEmptyState(isDark)
              : RefreshIndicator(
                  onRefresh: _loadEmails,
                  color: Theme.of(context).colorScheme.primary,
                  child: ListView.builder(
                    itemCount: _emailThreads.length,
                    itemBuilder: (context, index) => _buildEmailTile(_emailThreads[index], isDark),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildEmailAddressBanner(bool isDark) {
    final emailAddress = _userHandle != null 
        ? '$_userHandle@gcrumbs.com' 
        : 'your-handle@gcrumbs.com';
    
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.blue.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.mail_outline,
            color: Colors.blue,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your GNS Email',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  emailAddress,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 20),
            color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
            onPressed: () {
              Clipboard.setData(ClipboardData(text: emailAddress));
              HapticFeedback.lightImpact();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Copied $emailAddress'),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            tooltip: 'Copy email address',
          ),
          IconButton(
            icon: const Icon(Icons.edit, size: 20),
            color: Colors.blue,
            onPressed: _composeNewEmail,
            tooltip: 'Compose email',
          ),
        ],
      ),
    );
  }

  Widget _buildSelectionBar(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.blue,
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () {
              setState(() {
                _selectionMode = false;
                _selectedEmails.clear();
              });
            },
          ),
          Text(
            '${_selectedEmails.length} selected',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.select_all, color: Colors.white),
            onPressed: () {
              setState(() {
                if (_selectedEmails.length == _emailThreads.length) {
                  _selectedEmails.clear();
                } else {
                  _selectedEmails = _emailThreads.map((t) => t.externalEmail).toSet();
                }
              });
            },
            tooltip: 'Select all',
          ),
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.white),
            onPressed: _selectedEmails.isEmpty ? null : _deleteSelected,
            tooltip: 'Delete selected',
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.mail_outline,
            size: 64,
            color: (isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted).withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'No emails yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Emails sent to your @gcrumbs.com address\nwill appear here',
            textAlign: TextAlign.center,
            style: TextStyle(color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _userHandle != null 
                  ? '$_userHandle@gcrumbs.com' 
                  : 'your-handle@gcrumbs.com',
              style: const TextStyle(
                color: Colors.blue,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmailTile(EmailThread emailThread, bool isDark) {
    final hasUnread = emailThread.unreadCount > 0;
    final isSelected = _selectedEmails.contains(emailThread.externalEmail);
    
    // Format time
    String timeText = '';
    final diff = DateTime.now().difference(emailThread.lastMessageTime);
    if (diff.inDays > 0) {
      timeText = '${diff.inDays}d';
    } else if (diff.inHours > 0) {
      timeText = '${diff.inHours}h';
    } else if (diff.inMinutes > 0) {
      timeText = '${diff.inMinutes}m';
    } else {
      timeText = 'now';
    }

    return Dismissible(
      key: Key(emailThread.externalEmail),
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      direction: DismissDirection.endToStart,
      confirmDismiss: (direction) => _confirmDeleteThread(emailThread),
      child: InkWell(
        onTap: _selectionMode
            ? () {
                setState(() {
                  if (isSelected) {
                    _selectedEmails.remove(emailThread.externalEmail);
                    if (_selectedEmails.isEmpty) _selectionMode = false;
                  } else {
                    _selectedEmails.add(emailThread.externalEmail);
                  }
                });
              }
            : () => _openEmailConversation(emailThread),
        onLongPress: () {
          setState(() {
            _selectionMode = true;
            _selectedEmails.add(emailThread.externalEmail);
          });
          HapticFeedback.mediumImpact();
        },
        child: Container(
          color: isSelected ? Colors.blue.withOpacity(0.1) : null,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: Stack(
              children: [
                if (_selectionMode)
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: isSelected ? Colors.blue : Colors.grey.withOpacity(0.3),
                    child: isSelected
                        ? const Icon(Icons.check, color: Colors.white)
                        : null,
                  )
                else
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: Colors.blue.withOpacity(0.2),
                    child: Text(
                      emailThread.senderName.isNotEmpty 
                          ? emailThread.senderName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        color: Colors.blue,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                if (hasUnread && !_selectionMode)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.blue,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        emailThread.unreadCount > 9 ? '9+' : '${emailThread.unreadCount}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            title: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        emailThread.senderName,
                        style: TextStyle(
                          fontWeight: hasUnread ? FontWeight.bold : FontWeight.w500,
                          color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                          fontSize: 15,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (emailThread.senderDomain.isNotEmpty)
                        Text(
                          '@${emailThread.senderDomain}',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                          ),
                        ),
                    ],
                  ),
                ),
                Text(
                  timeText,
                  style: TextStyle(
                    fontSize: 12,
                    color: hasUnread ? Colors.blue : (isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted),
                  ),
                ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  emailThread.lastSubject,
                  style: TextStyle(
                    fontWeight: hasUnread ? FontWeight.w600 : FontWeight.normal,
                    color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  emailThread.previewText,
                  style: TextStyle(
                    color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<bool> _confirmDeleteThread(EmailThread thread) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Emails?'),
        content: Text('Delete all ${thread.messages.length} emails from ${thread.senderName}?'),
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
    
    if (confirmed == true) {
      final ids = thread.messages.map((m) => m.id).toList();
      await _emailService.deleteEmails(ids);
      _loadEmails();
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${ids.length} emails deleted')),
      );
    }
    
    return false; // Don't auto-dismiss, we handle it
  }

  Future<void> _deleteSelected() async {
    final count = _selectedEmails.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Emails?'),
        content: Text('Delete emails from $count sender${count > 1 ? 's' : ''}?'),
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
    
    if (confirmed == true) {
      int totalDeleted = 0;
      for (final email in _selectedEmails) {
        final thread = _emailThreads.firstWhere((t) => t.externalEmail == email);
        final ids = thread.messages.map((m) => m.id).toList();
        await _emailService.deleteEmails(ids);
        totalDeleted += ids.length;
      }
      
      setState(() {
        _selectionMode = false;
        _selectedEmails.clear();
      });
      
      _loadEmails();
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$totalDeleted emails deleted')),
      );
    }
  }

  void _openEmailConversation(EmailThread emailThread) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EmailConversationScreen(
          emailThread: emailThread,
          commService: widget.commService,
          wallet: widget.wallet,
        ),
      ),
    ).then((_) => _loadEmails());
  }

  void _composeNewEmail() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EmailComposeScreen(
          wallet: widget.wallet,
        ),
        fullscreenDialog: true,
      ),
    );
  }
}
