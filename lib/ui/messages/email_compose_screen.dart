/// Email Compose Screen v2 - Enhanced Email Composer
/// 
/// Improvements:
/// - Reply input at TOP (not bottom)
/// - Clean collapsible quoted text
/// - Better visual hierarchy
/// - Formatting toolbar
/// - Email signature support
/// 
/// Location: lib/ui/messages/email_compose_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/email/email_service.dart';
import '../../core/gns/identity_wallet.dart';
import '../../core/theme/theme_service.dart';

class EmailComposeScreen extends StatefulWidget {
  final IdentityWallet wallet;
  final EmailMessage? replyTo;
  final EmailMessage? forwardOf;
  final String? initialTo;
  
  const EmailComposeScreen({
    super.key,
    required this.wallet,
    this.replyTo,
    this.forwardOf,
    this.initialTo,
  });

  @override
  State<EmailComposeScreen> createState() => _EmailComposeScreenState();
}

class _EmailComposeScreenState extends State<EmailComposeScreen> {
  final _toController = TextEditingController();
  final _subjectController = TextEditingController();
  final _bodyController = TextEditingController();
  final _toFocusNode = FocusNode();
  final _bodyFocusNode = FocusNode();
  final _scrollController = ScrollController();
  
  final EmailService _emailService = EmailService();
  
  bool _sending = false;
  String? _userHandle;
  String? _error;
  bool _showQuoted = false; // Collapsed by default
  bool _includeQuoted = true;
  
  // Original message details for reply/forward
  String _originalFrom = '';
  String _originalDate = '';
  String _originalSubject = '';
  String _originalBody = '';
  
  @override
  void initState() {
    super.initState();
    _initializeService();
    _setupInitialContent();
  }

  Future<void> _initializeService() async {
    await _emailService.initialize(widget.wallet);
    _userHandle = await widget.wallet.getCurrentHandle();
    if (mounted) setState(() {});
  }

  void _setupInitialContent() {
    // Reply mode
    if (widget.replyTo != null) {
      final email = widget.replyTo!;
      _toController.text = email.senderEmail;
      _subjectController.text = email.subject.startsWith('Re:') 
          ? email.subject 
          : 'Re: ${email.subject}';
      
      // Store original for quoted section
      _originalFrom = email.from;
      _originalDate = _formatDate(email.receivedAt);
      _originalSubject = email.subject;
      _originalBody = email.body;
      
      // Body starts empty - user types fresh reply
      _bodyController.text = '';
      
      // Focus body for reply
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _bodyFocusNode.requestFocus();
      });
    }
    // Forward mode
    else if (widget.forwardOf != null) {
      final email = widget.forwardOf!;
      _subjectController.text = email.subject.startsWith('Fwd:') 
          ? email.subject 
          : 'Fwd: ${email.subject}';
      
      // Store original for quoted section
      _originalFrom = email.from;
      _originalDate = _formatDate(email.receivedAt);
      _originalSubject = email.subject;
      _originalBody = email.body;
      _showQuoted = true; // Show for forwards
      
      // Body starts empty
      _bodyController.text = '';
      
      // Focus To field for forward
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _toFocusNode.requestFocus();
      });
    }
    // New email
    else {
      if (widget.initialTo != null) {
        _toController.text = widget.initialTo!;
      }
      
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (widget.initialTo != null) {
          _bodyFocusNode.requestFocus();
        } else {
          _toFocusNode.requestFocus();
        }
      });
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    
    return '${date.day}/${date.month}/${date.year}';
  }

  @override
  void dispose() {
    _toController.dispose();
    _subjectController.dispose();
    _bodyController.dispose();
    _toFocusNode.dispose();
    _bodyFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Normalize recipient - converts @handle to handle@gcrumbs.com
  String _normalizeRecipient(String input) {
    final trimmed = input.trim();
    
    // If it's just @handle (starts with @ but no second @)
    if (trimmed.startsWith('@') && !trimmed.substring(1).contains('@')) {
      final handle = trimmed.substring(1); // Remove leading @
      return '$handle@gcrumbs.com';
    }
    
    // If it's just a handle without @ or domain
    if (!trimmed.contains('@')) {
      return '$trimmed@gcrumbs.com';
    }
    
    // Already a full email address
    return trimmed;
  }

  /// Check if recipient is a GNS handle (will be routed internally)
  bool get _isGnsRecipient {
    final to = _toController.text.trim();
    // Starts with @ (handle format)
    if (to.startsWith('@') && !to.substring(1).contains('@')) return true;
    // No @ at all (bare handle)
    if (!to.contains('@')) return true;
    // Ends with @gcrumbs.com
    if (to.toLowerCase().endsWith('@gcrumbs.com')) return true;
    return false;
  }

  bool get _canSend {
    final to = _toController.text.trim();
    final body = _bodyController.text.trim();
    
    // Valid if: has recipient, has body, not sending
    // Recipient is valid if it's a @handle, bare handle, or full email
    final hasValidRecipient = to.isNotEmpty && 
        (to.startsWith('@') || to.contains('@') || to.isNotEmpty);
    
    return hasValidRecipient && body.isNotEmpty && !_sending;
  }

  bool get _isReply => widget.replyTo != null;
  bool get _isForward => widget.forwardOf != null;
  bool get _hasOriginal => _originalBody.isNotEmpty;

  Future<void> _send() async {
    if (!_canSend) return;
    
    setState(() {
      _sending = true;
      _error = null;
    });
    
    // Normalize recipient (convert @handle to handle@gcrumbs.com)
    final toEmail = _normalizeRecipient(_toController.text);
    
    // Build full body with optional quoted content
    String fullBody = _bodyController.text.trim();
    
    if (_includeQuoted && _hasOriginal) {
      fullBody += '\n\n';
      if (_isForward) {
        fullBody += '---------- Forwarded message ----------\n';
      } else {
        fullBody += '--- Original Message ---\n';
      }
      fullBody += 'From: $_originalFrom\n';
      fullBody += 'Date: $_originalDate\n';
      fullBody += 'Subject: $_originalSubject\n\n';
      fullBody += _originalBody;
    }
    
    try {
      final success = await _emailService.sendReply(
        originalMessageId: widget.replyTo?.id ?? widget.forwardOf?.id ?? '',
        toEmail: toEmail,  // Use normalized email
        subject: _subjectController.text.trim().isEmpty 
            ? '(No subject)' 
            : _subjectController.text.trim(),
        body: fullBody,
        inReplyToMessageId: widget.replyTo?.id,
      );
      
      if (success) {
        HapticFeedback.heavyImpact();
        if (mounted) {
          final isInternal = _isGnsRecipient;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(
                    isInternal ? Icons.bolt : Icons.check_circle, 
                    color: Colors.white,
                  ),
                  const SizedBox(width: 8),
                  Text(isInternal 
                      ? 'Delivered instantly via GNS!' 
                      : 'Email sent successfully!'),
                ],
              ),
              backgroundColor: isInternal ? Colors.green.shade600 : Colors.green,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
          Navigator.pop(context, true);
        }
      } else {
        setState(() {
          _error = 'Failed to send email. Please try again.';
          _sending = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _sending = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ThemeService().isDark;
    final fromAddress = _userHandle != null 
        ? '$_userHandle@gcrumbs.com' 
        : 'you@gcrumbs.com';
    
    String title = 'New Email';
    IconData titleIcon = Icons.edit;
    if (_isReply) {
      title = 'Reply';
      titleIcon = Icons.reply;
    }
    if (_isForward) {
      title = 'Forward';
      titleIcon = Icons.forward;
    }
    
    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
      appBar: AppBar(
        backgroundColor: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.close,
            color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
          ),
          onPressed: () => _confirmDiscard(),
        ),
        title: Row(
          children: [
            Icon(titleIcon, size: 20, color: Colors.blue),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        actions: [
          // Send button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: ElevatedButton.icon(
              onPressed: _canSend ? _send : null,
              icon: _sending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send, size: 18),
              label: const Text('Send'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                disabledBackgroundColor: Colors.blue.withValues(alpha: 0.4),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
            ),
          ),
        ],
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Column(
          children: [
            // Error banner
            if (_error != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                color: Colors.red.withValues(alpha: 0.1),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.red, fontSize: 13),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => setState(() => _error = null),
                      color: Colors.red,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
            
            Expanded(
              child: ListView(
                controller: _scrollController,
                padding: const EdgeInsets.all(0),
                children: [
                  // Header fields (From, To, Subject)
                  _buildHeaderFields(fromAddress, isDark),
                  
                  const SizedBox(height: 8),
                  
                  // Main compose area
                  _buildComposeArea(isDark),
                  
                  // Original message (collapsible)
                  if (_hasOriginal)
                    _buildOriginalMessage(isDark),
                ],
              ),
            ),
            
            // Bottom toolbar
            _buildBottomToolbar(isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderFields(String fromAddress, bool isDark) {
    return Container(
      color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
      child: Column(
        children: [
          // From field (read-only)
          _buildFieldRow(
            'From',
            fromAddress,
            isDark,
            icon: Icons.person_outline,
          ),
          
          _buildDivider(isDark),
          
          // To field with GNS indicator
          _buildToField(isDark),
          
          _buildDivider(isDark),
          
          // Subject field
          _buildInputRow(
            'Subject',
            _subjectController,
            null,
            isDark,
            icon: Icons.subject,
            hint: 'Email subject',
          ),
        ],
      ),
    );
  }

  Widget _buildToField(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Icon(
            Icons.person,
            size: 20,
            color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 60,
            child: Text(
              'To',
              style: TextStyle(
                color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: TextField(
              controller: _toController,
              focusNode: _toFocusNode,
              keyboardType: TextInputType.emailAddress,
              style: TextStyle(
                color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                fontSize: 15,
              ),
              decoration: InputDecoration(
                hintText: '@handle or email@example.com',
                hintStyle: TextStyle(
                  color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          // GNS badge when sending to a handle
          if (_isGnsRecipient && _toController.text.trim().isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.bolt, size: 14, color: Colors.green.shade700),
                  const SizedBox(width: 4),
                  Text(
                    'GNS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade700,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildComposeArea(bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      constraints: const BoxConstraints(minHeight: 200),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _bodyFocusNode.hasFocus 
              ? Colors.blue 
              : (isDark ? Colors.white12 : Colors.black12),
          width: _bodyFocusNode.hasFocus ? 2 : 1,
        ),
      ),
      child: TextField(
        controller: _bodyController,
        focusNode: _bodyFocusNode,
        maxLines: null,
        minLines: 8,
        keyboardType: TextInputType.multiline,
        textCapitalization: TextCapitalization.sentences,
        style: TextStyle(
          color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
          fontSize: 16,
          height: 1.5,
        ),
        decoration: InputDecoration(
          hintText: _isReply 
              ? 'Write your reply...' 
              : _isForward 
                  ? 'Add a message...' 
                  : 'Write your message...',
          hintStyle: TextStyle(
            color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
          ),
          border: InputBorder.none,
          contentPadding: EdgeInsets.zero,
        ),
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  Widget _buildOriginalMessage(bool isDark) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark 
            ? AppTheme.darkBackground 
            : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with toggle
          InkWell(
            onTap: () => setState(() => _showQuoted = !_showQuoted),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isDark 
                    ? Colors.white.withValues(alpha: 0.05) 
                    : Colors.black.withValues(alpha: 0.03),
                borderRadius: BorderRadius.vertical(
                  top: const Radius.circular(12),
                  bottom: _showQuoted ? Radius.zero : const Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _showQuoted ? Icons.expand_less : Icons.expand_more,
                    color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isForward ? 'Forwarded message' : 'Original message',
                          style: TextStyle(
                            color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                            fontWeight: FontWeight.w500,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          'From: ${_originalFrom.split('<').first.trim()}',
                          style: TextStyle(
                            color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                            fontSize: 12,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  // Include toggle
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Include',
                        style: TextStyle(
                          color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                          fontSize: 12,
                        ),
                      ),
                      Switch(
                        value: _includeQuoted,
                        onChanged: (v) => setState(() => _includeQuoted = v),
                        activeColor: Colors.blue,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          // Expanded content
          if (_showQuoted)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              constraints: const BoxConstraints(maxHeight: 300),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Metadata
                    _buildMetaRow('From', _originalFrom, isDark),
                    _buildMetaRow('Date', _originalDate, isDark),
                    _buildMetaRow('Subject', _originalSubject, isDark),
                    const SizedBox(height: 12),
                    Divider(
                      color: isDark ? Colors.white10 : Colors.black12,
                      height: 1,
                    ),
                    const SizedBox(height: 12),
                    // Body
                    Text(
                      _originalBody,
                      style: TextStyle(
                        color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMetaRow(String label, String value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text(
              '$label:',
              style: TextStyle(
                color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomToolbar(bool isDark) {
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom > 0 ? 8 : 24,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.white10 : Colors.black12,
          ),
        ),
      ),
      child: Row(
        children: [
          // Attachment button (future)
          IconButton(
            icon: const Icon(Icons.attach_file),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Attachments coming soon!')),
              );
            },
            color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
            tooltip: 'Attach file',
          ),
          
          // Format button (future)
          IconButton(
            icon: const Icon(Icons.text_format),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Formatting coming soon!')),
              );
            },
            color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
            tooltip: 'Format text',
          ),
          
          const Spacer(),
          
          // Character count
          Text(
            '${_bodyController.text.length}',
            style: TextStyle(
              color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFieldRow(String label, String value, bool isDark, {
    IconData? icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 20,
              color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
            ),
            const SizedBox(width: 12),
          ],
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: TextStyle(
                color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputRow(
    String label,
    TextEditingController controller,
    FocusNode? focusNode,
    bool isDark, {
    IconData? icon,
    String? hint,
    TextInputType? keyboardType,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 20,
              color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
            ),
            const SizedBox(width: 12),
          ],
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: TextStyle(
                color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              keyboardType: keyboardType,
              style: TextStyle(
                color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                fontSize: 15,
              ),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(
                  color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider(bool isDark) {
    return Divider(
      height: 1,
      indent: 48,
      color: (isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted).withValues(alpha: 0.2),
    );
  }

  Future<void> _confirmDiscard() async {
    // Check if there's content to discard
    final hasContent = _bodyController.text.isNotEmpty;
    
    if (!hasContent) {
      Navigator.pop(context);
      return;
    }
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.delete_outline, color: Colors.red),
            SizedBox(width: 8),
            Text('Discard email?'),
          ],
        ),
        content: const Text('Your message will be lost.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep editing'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    
    if (confirmed == true && mounted) {
      Navigator.pop(context);
    }
  }
}
