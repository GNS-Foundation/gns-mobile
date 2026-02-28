/// Globe Crumbs - Identity through Presence
/// 
/// Entry point - delegates to app.dart
/// 
/// Location: lib/main.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app.dart';
import 'core/gns/identity_wallet.dart';
import 'ui/screens/handle_management_screen.dart';

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
  
  // Print encryption key on startup (for development)
  await _printEncryptionKey();
  
  runApp(const GlobeCrumbsApp());
}

/// Print encryption key for database setup (development helper)
Future<void> _printEncryptionKey() async {
  try {
    final wallet = IdentityWallet();
    await wallet.initialize();
    
    print('\n');
    print('========================================');
    print('🔑 COPY THIS FOR DATABASE:');
    print('========================================');  
    print('Ed25519 Public Key:');
    print(wallet.publicKey);
    print('\n');
    print('X25519 Encryption Key:');
    print(wallet.encryptionPublicKeyHex);
    print('========================================');
    print('Copy the X25519 key above! ☝️');
    print('========================================');
    print('\n');
  } catch (e) {
    print('Error getting keys: $e');
  }
}
