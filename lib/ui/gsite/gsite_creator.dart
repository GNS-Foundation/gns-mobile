// ============================================================
// GNS gSITE CREATOR WIDGET - FIXED VERSION
// ============================================================
// Location: lib/ui/gsite/gsite_creator.dart
// Purpose: One-click button to create your gSite
// FIX: Removed problematic since field format
// ============================================================

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cryptography/cryptography.dart';
import '../../core/gns/identity_wallet.dart';
import '../../core/gsite/gsite_service.dart';
import '../../core/gsite/gsite_models.dart';

// ============================================================
// MAIN WIDGET - Just add this button anywhere!
// ============================================================

class GSiteCreatorButton extends StatefulWidget {
  const GSiteCreatorButton({super.key});

  @override
  State<GSiteCreatorButton> createState() => _GSiteCreatorButtonState();
}

class _GSiteCreatorButtonState extends State<GSiteCreatorButton> {
  bool _loading = false;
  String? _result;
  bool? _success;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ElevatedButton.icon(
          onPressed: _loading ? null : _createGSite,
          icon: _loading 
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('🐆'),
          label: Text(_loading ? 'Creating...' : 'Create My gSite'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.deepPurple,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
        ),
        if (_result != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _success == true 
                  ? Colors.green.withOpacity(0.1) 
                  : Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _success == true ? Colors.green : Colors.red,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _success == true ? Icons.check_circle : Icons.error,
                  color: _success == true ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                Flexible(child: Text(_result!)),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _createGSite() async {
    setState(() {
      _loading = true;
      _result = null;
      _success = null;
    });

    try {
      final result = await createMyGSite();
      setState(() {
        _success = result.success;
        _result = result.message;
      });
    } catch (e) {
      setState(() {
        _success = false;
        _result = 'Error: $e';
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }
}

// ============================================================
// RESULT CLASS
// ============================================================

class GSiteCreationResult {
  final bool success;
  final String message;
  final GSite? gsite;

  GSiteCreationResult({
    required this.success,
    required this.message,
    this.gsite,
  });
}

// ============================================================
// MAIN CREATION FUNCTION
// ============================================================

Future<GSiteCreationResult> createMyGSite() async {
  print('🐆 Starting gSite creation...');

  // 1. Get identity
  final wallet = IdentityWallet();
  if (!wallet.hasIdentity) {
    return GSiteCreationResult(
      success: false,
      message: 'No identity found. Create identity first!',
    );
  }

  final publicKey = wallet.publicKey!;
  final handle = await wallet.getCurrentHandle();
  
  if (handle == null || handle.isEmpty) {
    return GSiteCreationResult(
      success: false,
      message: 'No handle claimed. Claim a handle first!',
    );
  }

  print('📋 Creating gSite for @$handle');

  // 2. Get identity info for trust data
  final identityInfo = await wallet.getIdentityInfo();

  // 3. Build gSite data
  final gsiteData = _buildGSiteData(
    handle: handle,
    trustScore: identityInfo.trustScore,
    breadcrumbs: identityInfo.breadcrumbCount,
  );

  // 4. Validate first
  print('✅ Validating gSite...');
  final validation = await gsiteService.validateGSiteJson(gsiteData);

  if (!validation.valid) {
    final errors = validation.errors.map((e) => e.message).join(', ');
    return GSiteCreationResult(
      success: false,
      message: 'Validation failed: $errors',
    );
  }

  print('✅ Validation passed! Warnings: ${validation.warnings.length}');

  // 5. Sign the gSite
  print('🔐 Signing gSite...');
  try {
    final contentToSign = _canonicalJson(gsiteData);
    final signature = await _signContent(contentToSign, wallet.privateKeyBytes!);
    gsiteData['signature'] = 'ed25519:$signature';
  } catch (e) {
    return GSiteCreationResult(
      success: false,
      message: 'Failed to sign: $e',
    );
  }

  // 6. Save to backend
  print('💾 Saving to backend...');
  try {
    final result = await gsiteService.saveGSiteJson(
      gsiteData,
      '@$handle',
      privateKey: wallet.privateKeyBytes!.toList(),
      publicKey: publicKey,
    );

    if (result.success && result.data != null) {
      print('🎉 gSite created successfully!');
      return GSiteCreationResult(
        success: true,
        message: 'gSite @$handle created! Version: ${result.data!.version}',
        gsite: result.data,
      );
    } else {
      return GSiteCreationResult(
        success: false,
        message: result.error ?? 'Unknown error saving gSite',
      );
    }
  } catch (e) {
    return GSiteCreationResult(
      success: false,
      message: 'Save failed: $e',
    );
  }
}

// ============================================================
// VALIDATION-ONLY FUNCTION (for testing)
// ============================================================

Future<GSiteCreationResult> validateMyGSite() async {
  print('🐆 Validating gSite...');

  final wallet = IdentityWallet();
  final handle = await wallet.getCurrentHandle() ?? 'test';
  final identityInfo = await wallet.getIdentityInfo();

  final gsiteData = _buildGSiteData(
    handle: handle,
    trustScore: identityInfo.trustScore,
    breadcrumbs: identityInfo.breadcrumbCount,
  );

  final validation = await gsiteService.validateGSiteJson(gsiteData);

  if (validation.valid) {
    final warnings = validation.warnings.map((w) => '${w.path}: ${w.message}').join('\n');
    return GSiteCreationResult(
      success: true,
      message: 'Valid! ✅\n\nWarnings:\n$warnings',
    );
  } else {
    final errors = validation.errors.map((e) => '${e.path}: ${e.message}').join('\n');
    return GSiteCreationResult(
      success: false,
      message: 'Invalid! ❌\n\nErrors:\n$errors',
    );
  }
}

// ============================================================
// BUILD gSITE DATA - SIMPLIFIED FOR PERSON TYPE
// ============================================================

Map<String, dynamic> _buildGSiteData({
  required String handle,
  required double trustScore,
  required int breadcrumbs,
}) {
  // Keep it simple - only required fields + a few extras
  return {
    // Required fields
    '@context': 'https://schema.gns.network/v1',
    '@type': 'Person',
    '@id': '@$handle',
    'name': _formatName(handle),
    'signature': 'ed25519:PLACEHOLDER',
    
    // Recommended fields
    'tagline': 'GNS identity verified through proof-of-trajectory',
    'bio': 'Your keys, your identity, your data.',
    
    // Trust info (no 'since' to avoid date format issues)
    'trust': {
      'score': trustScore,
      'breadcrumbs': breadcrumbs,
    },
    
    // Simple arrays
    'skills': ['GNS Identity'],
    
    // Status
    'status': {
      'emoji': '🐆',
      'text': 'On PANTHERA',
      'available': true,
    },
    
    // Links
    'links': [
      {'type': 'website', 'url': 'https://gcrumbs.com'},
    ],
    
    // Actions
    'actions': {
      'message': true,
      'payment': true,
      'share': true,
    },
    
    // Metadata
    'version': 1,
    'language': 'en',
  };
}

// ============================================================
// HELPERS
// ============================================================

String _formatName(String handle) {
  // Convert "camiloayerbe" to "Camiloayerbe" (just capitalize first letter)
  if (handle.isEmpty) return handle;
  return handle[0].toUpperCase() + handle.substring(1);
}

String _canonicalJson(Map<String, dynamic> data) {
  // Remove signature before signing
  final copy = Map<String, dynamic>.from(data);
  copy.remove('signature');
  return jsonEncode(copy);
}

Future<String> _signContent(String content, List<int> privateKey) async {
  final algorithm = Ed25519();
  final keyPair = await algorithm.newKeyPairFromSeed(privateKey);
  final signature = await algorithm.sign(
    utf8.encode(content),
    keyPair: keyPair,
  );
  return base64Encode(signature.bytes);
}

// ============================================================
// FULL CARD WIDGET (Alternative - more visual)
// ============================================================

class GSiteCreatorCard extends StatefulWidget {
  const GSiteCreatorCard({super.key});

  @override
  State<GSiteCreatorCard> createState() => _GSiteCreatorCardState();
}

class _GSiteCreatorCardState extends State<GSiteCreatorCard> {
  bool _loading = false;
  GSiteCreationResult? _result;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(0),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Text('🐆', style: TextStyle(fontSize: 24)),
                const SizedBox(width: 12),
                Text(
                  'Create Your gSite',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Your gSite is your identity on the decentralized web. '
              'It includes your profile, trust score, and facets.',
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            
            // Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _loading ? null : _validateOnly,
                    child: const Text('Validate Only'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _loading ? null : _createGSite,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                    ),
                    child: _loading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Create & Save'),
                  ),
                ),
              ],
            ),

            // Result
            if (_result != null) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _result!.success
                      ? Colors.green.withOpacity(0.1)
                      : Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _result!.success ? Colors.green : Colors.red,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _result!.success ? Icons.check_circle : Icons.error,
                          color: _result!.success ? Colors.green : Colors.red,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _result!.success ? 'Success!' : 'Failed',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _result!.success ? Colors.green : Colors.red,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _result!.message,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _validateOnly() async {
    setState(() {
      _loading = true;
      _result = null;
    });

    try {
      final result = await validateMyGSite();
      setState(() => _result = result);
    } catch (e) {
      setState(() => _result = GSiteCreationResult(
        success: false,
        message: 'Error: $e',
      ));
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _createGSite() async {
    setState(() {
      _loading = true;
      _result = null;
    });

    try {
      final result = await createMyGSite();
      setState(() => _result = result);
    } catch (e) {
      setState(() => _result = GSiteCreationResult(
        success: false,
        message: 'Error: $e',
      ));
    } finally {
      setState(() => _loading = false);
    }
  }
}
