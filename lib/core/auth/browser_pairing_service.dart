/// Browser Pairing Service v2 - QR Auth WITH Message Sync
/// 
/// Phase B: Mobile decrypts messages and sends to browser
/// 
/// Location: lib/core/auth/browser_pairing_service.dart

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:cryptography/cryptography.dart';

// Your existing imports - adjust paths as needed
import '../gns/identity_wallet.dart';
import '../comm/message_storage.dart';
import '../comm/gns_envelope.dart';
import '../vault/gns_channel_service.dart';

/// QR code data from browser
class BrowserAuthRequest {
  final String type;
  final int version;
  final String sessionId;
  final String challenge;
  final String browserInfo;
  final int expiresAt;

  BrowserAuthRequest({
    required this.type,
    required this.version,
    required this.sessionId,
    required this.challenge,
    required this.browserInfo,
    required this.expiresAt,
  });

  factory BrowserAuthRequest.fromJson(Map<String, dynamic> json) {
    return BrowserAuthRequest(
      type: json['type'] as String,
      version: json['version'] as int? ?? 1,
      sessionId: json['sessionId'] as String,
      challenge: json['challenge'] as String,
      browserInfo: json['browserInfo'] as String? ?? 'Unknown Browser',
      expiresAt: json['expiresAt'] as int,
    );
  }

  factory BrowserAuthRequest.fromQRData(String qrData) {
    try {
      final json = jsonDecode(qrData) as Map<String, dynamic>;
      return BrowserAuthRequest.fromJson(json);
    } catch (e) {
      throw FormatException('Invalid QR code data: $e');
    }
  }

  bool get isExpired => DateTime.now().millisecondsSinceEpoch > expiresAt;
  bool get isValid => type == 'gns_browser_auth' && !isExpired;
  bool get supportsMessageSync => version >= 2;

  Duration get timeRemaining {
    final remaining = expiresAt - DateTime.now().millisecondsSinceEpoch;
    return Duration(milliseconds: remaining > 0 ? remaining : 0);
  }
}

/// Decrypted message for sync
class DecryptedMessageSync {
  final String id;
  final String direction; // 'incoming' or 'outgoing'
  final String text;
  final int timestamp;
  final String? status;

  DecryptedMessageSync({
    required this.id,
    required this.direction,
    required this.text,
    required this.timestamp,
    this.status,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'direction': direction,
    'text': text,
    'timestamp': timestamp,
    if (status != null) 'status': status,
  };
}

/// Conversation sync data
class ConversationSync {
  final String withPublicKey;
  final String? withHandle;
  final List<DecryptedMessageSync> messages;
  final int lastSyncedAt;

  ConversationSync({
    required this.withPublicKey,
    this.withHandle,
    required this.messages,
    required this.lastSyncedAt,
  });

  Map<String, dynamic> toJson() => {
    'withPublicKey': withPublicKey,
    if (withHandle != null) 'withHandle': withHandle,
    'messages': messages.map((m) => m.toJson()).toList(),
    'lastSyncedAt': lastSyncedAt,
  };
}



/// Result of approval/rejection
class BrowserAuthResult {
  final bool success;
  final String? error;
  final String? sessionId;
  final String? sessionToken;   // stored by app to reconnect channel
  final int messagesSynced;

  BrowserAuthResult.success(this.sessionId, {this.messagesSynced = 0, this.sessionToken})
      : success = true, error = null;
  BrowserAuthResult.failure(this.error)
      : success = false, sessionId = null, sessionToken = null, messagesSynced = 0;
}

/// Browser Pairing Service v2
/// 
/// Key changes from v1:
/// - Generates SESSION encryption keys (not permanent)
/// - Decrypts recent messages before approval
/// - Sends pre-decrypted history to browser
class BrowserPairingService {
  static const String _baseUrl = 'https://gns-browser-production.up.railway.app';
  static const int _maxConversationsToSync = 20;
  static const int _maxMessagesPerConversation = 50;
  
  final IdentityWallet _wallet;
  final MessageStorage _storage;
  final Dio _dio;

  BrowserPairingService({
    required IdentityWallet wallet,
    required MessageStorage storage,
  }) : _wallet = wallet,
       _storage = storage,
       _dio = Dio(BaseOptions(
         baseUrl: _baseUrl,
         connectTimeout: const Duration(seconds: 15),
         receiveTimeout: const Duration(seconds: 15),
       ));

  /// Parse QR code data
  BrowserAuthRequest? parseQRCode(String qrData) {
    try {
      final request = BrowserAuthRequest.fromQRData(qrData);
      
      if (!request.isValid) {
        debugPrint('âŒ Invalid or expired QR code');
        return null;
      }
      
      debugPrint('âœ… Valid browser auth QR: ${request.sessionId.substring(0, 8)}...');
      debugPrint('   Browser: ${request.browserInfo}');
      debugPrint('   Version: ${request.version} (sync: ${request.supportsMessageSync})');
      debugPrint('   Expires in: ${request.timeRemaining.inSeconds}s');
      
      return request;
    } catch (e) {
      debugPrint('âŒ Failed to parse QR code: $e');
      return null;
    }
  }



  /// Prepare recent messages for sync
  /// Messages are ALREADY DECRYPTED in MessageStorage!
  Future<List<ConversationSync>> _prepareMessageSync() async {
    debugPrint('ðŸ“¨ Preparing message sync for browser...');
    
    final myPublicKey = _wallet.publicKey;
    if (myPublicKey == null) {
      debugPrint('   âš ï¸ No public key available');
      return [];
    }
    
    final results = <ConversationSync>[];
    
    try {
      // 1. Get recent threads from MessageStorage
      final threads = await _storage.getThreads(
        includeArchived: false,
        limit: _maxConversationsToSync,
      );
      
      debugPrint('   Found ${threads.length} conversations');
      
      // 2. For each thread, get messages
      for (final threadPreview in threads) {
        final thread = threadPreview.thread;
        
        // Skip group chats for now (direct only)
        if (!thread.isDirect) {
          debugPrint('   Skipping group thread: ${thread.id}');
          continue;
        }
        
        // Get the other participant's public key
        final otherPublicKey = thread.otherParticipant(myPublicKey);
        if (otherPublicKey == null) {
          debugPrint('   âš ï¸ Could not determine other party for thread: ${thread.id}');
          continue;
        }
        
        // 3. Get messages for this thread (ALREADY DECRYPTED in storage!)
        final messages = await _storage.getMessages(
          thread.id,
          limit: _maxMessagesPerConversation,
        );
        
        if (messages.isEmpty) {
          debugPrint('   Skipping empty thread: ${thread.title ?? thread.id}');
          continue;
        }
        
        // 4. Transform GnsMessage to DecryptedMessageSync
        final syncMessages = <DecryptedMessageSync>[];
        
        for (final msg in messages) {
          // Get text content - messages are already decrypted in MessageStorage
          final text = msg.textContent ?? msg.previewText;
          
          if (text.isEmpty || text == 'Message deleted') {
            continue;
          }
          
          syncMessages.add(DecryptedMessageSync(
            id: msg.id,
            direction: msg.isOutgoing ? 'outgoing' : 'incoming',
            text: text,
            timestamp: msg.timestamp.millisecondsSinceEpoch,
            status: msg.status.name,
          ));
        }
        
        if (syncMessages.isEmpty) continue;
        
        // 5. Build conversation sync object
        results.add(ConversationSync(
          withPublicKey: otherPublicKey,
          withHandle: thread.title,  // This is often the handle
          messages: syncMessages,
          lastSyncedAt: DateTime.now().millisecondsSinceEpoch,
        ));
        
        debugPrint('   âœ… ${thread.title ?? otherPublicKey.substring(0, 8)}: ${syncMessages.length} messages');
      }
      
      final totalMessages = results.fold<int>(0, (sum, c) => sum + c.messages.length);
      debugPrint('ðŸ“¨ Sync prepared: ${results.length} conversations, $totalMessages messages');
      
      return results;
      
    } catch (e, stack) {
      debugPrint('âŒ Error preparing message sync: $e');
      debugPrint('   Stack: $stack');
      return [];
    }
  }

  /// Approve browser session WITH message sync
  /// This is the key Phase B method
  Future<BrowserAuthResult> approveSession(BrowserAuthRequest request) async {
    try {
      if (!request.isValid) {
        return BrowserAuthResult.failure('Session expired');
      }

      if (_wallet.publicKey == null || _wallet.privateKeyBytes == null) {
        return BrowserAuthResult.failure('Wallet not initialized');
      }

      debugPrint('ðŸ” Approving browser session with message sync...');

      // âœ… Get mobile's PERMANENT encryption key from wallet
      // Browser will use this to create dual-encrypted envelopes
      final mobileEncryptionKey = _wallet.encryptionPublicKeyHex;
      
      if (mobileEncryptionKey == null) {
        return BrowserAuthResult.failure('Wallet encryption key not available');
      }
      
      debugPrint('   ðŸ”‘ Mobile encryption key: ${mobileEncryptionKey.substring(0, 16)}...');

      // Decrypt recent messages for sync (if browser supports it)
      List<ConversationSync> messageSync = [];
      if (request.supportsMessageSync) {
        messageSync = await _prepareMessageSync();
      }
      
      final totalMessages = messageSync.fold<int>(0, (sum, c) => sum + c.messages.length);

      // 3. Sign the approval
      final signedData = {
        'action': 'approve',
        'challenge': request.challenge,
        'publicKey': _wallet.publicKey!.toLowerCase(),
        'sessionId': request.sessionId,
      };

      final canonicalString = _canonicalJson(signedData);
      debugPrint('   Signing approval...');

      final signature = await _wallet.signBytes(utf8.encode(canonicalString));
      
      if (signature == null) {
        return BrowserAuthResult.failure('Failed to sign');
      }

      final signatureHex = _bytesToHex(signature);

      // 4. Send approval with session keys + message sync
      debugPrint('   Sending approval to server...');
      
      final response = await _dio.post(
        '/auth/sessions/approve',
        data: {
          'sessionId': request.sessionId,
          'publicKey': _wallet.publicKey,
          'signature': signatureHex,
          'deviceInfo': {
            'platform': defaultTargetPlatform.name,
            'approvedAt': DateTime.now().toIso8601String(),
          },
          // âœ… CRITICAL: Mobile's PERMANENT X25519 public key for dual encryption
          // Browser will use this to encrypt the "sender copy" of messages
          // This is the wallet's permanent encryption key, NOT a temporary session key!
          'encryptionKey': mobileEncryptionKey,  // â† Wallet's permanent key!
          
          // Pre-decrypted message history
          'messageSync': {
            'conversations': messageSync.map((c) => c.toJson()).toList(),
          },
        },
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        final messagesSynced = response.data['data']?['messagesSynced'] ?? totalMessages;
        final sessionToken   = response.data['data']?['sessionToken'] as String?;

        debugPrint('[PAIRING] Browser session approved! Messages: $messagesSynced');

        // Connect the persistent mobile WebSocket channel.
        // This receives credential_request events from the Chrome extension in real-time.
        if (sessionToken != null && _wallet.publicKey != null) {
          debugPrint('[PAIRING] Starting persistent mobile channel...');
          await GnsChannelService().connect(
            publicKey:    _wallet.publicKey!,
            sessionToken: sessionToken,
          );
        }

        return BrowserAuthResult.success(
          request.sessionId,
          messagesSynced: messagesSynced,
          sessionToken: sessionToken,
        );
      } else {
        final error = response.data['error'] ?? 'Approval failed';
        debugPrint('âŒ Approval failed: $error');
        return BrowserAuthResult.failure(error);
      }
    } catch (e) {
      debugPrint('âŒ Approval error: $e');
      if (e is DioException) {
        final message = e.response?.data?['error'] ?? e.message;
        return BrowserAuthResult.failure(message);
      }
      return BrowserAuthResult.failure(e.toString());
    }
  }

  /// Reject browser session
  Future<BrowserAuthResult> rejectSession(BrowserAuthRequest request) async {
    try {
      debugPrint('âŒ Rejecting browser session...');

      final signedData = {
        'action': 'reject',
        'challenge': request.challenge,
        'publicKey': _wallet.publicKey!.toLowerCase(),
        'sessionId': request.sessionId,
      };

      final canonicalString = _canonicalJson(signedData);
      final signature = await _wallet.signBytes(utf8.encode(canonicalString));
      final signatureHex = signature != null ? _bytesToHex(signature) : '';

      await _dio.post(
        '/auth/sessions/reject',
        data: {
          'sessionId': request.sessionId,
          'publicKey': _wallet.publicKey,
          'signature': signatureHex,
        },
      );

      debugPrint('âœ… Browser session rejected');
      return BrowserAuthResult.success(request.sessionId);
    } catch (e) {
      debugPrint('âŒ Reject error: $e');
      return BrowserAuthResult.failure(e.toString());
    }
  }

  /// Get list of active browser sessions
  Future<List<Map<String, dynamic>>> getActiveSessions() async {
    try {
      final response = await _dio.get(
        '/auth/sessions',
        options: Options(headers: {
          'X-GNS-PublicKey': _wallet.publicKey,
        }),
      );

      if (response.data['success'] == true) {
        return List<Map<String, dynamic>>.from(response.data['data'] ?? []);
      }

      return [];
    } catch (e) {
      debugPrint('Error fetching sessions: $e');
      return [];
    }
  }

  /// Revoke all browser sessions
  Future<bool> revokeAllSessions() async {
    try {
      final response = await _dio.post(
        '/auth/sessions/revoke-all',
        options: Options(headers: {
          'X-GNS-PublicKey': _wallet.publicKey,
        }),
      );

      return response.data['success'] == true;
    } catch (e) {
      debugPrint('Error revoking sessions: $e');
      return false;
    }
  }

  /// Canonical JSON (keys sorted alphabetically)
  String _canonicalJson(Map<String, dynamic> obj) {
    final sortedKeys = obj.keys.toList()..sort();
    final pairs = sortedKeys.map((k) {
      final v = obj[k];
      final value = v is String ? '"$v"' : v.toString();
      return '"$k":$value';
    });
    return '{${pairs.join(',')}}';
  }

  /// Convert bytes to hex string
  String _bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}