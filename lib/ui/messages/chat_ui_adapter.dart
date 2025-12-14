import 'package:flutter_chat_types/flutter_chat_types.dart' as types;
import '../../core/comm/gns_envelope.dart';
import '../../core/comm/message_storage.dart';  // ✅ ADDED - for GnsMessage
import '../../core/comm/communication_service.dart';

class ChatUIAdapter {
  final CommunicationService commService;
  
  ChatUIAdapter(this.commService);
  
  // Convert GnsMessage → flutter_chat_ui Message
  types.Message toFlutterMessage(GnsMessage gnsMsg) {
    final author = types.User(
      id: gnsMsg.fromPublicKey,
      firstName: gnsMsg.fromHandle ?? gnsMsg.fromPublicKey.substring(0, 8),
    );
    
    // Determine message status
    types.Status status;
    if (gnsMsg.isOutgoing) {
      // For outgoing messages, show as sent
      status = types.Status.sent;
    } else {
      // For incoming messages, show as seen
      status = types.Status.seen;
    }
    
    return types.TextMessage(
      id: gnsMsg.id,
      author: author,
      text: gnsMsg.textContent ?? '',
      createdAt: gnsMsg.timestamp.millisecondsSinceEpoch,
      status: status,  // ✅ FIXED
    );
  }
  
  // Get current user
  types.User get currentUser => types.User(
    id: commService.myPublicKey ?? 'unknown',  // ✅ FIXED - handle null
    firstName: 'You',
  );
}