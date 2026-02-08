/// GNS Push Notification Service - Sprint 7
/// 
/// Handles push notifications for:
/// - Payment received/sent
/// - Refund status updates
/// - Loyalty rewards
/// - Subscription reminders
/// - Security alerts
/// 
/// Supports: FCM (Android/iOS), APNs (iOS), Web Push
/// 
/// Location: lib/core/notifications/push_notification_service.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Notification types
enum GnsNotificationType {
  // Payments
  paymentReceived,
  paymentSent,
  paymentFailed,
  paymentRequest,
  
  // Refunds
  refundRequested,
  refundApproved,
  refundRejected,
  refundCompleted,
  
  // Loyalty
  pointsEarned,
  tierUpgrade,
  rewardAvailable,
  achievementUnlocked,
  
  // Subscriptions
  subscriptionRenewal,
  subscriptionExpiring,
  subscriptionCancelled,
  paymentDue,
  
  // Security
  newDeviceLogin,
  suspiciousActivity,
  passwordChanged,
  
  // System
  systemUpdate,
  maintenanceScheduled,
  featureAnnouncement,
}

/// Notification priority
enum NotificationPriority {
  low,
  normal,
  high,
  urgent,
}

/// Notification channel (for Android)
enum NotificationChannel {
  payments,
  refunds,
  loyalty,
  subscriptions,
  security,
  system,
}

/// GNS Notification model
class GnsNotification {
  final String notificationId;
  final GnsNotificationType type;
  final String title;
  final String body;
  final Map<String, dynamic>? data;
  final NotificationPriority priority;
  final NotificationChannel channel;
  final DateTime timestamp;
  final bool isRead;
  final String? imageUrl;
  final String? actionUrl;
  
  GnsNotification({
    required this.notificationId,
    required this.type,
    required this.title,
    required this.body,
    this.data,
    this.priority = NotificationPriority.normal,
    required this.channel,
    required this.timestamp,
    this.isRead = false,
    this.imageUrl,
    this.actionUrl,
  });
  
  factory GnsNotification.fromJson(Map<String, dynamic> json) {
    return GnsNotification(
      notificationId: json['notification_id'] as String,
      type: GnsNotificationType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => GnsNotificationType.systemUpdate,
      ),
      title: json['title'] as String,
      body: json['body'] as String,
      data: json['data'] as Map<String, dynamic>?,
      priority: NotificationPriority.values.firstWhere(
        (p) => p.name == json['priority'],
        orElse: () => NotificationPriority.normal,
      ),
      channel: NotificationChannel.values.firstWhere(
        (c) => c.name == json['channel'],
        orElse: () => NotificationChannel.system,
      ),
      timestamp: DateTime.parse(json['timestamp'] as String),
      isRead: json['is_read'] as bool? ?? false,
      imageUrl: json['image_url'] as String?,
      actionUrl: json['action_url'] as String?,
    );
  }
  
  Map<String, dynamic> toJson() => {
    'notification_id': notificationId,
    'type': type.name,
    'title': title,
    'body': body,
    if (data != null) 'data': data,
    'priority': priority.name,
    'channel': channel.name,
    'timestamp': timestamp.toIso8601String(),
    'is_read': isRead,
    if (imageUrl != null) 'image_url': imageUrl,
    if (actionUrl != null) 'action_url': actionUrl,
  };
}

/// Notification preferences
class NotificationPreferences {
  // Payments
  final bool paymentReceived;
  final bool paymentSent;
  final bool paymentFailed;
  final bool paymentRequest;
  
  // Refunds
  final bool refundUpdates;
  
  // Loyalty
  final bool pointsEarned;
  final bool tierUpgrade;
  final bool rewardAvailable;
  final bool achievementUnlocked;
  
  // Subscriptions
  final bool subscriptionReminders;
  
  // Security
  final bool securityAlerts;
  
  // System
  final bool systemUpdates;
  final bool marketingMessages;
  
  // Quiet hours
  final bool quietHoursEnabled;
  final int quietHoursStart; // 0-23
  final int quietHoursEnd; // 0-23
  
  NotificationPreferences({
    this.paymentReceived = true,
    this.paymentSent = true,
    this.paymentFailed = true,
    this.paymentRequest = true,
    this.refundUpdates = true,
    this.pointsEarned = true,
    this.tierUpgrade = true,
    this.rewardAvailable = true,
    this.achievementUnlocked = true,
    this.subscriptionReminders = true,
    this.securityAlerts = true,
    this.systemUpdates = true,
    this.marketingMessages = false,
    this.quietHoursEnabled = false,
    this.quietHoursStart = 22,
    this.quietHoursEnd = 8,
  });
  
  factory NotificationPreferences.fromJson(Map<String, dynamic> json) {
    return NotificationPreferences(
      paymentReceived: json['payment_received'] as bool? ?? true,
      paymentSent: json['payment_sent'] as bool? ?? true,
      paymentFailed: json['payment_failed'] as bool? ?? true,
      paymentRequest: json['payment_request'] as bool? ?? true,
      refundUpdates: json['refund_updates'] as bool? ?? true,
      pointsEarned: json['points_earned'] as bool? ?? true,
      tierUpgrade: json['tier_upgrade'] as bool? ?? true,
      rewardAvailable: json['reward_available'] as bool? ?? true,
      achievementUnlocked: json['achievement_unlocked'] as bool? ?? true,
      subscriptionReminders: json['subscription_reminders'] as bool? ?? true,
      securityAlerts: json['security_alerts'] as bool? ?? true,
      systemUpdates: json['system_updates'] as bool? ?? true,
      marketingMessages: json['marketing_messages'] as bool? ?? false,
      quietHoursEnabled: json['quiet_hours_enabled'] as bool? ?? false,
      quietHoursStart: json['quiet_hours_start'] as int? ?? 22,
      quietHoursEnd: json['quiet_hours_end'] as int? ?? 8,
    );
  }
  
  Map<String, dynamic> toJson() => {
    'payment_received': paymentReceived,
    'payment_sent': paymentSent,
    'payment_failed': paymentFailed,
    'payment_request': paymentRequest,
    'refund_updates': refundUpdates,
    'points_earned': pointsEarned,
    'tier_upgrade': tierUpgrade,
    'reward_available': rewardAvailable,
    'achievement_unlocked': achievementUnlocked,
    'subscription_reminders': subscriptionReminders,
    'security_alerts': securityAlerts,
    'system_updates': systemUpdates,
    'marketing_messages': marketingMessages,
    'quiet_hours_enabled': quietHoursEnabled,
    'quiet_hours_start': quietHoursStart,
    'quiet_hours_end': quietHoursEnd,
  };
  
  NotificationPreferences copyWith({
    bool? paymentReceived,
    bool? paymentSent,
    bool? paymentFailed,
    bool? paymentRequest,
    bool? refundUpdates,
    bool? pointsEarned,
    bool? tierUpgrade,
    bool? rewardAvailable,
    bool? achievementUnlocked,
    bool? subscriptionReminders,
    bool? securityAlerts,
    bool? systemUpdates,
    bool? marketingMessages,
    bool? quietHoursEnabled,
    int? quietHoursStart,
    int? quietHoursEnd,
  }) {
    return NotificationPreferences(
      paymentReceived: paymentReceived ?? this.paymentReceived,
      paymentSent: paymentSent ?? this.paymentSent,
      paymentFailed: paymentFailed ?? this.paymentFailed,
      paymentRequest: paymentRequest ?? this.paymentRequest,
      refundUpdates: refundUpdates ?? this.refundUpdates,
      pointsEarned: pointsEarned ?? this.pointsEarned,
      tierUpgrade: tierUpgrade ?? this.tierUpgrade,
      rewardAvailable: rewardAvailable ?? this.rewardAvailable,
      achievementUnlocked: achievementUnlocked ?? this.achievementUnlocked,
      subscriptionReminders: subscriptionReminders ?? this.subscriptionReminders,
      securityAlerts: securityAlerts ?? this.securityAlerts,
      systemUpdates: systemUpdates ?? this.systemUpdates,
      marketingMessages: marketingMessages ?? this.marketingMessages,
      quietHoursEnabled: quietHoursEnabled ?? this.quietHoursEnabled,
      quietHoursStart: quietHoursStart ?? this.quietHoursStart,
      quietHoursEnd: quietHoursEnd ?? this.quietHoursEnd,
    );
  }
}

/// Device registration
class DeviceRegistration {
  final String deviceId;
  final String pushToken;
  final String platform; // 'android', 'ios', 'web'
  final String? deviceName;
  final DateTime registeredAt;
  final DateTime? lastActive;
  
  DeviceRegistration({
    required this.deviceId,
    required this.pushToken,
    required this.platform,
    this.deviceName,
    required this.registeredAt,
    this.lastActive,
  });
  
  factory DeviceRegistration.fromJson(Map<String, dynamic> json) {
    return DeviceRegistration(
      deviceId: json['device_id'] as String,
      pushToken: json['push_token'] as String,
      platform: json['platform'] as String,
      deviceName: json['device_name'] as String?,
      registeredAt: DateTime.parse(json['registered_at'] as String),
      lastActive: json['last_active'] != null 
          ? DateTime.parse(json['last_active'] as String)
          : null,
    );
  }
  
  Map<String, dynamic> toJson() => {
    'device_id': deviceId,
    'push_token': pushToken,
    'platform': platform,
    if (deviceName != null) 'device_name': deviceName,
    'registered_at': registeredAt.toIso8601String(),
    if (lastActive != null) 'last_active': lastActive!.toIso8601String(),
  };
}

/// GNS Push Notification Service
class PushNotificationService {
  static final PushNotificationService _instance = PushNotificationService._internal();
  factory PushNotificationService() => _instance;
  PushNotificationService._internal();
  
  static const _baseUrl = 'https://api.gns.network';
  
  String? _userPublicKey;
  String? _deviceId;
  String? _pushToken;
  NotificationPreferences _preferences = NotificationPreferences();
  
  // Notification stream
  final _notificationController = StreamController<GnsNotification>.broadcast();
  Stream<GnsNotification> get notificationStream => _notificationController.stream;
  
  // Unread count stream
  final _unreadCountController = StreamController<int>.broadcast();
  Stream<int> get unreadCountStream => _unreadCountController.stream;
  
  /// Initialize with user public key
  Future<void> initialize({
    required String userPublicKey,
    required String deviceId,
  }) async {
    _userPublicKey = userPublicKey;
    _deviceId = deviceId;
    
    // Load preferences
    await loadPreferences();
    
    debugPrint('🔔 Push Notification Service initialized');
  }
  
  /// Register device for push notifications
  Future<bool> registerDevice({
    required String pushToken,
    required String platform,
    String? deviceName,
  }) async {
    _pushToken = pushToken;
    
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/notifications/devices/register'),
        headers: _headers,
        body: jsonEncode({
          'device_id': _deviceId,
          'push_token': pushToken,
          'platform': platform,
          if (deviceName != null) 'device_name': deviceName,
        }),
      );
      
      if (response.statusCode == 200) {
        debugPrint('✅ Device registered for push notifications');
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Register device error: $e');
      return false;
    }
  }
  
  /// Unregister device
  Future<bool> unregisterDevice() async {
    try {
      final response = await http.delete(
        Uri.parse('$_baseUrl/notifications/devices/$_deviceId'),
        headers: _headers,
      );
      
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Unregister device error: $e');
      return false;
    }
  }
  
  /// Load notification preferences
  Future<NotificationPreferences> loadPreferences() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/notifications/preferences'),
        headers: _headers,
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'];
        _preferences = NotificationPreferences.fromJson(data);
      }
    } catch (e) {
      debugPrint('Load preferences error: $e');
    }
    return _preferences;
  }
  
  /// Save notification preferences
  Future<bool> savePreferences(NotificationPreferences preferences) async {
    try {
      final response = await http.put(
        Uri.parse('$_baseUrl/notifications/preferences'),
        headers: _headers,
        body: jsonEncode(preferences.toJson()),
      );
      
      if (response.statusCode == 200) {
        _preferences = preferences;
        debugPrint('✅ Notification preferences saved');
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Save preferences error: $e');
      return false;
    }
  }
  
  /// Get current preferences
  NotificationPreferences get preferences => _preferences;
  
  /// Get notification history
  Future<List<GnsNotification>> getNotifications({
    int limit = 50,
    int offset = 0,
    bool unreadOnly = false,
  }) async {
    try {
      final queryParams = <String, String>{
        'limit': limit.toString(),
        'offset': offset.toString(),
        if (unreadOnly) 'unread_only': 'true',
      };
      
      final uri = Uri.parse('$_baseUrl/notifications')
          .replace(queryParameters: queryParams);
      
      final response = await http.get(uri, headers: _headers);
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'] as List;
        return data.map((n) => GnsNotification.fromJson(n)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('Get notifications error: $e');
      return [];
    }
  }
  
  /// Get unread count
  Future<int> getUnreadCount() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/notifications/unread/count'),
        headers: _headers,
      );
      
      if (response.statusCode == 200) {
        final count = jsonDecode(response.body)['data']['count'] as int;
        _unreadCountController.add(count);
        return count;
      }
      return 0;
    } catch (e) {
      debugPrint('Get unread count error: $e');
      return 0;
    }
  }
  
  /// Mark notification as read
  Future<bool> markAsRead(String notificationId) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/notifications/$notificationId/read'),
        headers: _headers,
      );
      
      if (response.statusCode == 200) {
        await getUnreadCount(); // Update count
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Mark as read error: $e');
      return false;
    }
  }
  
  /// Mark all as read
  Future<bool> markAllAsRead() async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/notifications/read-all'),
        headers: _headers,
      );
      
      if (response.statusCode == 200) {
        _unreadCountController.add(0);
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Mark all as read error: $e');
      return false;
    }
  }
  
  /// Delete notification
  Future<bool> deleteNotification(String notificationId) async {
    try {
      final response = await http.delete(
        Uri.parse('$_baseUrl/notifications/$notificationId'),
        headers: _headers,
      );
      
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Delete notification error: $e');
      return false;
    }
  }
  
  /// Handle incoming push notification
  void handlePushNotification(Map<String, dynamic> message) {
    try {
      final notification = GnsNotification.fromJson(message);
      _notificationController.add(notification);
      
      // Update unread count
      getUnreadCount();
      
      debugPrint('🔔 Notification received: ${notification.type.name}');
    } catch (e) {
      debugPrint('Handle push notification error: $e');
    }
  }
  
  /// Check if notification type is enabled
  bool isNotificationEnabled(GnsNotificationType type) {
    switch (type) {
      case GnsNotificationType.paymentReceived:
        return _preferences.paymentReceived;
      case GnsNotificationType.paymentSent:
        return _preferences.paymentSent;
      case GnsNotificationType.paymentFailed:
        return _preferences.paymentFailed;
      case GnsNotificationType.paymentRequest:
        return _preferences.paymentRequest;
      case GnsNotificationType.refundRequested:
      case GnsNotificationType.refundApproved:
      case GnsNotificationType.refundRejected:
      case GnsNotificationType.refundCompleted:
        return _preferences.refundUpdates;
      case GnsNotificationType.pointsEarned:
        return _preferences.pointsEarned;
      case GnsNotificationType.tierUpgrade:
        return _preferences.tierUpgrade;
      case GnsNotificationType.rewardAvailable:
        return _preferences.rewardAvailable;
      case GnsNotificationType.achievementUnlocked:
        return _preferences.achievementUnlocked;
      case GnsNotificationType.subscriptionRenewal:
      case GnsNotificationType.subscriptionExpiring:
      case GnsNotificationType.subscriptionCancelled:
      case GnsNotificationType.paymentDue:
        return _preferences.subscriptionReminders;
      case GnsNotificationType.newDeviceLogin:
      case GnsNotificationType.suspiciousActivity:
      case GnsNotificationType.passwordChanged:
        return _preferences.securityAlerts;
      case GnsNotificationType.systemUpdate:
      case GnsNotificationType.maintenanceScheduled:
      case GnsNotificationType.featureAnnouncement:
        return _preferences.systemUpdates;
    }
  }
  
  /// Check if in quiet hours
  bool isQuietHours() {
    if (!_preferences.quietHoursEnabled) return false;
    
    final now = DateTime.now();
    final hour = now.hour;
    
    final start = _preferences.quietHoursStart;
    final end = _preferences.quietHoursEnd;
    
    if (start < end) {
      // Same day (e.g., 9 AM to 5 PM)
      return hour >= start && hour < end;
    } else {
      // Overnight (e.g., 10 PM to 8 AM)
      return hour >= start || hour < end;
    }
  }
  
  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'X-GNS-Public-Key': _userPublicKey ?? '',
  };
  
  /// Dispose
  void dispose() {
    _notificationController.close();
    _unreadCountController.close();
  }
}

/// Notification channel configuration (for Android)
extension NotificationChannelExtension on NotificationChannel {
  String get id => name;
  
  String get displayName {
    switch (this) {
      case NotificationChannel.payments:
        return 'Payments';
      case NotificationChannel.refunds:
        return 'Refunds';
      case NotificationChannel.loyalty:
        return 'Rewards & Loyalty';
      case NotificationChannel.subscriptions:
        return 'Subscriptions';
      case NotificationChannel.security:
        return 'Security Alerts';
      case NotificationChannel.system:
        return 'System Updates';
    }
  }
  
  String get description {
    switch (this) {
      case NotificationChannel.payments:
        return 'Payment notifications';
      case NotificationChannel.refunds:
        return 'Refund status updates';
      case NotificationChannel.loyalty:
        return 'Points and rewards notifications';
      case NotificationChannel.subscriptions:
        return 'Subscription reminders';
      case NotificationChannel.security:
        return 'Security and account alerts';
      case NotificationChannel.system:
        return 'App updates and announcements';
    }
  }
}
