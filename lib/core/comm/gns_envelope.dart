/// GNS Envelope - Universal Communication Wrapper
/// 
/// The envelope is the universal container for all GNS communications.
/// Whether it's a chat message, email, file, or payment - they all
/// use the same envelope structure with different payload types.
/// 
/// Location: lib/core/comm/gns_envelope.dart

import 'dart:convert';
import 'package:uuid/uuid.dart';

/// Thread type enumeration
enum ThreadType {
  direct,
  group,
  channel,
}

/// Universal communication envelope
/// 
/// This wraps ANY type of communication between GNS identities.
/// The envelope handles routing, encryption metadata, and signatures
/// while remaining agnostic to the actual payload content.
class GnsEnvelope {
  // === IDENTITY ===
  
  /// Unique envelope ID (UUID v4)
  final String id;
  
  /// Protocol version for future compatibility
  final int version;
  
  // === ROUTING ===
  
  /// Sender's GNS public key (hex encoded)
  final String fromPublicKey;
  
  /// Sender's @handle (optional, for display)
  final String? fromHandle;
  
  /// Primary recipient public keys
  final List<String> toPublicKeys;
  
  /// CC recipients (visible to all)
  final List<String>? ccPublicKeys;
  
  /// BCC recipients (hidden, separate envelopes sent)
  final List<String>? bccPublicKeys;
  
  // === CONTENT ===
  
  /// Payload type identifier (MIME-like)
  /// Examples: 'gns/text.plain', 'gns/email', 'gns/attachment'
  final String payloadType;
  
  /// Encrypted payload (Base64 encoded)
  final String encryptedPayload;
  
  /// Size of decrypted payload in bytes
  final int payloadSize;
  
  // === THREADING ===
  
  /// Conversation/thread ID (groups related messages)
  final String? threadId;
  
  /// ID of envelope being replied to
  final String? replyToId;
  
  /// ID of envelope being forwarded
  final String? forwardOfId;
  
  // === TIMING ===
  
  /// When the envelope was created (milliseconds since epoch)
  final int timestamp;
  
  /// When the envelope expires (optional, milliseconds since epoch)
  final int? expiresAt;
  
  // === CRYPTOGRAPHY ===
  
  /// Ephemeral public key for key exchange (Base64)
  /// Used by recipient to derive decryption key
  final String ephemeralPublicKey;
  
  /// For multi-recipient: map of recipientPubKey -> encrypted symmetric key
  /// If null, single-recipient mode using ephemeral key exchange
  final Map<String, String>? recipientKeys;
  
  /// Nonce used for encryption (Base64)
  final String nonce;
  
  /// Ed25519 signature of envelope hash (Base64)
  final String signature;
  
  // === METADATA ===
  
  /// Priority level: 0=low, 1=normal, 2=high, 3=urgent
  final int priority;
  
  /// Request read receipt from recipient
  final bool requestReadReceipt;
  
  /// Extensible headers for future use
  final Map<String, dynamic> headers;

  GnsEnvelope({
    required this.id,
    this.version = 1,
    required this.fromPublicKey,
    this.fromHandle,
    required this.toPublicKeys,
    this.ccPublicKeys,
    this.bccPublicKeys,
    required this.payloadType,
    required this.encryptedPayload,
    required this.payloadSize,
    this.threadId,
    this.replyToId,
    this.forwardOfId,
    required this.timestamp,
    this.expiresAt,
    required this.ephemeralPublicKey,
    this.recipientKeys,
    required this.nonce,
    required this.signature,
    this.priority = 1,
    this.requestReadReceipt = false,
    this.headers = const {},
  });

  /// Create a new envelope ID
  static String generateId() => const Uuid().v4();

  /// Check if envelope has expired
  bool get isExpired {
    if (expiresAt == null) return false;
    return DateTime.now().millisecondsSinceEpoch > expiresAt!;
  }

  /// Get timestamp as DateTime
  DateTime get timestampDate => DateTime.fromMillisecondsSinceEpoch(timestamp);

  /// Get expiry as DateTime
  DateTime? get expiryDate => expiresAt != null 
      ? DateTime.fromMillisecondsSinceEpoch(expiresAt!) 
      : null;

  /// Check if this is a group message
  bool get isGroupMessage => toPublicKeys.length > 1 || (ccPublicKeys?.isNotEmpty ?? false);

  /// Get all recipients (to + cc, not bcc)
  List<String> get allVisibleRecipients => [
    ...toPublicKeys,
    ...?ccPublicKeys,
  ];

  /// Data to be signed (everything except signature)
  Map<String, dynamic> get signableData => {
    'id': id,
    'version': version,
    'fromPublicKey': fromPublicKey,
    'toPublicKeys': toPublicKeys,
    'ccPublicKeys': ccPublicKeys,
    'payloadType': payloadType,
    'encryptedPayload': encryptedPayload,
    'payloadSize': payloadSize,
    'threadId': threadId,
    'replyToId': replyToId,
    'forwardOfId': forwardOfId,
    'timestamp': timestamp,
    'expiresAt': expiresAt,
    'ephemeralPublicKey': ephemeralPublicKey,
    'recipientKeys': recipientKeys,
    'nonce': nonce,
    'priority': priority,
  };

  /// Canonical JSON for signing (sorted keys, no whitespace)
  String get canonicalJson {
    final data = signableData;
    return _canonicalize(data);
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() => {
    'id': id,
    'version': version,
    'fromPublicKey': fromPublicKey,
    'fromHandle': fromHandle,
    'toPublicKeys': toPublicKeys,
    'ccPublicKeys': ccPublicKeys,
    'bccPublicKeys': bccPublicKeys,
    'payloadType': payloadType,
    'encryptedPayload': encryptedPayload,
    'payloadSize': payloadSize,
    'threadId': threadId,
    'replyToId': replyToId,
    'forwardOfId': forwardOfId,
    'timestamp': timestamp,
    'expiresAt': expiresAt,
    'ephemeralPublicKey': ephemeralPublicKey,
    'recipientKeys': recipientKeys,
    'nonce': nonce,
    'signature': signature,
    'priority': priority,
    'requestReadReceipt': requestReadReceipt,
    'headers': headers,
  };

  /// Create from JSON - handles both camelCase and snake_case field names
  /// Also handles envelope_metadata from server responses
  factory GnsEnvelope.fromJson(Map<String, dynamic> json) {
    // Handle envelope_metadata if present (server format)
    final metadata = json['envelope_metadata'] as Map<String, dynamic>? ?? {};
    
    // Helper to get field from either main json, metadata, or with snake_case fallback
    String? getString(String camelCase, String snakeCase) {
      return json[camelCase] as String? ?? 
             json[snakeCase] as String? ?? 
             metadata[camelCase] as String? ?? 
             metadata[snakeCase] as String?;
    }
    
    int? getInt(String camelCase, String snakeCase) {
      return json[camelCase] as int? ?? 
             json[snakeCase] as int? ?? 
             metadata[camelCase] as int? ?? 
             metadata[snakeCase] as int?;
    }
    
    return GnsEnvelope(
      id: getString('id', 'id') ?? '',
      version: getInt('version', 'version') ?? 1,
      fromPublicKey: getString('fromPublicKey', 'from_pk') ?? '',
      fromHandle: getString('fromHandle', 'from_handle'),
      toPublicKeys: _parseStringList(json['toPublicKeys'] ?? json['to_pk'] ?? json['to_pks']),
      ccPublicKeys: json['ccPublicKeys'] != null 
          ? List<String>.from(json['ccPublicKeys'] as List) 
          : null,
      bccPublicKeys: json['bccPublicKeys'] != null 
          ? List<String>.from(json['bccPublicKeys'] as List) 
          : null,
      payloadType: getString('payloadType', 'payload_type') ?? 'text',
      encryptedPayload: getString('encryptedPayload', 'encrypted_payload') ?? '',
      payloadSize: getInt('payloadSize', 'payload_size') ?? 0,
      threadId: getString('threadId', 'thread_id'),
      replyToId: getString('replyToId', 'reply_to_id'),
      forwardOfId: getString('forwardOfId', 'forward_of_id'),
      timestamp: getInt('timestamp', 'timestamp') ?? DateTime.now().millisecondsSinceEpoch,
      expiresAt: getInt('expiresAt', 'expires_at'),
      ephemeralPublicKey: getString('ephemeralPublicKey', 'ephemeral_pk') ?? '',
      recipientKeys: json['recipientKeys'] != null
          ? Map<String, String>.from(json['recipientKeys'] as Map)
          : (json['recipient_keys'] != null 
              ? Map<String, String>.from(json['recipient_keys'] as Map)
              : null),
      nonce: getString('nonce', 'nonce') ?? '',
      signature: getString('signature', 'signature') ?? '',
      priority: getInt('priority', 'priority') ?? 1,
      requestReadReceipt: json['requestReadReceipt'] as bool? ?? 
                          json['request_read_receipt'] as bool? ?? false,
      headers: json['headers'] != null 
          ? Map<String, dynamic>.from(json['headers'] as Map)
          : {},
    );
  }
  
  /// Helper to parse string list from various formats
  static List<String> _parseStringList(dynamic value) {
    if (value == null) return [];
    if (value is String) return [value];
    if (value is List) return List<String>.from(value);
    return [];
  }

  /// Serialize to Base64 for transport
  String toBase64() => base64Encode(utf8.encode(jsonEncode(toJson())));

  /// Deserialize from Base64
  factory GnsEnvelope.fromBase64(String encoded) {
    final json = jsonDecode(utf8.decode(base64Decode(encoded)));
    return GnsEnvelope.fromJson(json as Map<String, dynamic>);
  }

  @override
  String toString() => 'GnsEnvelope(id: $id, type: $payloadType, from: ${fromHandle ?? fromPublicKey.substring(0, 8)}...)';
}

/// Builder for creating envelopes
class GnsEnvelopeBuilder {
  String? _fromPublicKey;
  String? _fromHandle;
  List<String> _toPublicKeys = [];
  List<String>? _ccPublicKeys;
  List<String>? _bccPublicKeys;
  String? _payloadType;
  String? _encryptedPayload;
  int _payloadSize = 0;
  String? _threadId;
  String? _replyToId;
  String? _forwardOfId;
  int? _expiresAt;
  String? _ephemeralPublicKey;
  Map<String, String>? _recipientKeys;
  String? _nonce;
  String? _signature;
  int _priority = 1;
  bool _requestReadReceipt = false;
  Map<String, dynamic> _headers = {};

  GnsEnvelopeBuilder from(String publicKey, {String? handle}) {
    _fromPublicKey = publicKey;
    _fromHandle = handle;
    return this;
  }

  GnsEnvelopeBuilder to(List<String> publicKeys) {
    _toPublicKeys = publicKeys;
    return this;
  }

  GnsEnvelopeBuilder cc(List<String> publicKeys) {
    _ccPublicKeys = publicKeys;
    return this;
  }

  GnsEnvelopeBuilder bcc(List<String> publicKeys) {
    _bccPublicKeys = publicKeys;
    return this;
  }

  GnsEnvelopeBuilder payload({
    required String type,
    required String encrypted,
    required int size,
  }) {
    _payloadType = type;
    _encryptedPayload = encrypted;
    _payloadSize = size;
    return this;
  }

  GnsEnvelopeBuilder thread(String? threadId, {String? replyTo, String? forwardOf}) {
    _threadId = threadId;
    _replyToId = replyTo;
    _forwardOfId = forwardOf;
    return this;
  }

  GnsEnvelopeBuilder expiresIn(Duration duration) {
    _expiresAt = DateTime.now().add(duration).millisecondsSinceEpoch;
    return this;
  }

  GnsEnvelopeBuilder crypto({
    required String ephemeralPublicKey,
    required String nonce,
    Map<String, String>? recipientKeys,
  }) {
    _ephemeralPublicKey = ephemeralPublicKey;
    _nonce = nonce;
    _recipientKeys = recipientKeys;
    return this;
  }

  GnsEnvelopeBuilder sign(String signature) {
    _signature = signature;
    return this;
  }

  GnsEnvelopeBuilder priority(int level) {
    _priority = level;
    return this;
  }

  GnsEnvelopeBuilder requestReceipt(bool request) {
    _requestReadReceipt = request;
    return this;
  }

  GnsEnvelopeBuilder header(String key, dynamic value) {
    _headers[key] = value;
    return this;
  }

  GnsEnvelope build() {
    if (_fromPublicKey == null) throw StateError('from() is required');
    if (_toPublicKeys.isEmpty) throw StateError('to() is required');
    if (_payloadType == null) throw StateError('payload() is required');
    if (_encryptedPayload == null) throw StateError('payload() is required');
    if (_ephemeralPublicKey == null) throw StateError('crypto() is required');
    if (_nonce == null) throw StateError('crypto() is required');
    if (_signature == null) throw StateError('sign() is required');

    return GnsEnvelope(
      id: GnsEnvelope.generateId(),
      fromPublicKey: _fromPublicKey!,
      fromHandle: _fromHandle,
      toPublicKeys: _toPublicKeys,
      ccPublicKeys: _ccPublicKeys,
      bccPublicKeys: _bccPublicKeys,
      payloadType: _payloadType!,
      encryptedPayload: _encryptedPayload!,
      payloadSize: _payloadSize,
      threadId: _threadId,
      replyToId: _replyToId,
      forwardOfId: _forwardOfId,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      expiresAt: _expiresAt,
      ephemeralPublicKey: _ephemeralPublicKey!,
      recipientKeys: _recipientKeys,
      nonce: _nonce!,
      signature: _signature!,
      priority: _priority,
      requestReadReceipt: _requestReadReceipt,
      headers: _headers,
    );
  }
}

/// Canonical JSON encoding (sorted keys) for consistent signatures
String _canonicalize(dynamic value) {
  if (value == null) return 'null';
  if (value is bool) return value.toString();
  if (value is num) return value.toString();
  if (value is String) return jsonEncode(value);
  if (value is List) {
    final items = value.map(_canonicalize).join(',');
    return '[$items]';
  }
  if (value is Map) {
    final keys = value.keys.toList()..sort();
    final pairs = keys
        .where((k) => value[k] != null)
        .map((k) => '${jsonEncode(k)}:${_canonicalize(value[k])}')
        .join(',');
    return '{$pairs}';
  }
  return jsonEncode(value);
}


/// Thread/Conversation grouping
class GnsThread {
  final String id;
  final String type;  // 'direct', 'group', 'channel'
  final List<String> participantKeys;
  final String? title;
  final String? avatarUrl;
  final DateTime createdAt;
  final DateTime lastActivityAt;
  final Map<String, dynamic> metadata;
  
  // Local state
  int unreadCount;
  bool isPinned;
  bool isMuted;
  bool isArchived;
  String? draftText;

  GnsThread({
    required this.id,
    required this.type,
    required this.participantKeys,
    this.title,
    this.avatarUrl,
    required this.createdAt,
    required this.lastActivityAt,
    this.metadata = const {},
    this.unreadCount = 0,
    this.isPinned = false,
    this.isMuted = false,
    this.isArchived = false,
    this.draftText,
  });

  /// Is this a direct (1:1) conversation?
  bool get isDirect => type == 'direct' && participantKeys.length == 2;

  /// Is this a group conversation?
  bool get isGroup => type == 'group';
  
  /// Alias for lastActivityAt (for compatibility)
  DateTime get updatedAt => lastActivityAt;

  /// Get the other participant in a direct thread
  String? otherParticipant(String myPublicKey) {
    if (!isDirect) return null;
    return participantKeys.firstWhere(
      (k) => k != myPublicKey,
      orElse: () => participantKeys.first,
    );
  }

  /// Generate thread ID for direct conversation (deterministic)
  static String directThreadId(String pubKey1, String pubKey2) {
    final sorted = [pubKey1, pubKey2]..sort();
    return 'direct:${sorted[0].substring(0, 16)}:${sorted[1].substring(0, 16)}';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'participantKeys': participantKeys,
    'title': title,
    'avatarUrl': avatarUrl,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'lastActivityAt': lastActivityAt.millisecondsSinceEpoch,
    'metadata': metadata,
    'unreadCount': unreadCount,
    'isPinned': isPinned,
    'isMuted': isMuted,
    'isArchived': isArchived,
    'draftText': draftText,
  };

  factory GnsThread.fromJson(Map<String, dynamic> json) => GnsThread(
    id: json['id'] as String,
    type: json['type'] as String,
    participantKeys: List<String>.from(json['participantKeys'] as List),
    title: json['title'] as String?,
    avatarUrl: json['avatarUrl'] as String?,
    createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
    lastActivityAt: DateTime.fromMillisecondsSinceEpoch(json['lastActivityAt'] as int),
    metadata: json['metadata'] != null 
        ? Map<String, dynamic>.from(json['metadata'] as Map)
        : {},
    unreadCount: json['unreadCount'] as int? ?? 0,
    isPinned: json['isPinned'] as bool? ?? false,
    isMuted: json['isMuted'] as bool? ?? false,
    isArchived: json['isArchived'] as bool? ?? false,
    draftText: json['draftText'] as String?,
  );
}
