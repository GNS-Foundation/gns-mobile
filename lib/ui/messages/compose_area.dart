/// Compose Area - Message Input
/// 
/// Text input with send button, attachments, and typing indicator.
/// 
/// Location: lib/ui/messages/compose_area.dart

import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/comm/message_storage.dart';
import '../../core/theme/theme_service.dart';

class ComposeArea extends StatefulWidget {
  final Future<void> Function(String text) onSendText;
  final Function(bool isTyping)? onTypingChanged;
  final GnsMessage? replyingTo;
  final VoidCallback? onCancelReply;
  final VoidCallback? onAttachmentPressed;
  final VoidCallback? onCameraPressed;
  final VoidCallback? onLocationPressed;

  const ComposeArea({
    super.key,
    required this.onSendText,
    this.onTypingChanged,
    this.replyingTo,
    this.onCancelReply,
    this.onAttachmentPressed,
    this.onCameraPressed,
    this.onLocationPressed,
  });

  @override
  State<ComposeArea> createState() => _ComposeAreaState();
}

class _ComposeAreaState extends State<ComposeArea> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  
  bool _hasText = false;
  bool _sending = false;
  bool _showAttachments = false;
  
  // Typing indicator debounce
  Timer? _typingTimer;
  bool _isTyping = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _typingTimer?.cancel();
    super.dispose();
  }

  void _onTextChanged() {
    final hasText = _controller.text.trim().isNotEmpty;
    
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
    }

    // Handle typing indicator
    if (hasText && !_isTyping) {
      _isTyping = true;
      widget.onTypingChanged?.call(true);
    }
    
    // Reset typing timer
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 3), () {
      if (_isTyping) {
        _isTyping = false;
        widget.onTypingChanged?.call(false);
      }
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);
    
    // Stop typing indicator
    _typingTimer?.cancel();
    if (_isTyping) {
      _isTyping = false;
      widget.onTypingChanged?.call(false);
    }

    try {
      await widget.onSendText(text);
      _controller.clear();
      setState(() => _hasText = false);
    } finally {
      setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Attachment picker
        if (_showAttachments) _buildAttachmentPicker(),
        
        // Main compose area
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.surface(context),
            border: Border(top: BorderSide(color: AppTheme.border(context))),
          ),
          child: SafeArea(
            top: false,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Attachment button
                IconButton(
                  icon: Icon(
                    _showAttachments ? Icons.close : Icons.add,
                    color: _showAttachments ? Theme.of(context).colorScheme.primary : AppTheme.textSecondary(context),
                  ),
                  onPressed: () => setState(() => _showAttachments = !_showAttachments),
                ),
                
                // Text input
                Expanded(child: _buildTextField()),
                
                // Send button
                const SizedBox(width: 8),
                _buildSendButton(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTextField() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 120),
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight(context),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.border(context), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              maxLines: null,
              keyboardAppearance: Brightness.dark,  // Force dark keyboard on iOS
              textCapitalization: TextCapitalization.sentences,
              style: TextStyle(color: AppTheme.textPrimary(context), fontSize: 16),
              cursorColor: Theme.of(context).colorScheme.primary,
              decoration: InputDecoration(
                hintText: widget.replyingTo != null ? 'Reply...' : 'Type a message...',
                hintStyle: TextStyle(color: AppTheme.textMuted(context)),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              onSubmitted: (_) => _send(),
              onTapOutside: (_) => _focusNode.unfocus(),  // Dismiss keyboard on tap outside
            ),
          ),
          
          // Emoji button
          IconButton(
            icon: Icon(Icons.emoji_emotions_outlined, color: AppTheme.textMuted(context)),
            onPressed: _showEmojiPicker,
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildSendButton() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      child: Material(
        color: _hasText ? Theme.of(context).colorScheme.primary : AppTheme.surfaceLight(context),
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          onTap: _hasText && !_sending ? _send : null,
          borderRadius: BorderRadius.circular(24),
          child: Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            child: _sending
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.textPrimary(context),
                    ),
                  )
                : Icon(
                    Icons.send,
                    color: _hasText ? Theme.of(context).colorScheme.onPrimary : AppTheme.textMuted(context),
                    size: 22,
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildAttachmentPicker() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        border: Border(top: BorderSide(color: AppTheme.border(context))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _AttachmentOption(
            icon: Icons.photo,
            label: 'Photo',
            color: Colors.purple,
            onTap: widget.onAttachmentPressed ?? () {},
          ),
          _AttachmentOption(
            icon: Icons.camera_alt,
            label: 'Camera',
            color: Colors.pink,
            onTap: widget.onCameraPressed ?? () {},
          ),
          _AttachmentOption(
            icon: Icons.location_on,
            label: 'Location',
            color: Colors.green,
            onTap: widget.onLocationPressed ?? () {},
          ),
          _AttachmentOption(
            icon: Icons.insert_drive_file,
            label: 'File',
            color: Colors.blue,
            onTap: widget.onAttachmentPressed ?? () {},
          ),
          _AttachmentOption(
            icon: Icons.person,
            label: 'Contact',
            color: Colors.orange,
            onTap: () {},
          ),
        ],
      ),
    );
  }

  void _showEmojiPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface(context),
      builder: (context) => _EmojiPicker(
        onEmojiSelected: (emoji) {
          Navigator.pop(context);
          final text = _controller.text;
          final selection = _controller.selection;
          final newText = text.replaceRange(
            selection.start,
            selection.end,
            emoji,
          );
          _controller.text = newText;
          _controller.selection = TextSelection.collapsed(
            offset: selection.start + emoji.length,
          );
        },
      ),
    );
  }
}

class _AttachmentOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _AttachmentOption({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color),
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
      ),
    );
  }
}

class _EmojiPicker extends StatelessWidget {
  final Function(String emoji) onEmojiSelected;

  const _EmojiPicker({required this.onEmojiSelected});

  static const _emojis = [
    // Smileys
    '😀', '😃', '😄', '😁', '😆', '😅', '🤣', '😂',
    '🙂', '😊', '😇', '🥰', '😍', '🤩', '😘', '😗',
    '😚', '😙', '🥲', '😋', '😛', '😜', '🤪', '😝',
    '🤗', '🤭', '🤫', '🤔', '🤐', '🤨', '😐', '😑',
    '😶', '😏', '😒', '🙄', '😬', '😮‍💨', '🤥', '😌',
    '😔', '😪', '🤤', '😴', '😷', '🤒', '🤕', '🤢',
    // Gestures
    '👍', '👎', '👊', '✊', '🤛', '🤜', '🤝', '👏',
    '🙌', '👐', '🤲', '🤗', '🙏', '✌️', '🤞', '🤟',
    '🤘', '🤙', '👈', '👉', '👆', '👇', '☝️', '✋',
    '🤚', '🖐️', '🖖', '👋', '🤏', '✍️', '💪', '🦾',
    // Hearts
    '❤️', '🧡', '💛', '💚', '💙', '💜', '🖤', '🤍',
    '🤎', '💔', '❣️', '💕', '💞', '💓', '💗', '💖',
    '💘', '💝', '💟', '♥️', '😻', '💑', '💏', '👩‍❤️‍👨',
    // Objects
    '🔥', '✨', '⭐', '🌟', '💫', '🎉', '🎊', '🎁',
    '🎈', '🎀', '🏆', '🥇', '🎯', '💯', '✅', '❌',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 300,
      padding: const EdgeInsets.all(8),
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
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
              ),
              itemCount: _emojis.length,
              itemBuilder: (context, index) {
                return InkWell(
                  onTap: () => onEmojiSelected(_emojis[index]),
                  borderRadius: BorderRadius.circular(8),
                  child: Center(
                    child: Text(
                      _emojis[index],
                      style: const TextStyle(fontSize: 24),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
