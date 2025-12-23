/// GNS Payload Types - Content Type Registry
/// 
/// Defines all the payload types that can be sent through GNS envelopes.
/// Think of these like MIME types, but for GNS communications.
/// 
/// Location: lib/core/comm/payload_types.dart

import 'dart:convert';
import 'dart:typed_data';

/// Registry of payload type identifiers
/// 
/// Format: gns/<category>.<subtype>
/// 
/// Categories:
/// - text: Plain text, markdown, rich text
/// - email: Email-like structured messages
/// - attachment: Files and media
/// - location: Geographic data
/// - contact: Contact cards
/// - receipt: Delivery/read confirmations
/// - status: Typing, presence indicators
/// - system: System messages
abstract class PayloadType {
  // === TEXT MESSAGES ===
  
  /// Plain text message
  static const textPlain = 'gns/text.plain';
  
  /// Markdown formatted text
  static const textMarkdown = 'gns/text.markdown';
  
  /// Rich text (HTML subset)
  static const textRich = 'gns/text.rich';
  
  // === EMAIL-LIKE ===
  
  /// Full email structure with subject
  static const email = 'gns/email';
  
  /// Email reply (includes quoted content reference)
  static const emailReply = 'gns/email.reply';
  
  /// Forwarded email
  static const emailForward = 'gns/email.forward';
  
  // === ATTACHMENTS ===
  
  /// Generic file attachment
  static const attachment = 'gns/attachment';
  
  /// Image attachment with preview
  static const attachmentImage = 'gns/attachment.image';
  
  /// Video attachment
  static const attachmentVideo = 'gns/attachment.video';
  
  /// Audio/voice message
  static const attachmentAudio = 'gns/attachment.audio';
  
  /// Document (PDF, DOC, etc.)
  static const attachmentDocument = 'gns/attachment.document';
  
  // === LOCATION ===
  
  /// Single location point
  static const location = 'gns/location';
  
  /// Live location sharing
  static const locationLive = 'gns/location.live';
  
  // === CONTACT ===
  
  /// Contact card (vCard-like)
  static const contact = 'gns/contact';
  
  /// GNS identity card
  static const contactGns = 'gns/contact.gns';
  
  // === CALENDAR ===
  
  /// Calendar event
  static const event = 'gns/event';
  
  /// Event invitation
  static const eventInvite = 'gns/event.invite';
  
  /// Event response (accept/decline)
  static const eventResponse = 'gns/event.response';
  
  // === RECEIPTS ===
  
  /// Message was delivered to device
  static const receiptDelivered = 'gns/receipt.delivered';
  
  /// Message was read/seen
  static const receiptRead = 'gns/receipt.read';
  
  // === STATUS ===
  
  /// User is typing
  static const statusTyping = 'gns/status.typing';
  
  /// User presence (online/offline/away)
  static const statusPresence = 'gns/status.presence';
  
  // === MESSAGE ACTIONS ===
  
  /// Reaction to a message (emoji)
  static const reaction = 'gns/reaction';
  
  /// Edit a previous message
  static const edit = 'gns/edit';
  
  /// Delete/retract a message
  static const delete = 'gns/delete';
  
  // === SYSTEM ===
  
  /// Thread/group created
  static const systemThreadCreated = 'gns/system.thread_created';
  
  /// Participant added to thread
  static const systemParticipantAdded = 'gns/system.participant_added';
  
  /// Participant removed from thread
  static const systemParticipantRemoved = 'gns/system.participant_removed';
  
  /// Thread renamed
  static const systemThreadRenamed = 'gns/system.thread_renamed';
  
  // === FUTURE EXTENSIONS ===
  
  /// Payment request/invoice
  static const payment = 'gns/payment';
  
  /// Payment confirmation
  static const paymentConfirm = 'gns/payment.confirm';
  
  /// Poll/survey
  static const poll = 'gns/poll';
  
  /// Poll vote
  static const pollVote = 'gns/poll.vote';
}

// ============================================================
// PAYLOAD DATA STRUCTURES
// ============================================================

/// Base class for all payloads
abstract class GnsPayload {
  String get type;
  Map<String, dynamic> toJson();
  Uint8List toBytes() => Uint8List.fromList(utf8.encode(jsonEncode(toJson())));
  
  static GnsPayload fromJson(String type, Map<String, dynamic> json) {
    switch (type) {
      case PayloadType.textPlain:
      case PayloadType.textMarkdown:
      case PayloadType.textRich:
        return TextPayload.fromJson(json);
      case PayloadType.email:
      case PayloadType.emailReply:
      case PayloadType.emailForward:
        return EmailPayload.fromJson(json);
      case PayloadType.attachment:
      case PayloadType.attachmentImage:
      case PayloadType.attachmentVideo:
      case PayloadType.attachmentAudio:
      case PayloadType.attachmentDocument:
        return AttachmentPayload.fromJson(json);
      case PayloadType.location:
        return LocationPayload.fromJson(json);
      case PayloadType.contact:
      case PayloadType.contactGns:
        return ContactPayload.fromJson(json);
      case PayloadType.receiptDelivered:
      case PayloadType.receiptRead:
        return ReceiptPayload.fromJson(json);
      case PayloadType.statusTyping:
        return TypingPayload.fromJson(json);
      case PayloadType.reaction:
        return ReactionPayload.fromJson(json);
      case PayloadType.edit:
        return EditPayload.fromJson(json);
      case PayloadType.delete:
        return DeletePayload.fromJson(json);
      default:
        return GenericPayload(type: type, data: json);
    }
  }
}

/// Simple text message
class TextPayload extends GnsPayload {
  @override
  final String type;
  
  /// The text content
  final String text;
  
  /// Optional preview/summary (for long messages)
  final String? preview;
  
  /// Optional link previews
  final List<LinkPreview>? linkPreviews;

  TextPayload({
    this.type = PayloadType.textPlain,
    required this.text,
    this.preview,
    this.linkPreviews,
  });

  @override
  Map<String, dynamic> toJson() => {
    'text': text,
    'preview': preview,
    'linkPreviews': linkPreviews?.map((l) => l.toJson()).toList(),
  };

  factory TextPayload.fromJson(Map<String, dynamic> json) => TextPayload(
    text: json['text'] as String,
    preview: json['preview'] as String?,
    linkPreviews: json['linkPreviews'] != null
        ? (json['linkPreviews'] as List).map((l) => LinkPreview.fromJson(l)).toList()
        : null,
  );
  
  /// Create plain text
  factory TextPayload.plain(String text) => TextPayload(
    type: PayloadType.textPlain,
    text: text,
  );
  
  /// Create markdown text
  factory TextPayload.markdown(String text) => TextPayload(
    type: PayloadType.textMarkdown,
    text: text,
  );
}

/// Link preview data
class LinkPreview {
  final String url;
  final String? title;
  final String? description;
  final String? imageUrl;
  final String? siteName;

  LinkPreview({
    required this.url,
    this.title,
    this.description,
    this.imageUrl,
    this.siteName,
  });

  Map<String, dynamic> toJson() => {
    'url': url,
    'title': title,
    'description': description,
    'imageUrl': imageUrl,
    'siteName': siteName,
  };

  factory LinkPreview.fromJson(Map<String, dynamic> json) => LinkPreview(
    url: json['url'] as String,
    title: json['title'] as String?,
    description: json['description'] as String?,
    imageUrl: json['imageUrl'] as String?,
    siteName: json['siteName'] as String?,
  );
}

/// Email-like structured message (from gcrumbs.com gateway)
class EmailPayload extends GnsPayload {
  @override
  String get type => PayloadType.email;
  
  /// Email subject line
  final String subject;
  
  /// Email body content
  final String body;
  
  /// Body format: 'plain', 'markdown', 'html'
  final String bodyFormat;
  
  /// External sender email address (e.g., "friend@gmail.com")
  /// This is set when receiving emails from the gateway
  final String? from;
  
  /// Original message ID from email headers
  final String? messageId;
  
  /// When the email was received by the gateway (ISO timestamp)
  final String? receivedAt;
  
  /// Email reference chain for threading
  final List<String>? references;
  
  /// Attachment references
  final List<AttachmentRef>? attachments;
  
  /// Custom headers
  final Map<String, String>? customHeaders;
  
  /// For replies: ID of original message
  final String? inReplyTo;
  
  /// For replies: quoted content
  final String? quotedContent;

  EmailPayload({
    required this.subject,
    required this.body,
    this.bodyFormat = 'plain',
    this.from,
    this.messageId,
    this.receivedAt,
    this.references,
    this.attachments,
    this.customHeaders,
    this.inReplyTo,
    this.quotedContent,
  });

  @override
  Map<String, dynamic> toJson() => {
    'type': 'email',
    'subject': subject,
    'body': body,
    'bodyFormat': bodyFormat,
    'from': from,
    'messageId': messageId,
    'receivedAt': receivedAt,
    'references': references,
    'attachments': attachments?.map((a) => a.toJson()).toList(),
    'customHeaders': customHeaders,
    'inReplyTo': inReplyTo,
    'quotedContent': quotedContent,
  };

  factory EmailPayload.fromJson(Map<String, dynamic> json) => EmailPayload(
    subject: json['subject'] as String? ?? '(No subject)',
    body: json['body'] as String? ?? '',
    bodyFormat: json['bodyFormat'] as String? ?? 'plain',
    from: json['from'] as String?,
    messageId: json['messageId'] as String?,
    receivedAt: json['receivedAt'] as String?,
    references: json['references'] != null
        ? List<String>.from(json['references'] as List)
        : null,
    attachments: json['attachments'] != null
        ? (json['attachments'] as List).map((a) => AttachmentRef.fromJson(a)).toList()
        : null,
    customHeaders: json['customHeaders'] != null
        ? Map<String, String>.from(json['customHeaders'] as Map)
        : null,
    inReplyTo: json['inReplyTo'] as String?,
    quotedContent: json['quotedContent'] as String?,
  );
  
  /// Get display-friendly sender name (part before @)
  String get senderName {
    if (from == null || from!.isEmpty) return 'Unknown';
    final parts = from!.split('@');
    return parts.first;
  }
  
  /// Get sender domain (part after @)
  String get senderDomain {
    if (from == null || !from!.contains('@')) return '';
    final parts = from!.split('@');
    return parts.length > 1 ? parts.last : '';
  }
  
  /// Get formatted sender display (name + domain)
  String get senderDisplay {
    if (from == null || from!.isEmpty) return 'Unknown sender';
    return from!;
  }
}

/// Reference to an attachment (metadata only, content stored separately)
class AttachmentRef {
  final String id;
  final String filename;
  final String mimeType;
  final int size;
  final String checksum;  // SHA-256 of content
  final String? thumbnailBase64;  // For images/videos
  final int? width;
  final int? height;
  final int? durationMs;  // For audio/video

  AttachmentRef({
    required this.id,
    required this.filename,
    required this.mimeType,
    required this.size,
    required this.checksum,
    this.thumbnailBase64,
    this.width,
    this.height,
    this.durationMs,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'filename': filename,
    'mimeType': mimeType,
    'size': size,
    'checksum': checksum,
    'thumbnailBase64': thumbnailBase64,
    'width': width,
    'height': height,
    'durationMs': durationMs,
  };

  factory AttachmentRef.fromJson(Map<String, dynamic> json) => AttachmentRef(
    id: json['id'] as String,
    filename: json['filename'] as String,
    mimeType: json['mimeType'] as String,
    size: json['size'] as int,
    checksum: json['checksum'] as String,
    thumbnailBase64: json['thumbnailBase64'] as String?,
    width: json['width'] as int?,
    height: json['height'] as int?,
    durationMs: json['durationMs'] as int?,
  );

  /// Is this an image?
  bool get isImage => mimeType.startsWith('image/');
  
  /// Is this a video?
  bool get isVideo => mimeType.startsWith('video/');
  
  /// Is this audio?
  bool get isAudio => mimeType.startsWith('audio/');
  
  /// Human-readable size
  String get sizeFormatted {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

/// File attachment payload (includes the actual content)
class AttachmentPayload extends GnsPayload {
  @override
  String get type => PayloadType.attachment;
  
  final AttachmentRef ref;
  final String contentBase64;  // Base64 encoded content
  final String? caption;

  AttachmentPayload({
    required this.ref,
    required this.contentBase64,
    this.caption,
  });

  @override
  Map<String, dynamic> toJson() => {
    'ref': ref.toJson(),
    'contentBase64': contentBase64,
    'caption': caption,
  };

  factory AttachmentPayload.fromJson(Map<String, dynamic> json) => AttachmentPayload(
    ref: AttachmentRef.fromJson(json['ref'] as Map<String, dynamic>),
    contentBase64: json['contentBase64'] as String,
    caption: json['caption'] as String?,
  );
  
  Uint8List get contentBytes => base64Decode(contentBase64);
}

/// Location share
class LocationPayload extends GnsPayload {
  @override
  String get type => PayloadType.location;
  
  final double latitude;
  final double longitude;
  final double? altitude;
  final double? accuracy;
  final String? label;
  final String? address;
  final String? h3Cell;  // GNS H3 cell reference

  LocationPayload({
    required this.latitude,
    required this.longitude,
    this.altitude,
    this.accuracy,
    this.label,
    this.address,
    this.h3Cell,
  });

  @override
  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'altitude': altitude,
    'accuracy': accuracy,
    'label': label,
    'address': address,
    'h3Cell': h3Cell,
  };

  factory LocationPayload.fromJson(Map<String, dynamic> json) => LocationPayload(
    latitude: (json['latitude'] as num).toDouble(),
    longitude: (json['longitude'] as num).toDouble(),
    altitude: (json['altitude'] as num?)?.toDouble(),
    accuracy: (json['accuracy'] as num?)?.toDouble(),
    label: json['label'] as String?,
    address: json['address'] as String?,
    h3Cell: json['h3Cell'] as String?,
  );
}

/// Contact card
class ContactPayload extends GnsPayload {
  @override
  String get type => PayloadType.contact;
  
  final String? displayName;
  final String? publicKey;  // For GNS contacts
  final String? handle;     // @handle
  final String? email;
  final String? phone;
  final String? avatarBase64;
  final Map<String, String>? customFields;

  ContactPayload({
    this.displayName,
    this.publicKey,
    this.handle,
    this.email,
    this.phone,
    this.avatarBase64,
    this.customFields,
  });

  @override
  Map<String, dynamic> toJson() => {
    'displayName': displayName,
    'publicKey': publicKey,
    'handle': handle,
    'email': email,
    'phone': phone,
    'avatarBase64': avatarBase64,
    'customFields': customFields,
  };

  factory ContactPayload.fromJson(Map<String, dynamic> json) => ContactPayload(
    displayName: json['displayName'] as String?,
    publicKey: json['publicKey'] as String?,
    handle: json['handle'] as String?,
    email: json['email'] as String?,
    phone: json['phone'] as String?,
    avatarBase64: json['avatarBase64'] as String?,
    customFields: json['customFields'] != null
        ? Map<String, String>.from(json['customFields'] as Map)
        : null,
  );
}

/// Delivery/read receipt
class ReceiptPayload extends GnsPayload {
  @override
  final String type;
  
  /// IDs of messages being acknowledged
  final List<String> messageIds;
  
  /// When the action occurred
  final int timestamp;

  ReceiptPayload({
    required this.type,
    required this.messageIds,
    required this.timestamp,
  });

  @override
  Map<String, dynamic> toJson() => {
    'messageIds': messageIds,
    'timestamp': timestamp,
  };

  factory ReceiptPayload.fromJson(Map<String, dynamic> json) => ReceiptPayload(
    type: PayloadType.receiptRead, // Default, actual type from envelope
    messageIds: List<String>.from(json['messageIds'] as List),
    timestamp: json['timestamp'] as int,
  );
  
  factory ReceiptPayload.delivered(List<String> messageIds) => ReceiptPayload(
    type: PayloadType.receiptDelivered,
    messageIds: messageIds,
    timestamp: DateTime.now().millisecondsSinceEpoch,
  );
  
  factory ReceiptPayload.read(List<String> messageIds) => ReceiptPayload(
    type: PayloadType.receiptRead,
    messageIds: messageIds,
    timestamp: DateTime.now().millisecondsSinceEpoch,
  );
}

/// Typing indicator
class TypingPayload extends GnsPayload {
  @override
  String get type => PayloadType.statusTyping;
  
  final String threadId;
  final bool isTyping;

  TypingPayload({
    required this.threadId,
    required this.isTyping,
  });

  @override
  Map<String, dynamic> toJson() => {
    'threadId': threadId,
    'isTyping': isTyping,
  };

  factory TypingPayload.fromJson(Map<String, dynamic> json) => TypingPayload(
    threadId: json['threadId'] as String,
    isTyping: json['isTyping'] as bool,
  );
}

/// Emoji reaction
class ReactionPayload extends GnsPayload {
  @override
  String get type => PayloadType.reaction;
  
  final String messageId;
  final String emoji;
  final bool remove;  // true to remove reaction

  ReactionPayload({
    required this.messageId,
    required this.emoji,
    this.remove = false,
  });

  @override
  Map<String, dynamic> toJson() => {
    'messageId': messageId,
    'emoji': emoji,
    'remove': remove,
  };

  factory ReactionPayload.fromJson(Map<String, dynamic> json) => ReactionPayload(
    messageId: json['messageId'] as String,
    emoji: json['emoji'] as String,
    remove: json['remove'] as bool? ?? false,
  );
}

/// Edit previous message
class EditPayload extends GnsPayload {
  @override
  String get type => PayloadType.edit;
  
  final String messageId;
  final String newText;
  final int editedAt;

  EditPayload({
    required this.messageId,
    required this.newText,
    required this.editedAt,
  });

  @override
  Map<String, dynamic> toJson() => {
    'messageId': messageId,
    'newText': newText,
    'editedAt': editedAt,
  };

  factory EditPayload.fromJson(Map<String, dynamic> json) => EditPayload(
    messageId: json['messageId'] as String,
    newText: json['newText'] as String,
    editedAt: json['editedAt'] as int,
  );
}

/// Delete/retract message
class DeletePayload extends GnsPayload {
  @override
  String get type => PayloadType.delete;
  
  final String messageId;
  final bool deleteForEveryone;  // vs just for self

  DeletePayload({
    required this.messageId,
    this.deleteForEveryone = false,
  });

  @override
  Map<String, dynamic> toJson() => {
    'messageId': messageId,
    'deleteForEveryone': deleteForEveryone,
  };

  factory DeletePayload.fromJson(Map<String, dynamic> json) => DeletePayload(
    messageId: json['messageId'] as String,
    deleteForEveryone: json['deleteForEveryone'] as bool? ?? false,
  );
}

/// Generic payload for unknown types
class GenericPayload extends GnsPayload {
  @override
  final String type;
  final Map<String, dynamic> data;

  GenericPayload({required this.type, required this.data});

  @override
  Map<String, dynamic> toJson() => data;
}
