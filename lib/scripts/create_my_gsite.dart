// ============================================================
// CREATE GSITE SCRIPT
// ============================================================
// Location: lib/scripts/create_my_gsite.dart
// Run with: Add a button in debug_screen.dart to call this
// ============================================================

import 'dart:convert';
import '../core/gsite/gsite_service.dart';
import '../core/gsite/gsite_models.dart';
import '../core/gns/identity_wallet.dart';

/// Creates and saves @camiloayerbe gSite
Future<void> createCamiloGSite() async {
  print('🐆 Creating @camiloayerbe gSite...');

  // 1. Build the gSite data
  final gsiteData = {
    '@context': 'https://schema.gns.network/v1',
    '@type': 'Person',
    '@id': '@camiloayerbe',
    'name': 'Camilo Ayerbe',
    'tagline': 'Building the identity layer the internet never had',
    'bio': 'Founder of GNS — proving humanity through trajectory, not biometrics. '
        'Building decentralized identity that gives you back control of your digital presence. '
        'Your keys, your identity, your data.',
    'trust': {
      'score': 85,
      'breadcrumbs': 247,
      'since': '2024-01-15',
      'verifications': [
        {
          'type': 'domain',
          'provider': 'gns',
          'value': 'gcrumbs.com',
          'verified': '2024-06-01T00:00:00Z',
        },
      ],
    },
    'location': {
      'city': 'Rome',
      'country': 'Italy',
    },
    'facets': [
      {'name': 'Personal', 'id': 'personal@camiloayerbe', 'public': true},
      {'name': 'Work', 'id': 'work@camiloayerbe', 'public': true},
      {'name': 'GNS Founder', 'id': 'gns@camiloayerbe', 'public': true},
    ],
    'skills': [
      'Flutter',
      'TypeScript', 
      'Cryptography',
      'Decentralized Systems',
      'Product Design',
      'Stellar Blockchain',
    ],
    'interests': [
      'Digital Identity',
      'Privacy',
      'Decentralization',
      'Open Source',
    ],
    'status': {
      'emoji': '🐆',
      'text': 'Building PANTHERA',
      'available': true,
    },
    'links': [
      {'type': 'website', 'url': 'https://gcrumbs.com'},
      {'type': 'github', 'handle': 'cayerbe'},
      {'type': 'email', 'url': 'mailto:camilo@gcrumbs.com'},
    ],
    'actions': {
      'message': true,
      'payment': true,
      'share': true,
      'follow': true,
    },
    'theme': 'profile-minimal',
    'version': 1,
    'language': 'en',
    'signature': 'ed25519:PLACEHOLDER', // Will be replaced
  };

  // 2. Validate first
  print('📋 Validating gSite...');
  final validation = await gsiteService.validateGSiteJson(gsiteData);

  if (!validation.valid) {
    print('❌ Validation failed:');
    for (final error in validation.errors) {
      print('   - ${error.path}: ${error.message}');
    }
    return;
  }

  print('✅ Validation passed!');
  
  if (validation.warnings.isNotEmpty) {
    print('⚠️ Warnings:');
    for (final warning in validation.warnings) {
      print('   - ${warning.path}: ${warning.message}');
    }
  }

  // 3. Sign and save (requires identity)
  // Uncomment when ready to actually save:
  /*
  try {
    final wallet = await IdentityWallet.load();
    
    // Sign the gSite content
    final contentToSign = jsonEncode(gsiteData);
    final signature = await wallet.sign(contentToSign);
    gsiteData['signature'] = 'ed25519:$signature';
    
    // Save to backend
    final result = await gsiteService.saveGSiteJson(
      gsiteData,
      '@camiloayerbe',
      privateKey: wallet.privateKeyBytes,
      publicKey: wallet.publicKeyHex,
    );
    
    if (result.success) {
      print('🎉 gSite saved! Version: ${result.data?.version}');
    } else {
      print('❌ Save failed: ${result.error}');
    }
  } catch (e) {
    print('❌ Error: $e');
  }
  */

  print('');
  print('📊 gSite JSON:');
  print(const JsonEncoder.withIndent('  ').convert(gsiteData));
}

/// Quick validation test
Future<ValidationResult> testValidation() async {
  final result = await gsiteService.validateGSiteJson({
    '@context': 'https://schema.gns.network/v1',
    '@type': 'Person',
    '@id': '@camiloayerbe',
    'name': 'Camilo Ayerbe',
    'signature': 'ed25519:test',
  });
  
  print('Valid: ${result.valid}');
  print('Errors: ${result.errors.length}');
  print('Warnings: ${result.warnings.length}');
  
  return result;
}
