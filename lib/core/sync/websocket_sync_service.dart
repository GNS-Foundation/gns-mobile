import 'dart:async';
import 'package:flutter/foundation.dart';

abstract class SyncEvent {}

class MessageReceivedEvent extends SyncEvent {
  final String conversationWith;
  final String messageId;

  MessageReceivedEvent({
    required this.conversationWith,
    required this.messageId,
  });
}

class WebSocketSyncService {
  static final WebSocketSyncService _instance = WebSocketSyncService._internal();

  factory WebSocketSyncService() {
    return _instance;
  }

  WebSocketSyncService._internal() {
    // TODO: Initialize real WebSocket connection and listen for incoming events
  }

  final _eventController = StreamController<SyncEvent>.broadcast();

  Stream<SyncEvent> get events => _eventController.stream;

  void emitEvent(SyncEvent event) {
    _eventController.add(event);
  }

  void dispose() {
    _eventController.close();
  }
}
