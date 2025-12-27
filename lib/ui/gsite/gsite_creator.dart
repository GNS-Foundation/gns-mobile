// ============================================================
// GNS gSITE CREATOR + VIEWER
// ============================================================
// Create and view your gSite identity
// ============================================================

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../core/gns/identity_wallet.dart';
import '../../core/gsite/gsite_service.dart';
import '../../core/gsite/gsite_models.dart';

// ============================================================
// COMBINED CARD - CREATE + VIEW
// ============================================================

class GSiteCreatorCard extends StatefulWidget {
  const GSiteCreatorCard({super.key});

  @override
  State<GSiteCreatorCard> createState() => _GSiteCreatorCardState();
}

class _GSiteCreatorCardState extends State<GSiteCreatorCard> {
  bool _loading = false;
  String? _resultMessage;
  bool? _success;

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
                  'Your gSite',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Your gSite is your identity on the decentralized web.',
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            
            // Buttons Row 1: Create & Validate
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _loading ? null : _validateOnly,
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: const Text('Validate'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _loading ? null : _createGSite,
                    icon: _loading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.upload, size: 18),
                    label: const Text('Create'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // Buttons Row 2: View
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _loading ? null : _viewMyGSite,
                icon: const Icon(Icons.visibility, size: 18),
                label: const Text('View My gSite'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.deepPurple,
                ),
              ),
            ),
            
            const SizedBox(height: 12),
            
            // Buttons Row 3: Create gcrumbs@ namespace
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _loading ? null : _createGcrumbsNamespace,
                icon: const Icon(Icons.business, size: 18),
                label: const Text('Create gcrumbs@ Namespace'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            
            const SizedBox(height: 8),
            
            // View gcrumbs@ button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _loading ? null : _viewGcrumbsNamespace,
                icon: const Icon(Icons.business_center, size: 18),
                label: const Text('View gcrumbs@'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.teal,
                ),
              ),
            ),

            // Result
            if (_resultMessage != null) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _success == true ? Icons.check_circle : Icons.error,
                          color: _success == true ? Colors.green : Colors.red,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _success == true ? 'Success!' : 'Failed',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _success == true ? Colors.green : Colors.red,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _resultMessage!,
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
      _resultMessage = null;
      _success = null;
    });

    try {
      final result = await _doValidateOnly();
      setState(() {
        _success = result.success;
        _resultMessage = result.message;
      });
    } catch (e) {
      setState(() {
        _success = false;
        _resultMessage = 'Error: $e';
      });
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _createGSite() async {
    setState(() {
      _loading = true;
      _resultMessage = null;
      _success = null;
    });

    try {
      final result = await _doCreateGSite();
      setState(() {
        _success = result.success;
        _resultMessage = result.message;
      });
    } catch (e) {
      setState(() {
        _success = false;
        _resultMessage = 'Error: $e';
      });
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _viewMyGSite() async {
    final wallet = IdentityWallet();
    final handle = await wallet.getCurrentHandle();
    
    if (handle == null || handle.isEmpty) {
      setState(() {
        _success = false;
        _resultMessage = 'No handle claimed yet!';
      });
      return;
    }

    setState(() {
      _loading = true;
      _resultMessage = null;
      _success = null;
    });

    try {
      final result = await gsiteService.getGSite('@$handle');
      
      if (result.success && result.data != null) {
        if (!mounted) return;
        _showGSiteViewer(context, result.data!);
        setState(() => _loading = false);
      } else {
        setState(() {
          _loading = false;
          _success = false;
          _resultMessage = result.error ?? 'gSite not found. Create one first!';
        });
      }
    } catch (e) {
      setState(() {
        _loading = false;
        _success = false;
        _resultMessage = 'Error: $e';
      });
    }
  }

  void _showGSiteViewer(BuildContext context, GSite gsite) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => GSiteViewerSheet(gsite: gsite),
    );
  }

  Future<void> _createGcrumbsNamespace() async {
    setState(() {
      _loading = true;
      _resultMessage = null;
      _success = null;
    });

    try {
      final result = await _doCreateGcrumbsNamespace();
      setState(() {
        _success = result.success;
        _resultMessage = result.message;
      });
    } catch (e) {
      setState(() {
        _success = false;
        _resultMessage = 'Error: $e';
      });
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _viewGcrumbsNamespace() async {
    setState(() {
      _loading = true;
      _resultMessage = null;
      _success = null;
    });

    try {
      final result = await gsiteService.getGSite('gcrumbs@');
      
      if (result.success && result.data != null) {
        if (!mounted) return;
        _showGSiteViewer(context, result.data!);
        setState(() => _loading = false);
      } else {
        setState(() {
          _loading = false;
          _success = false;
          _resultMessage = result.error ?? 'gcrumbs@ not found. Create it first!';
        });
      }
    } catch (e) {
      setState(() {
        _loading = false;
        _success = false;
        _resultMessage = 'Error: $e';
      });
    }
  }
}

// ============================================================
// gSITE VIEWER BOTTOM SHEET
// ============================================================

class GSiteViewerSheet extends StatelessWidget {
  final GSite gsite;

  const GSiteViewerSheet({super.key, required this.gsite});

  // Helper to get PersonGSite properties
  PersonGSite? get _person => gsite is PersonGSite ? gsite as PersonGSite : null;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              
              // Content
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(24),
                  children: [
                    // Header
                    _buildHeader(),
                    const SizedBox(height: 24),
                    
                    // Trust Score
                    if (gsite.trust != null) ...[
                      _buildTrustSection(),
                      const SizedBox(height: 24),
                    ],
                    
                    // Bio
                    if (gsite.bio != null && gsite.bio!.isNotEmpty) ...[
                      _buildSection('About', gsite.bio!),
                      const SizedBox(height: 24),
                    ],
                    
                    // Skills (Person only)
                    if (_person != null && _person!.skills.isNotEmpty) ...[
                      _buildSkillsSection(),
                      const SizedBox(height: 24),
                    ],
                    
                    // Status (Person only)
                    if (_person != null && (_person!.statusText != null || _person!.statusEmoji != null)) ...[
                      _buildStatusSection(),
                      const SizedBox(height: 24),
                    ],
                    
                    // Actions
                    _buildActionsSection(),
                    const SizedBox(height: 24),
                    
                    // Links
                    if (gsite.links.isNotEmpty) ...[
                      _buildLinksSection(),
                      const SizedBox(height: 24),
                    ],
                    
                    // Signature (collapsed)
                    _buildSignatureSection(),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    final emoji = _person?.statusEmoji ?? '🐆';
    
    return Column(
      children: [
        // Avatar placeholder
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: Colors.deepPurple.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: gsite.avatar != null
            ? ClipOval(
                child: Image.network(
                  gsite.avatar!.url,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Center(
                    child: Text(emoji, style: const TextStyle(fontSize: 36)),
                  ),
                ),
              )
            : Center(
                child: Text(emoji, style: const TextStyle(fontSize: 36)),
              ),
        ),
        const SizedBox(height: 16),
        
        // Name
        Text(
          gsite.name,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        
        // Handle
        Text(
          gsite.id,
          style: TextStyle(
            fontSize: 16,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 8),
        
        // Tagline
        if (gsite.tagline != null && gsite.tagline!.isNotEmpty)
          Text(
            gsite.tagline!,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[700],
              fontStyle: FontStyle.italic,
            ),
            textAlign: TextAlign.center,
          ),
        
        // Type badge
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.deepPurple.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            gsite.type.value[0].toUpperCase() + gsite.type.value.substring(1),
            style: const TextStyle(
              color: Colors.deepPurple,
              fontWeight: FontWeight.w500,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTrustSection() {
    final trust = gsite.trust!;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.deepPurple.withOpacity(0.1),
            Colors.purple.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildTrustStat(
            '${trust.score.toStringAsFixed(1)}%',
            'Trust Score',
            Icons.verified_user,
          ),
          Container(width: 1, height: 40, color: Colors.grey[300]),
          _buildTrustStat(
            trust.breadcrumbs.toString(),
            'Breadcrumbs',
            Icons.location_on,
          ),
        ],
      ),
    );
  }

  Widget _buildTrustStat(String value, String label, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.deepPurple, size: 24),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.deepPurple,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildSection(String title, String content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          content,
          style: const TextStyle(fontSize: 15, height: 1.5),
        ),
      ],
    );
  }

  Widget _buildSkillsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Skills',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _person!.skills.map((skill) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                skill,
                style: const TextStyle(fontSize: 13),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildStatusSection() {
    final available = _person?.available ?? false;
    final emoji = _person?.statusEmoji ?? '📍';
    final text = _person?.statusText ?? 'No status';
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: available ? Colors.green.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: available ? Colors.green.withOpacity(0.3) : Colors.grey.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                Text(
                  available ? 'Available' : 'Busy',
                  style: TextStyle(
                    fontSize: 12,
                    color: available ? Colors.green : Colors.grey,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: available ? Colors.green : Colors.grey,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionsSection() {
    final actions = gsite.actions;
    
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        if (actions.message)
          _buildActionButton(Icons.message, 'Message', Colors.blue),
        if (actions.payment)
          _buildActionButton(Icons.payment, 'Pay', Colors.green),
        if (actions.share)
          _buildActionButton(Icons.share, 'Share', Colors.orange),
      ],
    );
  }

  Widget _buildActionButton(IconData icon, String label, Color color) {
    return Column(
      children: [
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: color),
        ),
      ],
    );
  }

  Widget _buildLinksSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Links',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 8),
        ...gsite.links.map((link) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Icon(_getLinkIcon(link.type), size: 18, color: Colors.grey[600]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    link.displayUrl,
                    style: TextStyle(
                      color: Colors.blue[700],
                      fontSize: 14,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  IconData _getLinkIcon(String type) {
    switch (type.toLowerCase()) {
      case 'website': return Icons.language;
      case 'twitter': return Icons.alternate_email;
      case 'github': return Icons.code;
      case 'linkedin': return Icons.work;
      default: return Icons.link;
    }
  }

  Widget _buildSignatureSection() {
    final sig = gsite.signature;
    
    return ExpansionTile(
      title: const Text(
        'Cryptographic Signature',
        style: TextStyle(fontSize: 14, color: Colors.grey),
      ),
      leading: const Icon(Icons.fingerprint, color: Colors.deepPurple),
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 16),
                  SizedBox(width: 8),
                  Text(
                    'Verified Ed25519 Signature',
                    style: TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  sig,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: Colors.grey[700],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================
// RESULT CLASS
// ============================================================

class _Result {
  final bool success;
  final String message;
  _Result({required this.success, required this.message});
}

// ============================================================
// VALIDATE ONLY
// ============================================================

Future<_Result> _doValidateOnly() async {
  final wallet = IdentityWallet();
  final handle = await wallet.getCurrentHandle() ?? 'test';
  final info = await wallet.getIdentityInfo();

  final gsiteData = _buildSimpleGSite(handle, info.trustScore, info.breadcrumbCount);
  
  final validation = await gsiteService.validateGSiteJson(gsiteData);

  if (validation.valid) {
    final warnings = validation.warnings.map((w) => '• ${w.message}').join('\n');
    return _Result(success: true, message: 'Valid! ✅\n\n$warnings');
  } else {
    final errors = validation.errors.map((e) => '• ${e.message}').join('\n');
    return _Result(success: false, message: 'Invalid! ❌\n\n$errors');
  }
}

// ============================================================
// CREATE gSITE
// ============================================================

Future<_Result> _doCreateGSite() async {
  print('🐆 Starting gSite creation...');

  final wallet = IdentityWallet();
  
  if (!wallet.hasIdentity) {
    return _Result(success: false, message: 'No identity found!');
  }

  final publicKey = wallet.publicKey!;
  final handle = await wallet.getCurrentHandle();
  
  print('🔑 Public key: $publicKey');
  print('🔑 Public key length: ${publicKey.length}');
  
  if (publicKey.length != 64) {
    return _Result(
      success: false, 
      message: 'Public key wrong length! Got ${publicKey.length}, expected 64.',
    );
  }

  if (handle == null || handle.isEmpty) {
    return _Result(success: false, message: 'No handle claimed!');
  }

  print('📋 Creating gSite for @$handle');

  final info = await wallet.getIdentityInfo();
  final gsiteData = _buildSimpleGSite(handle, info.trustScore, info.breadcrumbCount);

  // 1. Validate
  print('✅ Validating...');
  final validation = await gsiteService.validateGSiteJson(gsiteData);
  if (!validation.valid) {
    final errors = validation.errors.map((e) => e.message).join(', ');
    return _Result(success: false, message: 'Validation failed: $errors');
  }

  // 2. Sign using wallet's existing method
  print('🔐 Signing...');
  final contentToSign = _sortedJson(gsiteData);
  final signature = await wallet.signString(contentToSign);
  
  if (signature == null) {
    return _Result(success: false, message: 'Failed to sign');
  }
  
  print('🔐 Signature length: ${signature.length}');
  gsiteData['signature'] = 'ed25519:$signature';

  // 3. Save with direct HTTP call
  print('💾 Saving...');
  
  try {
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final authMessage = 'PUT:/gsite/@$handle:$timestamp';
    print('🔐 Auth message: $authMessage');
    final authSignature = await wallet.signString(authMessage);
    
    if (authSignature == null) {
      return _Result(success: false, message: 'Failed to sign auth');
    }
    
    print('🔐 Auth signature length: ${authSignature.length}');

    final uri = Uri.parse('https://gns-browser-production.up.railway.app/gsite/@$handle');
    
    print('📤 Request headers:');
    print('   X-GNS-PublicKey: $publicKey');
    print('   X-GNS-Timestamp: $timestamp');
    print('   X-GNS-Signature: ${authSignature.substring(0, 32)}...');
    
    final response = await http.put(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'X-GNS-PublicKey': publicKey,
        'X-GNS-Signature': authSignature,
        'X-GNS-Timestamp': timestamp,
      },
      body: jsonEncode(gsiteData),
    );

    print('📡 Response: ${response.statusCode}');
    print('📡 Body: ${response.body}');

    final json = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode == 200 && json['success'] == true) {
      final version = json['version'] ?? 1;
      return _Result(success: true, message: 'gSite created! 🎉\nVersion: $version');
    } else {
      return _Result(success: false, message: json['error'] ?? 'Unknown error');
    }
  } catch (e) {
    print('❌ Error: $e');
    return _Result(success: false, message: 'Save failed: $e');
  }
}

// ============================================================
// BUILD SIMPLE gSITE
// ============================================================

Map<String, dynamic> _buildSimpleGSite(String handle, double trustScore, int breadcrumbs) {
  return {
    '@context': 'https://schema.gns.network/v1',
    '@type': 'Person',
    '@id': '@$handle',
    'name': handle[0].toUpperCase() + handle.substring(1),
    'tagline': 'GNS identity verified through proof-of-trajectory',
    'bio': 'Your keys, your identity, your data.',
    'trust': {
      'score': trustScore,
      'breadcrumbs': breadcrumbs,
    },
    'skills': ['GNS Identity'],
    'status': {
      'emoji': '🐆',
      'text': 'On PANTHERA',
      'available': true,
    },
    'links': [
      {'type': 'website', 'url': 'https://gcrumbs.com'},
    ],
    'actions': {
      'message': true,
      'payment': true,
      'share': true,
    },
    'version': 1,
    'language': 'en',
    'signature': 'ed25519:PLACEHOLDER',
  };
}

// ============================================================
// BUILD gcrumbs@ ORGANIZATION gSITE
// ============================================================

Map<String, dynamic> _buildGcrumbsOrgGSite() {
  return {
    '@context': 'https://schema.gns.network/v1',
    '@type': 'Organization',
    '@id': 'gcrumbs@',
    'name': 'Globe Crumbs',
    'tagline': 'Identity through Presence',
    'bio': 'The GNS Foundation - building the identity layer the internet never had. '
           'We prove humanity through proof-of-trajectory, not biometrics. '
           'Your keys, your identity, your data.',
    'orgType': 'foundation',
    'trust': {
      'score': 100.0,
      'breadcrumbs': 10000,
    },
    'founded': '2024',
    'team': [
      {
        'handle': '@camiloayerbe',
        'role': 'Founder & CEO',
      },
    ],
    'links': [
      {'type': 'website', 'url': 'https://gcrumbs.com'},
      {'type': 'github', 'url': 'https://github.com/gns-protocol'},
      {'type': 'twitter', 'handle': 'glocrumbs'},
    ],
    'actions': {
      'message': true,
      'payment': true,
      'share': true,
      'follow': true,
    },
    'version': 1,
    'language': 'en',
    'signature': 'ed25519:PLACEHOLDER',
  };
}

// ============================================================
// CREATE gcrumbs@ NAMESPACE
// ============================================================

Future<_Result> _doCreateGcrumbsNamespace() async {
  print('🏢 Creating gcrumbs@ namespace...');

  final wallet = IdentityWallet();
  
  if (!wallet.hasIdentity) {
    return _Result(success: false, message: 'No identity found!');
  }

  final publicKey = wallet.publicKey!;
  
  print('🔑 Public key: $publicKey');

  final gsiteData = _buildGcrumbsOrgGSite();

  // 1. Validate
  print('✅ Validating...');
  final validation = await gsiteService.validateGSiteJson(gsiteData);
  if (!validation.valid) {
    final errors = validation.errors.map((e) => e.message).join(', ');
    return _Result(success: false, message: 'Validation failed: $errors');
  }

  // 2. Sign
  print('🔐 Signing...');
  final contentToSign = _sortedJson(gsiteData);
  final signature = await wallet.signString(contentToSign);
  
  if (signature == null) {
    return _Result(success: false, message: 'Failed to sign');
  }
  
  print('🔐 Signature length: ${signature.length}');
  gsiteData['signature'] = 'ed25519:$signature';

  // 3. Save
  print('💾 Saving...');
  
  try {
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final authMessage = 'PUT:/gsite/gcrumbs@:$timestamp';
    print('🔐 Auth message: $authMessage');
    final authSignature = await wallet.signString(authMessage);
    
    if (authSignature == null) {
      return _Result(success: false, message: 'Failed to sign auth');
    }

    final uri = Uri.parse('https://gns-browser-production.up.railway.app/gsite/gcrumbs@');
    
    final response = await http.put(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'X-GNS-PublicKey': publicKey,
        'X-GNS-Signature': authSignature,
        'X-GNS-Timestamp': timestamp,
      },
      body: jsonEncode(gsiteData),
    );

    print('📡 Response: ${response.statusCode}');
    print('📡 Body: ${response.body}');

    final json = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode == 200 && json['success'] == true) {
      final version = json['version'] ?? 1;
      return _Result(success: true, message: 'gcrumbs@ namespace created! 🏢\nVersion: $version');
    } else {
      return _Result(success: false, message: json['error'] ?? 'Unknown error');
    }
  } catch (e) {
    print('❌ Error: $e');
    return _Result(success: false, message: 'Save failed: $e');
  }
}

// ============================================================
// SORTED JSON (for signing)
// ============================================================

String _sortedJson(Map<String, dynamic> data) {
  final copy = Map<String, dynamic>.from(data);
  copy.remove('signature');
  return _sortedJsonEncode(copy);
}

String _sortedJsonEncode(dynamic obj) {
  if (obj == null || obj is! Map && obj is! List) {
    return jsonEncode(obj);
  }
  
  if (obj is List) {
    return '[${obj.map(_sortedJsonEncode).join(',')}]';
  }
  
  final map = obj as Map<String, dynamic>;
  final keys = map.keys.toList()..sort();
  final pairs = keys.map((k) => '"$k":${_sortedJsonEncode(map[k])}');
  return '{${pairs.join(',')}}';
}
