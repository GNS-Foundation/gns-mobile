/// Communication Service - Main API (REFACTORED to use RelayChannel)
/// 
/// The primary interface for all GNS communications.
/// Handles sending, receiving, encryption, and storage.
/// 
/// Location: lib/core/comm/communication_service.dart
/// 
/// ARCHITECTURE CHANGE:
/// - Now uses RelayChannel for all HTTP/WebSocket transport
/// - Separation of concerns: Service = business logic, Channel = transport
/// - Industry-standard dependency injection pattern

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';  // ✅ CRITICAL FIX: For unique message IDs
import 'gns_envelope.dart';
import 'payload_types.dart';
import 'comm_crypto_service.dart';
import 'message_storage.dart';
import 'relay_channel.dart';  // ✅ NEW: Use RelayChannel
import '../calls/call_service.dart';
import '../gns/identity_wallet.dart';

/// Result of sending a message
class SendResult {
  final bool success;
  final String? messageId;
  final String? error;
  final GnsMessage? message;

  SendResult.success(this.messageId, {this.message}) 
      : success = true, error = null;
  SendResult.failure(this.error) 
      : success = false, messageId = null, message = null;
}

/// Connection state for real-time updates
enum CommConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
}

/// Communication service configuration
class CommServiceConfig {
  final RelayChannelConfig relayConfig;  // ✅ NEW: Use RelayChannelConfig
  final Duration messageTimeout;
  final int maxRetries;

  const CommServiceConfig({
    this.relayConfig = const RelayChannelConfig(
      baseUrl: 'https://gns-browser-production.up.railway.app',
    ),
    this.messageTimeout = const Duration(seconds: 30),
    this.maxRetries = 3,
  });
  
  /// Production config
  factory CommServiceConfig.production() => CommServiceConfig(
    relayConfig: RelayChannelConfig.production(),
  );
  
  /// Local development config
  factory CommServiceConfig.local() => CommServiceConfig(
    relayConfig: RelayChannelConfig.local(),
  );
}

/// Main communication service
class CommunicationService {
  static CommunicationService? _instance;
  static const _uuid = Uuid();  // ✅ CRITICAL FIX: UUID generator for unique message IDs
  
  final IdentityWallet _wallet;
  final CommServiceConfig _config;
  final MessageStorage _storage = MessageStorage();
  final CommCryptoService _crypto = CommCryptoService();
  
  // ✅ NEW: Use RelayChannel instead of Dio
  late final RelayChannel _relayChannel;
  StreamSubscription? _incomingEnvelopesSubscription;
  
  // State - NO duplication, map from RelayChannel
  bool _initialized = false;
  
  // Stream controllers
  final _messageController = StreamController<GnsMessage>.broadcast();
  final _typingController = StreamController<TypingEvent>.broadcast();
  
  // ✅ NEW: Encryption key cache to prevent 100+ API calls per message load
  final Map<String, String> _encryptionKeyCache = {};
  
  // Callbacks
  Function(GnsMessage)? onMessageReceived;
  Function(String threadId, String publicKey, bool isTyping)? onTypingChanged;
  Function(String messageId, MessageStatus status)? onStatusChanged;

  CommunicationService._({
    required IdentityWallet wallet,
    CommServiceConfig config = const CommServiceConfig(),
  }) : _wallet = wallet, _config = config {
    // ✅ NEW: Initialize RelayChannel with auth provider
    _relayChannel = RelayChannel(
      config: _config.relayConfig,
      authProvider: _createAuth,
    );
    
    // ✅ Listen to incoming envelopes from WebSocket
    _incomingEnvelopesSubscription = _relayChannel.incomingEnvelopes.listen((envelope) async {
      // Process envelope and save message immediately (WebSocket = single message at a time)
      final message = await _handleIncomingEnvelope(envelope);
      if (message != null) {
        await _storage.saveMessage(message);
        await _storage.incrementUnread(message.threadId);
        _messageController.add(message);
        onMessageReceived?.call(message);
      }
    });

    // ✅ Route incoming call signals to CallService
    _relayChannel.callSignalStream.listen((json) {
      final type = json['type'] as String;
      CallService().handleCallSignal(type, json);
    });

    _relayChannel.browserMessages.listen((event) async {
      try {
        debugPrint('🌐 Browser message event: ${event['type']}');
        final text = event['decryptedText'] as String? ?? '';
        final conversationWith = event['conversationWith'] as String? ?? '';
        final messageId = event['messageId'] as String? ?? '';
        final timestamp = event['timestamp'] as int? ??
            DateTime.now().millisecondsSinceEpoch;

        if (text.isEmpty || conversationWith.isEmpty) return;

        final thread = await _storage.getOrCreateDirectThread(
          myPublicKey: _wallet.publicKey!,
          otherPublicKey: conversationWith,
        );

        final message = GnsMessage(
          id: messageId.isNotEmpty ? messageId :
              DateTime.now().millisecondsSinceEpoch.toString(),
          threadId: thread.id,
          fromPublicKey: _wallet.publicKey!,
          payloadType: PayloadType.textPlain,
          payload: TextPayload.plain(text),
          timestamp: DateTime.fromMillisecondsSinceEpoch(timestamp),
          status: MessageStatus.sent,
          isOutgoing: true,
        );

        final existing = await _storage.getMessage(message.id);
        if (existing != null) return;

        await _storage.saveMessage(message);
        _messageController.add(message);
        debugPrint('🌐 Browser message saved: ${message.id.substring(0, 8)}...');
      } catch (e) {
        debugPrint('⚠️ Browser message save failed: $e');
      }
    });
  }

  /// Get or create singleton instance
  static CommunicationService instance(IdentityWallet wallet, {CommServiceConfig? config}) {
    _instance ??= CommunicationService._(
      wallet: wallet,
      config: config ?? CommServiceConfig.production(),
    );
    return _instance!;
  }

  /// Stream of incoming messages
  Stream<GnsMessage> get incomingMessages => _messageController.stream;
  
  /// Stream of connection state changes
  /// ✅ FIXED: Map directly from RelayChannel, no duplication
  Stream<CommConnectionState> get connectionState => 
    _relayChannel.stateStream.map(_mapChannelState);
  
  /// Stream of typing events
  Stream<TypingEvent> get typingEvents => _typingController.stream;
  
  /// Current connection state
  /// ✅ FIXED: Read directly from RelayChannel
  CommConnectionState get currentConnectionState => _mapChannelState(_relayChannel.state);
  
  /// Is connected to relay
  bool get isConnected => currentConnectionState == CommConnectionState.connected;

  /// My public key (from wallet)
  String? get myPublicKey => _wallet.publicKey;

  // ✅ NEW: Auth provider for RelayChannel
  Future<RelayAuth> _createAuth() async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final authData = '$timestamp:${_wallet.publicKey!}';
    final signature = await _wallet.signBytes(utf8.encode(authData));
    
    return RelayAuth(
      publicKey: _wallet.publicKey!,
      timestamp: timestamp,
      signature: base64Encode(signature ?? Uint8List(0)),
    );
  }

  // ✅ Map ChannelState to CommConnectionState
  static CommConnectionState _mapChannelState(ChannelState channelState) {
    return switch (channelState) {
      ChannelState.disconnected => CommConnectionState.disconnected,
      ChannelState.connecting => CommConnectionState.connecting,
      ChannelState.connected => CommConnectionState.connected,
      ChannelState.reconnecting => CommConnectionState.reconnecting,
      ChannelState.error => CommConnectionState.disconnected,
    };
  }

  /// Initialize the service
  Future<void> initialize() async {
    if (_initialized) return;
    
    try {
      // Initialize storage
      await _storage.initialize(_wallet.privateKeyBytes!);
      
      _initialized = true;
      debugPrint('✅ Communication service initialized');
      
      // Connect to WebSocket via RelayChannel
      await connect();

      // ✅ Wire CallService to WebSocket
      await CallService().initialize(
        publicKey: _wallet.publicKey!,
        sendRaw: _relayChannel.sendRaw,
      );
      
      // ✅ NEW: Sync messages from server
      await syncMessages();
    } catch (e) {
      debugPrint('❌ Failed to initialize communication service: $e');
      rethrow;
    }
  }

  /// Connect to real-time WebSocket
  Future<void> connect() async {
    if (currentConnectionState == CommConnectionState.connecting) return;
    
    debugPrint('🔌 Connecting to relay...');
    await _relayChannel.connect();
  }

  /// Disconnect from relay
  Future<void> disconnect() async {
    debugPrint('🔌 Disconnecting from relay...');
    await _relayChannel.disconnect();
  }

  // ==================== 🆕 PUBLIC MESSAGE SYNC ====================
  
  /// ✅ NEW: Sync messages from server
  /// This is what was missing! Now ConversationScreen can call this.
  Future<void> syncMessages({int? since}) async {
    debugPrint('🔄 Syncing messages from server...');
    
    try {
      // ✅ Use RelayChannel.fetchPending instead of direct HTTP
      final envelopes = await _relayChannel.fetchPending(
        since: since,
        limit: 100,
      );
      
      debugPrint('📥 Fetched ${envelopes.length} messages from server');
      
      // ✅ FIXED: Process envelopes in batches and save messages in bulk
      const batchSize = 10;
      final List<GnsMessage> allMessages = [];
      
      for (int i = 0; i < envelopes.length; i += batchSize) {
        final batch = envelopes.skip(i).take(batchSize).toList();
        
        // Process batch in parallel and collect messages
        final messages = await Future.wait(
          batch.map((envelope) => _handleIncomingEnvelope(envelope)),
          eagerError: false, // Continue even if one fails
        );
        
        // Filter out null values (failed decryptions/verifications)
        allMessages.addAll(messages.whereType<GnsMessage>());
        
        // Small delay between batches to avoid overwhelming the system
        if (i + batchSize < envelopes.length) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }
      
      debugPrint('✅ Processed ${envelopes.length} envelopes → ${allMessages.length} valid messages');
      
      // ✅ CRITICAL: Save all messages in one batch transaction (prevents database locks!)
      if (allMessages.isNotEmpty) {
        await _storage.saveMessagesBatch(allMessages);
        
        // Increment unread counts for affected threads
        final threadIds = allMessages.map((m) => m.threadId).toSet();
        for (final threadId in threadIds) {
          final count = allMessages.where((m) => m.threadId == threadId).length;
          await _storage.incrementUnreadBy(threadId, count);
        }
        
        // Emit all messages to listeners
        for (final message in allMessages) {
          _messageController.add(message);
          onMessageReceived?.call(message);
        }
      }
      
      // Acknowledge messages
      if (envelopes.isNotEmpty) {
        final messageIds = envelopes.map((e) => e.id).whereType<String>().toList();
        await _relayChannel.acknowledgeMessages(messageIds);
      }
    } catch (e) {
      debugPrint('❌ Error syncing messages: $e');
    }
  }

  // ==================== SENDING MESSAGES ====================

  /// Send a text message
  Future<SendResult> sendText({
    required String toPublicKey,
    required String text,
    String? threadId,
    String? replyToId,
  }) async {
    try {
      // ✅ Fetch recipient's X25519 key
      final toEncryptionKey = await _fetchRecipientEncryptionKey(toPublicKey);
      
      if (toEncryptionKey == null) {
        return SendResult.failure('Could not fetch recipient encryption key');
      }
      
      debugPrint('💬 Sending to X25519: ${toEncryptionKey.substring(0, 16)}...');
      
      // Create payload
      final payload = TextPayload.plain(text);  // ✅ FIXED: Use factory method
      
      // Get or create thread first (ensures we have a valid threadId)
      final actualThreadId = threadId ?? GnsThread.directThreadId(_wallet.publicKey!, toPublicKey);
      await _storage.getOrCreateDirectThread(
        myPublicKey: _wallet.publicKey!,
        otherPublicKey: toPublicKey,
      );
      
      // Create envelope
      final envelope = await _createEnvelope(
        toPublicKey: toPublicKey,
        toEncryptionKey: toEncryptionKey,
        payload: payload,
        threadId: actualThreadId,
        replyToId: replyToId,
      );
      
      // ✅ Use RelayChannel.send instead of direct HTTP
      final result = await _relayChannel.send(envelope);
      
      if (!result.success) {
        return SendResult.failure(result.error);
      }
      
      // Create and store message locally
      final message = GnsMessage(
        id: envelope.id,
        threadId: actualThreadId,
        fromPublicKey: _wallet.publicKey!,
        payloadType: payload.type,
        payload: payload,
        timestamp: DateTime.fromMillisecondsSinceEpoch(envelope.timestamp),
        status: MessageStatus.sending,
        isOutgoing: true,
      );
      
      await _storage.saveMessage(message);
      _syncMessageToBrowser(message: message, otherPublicKey: toPublicKey, direction: 'outgoing');
      
      // Update status to sent after successful delivery
      await _storage.updateMessageStatus(message.id, MessageStatus.sent);
      
      return SendResult.success(message.id, message: message);
    } catch (e) {
      debugPrint('Error sending text: $e');
      return SendResult.failure(e.toString());
    }
  }

  /// Send typing indicator
  Future<void> sendTyping({
    required String threadId,
    required String toPublicKey,
    required bool isTyping,
  }) async {
    // ✅ Use RelayChannel.sendTyping
    await _relayChannel.sendTyping(
      threadId: threadId,
      isTyping: isTyping,
    );
  }

  /// Send a reaction
  Future<SendResult> sendReaction({
    required String messageId,
    required String threadId,
    required String toPublicKey,
    required String emoji,
  }) async {
    try {
      // ✅ Fetch recipient's X25519 encryption key
      final toEncryptionKey = await _fetchRecipientEncryptionKey(toPublicKey);
      
      if (toEncryptionKey == null) {
        return SendResult.failure('Could not fetch recipient encryption key');
      }
      
      final payload = ReactionPayload(
        messageId: messageId,
        emoji: emoji,
        remove: false,  // ✅ FIXED: Added missing parameter
      );
      
      final envelope = await _createEnvelope(
        toPublicKey: toPublicKey,
        toEncryptionKey: toEncryptionKey, 
        payload: payload,
        threadId: threadId,
      );
      
      // ✅ Use RelayChannel.send
      final result = await _relayChannel.send(envelope);
      
      if (!result.success) {
        return SendResult.failure(result.error);
      }
      
      // Create and store reaction message locally
      final message = GnsMessage(
        id: envelope.id,
        threadId: threadId,
        fromPublicKey: _wallet.publicKey!,
        payloadType: payload.type,
        payload: payload,
        timestamp: DateTime.fromMillisecondsSinceEpoch(envelope.timestamp),
        status: MessageStatus.sent,
        isOutgoing: true,
      );
      
      await _storage.saveMessage(message);
      _syncMessageToBrowser(message: message, otherPublicKey: toPublicKey, direction: 'outgoing');
      return SendResult.success(message.id, message: message);
    } catch (e) {
      return SendResult.failure(e.toString());
    }
  }

  /// Delete a message
  Future<SendResult> deleteMessage({
    required String messageId,
    required String threadId,
    required String toPublicKey,
    bool deleteForEveryone = false,
  }) async {
    try {
      // ✅ Fetch recipient's X25519 encryption key
      final toEncryptionKey = await _fetchRecipientEncryptionKey(toPublicKey);
      
      if (toEncryptionKey == null) {
        return SendResult.failure('Could not fetch recipient encryption key');
      }
      
      final payload = DeletePayload(
        messageId: messageId,
        deleteForEveryone: deleteForEveryone,
      );  // ✅ FIXED: Removed sentAt
      
      final envelope = await _createEnvelope(
        toPublicKey: toPublicKey,
        toEncryptionKey: toEncryptionKey,  // ✅ FIXED: Use fetched X25519 key
        payload: payload,
        threadId: threadId,
      );
      
      // ✅ Use RelayChannel.send
      final result = await _relayChannel.send(envelope);
      
      if (!result.success) {
        return SendResult.failure(result.error);
      }
      
      // Update local storage
      await _storage.markMessageDeleted(messageId);
      
      return SendResult.success(messageId);
    } catch (e) {
      return SendResult.failure(e.toString());
    }
  }

  // ==================== RECEIVING MESSAGES ====================

  /// ✅ NEW: Get sender's encryption key with caching
  /// This prevents 100+ API calls when loading messages from the same sender
  Future<String?> _getSenderEncryptionKey(String publicKey, String? handle) async {
    // Check cache first
    final cacheKey = handle ?? publicKey;
    if (_encryptionKeyCache.containsKey(cacheKey)) {
      debugPrint('✅ Using cached encryption key for $cacheKey');
      return _encryptionKeyCache[cacheKey];
    }
    
    String? encryptionKey;
    
    // Try to get from handle first
    if (handle != null) {
      try {
        final handleInfo = await resolveHandleInfo(handle);
        encryptionKey = handleInfo?['encryption_key'] as String?;
        if (encryptionKey != null) {
          debugPrint('✅ Fetched encryption key for @$handle from handle resolution');
        }
      } catch (e) {
        debugPrint('⚠️ Failed to resolve handle for encryption key: $e');
      }
    }
    
    // If no handle or resolution failed, try to get from database
    if (encryptionKey == null) {
      try {
        final identity = await _relayChannel.getIdentity(publicKey);
        if (identity != null) {
          encryptionKey = identity['encryption_key'] as String?;
        }
        if (encryptionKey != null) {
          debugPrint('✅ Fetched encryption key for ${publicKey.substring(0, 8)}... from database');
        }
      } catch (e) {
        debugPrint('⚠️ Failed to fetch sender encryption key from database: $e');
      }
    }
    
    // Cache the result (even if null, to avoid repeated failed attempts)
    if (encryptionKey != null) {
      _encryptionKeyCache[cacheKey] = encryptionKey;
      debugPrint('💾 Cached encryption key for $cacheKey');
    }
    
    return encryptionKey;
  }

  /// Handle incoming envelope from RelayChannel
  /// Process incoming envelope and return message (or null if failed)
  /// ⚠️ Does NOT save to database - caller must use saveMessagesBatch()
  Future<GnsMessage?> _handleIncomingEnvelope(GnsEnvelope envelope, {bool skipSignature = false}) async {
    try {
      debugPrint('📨 Processing envelope from ${envelope.fromPublicKey.substring(0, 8)}...');
      debugPrint('   📧 PayloadType: ${envelope.payloadType}');
      debugPrint('   📧 isEmail: ${envelope.payloadType == PayloadType.email}');
      debugPrint('   📧 fromGateway: ${envelope.fromPublicKey.toLowerCase() == '007dd9b2c19308dd0e2dfc044da05a522a1d1adbd6f1c84147cc4e0b7a4bd53d'}');
      
      // Verify signature first (unless skipped for browser syncs)
      if (!skipSignature) {
        final senderPubKeyBytes = _hexToBytes(envelope.fromPublicKey);
        final isValid = await _crypto.verifyEnvelope(
          envelope: envelope,
          senderPublicKey: senderPubKeyBytes,
        );
        
        if (!isValid) {
          debugPrint('⚠️ Invalid signature on envelope');
          return null;
        }
      } else {
        debugPrint('⏭️ Skipping signature validation (browser sync)');
      }
      
      // Decrypt payload (using X25519 encryption keys!)
      // ✅ CRITICAL: Must use X25519 encryption keys, not Ed25519 identity keys
      
      // ✅ FIX: For single-recipient messages (with ephemeral key), we DON'T need sender's encryption key
      final isSingleRecipient = envelope.recipientKeys == null;
      
      Uint8List senderEncryptionKeyBytes;
      
      if (isSingleRecipient) {
        // Single-recipient: use dummy 32-byte key (not used in decryption anyway)
        senderEncryptionKeyBytes = Uint8List(32);
        debugPrint('📬 Single-recipient message, using ephemeral key for decryption');
      } else {
        // Multi-recipient: need sender's encryption key
        final senderEncryptionKey = await _getSenderEncryptionKey(
          envelope.fromPublicKey,
          envelope.fromHandle,
        );
        
        if (senderEncryptionKey == null) {
          debugPrint('❌ Cannot decrypt multi-recipient: sender encryption key not found');
          return null;
        }
        senderEncryptionKeyBytes = _hexToBytes(senderEncryptionKey);
      }
      
      final decrypted = await _crypto.decrypt(
        envelope: envelope,
        recipientPrivateKey: _wallet.encryptionPrivateKeyBytes!,
        recipientPublicKey: _wallet.encryptionPublicKeyBytes!,  // ✅ CRITICAL: YOUR X25519 public key for HKDF!
      );
      
      if (!decrypted.success || decrypted.payload == null) {
        debugPrint('⚠️ Failed to decrypt envelope: ${decrypted.error}');
        return null;
      }
      
      // Parse payload from bytes
      final payloadJson = jsonDecode(utf8.decode(decrypted.payload!));
      final payload = GnsPayload.fromJson(
        envelope.payloadType,
        payloadJson as Map<String, dynamic>,
      );
      
      // Get sender's avatar (for thread display)
      final senderAvatarUrl = await _fetchSenderAvatarUrl(
        envelope.fromPublicKey, 
        envelope.fromHandle,
      );
      
      // Get or create thread
      final thread = await _storage.getOrCreateDirectThread(
        myPublicKey: _wallet.publicKey!,
        otherPublicKey: envelope.fromPublicKey,
        otherHandle: envelope.fromHandle,
        otherAvatarUrl: senderAvatarUrl,  // ✅ NEW: Pass avatar
      );
      
      // Create message (but don't save yet - caller will batch save)
      final message = GnsMessage(
        id: envelope.id,
        threadId: thread.id,
        fromPublicKey: envelope.fromPublicKey,
        fromHandle: envelope.fromHandle,
        payloadType: payload.type,
        payload: payload,
        timestamp: DateTime.fromMillisecondsSinceEpoch(envelope.timestamp),
        status: MessageStatus.delivered,
        isOutgoing: false,
      );
      
      debugPrint('✅ Message validated: ${message.id}');

      // ✅ Sync decrypted message to Panthera browser via WebSocket
      // Backend 'sync_to_browser' handler forwards to any connected browser
      // with the same identity, so Panthera shows messages in real time
      _syncMessageToBrowser(
        message: message,
        otherPublicKey: envelope.fromPublicKey,
        otherHandle: envelope.fromHandle,
        direction: 'incoming',
      );

      return message;
    } catch (e) {
      debugPrint('❌ Error handling envelope: $e');
      return null;
    }
  }

  // ==================== MESSAGE RETRIEVAL ====================

  /// Get messages for a thread
  /// ✅ FIXED: Now syncs from server first, then reads local storage
  Future<List<GnsMessage>> getMessages(
    String threadId, {
    int limit = 50,
    String? beforeId,
  }) async {
    // ✅ NEW: Sync from server first
    await syncMessages();
    
    // Then read from local storage
    return _storage.getMessages(threadId, limit: limit, beforeId: beforeId);
  }

  /// Get all threads
  Future<List<ThreadWithPreview>> getThreads() async {
    // ✅ NEW: Sync from server first
    await syncMessages();
    
    return _storage.getThreads();
  }

  /// Get all conversations for contact picker
  Future<List<GnsThread>> getAllConversations() async {
    // Return all threads (conversations) from storage
    final threadsWithPreview = await _storage.getThreads();
    // Convert ThreadWithPreview to GnsThread
    return threadsWithPreview.map((t) => t.thread).toList();
  }

  /// Get total unread count
  Future<int> getTotalUnreadCount() async {
    return _storage.getTotalUnreadCount();
  }

  /// Mark messages as read
  /// Mark messages as read
  /// ✅ ECHO BOT FIX (2025-12-09): Removed read receipt messages to prevent infinite loop
  Future<void> markAsRead({
    required String threadId,
    required List<String> messageIds,
    required String toPublicKey,
  }) async {
    // Update individual message statuses
    for (final msgId in messageIds) {
      await _storage.updateMessageStatus(msgId, MessageStatus.read);
    }
    
    // Clear unread count for thread
    await _storage.markThreadRead(threadId);
    
    // ✅ Use RelayChannel.markMessagesRead - this is ALL you need!
    await _relayChannel.markMessagesRead(messageIds);
    
    // ✅ ECHO BOT FIX: Removed code that sent read receipts as encrypted messages
    // This was causing the infinite loop with @echo bot!
    // 
    // The code previously created a ReceiptPayload.read() and sent it as an
    // encrypted message to the recipient. The echo bot would process these
    // read receipt messages and respond to them, creating an infinite loop:
    //
    // 1. User sends message
    // 2. Echo bot replies
    // 3. User's app sends read receipt AS A MESSAGE
    // 4. Echo bot processes the read receipt message
    // 5. Echo bot sends "Echo received your message!"
    // 6. User's app sends another read receipt
    // 7. Loop continues forever
    //
    // Solution: Only use the API call above (markMessagesRead) to update
    // message status. Do not send read receipts as messages to the queue.
  }

  // ==================== HANDLE RESOLUTION ====================

  /// Resolve a @handle to its public key
  /// ✅ Uses RelayChannel for HTTP request
  Future<String?> resolveHandle(String handle) async {
    try {
      debugPrint('🔍 Resolving handle: $handle');
      final publicKey = await _relayChannel.resolveHandle(handle);
      
      if (publicKey != null) {
        debugPrint('✅ Handle $handle → $publicKey');
      } else {
        debugPrint('⚠️ Handle $handle not found');
      }
      
      return publicKey;
    } catch (e) {
      debugPrint('❌ Error resolving handle $handle: $e');
      return null;
    }
  }

  /// Resolve handle and return full info (including encryption key)
  /// ✅ Uses RelayChannel for HTTP request
  Future<Map<String, dynamic>?> resolveHandleInfo(String handle) async {
    try {
      debugPrint('🔍 Resolving handle info: $handle');
      final info = await _relayChannel.resolveHandleInfo(handle);
      
      if (info != null) {
        debugPrint('✅ Handle $handle resolved');
      } else {
        debugPrint('⚠️ Handle $handle not found');
      }
      
      return info;
    } catch (e) {
      debugPrint('❌ Error resolving handle info $handle: $e');
      return null;
    }
  }

  /// Fetch sender's avatar URL from their profile
  Future<String?> _fetchSenderAvatarUrl(String publicKey, String? handle) async {
    try {
      // Try to get from handle resolution first (has avatar)
      if (handle != null) {
        final info = await resolveHandleInfo(handle);
        if (info != null && info['avatar_url'] != null) {
          return info['avatar_url'] as String;
        }
      }
      
      // Try to get from identity record
      final identity = await _relayChannel.getIdentity(publicKey);
      if (identity != null && identity['avatar_url'] != null) {
        return identity['avatar_url'] as String;
      }
      
      return null;
    } catch (e) {
      debugPrint('⚠️ Failed to fetch sender avatar: $e');
      return null;
    }
  }

  /// Fetch recipient's X25519 encryption key from their GNS record
  /// This function is CRITICAL for sending messages.
  Future<String?> _fetchRecipientEncryptionKey(String ed25519PublicKey) async {
    try {
      debugPrint('🔍 Fetching X25519 key for: ${ed25519PublicKey.substring(0, 16)}...');
      
      // ✅ FIX: Call the RelayChannel's dedicated identity getter.
      // This function handles the temporary URL switch to hit /identities/:pk.
      final identity = await _relayChannel.getIdentity(ed25519PublicKey);
      
      if (identity == null || identity['encryption_key'] == null) {
        debugPrint('⚠️ Could not get recipient encryption key from identity record.');
        // The log shows the database has the key, so the 404 is the issue. 
        // If we reach here, the 404/failure has occurred.
        return null;
      }
      
      final encryptionKey = identity['encryption_key'] as String;
      debugPrint('✅ Fetched recipient X25519: ${encryptionKey.substring(0, 16)}...');
      return encryptionKey;
    } catch (e) {
      debugPrint('❌ Error fetching encryption key: $e');
      return null;
    }
  }

  /// Find existing thread by participant public key
  Future<GnsThread?> findThreadByParticipant(String publicKey) async {
    try {
      final threads = await _storage.getThreads();
      
      for (final threadPreview in threads) {
        final thread = threadPreview.thread;
        if (thread.participantKeys.any((k) => k.toLowerCase() == publicKey.toLowerCase())) {
          return thread;
        }
      }
      
      return null;
    } catch (e) {
      debugPrint('Error finding thread: $e');
      return null;
    }
  }

  /// Create a new thread
  Future<GnsThread> createThread({
    required List<String> participantKeys,
    String? title,
    String type = 'direct',
  }) async {
    // Add self to participants if not present
    final myKey = _wallet.publicKey!;
    final allParticipants = <String>{myKey, ...participantKeys}.toList();
    
    // Generate thread ID
    final threadId = _generateThreadId(allParticipants);
    
    // Create thread in storage
    final thread = await _storage.createThread(
      id: threadId,
      participantKeys: allParticipants,
      title: title,
      type: type,
    );
    
    return thread;
  }

  /// Get a single thread by ID
  Future<GnsThread?> getThread(String threadId) async {
    try {
      return await _storage.getThread(threadId);
    } catch (e) {
      debugPrint('Error getting thread: $e');
      return null;
    }
  }

  // ==================== THREAD MANAGEMENT ====================

  /// Delete a thread
  Future<void> deleteThread(String threadId) async {
    await _storage.deleteThread(threadId);
  }

  /// Pin/unpin a thread
  Future<void> pinThread(String threadId, {required bool pinned}) async {
    await _storage.setThreadPinned(threadId, pinned);
  }

  /// Mute/unmute a thread
  Future<void> muteThread(String threadId, {required bool muted}) async {
    await _storage.setThreadMuted(threadId, muted);
  }

  /// Archive a thread
  Future<void> archiveThread(String threadId) async {
    await _storage.setThreadArchived(threadId, true);
  }

  // ==================== UTILITY ====================

  /// Create envelope with encryption
  Future<GnsEnvelope> _createEnvelope({
    required String toPublicKey,
    required String toEncryptionKey,  // ✅ REQUIRED - no fallback
    required GnsPayload payload,  // ✅ FIXED: GnsPayload, not MessagePayload
    String? threadId,
    String? replyToId,
  }) async {
    // ✅ No fallback to Ed25519!
    debugPrint('🔐 Encrypting with X25519: ${toEncryptionKey.substring(0, 16)}...');
    
    // Get my handle for the envelope
    final myHandle = await _wallet.getCurrentHandle();
    
    // Convert payload to bytes
    final payloadBytes = payload.toBytes();
    
    // Convert encryption key to bytes
    final recipientKeyBytes = _hexToBytes(toEncryptionKey);
    
    // Encrypt
    final encResult = await _crypto.encryptForRecipient(
      payload: payloadBytes,
      recipientPublicKey: recipientKeyBytes,
    );
    
    // Create envelope
    final envelope = GnsEnvelope(
      id: _generateMessageId(),
      fromPublicKey: _wallet.publicKey!,
      fromHandle: myHandle,  // ✅ Added fromHandle
      toPublicKeys: [toPublicKey],
      payloadType: payload.type,
      encryptedPayload: encResult.encryptedPayload,
      payloadSize: encResult.payloadSize,
      ephemeralPublicKey: encResult.ephemeralPublicKey,
      recipientKeys: encResult.recipientKeys,
      nonce: encResult.nonce,
      threadId: threadId,
      replyToId: replyToId,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      signature: '',  // Placeholder for signing
    );
    
    // Sign envelope
    final signature = await _crypto.signEnvelope(
      envelope: envelope,
      privateKey: _wallet.privateKeyBytes!,
    );
    
    // Create signed envelope
    return GnsEnvelope(
      id: envelope.id,
      fromPublicKey: envelope.fromPublicKey,
      fromHandle: envelope.fromHandle,
      toPublicKeys: envelope.toPublicKeys,
      ccPublicKeys: envelope.ccPublicKeys,
      payloadType: envelope.payloadType,
      encryptedPayload: envelope.encryptedPayload,
      payloadSize: envelope.payloadSize,
      threadId: envelope.threadId,
      replyToId: envelope.replyToId,
      timestamp: envelope.timestamp,
      expiresAt: envelope.expiresAt,
      ephemeralPublicKey: envelope.ephemeralPublicKey,
      recipientKeys: envelope.recipientKeys,
      nonce: envelope.nonce,
      signature: signature,
      priority: envelope.priority,
      requestReadReceipt: envelope.requestReadReceipt,
    );
  }

  /// Convert hex string to bytes
  Uint8List _hexToBytes(String hex) {
    final result = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < hex.length; i += 2) {
      result[i ~/ 2] = int.parse(hex.substring(i, i + 2), radix: 16);
    }
    return result;
  }

  /// Generate a cryptographically unique message ID
  /// ✅ CRITICAL FIX: Uses UUID v4 to prevent collisions
  String _generateMessageId() {
    // UUID v4 = 128-bit random ID, cryptographically unique
    // No collision risk even with high-frequency messaging
    return _uuid.v4();
  }

  /// Generate deterministic thread ID from participants
  String _generateThreadId(List<String> participantKeys) {
    // Sort keys for deterministic ID
    final sorted = List<String>.from(participantKeys)..sort();
    final combined = sorted.join(':');
    
    // Simple hash - in production use proper hash function
    var hash = 0;
    for (var i = 0; i < combined.length; i++) {
      hash = ((hash << 5) - hash + combined.codeUnitAt(i)) & 0xFFFFFFFF;
    }
    
    return 'thread_${hash.toRadixString(16).padLeft(8, '0')}';
  }

  /// Dispose resources
  Future<void> dispose() async {
    await _incomingEnvelopesSubscription?.cancel();
    await _relayChannel.dispose();
    await _messageController.close();
    await _typingController.close();
  }

  /// Sync a decrypted message to any paired Panthera browser.
  /// The backend forwards it via WebSocket as 'message_synced'.
  void _syncMessageToBrowser({
    required GnsMessage message,
    required String otherPublicKey,
    String? otherHandle,
    String direction = 'incoming',
  }) {
    try {
      final text = message.textContent ?? '';
      if (text.isEmpty) return; // only sync text messages for now

      _relayChannel.sendRaw(jsonEncode({
        'type': 'sync_to_browser',
        'messageId': message.id,
        'conversationWith': otherPublicKey,
        'decryptedText': text,
        'direction': direction,
        'timestamp': message.timestamp.millisecondsSinceEpoch,
        'fromHandle': otherHandle ?? '',
      }));

      debugPrint('🌐 Synced to browser: ${message.id.substring(0, 8)}...');
    } catch (e) {
      debugPrint('⚠️ Browser sync failed (non-critical): $e');
    }
  }
}

/// Typing event
class TypingEvent {
  final String threadId;
  final String publicKey;
  final bool isTyping;
  final DateTime timestamp;

  TypingEvent({
    required this.threadId,
    required this.publicKey,
    required this.isTyping,
    required this.timestamp,
  });
}
