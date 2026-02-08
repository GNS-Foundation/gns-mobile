/// GNS Webhook Service - Sprint 8
/// 
/// Manages merchant webhooks for real-time event notifications.
/// 
/// Features:
/// - Webhook endpoint registration
/// - Event subscriptions
/// - Delivery retry with exponential backoff
/// - Signature verification
/// - Delivery logs
/// 
/// Location: lib/core/webhooks/webhook_service.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';

/// Webhook event types
enum WebhookEventType {
  // Payment events
  paymentReceived,
  paymentCompleted,
  paymentFailed,
  paymentRefunded,
  
  // Settlement events
  settlementCreated,
  settlementCompleted,
  settlementFailed,
  batchSettlementCompleted,
  
  // Subscription events
  subscriptionCreated,
  subscriptionActivated,
  subscriptionCancelled,
  subscriptionRenewed,
  subscriptionPaymentFailed,
  
  // Customer events
  customerCreated,
  customerUpdated,
  trustlineAdded,
  
  // Refund events
  refundRequested,
  refundApproved,
  refundRejected,
  refundCompleted,
}

/// Webhook delivery status
enum WebhookDeliveryStatus {
  pending,
  delivered,
  failed,
  retrying,
}

/// Webhook endpoint configuration
class WebhookEndpoint {
  final String endpointId;
  final String url;
  final String? description;
  final List<WebhookEventType> events;
  final String secret;
  final bool isActive;
  final DateTime createdAt;
  final DateTime? lastDeliveryAt;
  final int successCount;
  final int failureCount;
  
  WebhookEndpoint({
    required this.endpointId,
    required this.url,
    this.description,
    required this.events,
    required this.secret,
    this.isActive = true,
    required this.createdAt,
    this.lastDeliveryAt,
    this.successCount = 0,
    this.failureCount = 0,
  });
  
  double get successRate {
    final total = successCount + failureCount;
    return total > 0 ? successCount / total : 1.0;
  }
  
  factory WebhookEndpoint.fromJson(Map<String, dynamic> json) {
    return WebhookEndpoint(
      endpointId: json['endpoint_id'] as String,
      url: json['url'] as String,
      description: json['description'] as String?,
      events: (json['events'] as List)
          .map((e) => WebhookEventType.values.firstWhere(
                (t) => t.name == e,
                orElse: () => WebhookEventType.paymentReceived,
              ))
          .toList(),
      secret: json['secret'] as String,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
      lastDeliveryAt: json['last_delivery_at'] != null
          ? DateTime.parse(json['last_delivery_at'] as String)
          : null,
      successCount: json['success_count'] as int? ?? 0,
      failureCount: json['failure_count'] as int? ?? 0,
    );
  }
  
  Map<String, dynamic> toJson() => {
    'endpoint_id': endpointId,
    'url': url,
    if (description != null) 'description': description,
    'events': events.map((e) => e.name).toList(),
    'secret': secret,
    'is_active': isActive,
    'created_at': createdAt.toIso8601String(),
    if (lastDeliveryAt != null) 'last_delivery_at': lastDeliveryAt!.toIso8601String(),
    'success_count': successCount,
    'failure_count': failureCount,
  };
}

/// Webhook event payload
class WebhookEvent {
  final String eventId;
  final WebhookEventType type;
  final Map<String, dynamic> data;
  final DateTime timestamp;
  final String? relatedId; // Payment ID, subscription ID, etc.
  
  WebhookEvent({
    required this.eventId,
    required this.type,
    required this.data,
    required this.timestamp,
    this.relatedId,
  });
  
  factory WebhookEvent.fromJson(Map<String, dynamic> json) {
    return WebhookEvent(
      eventId: json['event_id'] as String,
      type: WebhookEventType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => WebhookEventType.paymentReceived,
      ),
      data: json['data'] as Map<String, dynamic>,
      timestamp: DateTime.parse(json['timestamp'] as String),
      relatedId: json['related_id'] as String?,
    );
  }
  
  Map<String, dynamic> toJson() => {
    'event_id': eventId,
    'type': type.name,
    'data': data,
    'timestamp': timestamp.toIso8601String(),
    if (relatedId != null) 'related_id': relatedId,
  };
}

/// Webhook delivery attempt
class WebhookDelivery {
  final String deliveryId;
  final String endpointId;
  final String eventId;
  final WebhookEventType eventType;
  final WebhookDeliveryStatus status;
  final int httpStatus;
  final String? responseBody;
  final int attemptNumber;
  final DateTime attemptedAt;
  final int? durationMs;
  final String? errorMessage;
  
  WebhookDelivery({
    required this.deliveryId,
    required this.endpointId,
    required this.eventId,
    required this.eventType,
    required this.status,
    this.httpStatus = 0,
    this.responseBody,
    required this.attemptNumber,
    required this.attemptedAt,
    this.durationMs,
    this.errorMessage,
  });
  
  bool get isSuccess => status == WebhookDeliveryStatus.delivered;
  
  factory WebhookDelivery.fromJson(Map<String, dynamic> json) {
    return WebhookDelivery(
      deliveryId: json['delivery_id'] as String,
      endpointId: json['endpoint_id'] as String,
      eventId: json['event_id'] as String,
      eventType: WebhookEventType.values.firstWhere(
        (t) => t.name == json['event_type'],
        orElse: () => WebhookEventType.paymentReceived,
      ),
      status: WebhookDeliveryStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => WebhookDeliveryStatus.pending,
      ),
      httpStatus: json['http_status'] as int? ?? 0,
      responseBody: json['response_body'] as String?,
      attemptNumber: json['attempt_number'] as int,
      attemptedAt: DateTime.parse(json['attempted_at'] as String),
      durationMs: json['duration_ms'] as int?,
      errorMessage: json['error_message'] as String?,
    );
  }
}

/// Webhook test result
class WebhookTestResult {
  final bool success;
  final int httpStatus;
  final int durationMs;
  final String? responseBody;
  final String? error;
  
  WebhookTestResult({
    required this.success,
    this.httpStatus = 0,
    this.durationMs = 0,
    this.responseBody,
    this.error,
  });
}

/// GNS Webhook Service (for merchants)
class WebhookService {
  static final WebhookService _instance = WebhookService._internal();
  factory WebhookService() => _instance;
  WebhookService._internal();
  
  static const _baseUrl = 'https://api.gns.network';
  
  String? _merchantApiKey;
  String? _merchantId;
  
  /// Initialize with merchant credentials
  Future<void> initialize({
    required String merchantApiKey,
    required String merchantId,
  }) async {
    _merchantApiKey = merchantApiKey;
    _merchantId = merchantId;
    debugPrint('🪝 Webhook Service initialized');
  }
  
  /// Get all webhook endpoints
  Future<List<WebhookEndpoint>> getEndpoints() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/webhooks/endpoints'),
        headers: _headers,
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'] as List;
        return data.map((e) => WebhookEndpoint.fromJson(e)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('Get endpoints error: $e');
      return [];
    }
  }
  
  /// Create webhook endpoint
  Future<WebhookEndpoint?> createEndpoint({
    required String url,
    String? description,
    required List<WebhookEventType> events,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/webhooks/endpoints'),
        headers: _headers,
        body: jsonEncode({
          'url': url,
          if (description != null) 'description': description,
          'events': events.map((e) => e.name).toList(),
        }),
      );
      
      if (response.statusCode == 201) {
        final data = jsonDecode(response.body)['data'];
        debugPrint('✅ Webhook endpoint created');
        return WebhookEndpoint.fromJson(data);
      }
      return null;
    } catch (e) {
      debugPrint('Create endpoint error: $e');
      return null;
    }
  }
  
  /// Update webhook endpoint
  Future<WebhookEndpoint?> updateEndpoint(
    String endpointId, {
    String? url,
    String? description,
    List<WebhookEventType>? events,
    bool? isActive,
  }) async {
    try {
      final response = await http.put(
        Uri.parse('$_baseUrl/webhooks/endpoints/$endpointId'),
        headers: _headers,
        body: jsonEncode({
          if (url != null) 'url': url,
          if (description != null) 'description': description,
          if (events != null) 'events': events.map((e) => e.name).toList(),
          if (isActive != null) 'is_active': isActive,
        }),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'];
        return WebhookEndpoint.fromJson(data);
      }
      return null;
    } catch (e) {
      debugPrint('Update endpoint error: $e');
      return null;
    }
  }
  
  /// Delete webhook endpoint
  Future<bool> deleteEndpoint(String endpointId) async {
    try {
      final response = await http.delete(
        Uri.parse('$_baseUrl/webhooks/endpoints/$endpointId'),
        headers: _headers,
      );
      
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Delete endpoint error: $e');
      return false;
    }
  }
  
  /// Rotate endpoint secret
  Future<String?> rotateSecret(String endpointId) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/webhooks/endpoints/$endpointId/rotate-secret'),
        headers: _headers,
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'];
        return data['secret'] as String;
      }
      return null;
    } catch (e) {
      debugPrint('Rotate secret error: $e');
      return null;
    }
  }
  
  /// Test webhook endpoint
  Future<WebhookTestResult> testEndpoint(String endpointId) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/webhooks/endpoints/$endpointId/test'),
        headers: _headers,
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'];
        return WebhookTestResult(
          success: data['success'] as bool,
          httpStatus: data['http_status'] as int? ?? 0,
          durationMs: data['duration_ms'] as int? ?? 0,
          responseBody: data['response_body'] as String?,
        );
      }
      
      return WebhookTestResult(success: false, error: 'Test failed');
    } catch (e) {
      return WebhookTestResult(success: false, error: e.toString());
    }
  }
  
  /// Get recent events
  Future<List<WebhookEvent>> getEvents({
    WebhookEventType? type,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final queryParams = <String, String>{
        'limit': limit.toString(),
        'offset': offset.toString(),
      };
      if (type != null) queryParams['type'] = type.name;
      
      final uri = Uri.parse('$_baseUrl/webhooks/events')
          .replace(queryParameters: queryParams);
      
      final response = await http.get(uri, headers: _headers);
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'] as List;
        return data.map((e) => WebhookEvent.fromJson(e)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('Get events error: $e');
      return [];
    }
  }
  
  /// Get delivery attempts for an event
  Future<List<WebhookDelivery>> getDeliveries({
    String? eventId,
    String? endpointId,
    WebhookDeliveryStatus? status,
    int limit = 50,
  }) async {
    try {
      final queryParams = <String, String>{
        'limit': limit.toString(),
      };
      if (eventId != null) queryParams['event_id'] = eventId;
      if (endpointId != null) queryParams['endpoint_id'] = endpointId;
      if (status != null) queryParams['status'] = status.name;
      
      final uri = Uri.parse('$_baseUrl/webhooks/deliveries')
          .replace(queryParameters: queryParams);
      
      final response = await http.get(uri, headers: _headers);
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'] as List;
        return data.map((d) => WebhookDelivery.fromJson(d)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('Get deliveries error: $e');
      return [];
    }
  }
  
  /// Retry failed delivery
  Future<bool> retryDelivery(String deliveryId) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/webhooks/deliveries/$deliveryId/retry'),
        headers: _headers,
      );
      
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Retry delivery error: $e');
      return false;
    }
  }
  
  /// Verify webhook signature (for receiving webhooks)
  static bool verifySignature({
    required String payload,
    required String signature,
    required String secret,
  }) {
    final expectedSignature = _generateSignature(payload, secret);
    return signature == expectedSignature;
  }
  
  static String _generateSignature(String payload, String secret) {
    final hmac = Hmac(sha256, utf8.encode(secret));
    final digest = hmac.convert(utf8.encode(payload));
    return 'sha256=${digest.toString()}';
  }
  
  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'X-GNS-Merchant-Key': _merchantApiKey ?? '',
  };
}

/// Webhook event type extensions
extension WebhookEventTypeExtension on WebhookEventType {
  String get displayName {
    switch (this) {
      case WebhookEventType.paymentReceived:
        return 'Payment Received';
      case WebhookEventType.paymentCompleted:
        return 'Payment Completed';
      case WebhookEventType.paymentFailed:
        return 'Payment Failed';
      case WebhookEventType.paymentRefunded:
        return 'Payment Refunded';
      case WebhookEventType.settlementCreated:
        return 'Settlement Created';
      case WebhookEventType.settlementCompleted:
        return 'Settlement Completed';
      case WebhookEventType.settlementFailed:
        return 'Settlement Failed';
      case WebhookEventType.batchSettlementCompleted:
        return 'Batch Settlement Completed';
      case WebhookEventType.subscriptionCreated:
        return 'Subscription Created';
      case WebhookEventType.subscriptionActivated:
        return 'Subscription Activated';
      case WebhookEventType.subscriptionCancelled:
        return 'Subscription Cancelled';
      case WebhookEventType.subscriptionRenewed:
        return 'Subscription Renewed';
      case WebhookEventType.subscriptionPaymentFailed:
        return 'Subscription Payment Failed';
      case WebhookEventType.customerCreated:
        return 'Customer Created';
      case WebhookEventType.customerUpdated:
        return 'Customer Updated';
      case WebhookEventType.trustlineAdded:
        return 'Trustline Added';
      case WebhookEventType.refundRequested:
        return 'Refund Requested';
      case WebhookEventType.refundApproved:
        return 'Refund Approved';
      case WebhookEventType.refundRejected:
        return 'Refund Rejected';
      case WebhookEventType.refundCompleted:
        return 'Refund Completed';
    }
  }
  
  String get category {
    switch (this) {
      case WebhookEventType.paymentReceived:
      case WebhookEventType.paymentCompleted:
      case WebhookEventType.paymentFailed:
      case WebhookEventType.paymentRefunded:
        return 'Payments';
      case WebhookEventType.settlementCreated:
      case WebhookEventType.settlementCompleted:
      case WebhookEventType.settlementFailed:
      case WebhookEventType.batchSettlementCompleted:
        return 'Settlements';
      case WebhookEventType.subscriptionCreated:
      case WebhookEventType.subscriptionActivated:
      case WebhookEventType.subscriptionCancelled:
      case WebhookEventType.subscriptionRenewed:
      case WebhookEventType.subscriptionPaymentFailed:
        return 'Subscriptions';
      case WebhookEventType.customerCreated:
      case WebhookEventType.customerUpdated:
      case WebhookEventType.trustlineAdded:
        return 'Customers';
      case WebhookEventType.refundRequested:
      case WebhookEventType.refundApproved:
      case WebhookEventType.refundRejected:
      case WebhookEventType.refundCompleted:
        return 'Refunds';
    }
  }
}
