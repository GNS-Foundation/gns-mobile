/// Message Bubble - Individual Message Display
/// 
/// Displays a single message with styling, reactions, and actions.
/// NOW WITH: Light green incoming messages + Multi-select support!
/// 
/// Location: lib/ui/messages/message_bubble.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/comm/message_storage.dart';
import '../../core/comm/payload_types.dart';

class MessageBubble extends StatelessWidget {
  final GnsMessage message;
  final bool showAvatar;
  final VoidCallback? onReply;
  final Function(String emoji)? onReact;
  final VoidCallback? onCopy;
  final VoidCallback? onDelete;
  
  // 🆕 Multi-select support
  final bool isSelectionMode;
  final bool isSelected;
  final VoidCallback? onToggleSelection;
  final VoidCallback? onLongPress;

  const MessageBubble({
    super.key,
    required this.message,
    this.showAvatar = true,
    this.onReply,
    this.onReact,
    this.onCopy,
    this.onDelete,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.onToggleSelection,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final isOutgoing = message.isOutgoing;
    
    return GestureDetector(
      onTap: isSelectionMode ? onToggleSelection : null,
      onLongPress: isSelectionMode ? null : (onLongPress ?? () => _showMessageOptions(context)),
      child: Container(
        margin: EdgeInsets.only(
          top: showAvatar ? 8 : 2,
          bottom: 2,
          left: isOutgoing ? 60 : 0,
          right: isOutgoing ? 0 : 60,
        ),
        child: Row(
          mainAxisAlignment: isOutgoing ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // 🆕 Selection checkbox (left side for incoming)
            if (isSelectionMode && !isOutgoing) _buildCheckbox(),
            
            if (!isOutgoing && showAvatar && !isSelectionMode) _buildAvatar(),
            if (!isOutgoing && !showAvatar && !isSelectionMode) const SizedBox(width: 36),
            const SizedBox(width: 8),
            
            Flexible(child: _buildBubble(context)),
            
            const SizedBox(width: 8),
            
            // 🆕 Selection checkbox (right side for outgoing)
            if (isSelectionMode && isOutgoing) _buildCheckbox(),
            
            if (isOutgoing && !isSelectionMode) _buildStatus(),
          ],
        ),
      ),
    );
  }

  // 🆕 Checkbox for multi-select mode
  Widget _buildCheckbox() {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Checkbox(
        value: isSelected,
        onChanged: (_) => onToggleSelection?.call(),
        shape: const CircleBorder(),
        activeColor: const Color(0xFF3B82F6),
      ),
    );
  }

  Widget _buildAvatar() {
    final initial = (message.fromHandle ?? message.fromPublicKey)
        .replaceAll('@', '')
        .substring(0, 1)
        .toUpperCase();

    return CircleAvatar(
      radius: 14,
      backgroundColor: const Color(0xFF10B981).withOpacity(0.2), // Green tint for echo
      child: Text(
        initial,
        style: const TextStyle(
          color: Color(0xFF10B981), // Green color
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildBubble(BuildContext context) {
    final isOutgoing = message.isOutgoing;
    
    // Handle deleted messages
    if (message.isDeleted) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.block, size: 14, color: Colors.white38),
            const SizedBox(width: 8),
            Text(
              isOutgoing ? 'You deleted this message' : 'This message was deleted',
              style: const TextStyle(
                color: Colors.white38,
                fontStyle: FontStyle.italic,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    // 🆕 Selection highlight overlay
    Widget bubbleContent = Column(
      crossAxisAlignment: isOutgoing ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        // Reply preview if exists
        if (message.replyToId != null) _buildReplyPreview(),
        
        // Main bubble with NEW GREEN COLOR! 🎨
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            // 🎨 NEW COLOR: Light green for incoming messages!
            color: isOutgoing 
                ? const Color(0xFF3B82F6)           // Blue for outgoing (unchanged)
                : const Color(0xFFD4EDDA),          // 🆕 Light green for incoming!
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(isOutgoing ? 18 : 4),
              bottomRight: Radius.circular(isOutgoing ? 4 : 18),
            ),
            // 🆕 Selection highlight border
            border: isSelectionMode && isSelected
                ? Border.all(color: const Color(0xFF3B82F6), width: 2)
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildContent(),
              const SizedBox(height: 4),
              _buildTimestamp(),
            ],
          ),
        ),
        
        // Reactions
        if (message.reactions.isNotEmpty) _buildReactions(),
      ],
    );

    return bubbleContent;
  }

  Widget _buildReplyPreview() {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: const Border(
          left: BorderSide(color: Color(0xFF3B82F6), width: 2),
        ),
      ),
      child: const Text(
        'Reply to message',
        style: TextStyle(
          color: Colors.white38,
          fontSize: 12,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }

  Widget _buildContent() {
    // Text message
    final text = message.textContent;
    if (text != null && text.isNotEmpty) {
      return Text(
        text,
        style: TextStyle(
          // 🎨 Dark text for light green bubbles, white for blue
          color: message.isOutgoing 
              ? Colors.white 
              : const Color(0xFF1F2328), // Dark text on light green
          fontSize: 15,
          height: 1.3,
        ),
      );
    }

    // Location message
    if (message.payloadType == PayloadType.location) {
      return _buildLocationContent();
    }

    // Attachment
    if (message.payloadType == PayloadType.attachment) {
      return _buildAttachmentContent();
    }

    // Contact
    if (message.payloadType == PayloadType.contact) {
      return _buildContactContent();
    }

    // Fallback
    return Text(
      message.previewText,
      style: TextStyle(
        color: message.isOutgoing 
            ? Colors.white 
            : const Color(0xFF1F2328),
        fontSize: 15,
      ),
    );
  }

  Widget _buildLocationContent() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.location_on,
          color: message.isOutgoing ? Colors.white70 : const Color(0xFF1F2328),
          size: 20,
        ),
        const SizedBox(width: 8),
        Text(
          'Shared location',
          style: TextStyle(
            color: message.isOutgoing ? Colors.white : const Color(0xFF1F2328),
            fontSize: 15,
          ),
        ),
      ],
    );
  }

  Widget _buildAttachmentContent() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.attach_file,
          color: message.isOutgoing ? Colors.white70 : const Color(0xFF1F2328),
          size: 20,
        ),
        const SizedBox(width: 8),
        Text(
          'Attachment',
          style: TextStyle(
            color: message.isOutgoing ? Colors.white : const Color(0xFF1F2328),
            fontSize: 15,
          ),
        ),
      ],
    );
  }

  Widget _buildContactContent() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.person,
          color: message.isOutgoing ? Colors.white70 : const Color(0xFF1F2328),
          size: 20,
        ),
        const SizedBox(width: 8),
        Text(
          'Shared contact',
          style: TextStyle(
            color: message.isOutgoing ? Colors.white : const Color(0xFF1F2328),
            fontSize: 15,
          ),
        ),
      ],
    );
  }

  Widget _buildTimestamp() {
    final time = message.timestamp;
    final timeStr = '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

    return Text(
      timeStr,
      style: TextStyle(
        // 🎨 Adjusted timestamp color for light green bubbles
        color: message.isOutgoing 
            ? Colors.white60 
            : const Color(0xFF6E7681), // Darker gray for light green background
        fontSize: 11,
      ),
    );
  }

  Widget _buildStatus() {
    IconData icon;
    Color color;

    switch (message.status) {
      case MessageStatus.sending:
        icon = Icons.schedule;
        color = Colors.white38;
        break;
      case MessageStatus.sent:
        icon = Icons.done;
        color = Colors.white38;
        break;
      case MessageStatus.delivered:
        icon = Icons.done_all;
        color = Colors.white54;
        break;
      case MessageStatus.read:
        icon = Icons.done_all;
        color = const Color(0xFF3B82F6);
        break;
      case MessageStatus.failed:
        icon = Icons.error_outline;
        color = Colors.red;
        break;
      default:
        icon = Icons.done;
        color = Colors.white38;
    }

    return Icon(icon, size: 16, color: color);
  }

  Widget _buildReactions() {
    // Group reactions by emoji with count
    final reactionCounts = <String, int>{};
    for (final entry in message.reactions.entries) {
      final emoji = entry.key;
      final publicKeys = entry.value;
      reactionCounts[emoji] = publicKeys.length;
    }

    return Container(
      margin: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 4,
        children: reactionCounts.entries.map((entry) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF21262D),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(entry.key, style: const TextStyle(fontSize: 14)),
                if (entry.value > 1) ...[
                  const SizedBox(width: 4),
                  Text(
                    '${entry.value}',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  void _showMessageOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161B22),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Quick reactions
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: ['👍', '❤️', '😂', '😮', '😢', '🙏'].map((emoji) {
                  return InkWell(
                    onTap: () {
                      Navigator.pop(context);
                      onReact?.call(emoji);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: const BoxDecoration(
                        color: Color(0xFF21262D),
                        shape: BoxShape.circle,
                      ),
                      child: Text(emoji, style: const TextStyle(fontSize: 24)),
                    ),
                  );
                }).toList(),
              ),
            ),
            const Divider(color: Colors.white12),
            
            // Actions
            ListTile(
              leading: const Icon(Icons.reply, color: Colors.white70),
              title: const Text('Reply'),
              onTap: () {
                Navigator.pop(context);
                onReply?.call();
              },
            ),
            if (message.textContent != null)
              ListTile(
                leading: const Icon(Icons.copy, color: Colors.white70),
                title: const Text('Copy text'),
                onTap: () {
                  Navigator.pop(context);
                  _copyToClipboard(context);
                },
              ),
            // 🆕 Select messages option
            ListTile(
              leading: const Icon(Icons.checklist, color: Colors.white70),
              title: const Text('Select messages'),
              onTap: () {
                Navigator.pop(context);
                onLongPress?.call(); // Enter selection mode
              },
            ),
            ListTile(
              leading: const Icon(Icons.forward, color: Colors.white70),
              title: const Text('Forward'),
              onTap: () {
                Navigator.pop(context);
                // TODO: Implement forward
              },
            ),
            if (onDelete != null)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Delete', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  _confirmDelete(context);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _copyToClipboard(BuildContext context) {
    final text = message.textContent;
    if (text != null) {
      Clipboard.setData(ClipboardData(text: text));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Copied to clipboard'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        title: const Text('Delete Message?'),
        content: const Text('This will delete the message for everyone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              onDelete?.call();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
