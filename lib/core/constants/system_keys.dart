// ===========================================
// GNS SYSTEM KEYS
// Public keys for system services
// ===========================================
//
// Location: lib/core/constants/system_keys.dart
//
// These are the Ed25519 public keys for GNS system services.
// They are used to verify signatures on messages from these services.

/// System service public keys
abstract class SystemKeys {
  // ===========================================
  // EMAIL GATEWAY
  // ===========================================
  
  /// Email Gateway Ed25519 public key (identity/signing)
  /// Service: email-gateway@gcrumbs.com
  /// Used to verify signatures on inbound email envelopes
  static const String emailGatewayPublicKey = 
      '007dd9b2c19308dd0e2dfc044da05a522a1d1adbd6f1c84147cc4e0b7a4bd53d';
  
  /// Email Gateway X25519 public key (encryption)
  /// Used for encrypting replies to the email gateway
  static const String emailGatewayEncryptionKey = 
      '7f8f309dab64c198'; // TODO: Get full key from Railway logs
  
  /// Email Gateway domain
  static const String emailGatewayDomain = 'gcrumbs.com';
  
  // ===========================================
  // ECHO BOT
  // ===========================================
  
  /// Echo Bot Ed25519 public key (identity/signing)
  /// Service: @echo test bot
  static const String echoBotPublicKey = 
      'e291e79b67e0d2fb'; // TODO: Get full key from Railway logs
  
  // ===========================================
  // HELPERS
  // ===========================================
  
  /// Check if a public key belongs to a known system service
  static bool isSystemService(String publicKey) {
    final normalized = publicKey.toLowerCase();
    return normalized == emailGatewayPublicKey.toLowerCase() ||
           normalized.startsWith(echoBotPublicKey.toLowerCase());
  }
  
  /// Get display name for a system service
  static String? getServiceName(String publicKey) {
    final normalized = publicKey.toLowerCase();
    if (normalized == emailGatewayPublicKey.toLowerCase()) {
      return 'Email Gateway';
    }
    if (normalized.startsWith(echoBotPublicKey.toLowerCase())) {
      return '@echo';
    }
    return null;
  }
}
