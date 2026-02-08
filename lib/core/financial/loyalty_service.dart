/// GNS Loyalty & Rewards Service - Sprint 6
/// 
/// Implements loyalty points, merchant rewards programs, and
/// achievement-based incentives for the GNS payment ecosystem.
/// 
/// Features:
/// - GNS Points (GP) earned on every transaction
/// - Merchant-specific loyalty programs
/// - Tiered membership levels
/// - Redeemable rewards
/// - Achievement badges
/// 
/// Location: lib/core/financial/loyalty_service.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../gns/identity_wallet.dart';

/// Loyalty tier levels
enum LoyaltyTier {
  bronze,
  silver,
  gold,
  platinum,
  diamond,
}

/// Point transaction types
enum PointTransactionType {
  earned,
  redeemed,
  expired,
  bonus,
  referral,
  adjustment,
}

/// User's loyalty profile
class LoyaltyProfile {
  final String userPublicKey;
  final int totalPoints;
  final int availablePoints;
  final int lifetimePoints;
  final LoyaltyTier tier;
  final int tierProgress;
  final int tierThreshold;
  final DateTime? tierExpiresAt;
  final int totalTransactions;
  final double totalSpent;
  final List<Achievement> achievements;
  final DateTime memberSince;
  final DateTime lastActivity;
  
  LoyaltyProfile({
    required this.userPublicKey,
    required this.totalPoints,
    required this.availablePoints,
    required this.lifetimePoints,
    required this.tier,
    required this.tierProgress,
    required this.tierThreshold,
    this.tierExpiresAt,
    required this.totalTransactions,
    required this.totalSpent,
    required this.achievements,
    required this.memberSince,
    required this.lastActivity,
  });
  
  double get tierProgressPercent => tierThreshold > 0 
      ? (tierProgress / tierThreshold) * 100 
      : 0;
  
  int get pointsToNextTier => tierThreshold - tierProgress;
  
  LoyaltyTier? get nextTier {
    final tiers = LoyaltyTier.values;
    final currentIndex = tiers.indexOf(tier);
    if (currentIndex < tiers.length - 1) {
      return tiers[currentIndex + 1];
    }
    return null;
  }
  
  factory LoyaltyProfile.fromJson(Map<String, dynamic> json) {
    return LoyaltyProfile(
      userPublicKey: json['user_public_key'] as String,
      totalPoints: json['total_points'] as int,
      availablePoints: json['available_points'] as int,
      lifetimePoints: json['lifetime_points'] as int,
      tier: LoyaltyTier.values.firstWhere(
        (t) => t.name == json['tier'],
        orElse: () => LoyaltyTier.bronze,
      ),
      tierProgress: json['tier_progress'] as int,
      tierThreshold: json['tier_threshold'] as int,
      tierExpiresAt: json['tier_expires_at'] != null
          ? DateTime.parse(json['tier_expires_at'])
          : null,
      totalTransactions: json['total_transactions'] as int,
      totalSpent: (json['total_spent'] as num).toDouble(),
      achievements: (json['achievements'] as List? ?? [])
          .map((a) => Achievement.fromJson(a))
          .toList(),
      memberSince: DateTime.parse(json['member_since'] as String),
      lastActivity: DateTime.parse(json['last_activity'] as String),
    );
  }
  
  Map<String, dynamic> toJson() => {
    'user_public_key': userPublicKey,
    'total_points': totalPoints,
    'available_points': availablePoints,
    'lifetime_points': lifetimePoints,
    'tier': tier.name,
    'tier_progress': tierProgress,
    'tier_threshold': tierThreshold,
    if (tierExpiresAt != null) 'tier_expires_at': tierExpiresAt!.toIso8601String(),
    'total_transactions': totalTransactions,
    'total_spent': totalSpent,
    'achievements': achievements.map((a) => a.toJson()).toList(),
    'member_since': memberSince.toIso8601String(),
    'last_activity': lastActivity.toIso8601String(),
  };
}

/// Achievement/Badge
class Achievement {
  final String id;
  final String name;
  final String description;
  final String iconUrl;
  final String category;
  final int pointsAwarded;
  final DateTime? unlockedAt;
  final bool isUnlocked;
  final double? progress;
  final double? target;
  
  Achievement({
    required this.id,
    required this.name,
    required this.description,
    required this.iconUrl,
    required this.category,
    required this.pointsAwarded,
    this.unlockedAt,
    required this.isUnlocked,
    this.progress,
    this.target,
  });
  
  double get progressPercent {
    if (target == null || target == 0) return isUnlocked ? 100 : 0;
    return ((progress ?? 0) / target!) * 100;
  }
  
  factory Achievement.fromJson(Map<String, dynamic> json) {
    return Achievement(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      iconUrl: json['icon_url'] as String? ?? '',
      category: json['category'] as String? ?? 'general',
      pointsAwarded: json['points_awarded'] as int? ?? 0,
      unlockedAt: json['unlocked_at'] != null
          ? DateTime.parse(json['unlocked_at'])
          : null,
      isUnlocked: json['is_unlocked'] as bool? ?? false,
      progress: (json['progress'] as num?)?.toDouble(),
      target: (json['target'] as num?)?.toDouble(),
    );
  }
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'icon_url': iconUrl,
    'category': category,
    'points_awarded': pointsAwarded,
    if (unlockedAt != null) 'unlocked_at': unlockedAt!.toIso8601String(),
    'is_unlocked': isUnlocked,
    if (progress != null) 'progress': progress,
    if (target != null) 'target': target,
  };
}

/// Points transaction record
class PointTransaction {
  final String transactionId;
  final String userPublicKey;
  final int points;
  final PointTransactionType type;
  final String description;
  final String? referenceId;
  final String? merchantId;
  final String? merchantName;
  final DateTime timestamp;
  final int balanceAfter;
  
  PointTransaction({
    required this.transactionId,
    required this.userPublicKey,
    required this.points,
    required this.type,
    required this.description,
    this.referenceId,
    this.merchantId,
    this.merchantName,
    required this.timestamp,
    required this.balanceAfter,
  });
  
  bool get isCredit => type == PointTransactionType.earned || 
                       type == PointTransactionType.bonus ||
                       type == PointTransactionType.referral;
  
  factory PointTransaction.fromJson(Map<String, dynamic> json) {
    return PointTransaction(
      transactionId: json['transaction_id'] as String,
      userPublicKey: json['user_public_key'] as String,
      points: json['points'] as int,
      type: PointTransactionType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => PointTransactionType.earned,
      ),
      description: json['description'] as String,
      referenceId: json['reference_id'] as String?,
      merchantId: json['merchant_id'] as String?,
      merchantName: json['merchant_name'] as String?,
      timestamp: DateTime.parse(json['timestamp'] as String),
      balanceAfter: json['balance_after'] as int,
    );
  }
  
  Map<String, dynamic> toJson() => {
    'transaction_id': transactionId,
    'user_public_key': userPublicKey,
    'points': points,
    'type': type.name,
    'description': description,
    if (referenceId != null) 'reference_id': referenceId,
    if (merchantId != null) 'merchant_id': merchantId,
    if (merchantName != null) 'merchant_name': merchantName,
    'timestamp': timestamp.toIso8601String(),
    'balance_after': balanceAfter,
  };
}

/// Redeemable reward
class Reward {
  final String rewardId;
  final String name;
  final String description;
  final String? imageUrl;
  final int pointsCost;
  final String? merchantId;
  final String? merchantName;
  final RewardType type;
  final double? discountAmount;
  final double? discountPercent;
  final String? couponCode;
  final DateTime? expiresAt;
  final int? quantityAvailable;
  final bool isAvailable;
  final List<String>? categories;
  final Map<String, dynamic>? terms;
  
  Reward({
    required this.rewardId,
    required this.name,
    required this.description,
    this.imageUrl,
    required this.pointsCost,
    this.merchantId,
    this.merchantName,
    required this.type,
    this.discountAmount,
    this.discountPercent,
    this.couponCode,
    this.expiresAt,
    this.quantityAvailable,
    required this.isAvailable,
    this.categories,
    this.terms,
  });
  
  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);
  bool get isOutOfStock => quantityAvailable != null && quantityAvailable! <= 0;
  
  factory Reward.fromJson(Map<String, dynamic> json) {
    return Reward(
      rewardId: json['reward_id'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      imageUrl: json['image_url'] as String?,
      pointsCost: json['points_cost'] as int,
      merchantId: json['merchant_id'] as String?,
      merchantName: json['merchant_name'] as String?,
      type: RewardType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => RewardType.discount,
      ),
      discountAmount: (json['discount_amount'] as num?)?.toDouble(),
      discountPercent: (json['discount_percent'] as num?)?.toDouble(),
      couponCode: json['coupon_code'] as String?,
      expiresAt: json['expires_at'] != null
          ? DateTime.parse(json['expires_at'])
          : null,
      quantityAvailable: json['quantity_available'] as int?,
      isAvailable: json['is_available'] as bool? ?? true,
      categories: (json['categories'] as List?)?.cast<String>(),
      terms: json['terms'] as Map<String, dynamic>?,
    );
  }
  
  Map<String, dynamic> toJson() => {
    'reward_id': rewardId,
    'name': name,
    'description': description,
    if (imageUrl != null) 'image_url': imageUrl,
    'points_cost': pointsCost,
    if (merchantId != null) 'merchant_id': merchantId,
    if (merchantName != null) 'merchant_name': merchantName,
    'type': type.name,
    if (discountAmount != null) 'discount_amount': discountAmount,
    if (discountPercent != null) 'discount_percent': discountPercent,
    if (couponCode != null) 'coupon_code': couponCode,
    if (expiresAt != null) 'expires_at': expiresAt!.toIso8601String(),
    if (quantityAvailable != null) 'quantity_available': quantityAvailable,
    'is_available': isAvailable,
    if (categories != null) 'categories': categories,
    if (terms != null) 'terms': terms,
  };
}

enum RewardType {
  discount,
  freeItem,
  cashback,
  upgrade,
  gnsTokens,
  experience,
}

/// Redeemed reward record
class RedeemedReward {
  final String redemptionId;
  final String rewardId;
  final String rewardName;
  final int pointsSpent;
  final String? couponCode;
  final DateTime redeemedAt;
  final DateTime? expiresAt;
  final DateTime? usedAt;
  final bool isUsed;
  final String? merchantId;
  
  RedeemedReward({
    required this.redemptionId,
    required this.rewardId,
    required this.rewardName,
    required this.pointsSpent,
    this.couponCode,
    required this.redeemedAt,
    this.expiresAt,
    this.usedAt,
    required this.isUsed,
    this.merchantId,
  });
  
  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);
  bool get isValid => !isUsed && !isExpired;
  
  factory RedeemedReward.fromJson(Map<String, dynamic> json) {
    return RedeemedReward(
      redemptionId: json['redemption_id'] as String,
      rewardId: json['reward_id'] as String,
      rewardName: json['reward_name'] as String,
      pointsSpent: json['points_spent'] as int,
      couponCode: json['coupon_code'] as String?,
      redeemedAt: DateTime.parse(json['redeemed_at'] as String),
      expiresAt: json['expires_at'] != null
          ? DateTime.parse(json['expires_at'])
          : null,
      usedAt: json['used_at'] != null
          ? DateTime.parse(json['used_at'])
          : null,
      isUsed: json['is_used'] as bool? ?? false,
      merchantId: json['merchant_id'] as String?,
    );
  }
  
  Map<String, dynamic> toJson() => {
    'redemption_id': redemptionId,
    'reward_id': rewardId,
    'reward_name': rewardName,
    'points_spent': pointsSpent,
    if (couponCode != null) 'coupon_code': couponCode,
    'redeemed_at': redeemedAt.toIso8601String(),
    if (expiresAt != null) 'expires_at': expiresAt!.toIso8601String(),
    if (usedAt != null) 'used_at': usedAt!.toIso8601String(),
    'is_used': isUsed,
    if (merchantId != null) 'merchant_id': merchantId,
  };
}

/// Merchant loyalty program
class MerchantLoyaltyProgram {
  final String programId;
  final String merchantId;
  final String merchantName;
  final String programName;
  final String? description;
  final double pointsPerDollar;
  final double bonusMultiplier;
  final List<Reward> rewards;
  final bool isActive;
  final String? logoUrl;
  
  MerchantLoyaltyProgram({
    required this.programId,
    required this.merchantId,
    required this.merchantName,
    required this.programName,
    this.description,
    required this.pointsPerDollar,
    this.bonusMultiplier = 1.0,
    required this.rewards,
    required this.isActive,
    this.logoUrl,
  });
  
  int calculatePoints(double amount) {
    return (amount * pointsPerDollar * bonusMultiplier).round();
  }
  
  factory MerchantLoyaltyProgram.fromJson(Map<String, dynamic> json) {
    return MerchantLoyaltyProgram(
      programId: json['program_id'] as String,
      merchantId: json['merchant_id'] as String,
      merchantName: json['merchant_name'] as String,
      programName: json['program_name'] as String,
      description: json['description'] as String?,
      pointsPerDollar: (json['points_per_dollar'] as num).toDouble(),
      bonusMultiplier: (json['bonus_multiplier'] as num?)?.toDouble() ?? 1.0,
      rewards: (json['rewards'] as List? ?? [])
          .map((r) => Reward.fromJson(r))
          .toList(),
      isActive: json['is_active'] as bool? ?? true,
      logoUrl: json['logo_url'] as String?,
    );
  }
  
  Map<String, dynamic> toJson() => {
    'program_id': programId,
    'merchant_id': merchantId,
    'merchant_name': merchantName,
    'program_name': programName,
    if (description != null) 'description': description,
    'points_per_dollar': pointsPerDollar,
    'bonus_multiplier': bonusMultiplier,
    'rewards': rewards.map((r) => r.toJson()).toList(),
    'is_active': isActive,
    if (logoUrl != null) 'logo_url': logoUrl,
  };
}

/// GNS Loyalty Service
class LoyaltyService {
  static final LoyaltyService _instance = LoyaltyService._internal();
  factory LoyaltyService() => _instance;
  LoyaltyService._internal();
  
  static const _baseUrl = 'https://api.gns.network';
  static const _uuid = Uuid();
  
  IdentityWallet? _wallet;
  LoyaltyProfile? _cachedProfile;
  DateTime? _profileCacheTime;
  
  // Cache duration
  static const _cacheDuration = Duration(minutes: 5);
  
  /// Initialize service
  Future<void> initialize(IdentityWallet wallet) async {
    _wallet = wallet;
    await refreshProfile();
  }
  
  /// Get current profile (cached)
  LoyaltyProfile? get profile => _cachedProfile;
  
  /// Get available points
  int get availablePoints => _cachedProfile?.availablePoints ?? 0;
  
  /// Get current tier
  LoyaltyTier get tier => _cachedProfile?.tier ?? LoyaltyTier.bronze;
  
  /// Refresh profile from server
  Future<LoyaltyProfile?> refreshProfile() async {
    if (_wallet == null) return null;
    
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/loyalty/profile'),
        headers: {
          'X-GNS-Public-Key': _wallet!.publicKeyHex,
        },
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'];
        _cachedProfile = LoyaltyProfile.fromJson(data);
        _profileCacheTime = DateTime.now();
        return _cachedProfile;
      }
      return null;
    } catch (e) {
      debugPrint('Refresh loyalty profile error: $e');
      return null;
    }
  }
  
  /// Get profile (with cache)
  Future<LoyaltyProfile?> getProfile({bool forceRefresh = false}) async {
    if (forceRefresh || _isCacheExpired()) {
      return refreshProfile();
    }
    return _cachedProfile;
  }
  
  bool _isCacheExpired() {
    if (_profileCacheTime == null) return true;
    return DateTime.now().difference(_profileCacheTime!) > _cacheDuration;
  }
  
  /// Get points history
  Future<List<PointTransaction>> getPointsHistory({
    int limit = 50,
    int offset = 0,
    PointTransactionType? type,
  }) async {
    if (_wallet == null) return [];
    
    try {
      final queryParams = <String, String>{
        'limit': limit.toString(),
        'offset': offset.toString(),
      };
      if (type != null) {
        queryParams['type'] = type.name;
      }
      
      final uri = Uri.parse('$_baseUrl/loyalty/points/history')
          .replace(queryParameters: queryParams);
      
      final response = await http.get(
        uri,
        headers: {
          'X-GNS-Public-Key': _wallet!.publicKeyHex,
        },
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'] as List;
        return data.map((t) => PointTransaction.fromJson(t)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('Get points history error: $e');
      return [];
    }
  }
  
  /// Get available rewards
  Future<List<Reward>> getAvailableRewards({
    String? merchantId,
    String? category,
    int? maxPoints,
  }) async {
    try {
      final queryParams = <String, String>{};
      if (merchantId != null) queryParams['merchant_id'] = merchantId;
      if (category != null) queryParams['category'] = category;
      if (maxPoints != null) queryParams['max_points'] = maxPoints.toString();
      
      final uri = Uri.parse('$_baseUrl/loyalty/rewards')
          .replace(queryParameters: queryParams);
      
      final response = await http.get(
        uri,
        headers: {
          'X-GNS-Public-Key': _wallet?.publicKeyHex ?? '',
        },
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'] as List;
        return data.map((r) => Reward.fromJson(r)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('Get rewards error: $e');
      return [];
    }
  }
  
  /// Redeem a reward
  Future<RedemptionResult> redeemReward(String rewardId) async {
    if (_wallet == null) {
      return RedemptionResult(success: false, error: 'Service not initialized');
    }
    
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/loyalty/rewards/$rewardId/redeem'),
        headers: {
          'Content-Type': 'application/json',
          'X-GNS-Public-Key': _wallet!.publicKeyHex,
        },
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'];
        final redeemed = RedeemedReward.fromJson(data);
        
        // Refresh profile to update points
        await refreshProfile();
        
        debugPrint('🎁 Reward redeemed: ${redeemed.rewardName}');
        return RedemptionResult(success: true, redemption: redeemed);
      } else {
        final error = jsonDecode(response.body)['error'] ?? 'Failed to redeem';
        return RedemptionResult(success: false, error: error);
      }
    } catch (e) {
      debugPrint('Redeem reward error: $e');
      return RedemptionResult(success: false, error: e.toString());
    }
  }
  
  /// Get user's redeemed rewards
  Future<List<RedeemedReward>> getRedeemedRewards({
    bool? unused,
    int limit = 50,
  }) async {
    if (_wallet == null) return [];
    
    try {
      final queryParams = <String, String>{
        'limit': limit.toString(),
      };
      if (unused != null) queryParams['unused'] = unused.toString();
      
      final uri = Uri.parse('$_baseUrl/loyalty/rewards/redeemed')
          .replace(queryParameters: queryParams);
      
      final response = await http.get(
        uri,
        headers: {
          'X-GNS-Public-Key': _wallet!.publicKeyHex,
        },
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'] as List;
        return data.map((r) => RedeemedReward.fromJson(r)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('Get redeemed rewards error: $e');
      return [];
    }
  }
  
  /// Get merchant loyalty programs
  Future<List<MerchantLoyaltyProgram>> getMerchantPrograms({
    bool? enrolled,
  }) async {
    try {
      final queryParams = <String, String>{};
      if (enrolled != null) queryParams['enrolled'] = enrolled.toString();
      
      final uri = Uri.parse('$_baseUrl/loyalty/programs')
          .replace(queryParameters: queryParams);
      
      final response = await http.get(
        uri,
        headers: {
          'X-GNS-Public-Key': _wallet?.publicKeyHex ?? '',
        },
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'] as List;
        return data.map((p) => MerchantLoyaltyProgram.fromJson(p)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('Get merchant programs error: $e');
      return [];
    }
  }
  
  /// Enroll in merchant loyalty program
  Future<bool> enrollInProgram(String programId) async {
    if (_wallet == null) return false;
    
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/loyalty/programs/$programId/enroll'),
        headers: {
          'X-GNS-Public-Key': _wallet!.publicKeyHex,
        },
      );
      
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Enroll in program error: $e');
      return false;
    }
  }
  
  /// Get all achievements
  Future<List<Achievement>> getAchievements({bool? unlocked}) async {
    if (_wallet == null) return [];
    
    try {
      final queryParams = <String, String>{};
      if (unlocked != null) queryParams['unlocked'] = unlocked.toString();
      
      final uri = Uri.parse('$_baseUrl/loyalty/achievements')
          .replace(queryParameters: queryParams);
      
      final response = await http.get(
        uri,
        headers: {
          'X-GNS-Public-Key': _wallet!.publicKeyHex,
        },
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'] as List;
        return data.map((a) => Achievement.fromJson(a)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('Get achievements error: $e');
      return [];
    }
  }
  
  /// Calculate points for a payment amount
  int calculatePointsForPayment(double amount, {String? merchantId}) {
    // Base rate: 1 point per dollar
    var basePoints = amount.round();
    
    // Tier bonus
    final tierMultiplier = _getTierMultiplier();
    basePoints = (basePoints * tierMultiplier).round();
    
    // TODO: Check merchant-specific programs for bonus
    
    return basePoints;
  }
  
  double _getTierMultiplier() {
    switch (tier) {
      case LoyaltyTier.bronze:
        return 1.0;
      case LoyaltyTier.silver:
        return 1.25;
      case LoyaltyTier.gold:
        return 1.5;
      case LoyaltyTier.platinum:
        return 2.0;
      case LoyaltyTier.diamond:
        return 3.0;
    }
  }
  
  /// Submit referral code
  Future<ReferralResult> submitReferralCode(String code) async {
    if (_wallet == null) {
      return ReferralResult(success: false, error: 'Service not initialized');
    }
    
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/loyalty/referral/submit'),
        headers: {
          'Content-Type': 'application/json',
          'X-GNS-Public-Key': _wallet!.publicKeyHex,
        },
        body: jsonEncode({'code': code}),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'];
        await refreshProfile();
        return ReferralResult(
          success: true,
          pointsEarned: data['points_earned'] as int,
          message: data['message'] as String?,
        );
      } else {
        final error = jsonDecode(response.body)['error'] ?? 'Invalid code';
        return ReferralResult(success: false, error: error);
      }
    } catch (e) {
      debugPrint('Submit referral error: $e');
      return ReferralResult(success: false, error: e.toString());
    }
  }
  
  /// Get user's referral code
  Future<String?> getReferralCode() async {
    if (_wallet == null) return null;
    
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/loyalty/referral/code'),
        headers: {
          'X-GNS-Public-Key': _wallet!.publicKeyHex,
        },
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'];
        return data['code'] as String?;
      }
      return null;
    } catch (e) {
      debugPrint('Get referral code error: $e');
      return null;
    }
  }
}

/// Redemption result
class RedemptionResult {
  final bool success;
  final RedeemedReward? redemption;
  final String? error;
  
  RedemptionResult({
    required this.success,
    this.redemption,
    this.error,
  });
}

/// Referral result
class ReferralResult {
  final bool success;
  final int? pointsEarned;
  final String? message;
  final String? error;
  
  ReferralResult({
    required this.success,
    this.pointsEarned,
    this.message,
    this.error,
  });
}

/// Tier display helpers
extension LoyaltyTierExtension on LoyaltyTier {
  String get displayName {
    switch (this) {
      case LoyaltyTier.bronze:
        return 'Bronze';
      case LoyaltyTier.silver:
        return 'Silver';
      case LoyaltyTier.gold:
        return 'Gold';
      case LoyaltyTier.platinum:
        return 'Platinum';
      case LoyaltyTier.diamond:
        return 'Diamond';
    }
  }
  
  String get emoji {
    switch (this) {
      case LoyaltyTier.bronze:
        return '🥉';
      case LoyaltyTier.silver:
        return '🥈';
      case LoyaltyTier.gold:
        return '🥇';
      case LoyaltyTier.platinum:
        return '💎';
      case LoyaltyTier.diamond:
        return '👑';
    }
  }
  
  int get threshold {
    switch (this) {
      case LoyaltyTier.bronze:
        return 0;
      case LoyaltyTier.silver:
        return 1000;
      case LoyaltyTier.gold:
        return 5000;
      case LoyaltyTier.platinum:
        return 15000;
      case LoyaltyTier.diamond:
        return 50000;
    }
  }
}
