/// Message Storage - Encrypted Local Database
/// 
/// Stores threads and messages locally with encryption at rest.
/// All message content is encrypted using a key derived from
/// the user's identity key.
/// 
/// Location: lib/core/comm/message_storage.dart

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:cryptography/cryptography.dart';
import 'gns_envelope.dart';
import 'payload_types.dart';

/// Message status enum
enum MessageStatus {
  sending,    // Being sent
  sent,       // Sent to relay/network
  delivered,  // Delivered to recipient device
  read,       // Read by recipient
  failed,     // Failed to send
}

/// Local message representation (decrypted)
class GnsMessage {
  final String id;
  final String threadId;
  final String fromPublicKey;
  final String? fromHandle;
  final String payloadType;
  final GnsPayload payload;
  final DateTime timestamp;
  final String? replyToId;
  final MessageStatus status;
  final bool isOutgoing;
  final Map<String, dynamic> metadata;
  
  // Reactions from other users
  final Map<String, List<String>> reactions;  // emoji -> list of public keys
  
  // Edit history
  final bool isEdited;
  final DateTime? editedAt;
  
  // Deletion
  final bool isDeleted;

  GnsMessage({
    required this.id,
    required this.threadId,
    required this.fromPublicKey,
    this.fromHandle,
    required this.payloadType,
    required this.payload,
    required this.timestamp,
    this.replyToId,
    this.status = MessageStatus.sent,
    required this.isOutgoing,
    this.metadata = const {},
    this.reactions = const {},
    this.isEdited = false,
    this.editedAt,
    this.isDeleted = false,
  });

  /// Get text content if this is a text message
  String? get textContent {
    if (payload is TextPayload) {
      return (payload as TextPayload).text;
    }
    if (payload is EmailPayload) {
      return (payload as EmailPayload).body;
    }
    return null;
  }

  /// Get preview text for thread list
  String get previewText {
    if (isDeleted) return 'Message deleted';
    
    switch (payloadType) {
      case PayloadType.textPlain:
      case PayloadType.textMarkdown:
        final text = (payload as TextPayload).text;
        return text.length > 100 ? '${text.substring(0, 100)}...' : text;
      case PayloadType.email:
        final email = payload as EmailPayload;
        return '${email.subject}: ${email.body.substring(0, 50.clamp(0, email.body.length))}...';
      case PayloadType.attachmentImage:
        return '📷 Photo';
      case PayloadType.attachmentVideo:
        return '🎥 Video';
      case PayloadType.attachmentAudio:
        return '🎵 Audio';
      case PayloadType.attachment:
      case PayloadType.attachmentDocument:
        return '📎 Attachment';
      case PayloadType.location:
        return '📍 Location';
      case PayloadType.contact:
      case PayloadType.contactGns:
        return '👤 Contact';
      default:
        return 'Message';
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'threadId': threadId,
    'fromPublicKey': fromPublicKey,
    'fromHandle': fromHandle,
    'payloadType': payloadType,
    'payload': payload.toJson(),
    'timestamp': timestamp.millisecondsSinceEpoch,
    'replyToId': replyToId,
    'status': status.name,
    'isOutgoing': isOutgoing,
    'metadata': metadata,
    'reactions': reactions,
    'isEdited': isEdited,
    'editedAt': editedAt?.millisecondsSinceEpoch,
    'isDeleted': isDeleted,
  };

  factory GnsMessage.fromJson(Map<String, dynamic> json) {
    final payloadType = json['payloadType'] as String;
    final payloadData = json['payload'] as Map<String, dynamic>;
    
    return GnsMessage(
      id: json['id'] as String,
      threadId: json['threadId'] as String,
      fromPublicKey: json['fromPublicKey'] as String,
      fromHandle: json['fromHandle'] as String?,
      payloadType: payloadType,
      payload: GnsPayload.fromJson(payloadType, payloadData),
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
      replyToId: json['replyToId'] as String?,
      status: MessageStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => MessageStatus.sent,
      ),
      isOutgoing: json['isOutgoing'] as bool,
      metadata: json['metadata'] != null 
          ? Map<String, dynamic>.from(json['metadata'] as Map)
          : {},
      reactions: json['reactions'] != null
          ? (json['reactions'] as Map).map(
              (k, v) => MapEntry(k as String, List<String>.from(v as List)),
            )
          : {},
      isEdited: json['isEdited'] as bool? ?? false,
      editedAt: json['editedAt'] != null 
          ? DateTime.fromMillisecondsSinceEpoch(json['editedAt'] as int)
          : null,
      isDeleted: json['isDeleted'] as bool? ?? false,
    );
  }

  /// Create from envelope (after decryption)
  factory GnsMessage.fromEnvelope({
    required GnsEnvelope envelope,
    required GnsPayload payload,
    required String myPublicKey,
    String? threadId,
  }) {
    return GnsMessage(
      id: envelope.id,
      threadId: threadId ?? envelope.threadId ?? _generateThreadId(envelope, myPublicKey),
      fromPublicKey: envelope.fromPublicKey,
      fromHandle: envelope.fromHandle,
      payloadType: envelope.payloadType,
      payload: payload,
      timestamp: envelope.timestampDate,
      replyToId: envelope.replyToId,
      status: MessageStatus.delivered,
      isOutgoing: envelope.fromPublicKey == myPublicKey,
    );
  }

  static String _generateThreadId(GnsEnvelope envelope, String myPublicKey) {
    // For direct messages, create deterministic thread ID
    if (envelope.toPublicKeys.length == 1) {
      final other = envelope.fromPublicKey == myPublicKey 
          ? envelope.toPublicKeys.first 
          : envelope.fromPublicKey;
      return GnsThread.directThreadId(myPublicKey, other);
    }
    // For group messages, use envelope ID as thread ID
    return 'group:${envelope.id}';
  }

  GnsMessage copyWith({
    MessageStatus? status,
    Map<String, List<String>>? reactions,
    bool? isEdited,
    DateTime? editedAt,
    bool? isDeleted,
    GnsPayload? payload,
  }) {
    return GnsMessage(
      id: id,
      threadId: threadId,
      fromPublicKey: fromPublicKey,
      fromHandle: fromHandle,
      payloadType: payloadType,
      payload: payload ?? this.payload,
      timestamp: timestamp,
      replyToId: replyToId,
      status: status ?? this.status,
      isOutgoing: isOutgoing,
      metadata: metadata,
      reactions: reactions ?? this.reactions,
      isEdited: isEdited ?? this.isEdited,
      editedAt: editedAt ?? this.editedAt,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }
}

/// Thread with last message info
class ThreadWithPreview {
  final GnsThread thread;
  final GnsMessage? lastMessage;
  final String? otherParticipantHandle;

  ThreadWithPreview({
    required this.thread,
    this.lastMessage,
    this.otherParticipantHandle,
  });
}

/// Message storage service
class MessageStorage {
  static final MessageStorage _instance = MessageStorage._internal();
  factory MessageStorage() => _instance;
  MessageStorage._internal();

  Database? _db;
  SecretKey? _encryptionKey;
  final _cipher = Chacha20.poly1305Aead();
  bool _initialized = false;

  bool get isInitialized => _initialized;
  
  /// Check if storage is initialized
  void _checkInitialized() {
    if (!_initialized) {
      throw StateError('MessageStorage not initialized. Call initialize() first.');
    }
  }

  /// Initialize storage with identity-derived key
  Future<void> initialize(Uint8List identityPrivateKey) async {
    if (_initialized) return;

    try {
      // Derive storage encryption key from identity
      _encryptionKey = await _deriveStorageKey(identityPrivateKey);

      // Open database
      final documentsDir = await getApplicationDocumentsDirectory();
      final dbPath = join(documentsDir.path, 'gns_messages.db');

      _db = await openDatabase(
        dbPath,
        version: 1,
        onCreate: _createTables,
        onUpgrade: _upgradeTables,
      );

      _initialized = true;
      debugPrint('Message storage initialized: $dbPath');
    } catch (e) {
      debugPrint('Failed to initialize message storage: $e');
      rethrow;
    }
  }

  Future<void> _createTables(Database db, int version) async {
    // Threads table
    await db.execute('''
      CREATE TABLE threads (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        participant_keys TEXT NOT NULL,
        title TEXT,
        avatar_url TEXT,
        created_at INTEGER NOT NULL,
        last_activity_at INTEGER NOT NULL,
        unread_count INTEGER DEFAULT 0,
        is_pinned INTEGER DEFAULT 0,
        is_muted INTEGER DEFAULT 0,
        is_archived INTEGER DEFAULT 0,
        draft_text TEXT,
        metadata TEXT
      )
    ''');

    // Messages table (payload is encrypted)
    await db.execute('''
      CREATE TABLE messages (
        id TEXT PRIMARY KEY,
        thread_id TEXT NOT NULL,
        from_public_key TEXT NOT NULL,
        from_handle TEXT,
        payload_type TEXT NOT NULL,
        payload_encrypted TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        reply_to_id TEXT,
        status TEXT DEFAULT 'sent',
        is_outgoing INTEGER NOT NULL,
        metadata TEXT,
        reactions TEXT,
        is_edited INTEGER DEFAULT 0,
        edited_at INTEGER,
        is_deleted INTEGER DEFAULT 0,
        FOREIGN KEY (thread_id) REFERENCES threads(id)
      )
    ''');

    // Attachments table
    await db.execute('''
      CREATE TABLE attachments (
        id TEXT PRIMARY KEY,
        message_id TEXT NOT NULL,
        filename TEXT NOT NULL,
        mime_type TEXT NOT NULL,
        size INTEGER NOT NULL,
        checksum TEXT NOT NULL,
        local_path TEXT,
        thumbnail_base64 TEXT,
        FOREIGN KEY (message_id) REFERENCES messages(id)
      )
    ''');

    // Indexes
    await db.execute('CREATE INDEX idx_messages_thread ON messages(thread_id, timestamp DESC)');
    await db.execute('CREATE INDEX idx_messages_status ON messages(status)');
    await db.execute('CREATE INDEX idx_threads_activity ON threads(last_activity_at DESC)');
    await db.execute('CREATE INDEX idx_threads_archived ON threads(is_archived)');
  }

  Future<void> _upgradeTables(Database db, int oldVersion, int newVersion) async {
    // Handle future migrations
  }

  /// Derive encryption key from identity private key
  Future<SecretKey> _deriveStorageKey(Uint8List privateKey) async {
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final inputKey = SecretKeyData(privateKey.sublist(0, 32));
    
    return await hkdf.deriveKey(
      secretKey: inputKey,
      info: utf8.encode('gns-message-storage-v1'),
      nonce: Uint8List(0),
    );
  }

  /// Encrypt data for storage
  Future<String> _encrypt(String plaintext) async {
    if (_encryptionKey == null) throw StateError('Storage not initialized');
    
    final data = utf8.encode(plaintext);
    final nonce = _cipher.newNonce();
    
    final secretBox = await _cipher.encrypt(
      data,
      secretKey: _encryptionKey!,
      nonce: nonce,
    );
    
    // Combine nonce + ciphertext + mac
    final combined = Uint8List.fromList([
      ...nonce,
      ...secretBox.cipherText,
      ...secretBox.mac.bytes,
    ]);
    
    return base64Encode(combined);
  }

  /// Decrypt data from storage
  Future<String> _decrypt(String encrypted) async {
    if (_encryptionKey == null) throw StateError('Storage not initialized');
    
    final combined = base64Decode(encrypted);
    
    // Extract nonce (12 bytes), ciphertext, mac (16 bytes)
    final nonce = combined.sublist(0, 12);
    final ciphertext = combined.sublist(12, combined.length - 16);
    final mac = Mac(combined.sublist(combined.length - 16));
    
    final secretBox = SecretBox(ciphertext, nonce: nonce, mac: mac);
    final plaintext = await _cipher.decrypt(secretBox, secretKey: _encryptionKey!);
    
    return utf8.decode(plaintext);
  }

  // ==================== THREAD OPERATIONS ====================

  /// Create or update a thread
  Future<void> saveThread(GnsThread thread) async {
    await _db!.insert(
      'threads',
      {
        'id': thread.id,
        'type': thread.type,
        'participant_keys': jsonEncode(thread.participantKeys),
        'title': thread.title,
        'avatar_url': thread.avatarUrl,
        'created_at': thread.createdAt.millisecondsSinceEpoch,
        'last_activity_at': thread.lastActivityAt.millisecondsSinceEpoch,
        'unread_count': thread.unreadCount,
        'is_pinned': thread.isPinned ? 1 : 0,
        'is_muted': thread.isMuted ? 1 : 0,
        'is_archived': thread.isArchived ? 1 : 0,
        'draft_text': thread.draftText,
        'metadata': jsonEncode(thread.metadata),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Get thread by ID
  Future<GnsThread?> getThread(String threadId) async {
    final rows = await _db!.query(
      'threads',
      where: 'id = ?',
      whereArgs: [threadId],
    );
    
    if (rows.isEmpty) return null;
    return _threadFromRow(rows.first);
  }

  /// Get all threads (with optional filters)
  Future<List<ThreadWithPreview>> getThreads({
    bool includeArchived = false,
    int limit = 50,
    int offset = 0,
  }) async {
    String where = includeArchived ? '' : 'is_archived = 0';
    
    final rows = await _db!.query(
      'threads',
      where: where.isEmpty ? null : where,
      orderBy: 'is_pinned DESC, last_activity_at DESC',
      limit: limit,
      offset: offset,
    );
    
    final results = <ThreadWithPreview>[];
    
    for (final row in rows) {
      final thread = _threadFromRow(row);
      final lastMessage = await _getLastMessage(thread.id);
      
      results.add(ThreadWithPreview(
        thread: thread,
        lastMessage: lastMessage,
      ));
    }
    
    return results;
  }

  /// Get or create direct thread with participant
  Future<GnsThread> getOrCreateDirectThread({
    required String myPublicKey,
    required String otherPublicKey,
    String? otherHandle,
  }) async {
    final threadId = GnsThread.directThreadId(myPublicKey, otherPublicKey);
    
    var thread = await getThread(threadId);
    if (thread != null) return thread;
    
    // Create new thread
    thread = GnsThread(
      id: threadId,
      type: 'direct',
      participantKeys: [myPublicKey, otherPublicKey],
      title: otherHandle,
      createdAt: DateTime.now(),
      lastActivityAt: DateTime.now(),
    );
    
    await saveThread(thread);
    return thread;
  }

  /// Update thread unread count
  Future<void> updateUnreadCount(String threadId, int count) async {
    await _db!.update(
      'threads',
      {'unread_count': count},
      where: 'id = ?',
      whereArgs: [threadId],
    );
  }

  /// Increment thread unread count
  Future<void> incrementUnread(String threadId) async {
    await _db!.rawUpdate(
      'UPDATE threads SET unread_count = unread_count + 1 WHERE id = ?',
      [threadId],
    );
  }

  /// Increment thread unread count by a specific amount (for batch operations)
  Future<void> incrementUnreadBy(String threadId, int count) async {
    if (count <= 0) return;
    await _db!.rawUpdate(
      'UPDATE threads SET unread_count = unread_count + ? WHERE id = ?',
      [count, threadId],
    );
  }

  /// Mark thread as read
  Future<void> markThreadRead(String threadId) async {
    await updateUnreadCount(threadId, 0);
  }

  /// Update thread last activity
  Future<void> updateThreadActivity(String threadId, DateTime time) async {
    await _db!.update(
      'threads',
      {'last_activity_at': time.millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [threadId],
    );
  }

  /// Set thread archived status
  Future<void> setThreadArchived(String threadId, bool archived) async {
    await _db!.update(
      'threads',
      {'is_archived': archived ? 1 : 0},
      where: 'id = ?',
      whereArgs: [threadId],
    );
  }

  /// Set thread pinned status
  Future<void> setThreadPinned(String threadId, bool pinned) async {
    await _db!.update(
      'threads',
      {'is_pinned': pinned ? 1 : 0},
      where: 'id = ?',
      whereArgs: [threadId],
    );
  }

  /// Set thread muted status
  Future<void> setThreadMuted(String threadId, bool muted) async {
    await _db!.update(
      'threads',
      {'is_muted': muted ? 1 : 0},
      where: 'id = ?',
      whereArgs: [threadId],
    );
  }

  /// Save thread draft
  Future<void> saveThreadDraft(String threadId, String? draft) async {
    await _db!.update(
      'threads',
      {'draft_text': draft},
      where: 'id = ?',
      whereArgs: [threadId],
    );
  }

  /// Delete thread and all messages
  Future<void> deleteThread(String threadId) async {
    await _db!.delete('messages', where: 'thread_id = ?', whereArgs: [threadId]);
    await _db!.delete('threads', where: 'id = ?', whereArgs: [threadId]);
  }

  GnsThread _threadFromRow(Map<String, dynamic> row) {
    return GnsThread(
      id: row['id'] as String,
      type: row['type'] as String,
      participantKeys: List<String>.from(jsonDecode(row['participant_keys'] as String)),
      title: row['title'] as String?,
      avatarUrl: row['avatar_url'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      lastActivityAt: DateTime.fromMillisecondsSinceEpoch(row['last_activity_at'] as int),
      unreadCount: row['unread_count'] as int? ?? 0,
      isPinned: (row['is_pinned'] as int? ?? 0) == 1,
      isMuted: (row['is_muted'] as int? ?? 0) == 1,
      isArchived: (row['is_archived'] as int? ?? 0) == 1,
      draftText: row['draft_text'] as String?,
      metadata: row['metadata'] != null 
          ? Map<String, dynamic>.from(jsonDecode(row['metadata'] as String))
          : {},
    );
  }

  // ==================== MESSAGE OPERATIONS ====================

  /// Save multiple messages in a single transaction (PREVENTS DATABASE LOCKS)
  Future<void> saveMessagesBatch(List<GnsMessage> messages) async {
    if (messages.isEmpty) return;
    
    // Group messages by thread for efficient thread updates
    final Map<String, DateTime> threadUpdates = {};
    
    // Use a transaction to prevent locks
    await _db!.transaction((txn) async {
      final batch = txn.batch();
      
      // Batch insert all messages
      for (final message in messages) {
        final payloadJson = jsonEncode(message.payload.toJson());
        final encryptedPayload = await _encrypt(payloadJson);
        
        batch.insert(
          'messages',
          {
            'id': message.id,
            'thread_id': message.threadId,
            'from_public_key': message.fromPublicKey,
            'from_handle': message.fromHandle,
            'payload_type': message.payloadType,
            'payload_encrypted': encryptedPayload,
            'timestamp': message.timestamp.millisecondsSinceEpoch,
            'reply_to_id': message.replyToId,
            'status': message.status.name,
            'is_outgoing': message.isOutgoing ? 1 : 0,
            'metadata': jsonEncode(message.metadata),
            'reactions': jsonEncode(message.reactions),
            'is_edited': message.isEdited ? 1 : 0,
            'edited_at': message.editedAt?.millisecondsSinceEpoch,
            'is_deleted': message.isDeleted ? 1 : 0,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        
        // Track latest timestamp per thread
        final currentTime = threadUpdates[message.threadId];
        if (currentTime == null || message.timestamp.isAfter(currentTime)) {
          threadUpdates[message.threadId] = message.timestamp;
        }
      }
      
      // Batch update thread activity for all affected threads
      for (final entry in threadUpdates.entries) {
        batch.update(
          'threads',
          {'last_activity_at': entry.value.millisecondsSinceEpoch},
          where: 'id = ?',
          whereArgs: [entry.key],
        );
      }
      
      // Commit all operations in one go
      await batch.commit(noResult: true);
    });
    
    debugPrint('✅ Saved ${messages.length} messages in batch across ${threadUpdates.length} threads');
  }

  /// Save a message (encrypts payload)
  /// ⚠️ For saving multiple messages, use saveMessagesBatch() instead to prevent database locks
  Future<void> saveMessage(GnsMessage message) async {
    final payloadJson = jsonEncode(message.payload.toJson());
    final encryptedPayload = await _encrypt(payloadJson);
    
    await _db!.insert(
      'messages',
      {
        'id': message.id,
        'thread_id': message.threadId,
        'from_public_key': message.fromPublicKey,
        'from_handle': message.fromHandle,
        'payload_type': message.payloadType,
        'payload_encrypted': encryptedPayload,
        'timestamp': message.timestamp.millisecondsSinceEpoch,
        'reply_to_id': message.replyToId,
        'status': message.status.name,
        'is_outgoing': message.isOutgoing ? 1 : 0,
        'metadata': jsonEncode(message.metadata),
        'reactions': jsonEncode(message.reactions),
        'is_edited': message.isEdited ? 1 : 0,
        'edited_at': message.editedAt?.millisecondsSinceEpoch,
        'is_deleted': message.isDeleted ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    
    // Update thread activity
    await updateThreadActivity(message.threadId, message.timestamp);
  }

  /// Batch status updates for acknowledgments
  Future<void> updateMessageStatusBatch(
    List<String> messageIds, 
    MessageStatus status
  ) async {
    if (messageIds.isEmpty) return;
    
    await _db!.transaction((txn) async {
      final batch = txn.batch();
      
      for (final messageId in messageIds) {
        batch.update(
          'messages',
          {'status': status.name},
          where: 'id = ?',
          whereArgs: [messageId],
        );
      }
      
      await batch.commit(noResult: true);
    });
    
    debugPrint('✅ Updated status for ${messageIds.length} messages to ${status.name}');
  }

  /// Get message by ID
  Future<GnsMessage?> getMessage(String messageId) async {
    final rows = await _db!.query(
      'messages',
      where: 'id = ?',
      whereArgs: [messageId],
    );
    
    if (rows.isEmpty) return null;
    return await _messageFromRow(rows.first);
  }

  /// Get messages in a thread
  Future<List<GnsMessage>> getMessages(
    String threadId, {
    int limit = 50,
    String? beforeId,
    String? afterId,
  }) async {
    String where = 'thread_id = ?';
    List<dynamic> whereArgs = [threadId];
    
    if (beforeId != null) {
      final beforeMsg = await getMessage(beforeId);
      if (beforeMsg != null) {
        where += ' AND timestamp < ?';
        whereArgs.add(beforeMsg.timestamp.millisecondsSinceEpoch);
      }
    }
    
    if (afterId != null) {
      final afterMsg = await getMessage(afterId);
      if (afterMsg != null) {
        where += ' AND timestamp > ?';
        whereArgs.add(afterMsg.timestamp.millisecondsSinceEpoch);
      }
    }
    
    final rows = await _db!.query(
      'messages',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'timestamp DESC',
      limit: limit,
    );
    
    final messages = <GnsMessage>[];
    for (final row in rows) {
      messages.add(await _messageFromRow(row));
    }
    
    return messages.reversed.toList(); // Return in chronological order
  }

  /// Get last message in thread
  Future<GnsMessage?> _getLastMessage(String threadId) async {
    final rows = await _db!.query(
      'messages',
      where: 'thread_id = ?',
      whereArgs: [threadId],
      orderBy: 'timestamp DESC',
      limit: 1,
    );
    
    if (rows.isEmpty) return null;
    return await _messageFromRow(rows.first);
  }

  /// Update message status
  Future<void> updateMessageStatus(String messageId, MessageStatus status) async {
    await _db!.update(
      'messages',
      {'status': status.name},
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  /// Add reaction to message
  Future<void> addReaction(String messageId, String emoji, String fromPublicKey) async {
    final message = await getMessage(messageId);
    if (message == null) return;
    
    final reactions = Map<String, List<String>>.from(message.reactions);
    reactions.putIfAbsent(emoji, () => []);
    if (!reactions[emoji]!.contains(fromPublicKey)) {
      reactions[emoji]!.add(fromPublicKey);
    }
    
    await _db!.update(
      'messages',
      {'reactions': jsonEncode(reactions)},
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  /// Remove reaction from message
  Future<void> removeReaction(String messageId, String emoji, String fromPublicKey) async {
    final message = await getMessage(messageId);
    if (message == null) return;
    
    final reactions = Map<String, List<String>>.from(message.reactions);
    reactions[emoji]?.remove(fromPublicKey);
    if (reactions[emoji]?.isEmpty ?? false) {
      reactions.remove(emoji);
    }
    
    await _db!.update(
      'messages',
      {'reactions': jsonEncode(reactions)},
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  /// Mark message as edited
  Future<void> markMessageEdited(String messageId, GnsPayload newPayload) async {
    final payloadJson = jsonEncode(newPayload.toJson());
    final encryptedPayload = await _encrypt(payloadJson);
    
    await _db!.update(
      'messages',
      {
        'payload_encrypted': encryptedPayload,
        'is_edited': 1,
        'edited_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  /// Mark message as deleted
  Future<void> markMessageDeleted(String messageId) async {
    await _db!.update(
      'messages',
      {'is_deleted': 1},
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  /// Search messages
  Future<List<GnsMessage>> searchMessages(String query, {int limit = 50}) async {
    // Note: This searches encrypted content, so we need to decrypt each
    // In production, consider a separate search index
    final rows = await _db!.query(
      'messages',
      orderBy: 'timestamp DESC',
      limit: limit * 3, // Fetch more since we filter after decryption
    );
    
    final results = <GnsMessage>[];
    final queryLower = query.toLowerCase();
    
    for (final row in rows) {
      if (results.length >= limit) break;
      
      final message = await _messageFromRow(row);
      final text = message.textContent?.toLowerCase() ?? '';
      
      if (text.contains(queryLower)) {
        results.add(message);
      }
    }
    
    return results;
  }

  Future<GnsMessage> _messageFromRow(Map<String, dynamic> row) async {
    final encryptedPayload = row['payload_encrypted'] as String;
    final decryptedJson = await _decrypt(encryptedPayload);
    final payloadData = jsonDecode(decryptedJson) as Map<String, dynamic>;
    final payloadType = row['payload_type'] as String;
    
    return GnsMessage(
      id: row['id'] as String,
      threadId: row['thread_id'] as String,
      fromPublicKey: row['from_public_key'] as String,
      fromHandle: row['from_handle'] as String?,
      payloadType: payloadType,
      payload: GnsPayload.fromJson(payloadType, payloadData),
      timestamp: DateTime.fromMillisecondsSinceEpoch(row['timestamp'] as int),
      replyToId: row['reply_to_id'] as String?,
      status: MessageStatus.values.firstWhere(
        (s) => s.name == row['status'],
        orElse: () => MessageStatus.sent,
      ),
      isOutgoing: (row['is_outgoing'] as int) == 1,
      metadata: row['metadata'] != null
          ? Map<String, dynamic>.from(jsonDecode(row['metadata'] as String))
          : {},
      reactions: row['reactions'] != null
          ? (jsonDecode(row['reactions'] as String) as Map).map(
              (k, v) => MapEntry(k as String, List<String>.from(v as List)),
            )
          : {},
      isEdited: (row['is_edited'] as int? ?? 0) == 1,
      editedAt: row['edited_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(row['edited_at'] as int)
          : null,
      isDeleted: (row['is_deleted'] as int? ?? 0) == 1,
    );
  }

  /// Get total unread count across all threads
  Future<int> getTotalUnreadCount() async {
    final result = await _db!.rawQuery(
      'SELECT SUM(unread_count) as total FROM threads WHERE is_archived = 0',
    );
    return (result.first['total'] as int?) ?? 0;
  }

  /// Create a new thread
  Future<GnsThread> createThread({
    required String id,
    required List<String> participantKeys,
    String? title,
    String type = 'direct',
  }) async {
    _checkInitialized();
    
    final now = DateTime.now();
    
    final thread = GnsThread(
      id: id,
      type: type,
      title: title,
      participantKeys: participantKeys,
      createdAt: now,
      lastActivityAt: now,
      unreadCount: 0,
      isPinned: false,
      isMuted: false,
      isArchived: false,
    );
    
    await saveThread(thread);
    
    return thread;
  }

  /// Close database
  Future<void> close() async {
    await _db?.close();
    _db = null;
    _initialized = false;
  }
}

/// Message reaction representation
class MessageReaction {
  final String emoji;
  final String fromPublicKey;
  
  MessageReaction({
    required this.emoji,
    required this.fromPublicKey,
  });
}

/// Extension for convenient reaction access
extension GnsMessageReactions on GnsMessage {
  List<MessageReaction> get reactionsList {
    final list = <MessageReaction>[];
    for (final entry in reactions.entries) {
      final emoji = entry.key;
      for (final publicKey in entry.value) {
        list.add(MessageReaction(
          emoji: emoji,
          fromPublicKey: publicKey,
        ));
      }
    }
    return list;
  }
}
