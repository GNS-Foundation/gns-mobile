/// Email Service - Email Operations
/// 
/// Handles email-specific operations:
/// - Delete emails (local)
/// - Mark read/unread
/// - Reply to emails (via backend SMTP)
/// - Forward emails
/// 
/// Location: lib/core/email/email_service.dart

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../comm/message_storage.dart';
import '../comm/payload_types.dart';
import '../gns/identity_wallet.dart';

/// Email message with enhanced metadata
class EmailMessage {
  final String id;
  final String threadId;
  final String from;
  final String to;
  final String subject;
  final String body;
  final String bodyFormat; // 'plain', 'html'
  final DateTime receivedAt;
  final bool isRead;
  final bool isStarred;
  final bool isDeleted;
  final List<EmailAttachment> attachments;
  final Map<String, String> headers;
  
  EmailMessage({
    required this.id,
    required this.threadId,
    required this.from,
    required this.to,
    required this.subject,
    required this.body,
    this.bodyFormat = 'plain',
    required this.receivedAt,
    this.isRead = false,
    this.isStarred = false,
    this.isDeleted = false,
    this.attachments = const [],
    this.headers = const {},
  });
  
  /// Create from GnsMessage
  factory EmailMessage.fromGnsMessage(GnsMessage msg) {
    String from = '';
    String to = '';
    String subject = '(No subject)';
    String body = '';
    String bodyFormat = 'plain';
    List<EmailAttachment> attachments = [];
    Map<String, String> headers = {};
    
    // Extract from EmailPayload
    if (msg.payload is EmailPayload) {
      final email = msg.payload as EmailPayload;
      subject = email.subject;
      body = email.body;
      bodyFormat = email.bodyFormat;
      
      // Convert attachment refs
      if (email.attachments != null) {
        attachments = email.attachments!.map((ref) => EmailAttachment(
          filename: ref.filename,
          mimeType: ref.mimeType,
          size: ref.size,
          url: ref.id, 
        )).toList();
      }
    }
    
    // Extract metadata
    final meta = msg.metadata;
    if (meta.containsKey('from')) from = meta['from'] as String? ?? '';
    if (meta.containsKey('to')) to = meta['to'] as String? ?? '';
    if (meta.containsKey('subject') && subject == '(No subject)') {
      subject = meta['subject'] as String? ?? subject;
    }
    
    // Try payload JSON
    try {
      final json = msg.payload.toJson();
      if (json.containsKey('from')) from = json['from'] as String? ?? from;
      if (json.containsKey('to')) to = json['to'] as String? ?? to;
      if (json.containsKey('subject')) subject = json['subject'] as String? ?? subject;
      if (json.containsKey('body')) body = json['body'] as String? ?? body;
      if (json.containsKey('bodyFormat')) bodyFormat = json['bodyFormat'] as String? ?? bodyFormat;
      if (json.containsKey('headers')) {
        headers = Map<String, String>.from(json['headers'] as Map? ?? {});
      }
    } catch (_) {}
    
    return EmailMessage(
      id: msg.id,
      threadId: msg.threadId,
      from: from,
      to: to,
      subject: subject,
      body: body,
      bodyFormat: bodyFormat,
      receivedAt: msg.timestamp,
      isRead: msg.status == MessageStatus.read,
      isDeleted: msg.isDeleted,
      attachments: attachments,
      headers: headers,
    );
  }
  
  /// Get sender display name
  String get senderName {
    // Try to extract name from "Name <email>" format
    final match = RegExp(r'^([^<]+)<([^>]+)>$').firstMatch(from.trim());
    if (match != null) {
      return match.group(1)!.trim();
    }
    // Return part before @
    return from.split('@').first;
  }
  
  /// Get sender email only
  String get senderEmail {
    final match = RegExp(r'<([^>]+)>$').firstMatch(from.trim());
    if (match != null) {
      return match.group(1)!;
    }
    return from;
  }
  
  /// Get sender domain
  String get senderDomain {
    final email = senderEmail;
    if (email.contains('@')) {
      return email.split('@').last;
    }
    return '';
  }
  
  /// Get preview text
  String get preview {
    final text = bodyFormat == 'html' ? _stripHtml(body) : body;
    if (text.length > 100) {
      return '${text.substring(0, 100)}...';
    }
    return text;
  }
  
  String _stripHtml(String html) {
    return html
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<p\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .trim();
  }
  
  EmailMessage copyWith({
    bool? isRead,
    bool? isStarred,
    bool? isDeleted,
  }) {
    return EmailMessage(
      id: id,
      threadId: threadId,
      from: from,
      to: to,
      subject: subject,
      body: body,
      bodyFormat: bodyFormat,
      receivedAt: receivedAt,
      isRead: isRead ?? this.isRead,
      isStarred: isStarred ?? this.isStarred,
      isDeleted: isDeleted ?? this.isDeleted,
      attachments: attachments,
      headers: headers,
    );
  }
}

/// Email attachment
class EmailAttachment {
  final String filename;
  final String mimeType;
  final int size;
  final String? url;
  final String? base64Content;
  
  EmailAttachment({
    required this.filename,
    required this.mimeType,
    required this.size,
    this.url,
    this.base64Content,
  });
  
  /// Get human-readable size
  String get sizeFormatted {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  
  /// Get icon for file type
  String get iconName {
    if (mimeType.startsWith('image/')) return 'image';
    if (mimeType.startsWith('video/')) return 'video';
    if (mimeType.startsWith('audio/')) return 'audio';
    if (mimeType.contains('pdf')) return 'pdf';
    if (mimeType.contains('word') || mimeType.contains('document')) return 'doc';
    if (mimeType.contains('sheet') || mimeType.contains('excel')) return 'spreadsheet';
    if (mimeType.contains('zip') || mimeType.contains('archive')) return 'archive';
    return 'file';
  }
}

/// Email Service singleton
class EmailService {
  static final EmailService _instance = EmailService._internal();
  factory EmailService() => _instance;
  EmailService._internal();
  
  static const String _baseUrl = 'https://gns-browser-production.up.railway.app';
  
  MessageStorage? _storage;
  IdentityWallet? _wallet;
  
  /// Initialize with wallet
  Future<void> initialize(IdentityWallet wallet) async {
    _wallet = wallet;
    if (wallet.publicKey != null) {
      _storage = MessageStorage();
      if (!_storage!.isInitialized) {
        // Storage initialization is handled by CommunicationService
      }
    }
  }
  
  // ============================================
  // LOCAL OPERATIONS
  // ============================================
  
  /// Mark email as read
  Future<void> markAsRead(String messageId) async {
    if (_storage == null || !_storage!.isInitialized) return;
    
    await _storage!.updateMessageStatus(messageId, MessageStatus.read);
    debugPrint('📧 Marked email $messageId as read');
  }
  
  /// Mark email as unread
  Future<void> markAsUnread(String messageId) async {
    if (_storage == null || !_storage!.isInitialized) return;
    
    await _storage!.updateMessageStatus(messageId, MessageStatus.delivered);
    debugPrint('📧 Marked email $messageId as unread');
  }
  
  /// Delete email (soft delete - marks as deleted)
  Future<void> deleteEmail(String messageId) async {
    if (_storage == null || !_storage!.isInitialized) return;
    
    await _storage!.markMessageDeleted(messageId);
    debugPrint('🗑️ Deleted email $messageId');
  }
  
  /// Delete multiple emails
  Future<void> deleteEmails(List<String> messageIds) async {
    for (final id in messageIds) {
      await deleteEmail(id);
    }
  }
  
  /// Star/unstar email (uses reactions internally)
  Future<void> toggleStar(String messageId, String userPublicKey) async {
    if (_storage == null || !_storage!.isInitialized) return;
    
    final message = await _storage!.getMessage(messageId);
    if (message == null) return;
    
    final isStarred = message.reactions.containsKey('⭐');
    
    if (isStarred) {
      await _storage!.removeReaction(messageId, '⭐', userPublicKey);
      debugPrint('⭐ Unstarred email $messageId');
    } else {
      await _storage!.addReaction(messageId, '⭐', userPublicKey);
      debugPrint('⭐ Starred email $messageId');
    }
  }
  
  // ============================================
  // REMOTE OPERATIONS (via Backend)
  // ============================================
  
  /// Send reply to email
  /// 
  /// This sends via the backend SMTP gateway
  Future<bool> sendReply({
    required String originalMessageId,
    required String toEmail,
    required String subject,
    required String body,
    String? inReplyToMessageId,
  }) async {
    if (_wallet?.publicKey == null) {
      debugPrint('❌ Cannot send reply: no wallet');
      return false;
    }
    
    try {
      final handle = await _wallet!.getCurrentHandle();
      if (handle == null) {
        debugPrint('❌ Cannot send reply: no handle claimed');
        return false;
      }
      
      // Sign the request
      final timestamp = DateTime.now().toUtc().toIso8601String();
      final signData = '$timestamp:$toEmail:$subject';
      final signature = await _wallet!.signString(signData) ?? '';
      
      final response = await http.post(
        Uri.parse('$_baseUrl/email/send'),
        headers: {
          'Content-Type': 'application/json',
          'X-GNS-PublicKey': _wallet!.publicKey ?? '',
          'X-GNS-Signature': signature,
          'X-GNS-Timestamp': timestamp,
        },
        body: jsonEncode({
          'from': '$handle@gcrumbs.com',
          'to': toEmail,
          'subject': subject,
          'body': body,
          'bodyFormat': 'plain',
          'inReplyTo': inReplyToMessageId,
          'references': inReplyToMessageId != null ? [inReplyToMessageId] : null,
        }),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          debugPrint('✅ Email sent successfully');
          return true;
        } else {
          debugPrint('❌ Failed to send email: ${data['error']}');
          return false;
        }
      } else {
        debugPrint('❌ Failed to send email: HTTP ${response.statusCode}');
        return false;
      }
    } catch (e) {
      debugPrint('❌ Failed to send email: $e');
      return false;
    }
  }
  
  /// Forward email
  Future<bool> forwardEmail({
    required String originalMessageId,
    required String toEmail,
    required String originalFrom,
    required String originalSubject,
    required String originalBody,
    String? additionalMessage,
  }) async {
    // Build forwarded body
    final forwardedBody = '''
${additionalMessage ?? ''}

---------- Forwarded message ----------
From: $originalFrom
Subject: $originalSubject

$originalBody
''';
    
    return sendReply(
      originalMessageId: originalMessageId,
      toEmail: toEmail,
      subject: 'Fwd: $originalSubject',
      body: forwardedBody.trim(),
    );
  }
  
  /// Compose new email
  Future<bool> sendNewEmail({
    required String toEmail,
    required String subject,
    required String body,
  }) async {
    return sendReply(
      originalMessageId: '',
      toEmail: toEmail,
      subject: subject,
      body: body,
    );
  }
}
