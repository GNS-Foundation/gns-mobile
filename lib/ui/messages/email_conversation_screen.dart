/// Email Conversation Screen v2 - Enhanced Email Thread View
/// 
/// Improvements:
/// - Quick reply at TOP
/// - Collapsible message thread below
/// - Sender avatars (initials)
/// - Better date formatting ("2 hours ago")
/// - Swipe actions
/// - Visual polish
/// 
/// Location: lib/ui/messages/email_conversation_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../core/comm/communication_service.dart';
import '../../core/email/email_service.dart';
import '../../core/gns/identity_wallet.dart';
import '../../core/theme/theme_service.dart';
import 'email_list_screen.dart';
import 'email_compose_screen.dart';

class EmailConversationScreen extends StatefulWidget {
  final EmailThread emailThread;
  final CommunicationService commService;
  final IdentityWallet wallet;
  
  const EmailConversationScreen({
    super.key,
    required this.emailThread,
    required this.commService,
    required this.wallet,
  });

  @override
  State<EmailConversationScreen> createState() => _EmailConversationScreenState();
}

class _EmailConversationScreenState extends State<EmailConversationScreen> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _quickReplyController = TextEditingController();
  final FocusNode _quickReplyFocus = FocusNode();
  final EmailService _emailService = EmailService();
  
  List<EmailMessage> _emails = [];
  Set<String> _expandedIds = {};
  bool _loading = true;
  bool _sending = false;
  String? _userHandle;
  
  @override
  void initState() {
    super.initState();
    _initializeService();
    _loadEmails();
  }

  Future<void> _initializeService() async {
    await _emailService.initialize(widget.wallet);
    _userHandle = await widget.wallet.getCurrentHandle();
    if (mounted) setState(() {});
  }

  Future<void> _loadEmails() async {
    setState(() => _loading = true);
    
    // Convert GnsMessages to EmailMessages
    final emails = widget.emailThread.messages
        .map((msg) => EmailMessage.fromGnsMessage(msg))
        .where((e) => !e.isDeleted)
        .toList();
    
    // Sort by date (newest first for thread view)
    emails.sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    
    setState(() {
      _emails = emails;
      _loading = false;
      // Expand the most recent email by default
      if (emails.isNotEmpty) {
        _expandedIds.add(emails.first.id);
      }
    });
    
    // Mark first unread as read
    final unread = emails.where((e) => !e.isRead).toList();
    for (final email in unread) {
      await _emailService.markAsRead(email.id);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _quickReplyController.dispose();
    _quickReplyFocus.dispose();
    super.dispose();
  }

  String _formatRelativeTime(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w ago';
    
    return DateFormat('MMM d').format(date);
  }

  String _getInitials(String email) {
    final name = email.split('@').first;
    if (name.length <= 2) return name.toUpperCase();
    
    // Try to get first letter of first and last word
    final parts = name.replaceAll(RegExp(r'[._-]'), ' ').split(' ');
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return name.substring(0, 2).toUpperCase();
  }

  Color _getAvatarColor(String email) {
    final colors = [
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.teal,
      Colors.pink,
      Colors.indigo,
      Colors.cyan,
    ];
    
    int hash = email.hashCode;
    return colors[hash.abs() % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ThemeService().isDark;
    final senderEmail = widget.emailThread.externalEmail;
    final senderName = senderEmail.split('@').first;
    
    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
      appBar: _buildAppBar(senderName, senderEmail, isDark),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Quick reply at TOP
                _buildQuickReplySection(isDark),
                
                // Divider
                Container(
                  height: 8,
                  color: isDark ? AppTheme.darkBackground : Colors.grey.shade100,
                ),
                
                // Thread label
                _buildThreadLabel(isDark),
                
                // Email thread (expandable cards)
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: _emails.length,
                    itemBuilder: (context, index) {
                      final email = _emails[index];
                      final isExpanded = _expandedIds.contains(email.id);
                      return _buildEmailCard(email, isExpanded, index, isDark);
                    },
                  ),
                ),
              ],
            ),
    );
  }

  PreferredSizeWidget _buildAppBar(String senderName, String senderEmail, bool isDark) {
    return AppBar(
      backgroundColor: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
      elevation: 0,
      leading: IconButton(
        icon: Icon(
          Icons.arrow_back,
          color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
        ),
        onPressed: () => Navigator.pop(context),
      ),
      title: Row(
        children: [
          // Avatar
          CircleAvatar(
            radius: 18,
            backgroundColor: _getAvatarColor(senderEmail),
            child: Text(
              _getInitials(senderEmail),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  senderName,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  senderEmail,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.more_vert),
          onPressed: () => _showMoreOptions(),
          color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
        ),
      ],
    );
  }

  Widget _buildQuickReplySection(bool isDark) {
    final replyTo = _emails.isNotEmpty ? _emails.first : null;
    
    return Container(
      padding: const EdgeInsets.all(16),
      color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Reply header
          Row(
            children: [
              Icon(
                Icons.reply,
                size: 18,
                color: Colors.blue,
              ),
              const SizedBox(width: 8),
              Text(
                'Quick Reply',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                ),
              ),
              const Spacer(),
              // Full compose button
              TextButton.icon(
                onPressed: () => _openFullCompose(replyTo),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Full editor'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.blue,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          // Input field
          Container(
            decoration: BoxDecoration(
              color: isDark ? AppTheme.darkBackground : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _quickReplyFocus.hasFocus 
                    ? Colors.blue 
                    : Colors.transparent,
                width: 2,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _quickReplyController,
                    focusNode: _quickReplyFocus,
                    maxLines: 4,
                    minLines: 1,
                    textCapitalization: TextCapitalization.sentences,
                    style: TextStyle(
                      color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Type your reply...',
                      hintStyle: TextStyle(
                        color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.all(12),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                // Send button
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: IconButton(
                    onPressed: _quickReplyController.text.trim().isEmpty || _sending
                        ? null
                        : () => _sendQuickReply(replyTo),
                    icon: _sending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                    color: Colors.blue,
                    disabledColor: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                  ),
                ),
              ],
            ),
          ),
          
          // From address hint
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 4),
            child: Text(
              'From: ${_userHandle ?? 'you'}@gcrumbs.com',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThreadLabel(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(
            Icons.forum_outlined,
            size: 16,
            color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
          ),
          const SizedBox(width: 8),
          Text(
            'Conversation (${_emails.length} ${_emails.length == 1 ? 'message' : 'messages'})',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: () {
              setState(() {
                if (_expandedIds.length == _emails.length) {
                  _expandedIds.clear();
                  if (_emails.isNotEmpty) _expandedIds.add(_emails.first.id);
                } else {
                  _expandedIds = _emails.map((e) => e.id).toSet();
                }
              });
            },
            child: Text(
              _expandedIds.length == _emails.length ? 'Collapse all' : 'Expand all',
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmailCard(EmailMessage email, bool isExpanded, int index, bool isDark) {
    final isFromMe = email.from.contains('@gcrumbs.com');
    final avatarColor = isFromMe ? Colors.blue : _getAvatarColor(email.from);
    final initials = isFromMe ? (_userHandle?[0].toUpperCase() ?? 'M') : _getInitials(email.from);
    
    return Dismissible(
      key: Key(email.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (direction) => _confirmDelete(email),
      child: GestureDetector(
        onTap: () {
          setState(() {
            if (isExpanded) {
              _expandedIds.remove(email.id);
            } else {
              _expandedIds.add(email.id);
            }
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isFromMe 
                  ? Colors.blue.withValues(alpha: 0.3)
                  : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
              width: isFromMe ? 1.5 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Collapsed header (always visible)
              _buildEmailHeader(email, isExpanded, isFromMe, avatarColor, initials, isDark),
              
              // Expanded content
              if (isExpanded) ...[
                const Divider(height: 1),
                _buildEmailBody(email, isDark),
                _buildEmailActions(email, isDark),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmailHeader(
    EmailMessage email, 
    bool isExpanded, 
    bool isFromMe,
    Color avatarColor,
    String initials,
    bool isDark,
  ) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          // Avatar
          CircleAvatar(
            radius: 20,
            backgroundColor: avatarColor,
            child: Text(
              initials,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          
          // Sender & subject
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        isFromMe ? 'You' : email.senderName,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      _formatRelativeTime(email.receivedAt),
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  email.subject,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (!isExpanded) ...[
                  const SizedBox(height: 2),
                  Text(
                    email.preview,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          
          // Expand/collapse icon
          Icon(
            isExpanded ? Icons.expand_less : Icons.expand_more,
            color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
          ),
        ],
      ),
    );
  }

  Widget _buildEmailBody(EmailMessage email, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      child: SelectableText(
        email.body,
        style: TextStyle(
          fontSize: 15,
          height: 1.5,
          color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
        ),
      ),
    );
  }

  Widget _buildEmailActions(EmailMessage email, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDark 
            ? Colors.white.withValues(alpha: 0.03)
            : Colors.black.withValues(alpha: 0.02),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
      ),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: () => _openFullCompose(email),
            icon: const Icon(Icons.reply, size: 16),
            label: const Text('Reply'),
            style: TextButton.styleFrom(
              foregroundColor: Colors.blue,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
          TextButton.icon(
            onPressed: () => _forwardEmail(email),
            icon: const Icon(Icons.forward, size: 16),
            label: const Text('Forward'),
            style: TextButton.styleFrom(
              foregroundColor: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: () => _copyEmailContent(email),
            icon: const Icon(Icons.copy, size: 18),
            color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
            tooltip: 'Copy',
          ),
        ],
      ),
    );
  }

  // ============================================
  // ACTIONS
  // ============================================

  Future<void> _sendQuickReply(EmailMessage? replyTo) async {
    if (replyTo == null || _quickReplyController.text.trim().isEmpty) return;
    
    setState(() => _sending = true);
    
    final success = await _emailService.sendReply(
      originalMessageId: replyTo.id,
      toEmail: replyTo.senderEmail,
      subject: replyTo.subject.startsWith('Re:') 
          ? replyTo.subject 
          : 'Re: ${replyTo.subject}',
      body: _quickReplyController.text.trim(),
      inReplyToMessageId: replyTo.id,
    );
    
    setState(() => _sending = false);
    
    if (success) {
      _quickReplyController.clear();
      _quickReplyFocus.unfocus();
      HapticFeedback.heavyImpact();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text('Reply sent!'),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Failed to send reply'),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: () => _sendQuickReply(replyTo),
            ),
          ),
        );
      }
    }
  }

  void _openFullCompose(EmailMessage? replyTo) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EmailComposeScreen(
          wallet: widget.wallet,
          replyTo: replyTo,
        ),
      ),
    ).then((sent) {
      if (sent == true) {
        // Reload thread to show sent message
        _loadEmails();
      }
    });
  }

  void _forwardEmail(EmailMessage email) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EmailComposeScreen(
          wallet: widget.wallet,
          forwardOf: email,
        ),
      ),
    );
  }

  Future<bool> _confirmDelete(EmailMessage email) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete email?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      await _emailService.deleteEmail(email.id);
      setState(() {
        _emails.removeWhere((e) => e.id == email.id);
        _expandedIds.remove(email.id);
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Email deleted')),
        );
      }
      
      // Pop if no more emails
      if (_emails.isEmpty && mounted) {
        Navigator.pop(context);
      }
    }
    
    return false; // We handle deletion ourselves
  }

  void _copyEmailContent(EmailMessage email) {
    final content = '${email.subject}\n\nFrom: ${email.from}\nDate: ${email.receivedAt}\n\n${email.body}';
    Clipboard.setData(ClipboardData(text: content));
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Email copied to clipboard')),
    );
  }

  void _showMoreOptions() {
    final isDark = ThemeService().isDark;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black26,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copy sender email'),
              onTap: () {
                Navigator.pop(context);
                Clipboard.setData(ClipboardData(text: widget.emailThread.externalEmail));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Email copied')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.mark_email_unread),
              title: const Text('Mark all as unread'),
              onTap: () async {
                Navigator.pop(context);
                for (final email in _emails) {
                  await _emailService.markAsUnread(email.id);
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Marked as unread')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Delete all', style: TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(context);
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Delete all emails?'),
                    content: const Text('This will delete all emails in this conversation.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Delete all'),
                      ),
                    ],
                  ),
                );
                
                if (confirmed == true) {
                  for (final email in _emails) {
                    await _emailService.deleteEmail(email.id);
                  }
                  if (mounted) Navigator.pop(context);
                }
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
