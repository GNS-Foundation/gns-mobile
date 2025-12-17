/// Compose Area - Message Input with Hashtag Detection
/// 
/// Text input with send button, attachments, typing indicator,
/// and smart hashtag routing to facets.
/// 
/// Features:
/// - Normal messages (no hashtag)
/// - Post to facet (#existingfacet)
/// - Create new facet (#newfacet)
/// 
/// Location: lib/ui/messages/compose_area.dart

import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/comm/message_storage.dart';
import '../../core/profile/profile_facet.dart';
import '../../core/utils/hashtag_detector.dart';
import '../../core/theme/theme_service.dart';

class ComposeArea extends StatefulWidget {
  /// Send as normal message (no hashtag)
  final Future<void> Function(String text) onSendText;
  
  /// Post to a facet (hashtag detected) - NEW
  final Future<void> Function(String text, ProfileFacet facet)? onPostToFacet;
  
  /// Create new facet (unknown hashtag) - NEW
  /// Returns created facet or null if cancelled
  final Future<ProfileFacet?> Function(String suggestedName)? onCreateFacet;
  
  final Function(bool isTyping)? onTypingChanged;
  final GnsMessage? replyingTo;
  final VoidCallback? onCancelReply;
  final VoidCallback? onAttachmentPressed;
  final VoidCallback? onCameraPressed;
  final VoidCallback? onLocationPressed;
  
  /// Enable hashtag detection (default: true) - NEW
  final bool enableHashtagDetection;

  const ComposeArea({
    super.key,
    required this.onSendText,
    this.onPostToFacet,
    this.onCreateFacet,
    this.onTypingChanged,
    this.replyingTo,
    this.onCancelReply,
    this.onAttachmentPressed,
    this.onCameraPressed,
    this.onLocationPressed,
    this.enableHashtagDetection = true,
  });

  @override
  State<ComposeArea> createState() => _ComposeAreaState();
}

class _ComposeAreaState extends State<ComposeArea> with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final HashtagDetector _detector = HashtagDetector();
  
  bool _hasText = false;
  bool _sending = false;
  bool _showAttachments = false;
  
  // Hashtag detection state - NEW
  HashtagParseResult? _parseResult;
  Timer? _parseDebounce;
  
  // Typing indicator debounce
  Timer? _typingTimer;
  bool _isTyping = false;
  
  // Animation for routing indicator - NEW
  late AnimationController _indicatorAnimController;
  late Animation<double> _indicatorAnimation;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
    
    // Setup animation for routing indicator
    _indicatorAnimController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _indicatorAnimation = CurvedAnimation(
      parent: _indicatorAnimController,
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _typingTimer?.cancel();
    _parseDebounce?.cancel();
    _indicatorAnimController.dispose();
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
    
    // Detect hashtags (debounced) - NEW
    if (widget.enableHashtagDetection) {
      _parseDebounce?.cancel();
      _parseDebounce = Timer(const Duration(milliseconds: 150), _detectHashtags);
    }
  }
  
  /// Parse text for hashtags and determine routing - NEW
  Future<void> _detectHashtags() async {
    final text = _controller.text;
    
    if (!_detector.hasHashtag(text)) {
      if (_parseResult != null) {
        setState(() => _parseResult = null);
        _indicatorAnimController.reverse();
      }
      return;
    }
    
    final result = await _detector.parse(text);
    setState(() => _parseResult = result);
    
    if (result.hasHashtags) {
      _indicatorAnimController.forward();
    } else {
      _indicatorAnimController.reverse();
    }
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
      // Route based on hashtag detection - NEW
      if (_parseResult != null && _parseResult!.hasHashtags) {
        await _handleRoutedSend(_parseResult!);
      } else {
        // Normal message (original behavior)
        await widget.onSendText(text);
      }
      
      _controller.clear();
      setState(() {
        _hasText = false;
        _parseResult = null;
      });
      _indicatorAnimController.reverse();
    } finally {
      setState(() => _sending = false);
    }
  }
  
  /// Handle sending based on hashtag routing - NEW
  Future<void> _handleRoutedSend(HashtagParseResult result) async {
    switch (result.routing) {
      case ContentRouting.message:
        // Normal message (fallback)
        await widget.onSendText(result.originalText);
        break;
        
      case ContentRouting.facetPost:
        // Post to existing facet
        if (widget.onPostToFacet != null && result.targetFacet != null) {
          await widget.onPostToFacet!(result.cleanText, result.targetFacet!);
        } else {
          // Fallback to normal message if no handler
          await widget.onSendText(result.originalText);
        }
        break;
        
      case ContentRouting.createFacet:
        // Need to create facet first
        if (widget.onCreateFacet != null && result.primaryNewFacet != null) {
          final suggestedName = _detector.suggestFacetName(result.primaryNewFacet!);
          final newFacet = await widget.onCreateFacet!(suggestedName);
          
          if (newFacet != null && widget.onPostToFacet != null) {
            // Facet created, now post to it
            await widget.onPostToFacet!(result.cleanText, newFacet);
          }
          // If cancelled, don't send anything
        } else {
          // Fallback to normal message
          await widget.onSendText(result.originalText);
        }
        break;
    }
  }
  
  /// Handle create facet button tap - NEW
  Future<void> _handleCreateFacet() async {
    if (_parseResult == null || _parseResult!.primaryNewFacet == null) return;
    
    final suggestedName = _detector.suggestFacetName(_parseResult!.primaryNewFacet!);
    final newFacet = await widget.onCreateFacet?.call(suggestedName);
    
    if (newFacet != null) {
      // Update parse result with new facet
      _detector.clearCache();
      await _detectHashtags();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Routing indicator (animated) - NEW
        _buildRoutingIndicator(),
        
        // Reply preview
        if (widget.replyingTo != null) _buildReplyPreview(),
        
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
                    color: _showAttachments 
                        ? Theme.of(context).colorScheme.primary 
                        : AppTheme.textSecondary(context),
                  ),
                  onPressed: () => setState(() => _showAttachments = !_showAttachments),
                ),
                
                // Text input
                Expanded(child: _buildTextField()),
                
                // Create facet button (when needed) - NEW
                if (_parseResult?.needsNewFacet == true)
                  _buildCreateFacetButton(),
                
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
  
  /// Build routing indicator showing where content will go - NEW
  Widget _buildRoutingIndicator() {
    return SizeTransition(
      sizeFactor: _indicatorAnimation,
      child: _parseResult != null && _parseResult!.hasHashtags
          ? Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: _getRoutingColor().withOpacity(0.1),
                border: Border(
                  top: BorderSide(color: _getRoutingColor().withOpacity(0.3)),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _getRoutingIcon(),
                    size: 18,
                    color: _getRoutingColor(),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _getRoutingLabel(),
                      style: TextStyle(
                        color: _getRoutingColor(),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (_parseResult!.targetFacet != null)
                    Text(
                      _parseResult!.targetFacet!.emoji,
                      style: const TextStyle(fontSize: 16),
                    ),
                ],
              ),
            )
          : const SizedBox.shrink(),
    );
  }
  
  Color _getRoutingColor() {
    if (_parseResult == null) return Colors.grey;
    
    switch (_parseResult!.routing) {
      case ContentRouting.message:
        return Colors.grey;
      case ContentRouting.facetPost:
        return Colors.green;
      case ContentRouting.createFacet:
        return Colors.orange;
    }
  }
  
  IconData _getRoutingIcon() {
    if (_parseResult == null) return Icons.send;
    
    switch (_parseResult!.routing) {
      case ContentRouting.message:
        return Icons.send;
      case ContentRouting.facetPost:
        return Icons.public;
      case ContentRouting.createFacet:
        return Icons.add_circle_outline;
    }
  }
  
  String _getRoutingLabel() {
    if (_parseResult == null) return '';
    
    switch (_parseResult!.routing) {
      case ContentRouting.message:
        return 'Sending as message';
      case ContentRouting.facetPost:
        final facet = _parseResult!.targetFacet;
        return 'Posting to ${facet?.label ?? _parseResult!.primaryHashtag}';
      case ContentRouting.createFacet:
        return 'Create "${_parseResult!.primaryNewFacet}" facet?';
    }
  }
  
  /// Build create facet button - NEW
  Widget _buildCreateFacetButton() {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Material(
        color: Colors.orange,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: _handleCreateFacet,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add, size: 16, color: Colors.white),
                SizedBox(width: 4),
                Text(
                  'Create',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  /// Build reply preview - NEW (extracted from original)
  Widget _buildReplyPreview() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        border: Border(
          top: BorderSide(color: AppTheme.border(context)),
          left: BorderSide(color: Theme.of(context).colorScheme.primary, width: 3),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Replying to',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.replyingTo?.textContent ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTheme.textSecondary(context),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, color: AppTheme.textMuted(context)),
            onPressed: widget.onCancelReply,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 120),
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight(context),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          // Highlight border when hashtag detected - NEW
          color: _parseResult?.hasHashtags == true 
              ? _getRoutingColor().withOpacity(0.5)
              : AppTheme.border(context), 
          width: 1,
        ),
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
                // Updated hint text - NEW
                hintText: widget.replyingTo != null 
                    ? 'Reply...' 
                    : 'Type a message or #facet...',
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
    final canSend = _hasText && !_sending;
    final isCreateNeeded = _parseResult?.needsNewFacet == true;
    
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      child: Material(
        // Color changes based on routing - NEW
        color: canSend 
            ? (isCreateNeeded ? Colors.grey : _getRoutingColor())
            : AppTheme.surfaceLight(context),
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          // Disable send if create needed - NEW
          onTap: canSend && !isCreateNeeded ? _send : null,
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
                    // Icon changes for facet post - NEW
                    _parseResult?.isFacetPost == true ? Icons.publish : Icons.send,
                    color: canSend && !isCreateNeeded
                        ? Colors.white 
                        : AppTheme.textMuted(context),
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
