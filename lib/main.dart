/// Globe Crumbs - Identity through Presence
/// 
/// Entry point - delegates to app.dart
/// 
/// Location: lib/main.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app.dart';
import 'core/gns/identity_wallet.dart';
import 'ui/screens/handle_management_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
