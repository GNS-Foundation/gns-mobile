/// Globe Crumbs - Identity through Presence
/// 
/// Entry point — simplified for Phase 1 (identity + breadcrumb collection).
/// WebSocket sync, messaging, and payment services deferred to TierGate unlock.
/// 
/// Location: lib/main.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app.dart';
import 'core/gns/identity_wallet.dart';
import 'core/tier_gate.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Supabase
  await Supabase.initialize(
    url: 'https://nsthmevgpkskmgmubdju.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5zdGhtZXZncGtza21nbXViZGp1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjQ2ODg3NjIsImV4cCI6MjA4MDI2NDc2Mn0.rwx4iV8Me_lrxE-wl6PExO7M0_YfdBSdFuTB09hDoc8',
  );
  
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  
  // Initialize identity (no messaging/payments at startup)
  await _initializeIdentity();
  
  runApp(const GlobeCrumbsApp());
}

/// Initialize identity wallet and TierGate.
/// WebSocket sync deferred to Navigator tier (250+ breadcrumbs).
/// Payment service deferred to Trailblazer tier (1000+ breadcrumbs).
Future<void> _initializeIdentity() async {
  try {
    final wallet = IdentityWallet();
    final exists = await wallet.checkIdentityExists();
    
    if (exists) {
      await wallet.initialize();
      
      debugPrint('\n');
      debugPrint('========================================');
      debugPrint('🔑 IDENTITY KEYS:');
      debugPrint('========================================');  
      debugPrint('Ed25519 Public Key:');
      debugPrint(wallet.publicKey ?? 'null');
      debugPrint('========================================');
      
      // Initialize TierGate from breadcrumb stats
      final stats = await wallet.breadcrumbEngine.getStats();
      TierGate().initializeFromStats(stats.breadcrumbCount);
      debugPrint('🌱 Tier: ${TierGate().currentTier.displayName} (${stats.breadcrumbCount} breadcrumbs)');
      debugPrint('========================================\n');
    }
  } catch (e) {
    debugPrint('Error initializing identity: $e');
  }
}
