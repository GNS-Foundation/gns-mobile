/// Organization Namespace Registration Screen - Phase 5 (v2)
/// 
/// Register a new organization namespace on GNS with DNS verification.
/// Organizations must prove domain ownership via DNS TXT record.
/// 
/// Flow:
/// 1. User submits registration form
/// 2. Server generates verification code
/// 3. User adds TXT record to their domain
/// 4. User clicks "Verify" → Server checks DNS
/// 5. On success → Namespace granted!
/// 
/// Location: lib/ui/screens/org_registration_screen.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

/// Organization namespace registration with DNS verification
class OrgRegistrationScreen extends StatefulWidget {
  const OrgRegistrationScreen({super.key});

  @override
  State<OrgRegistrationScreen> createState() => _OrgRegistrationScreenState();
}

class _OrgRegistrationScreenState extends State<OrgRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _namespaceController = TextEditingController();
  final _orgNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _websiteController = TextEditingController();
  final _descriptionController = TextEditingController();
  
  // Registration state
  _RegistrationState _state = _RegistrationState.form;
  String _selectedTier = 'starter';
  bool _loading = false;
  bool _checkingAvailability = false;
  bool? _isAvailable;
  
  // Verification state
  String? _verificationCode;
  String? _verificationDomain;
  String? _registrationId;
  bool _verifying = false;
  String? _verificationError;
  
  static const _apiBase = 'https://gns-browser-production.up.railway.app';
  
  final _tiers = [
    {
      'id': 'starter',
      'name': 'Starter',
      'price': '\$49/year',
      'features': ['Up to 10 users', '1 namespace', 'Basic support'],
      'icon': '🚀',
    },
    {
      'id': 'team',
      'name': 'Team',
      'price': '\$149/year',
      'features': ['Up to 50 users', '1 namespace', 'Priority support'],
      'icon': '👥',
    },
    {
      'id': 'business',
      'name': 'Business',
      'price': '\$299/year',
      'features': ['Up to 200 users', '1 namespace', 'Custom branding', 'API access'],
      'icon': '🏢',
    },
    {
      'id': 'enterprise',
      'name': 'Enterprise',
      'price': 'Custom',
      'features': ['Unlimited users', 'Multiple namespaces', 'SLA', 'Dedicated support'],
      'icon': '🏛️',
    },
  ];

  @override
  void dispose() {
    _namespaceController.dispose();
    _orgNameController.dispose();
    _emailController.dispose();
    _websiteController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  /// Extract domain from website URL
  String _extractDomain(String website) {
    String domain = website.toLowerCase().trim();
    domain = domain.replaceAll(RegExp(r'^https?://'), '');
    domain = domain.replaceAll(RegExp(r'^www\.'), '');
    domain = domain.split('/').first;
    return domain;
  }

  /// Check if namespace is available
  Future<void> _checkAvailability(String namespace) async {
    if (namespace.isEmpty || namespace.length < 3) {
      setState(() => _isAvailable = null);
      return;
    }
    
    String clean = namespace.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    setState(() => _checkingAvailability = true);
    
    try {
      final response = await http.get(
        Uri.parse('$_apiBase/gsite/$clean@'),
      ).timeout(const Duration(seconds: 10));
      
      setState(() {
        _isAvailable = response.statusCode == 404;
        _checkingAvailability = false;
      });
    } catch (e) {
      setState(() {
        _isAvailable = true; // Assume available if check fails
        _checkingAvailability = false;
      });
    }
  }

  /// Submit registration and get verification code
  Future<void> _submitRegistration() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isAvailable != true) {
      _showError('Please choose an available namespace');
      return;
    }
    if (_websiteController.text.isEmpty) {
      _showError('Website is required for DNS verification');
      return;
    }
    
    setState(() => _loading = true);
    
    try {
      final namespace = _namespaceController.text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      final domain = _extractDomain(_websiteController.text);
      
      // Request verification code from server
      final response = await http.post(
        Uri.parse('$_apiBase/org/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'namespace': namespace,
          'organization_name': _orgNameController.text,
          'email': _emailController.text,
          'website': _websiteController.text,
          'domain': domain,
          'description': _descriptionController.text,
          'tier': _selectedTier,
        }),
      ).timeout(const Duration(seconds: 15));
      
      final data = jsonDecode(response.body);
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        setState(() {
          _verificationCode = data['verification_code'] ?? 'gns-verify-${namespace.hashCode.abs().toString().substring(0, 8)}';
          _verificationDomain = domain;
          _registrationId = data['registration_id'];
          _state = _RegistrationState.verify;
          _loading = false;
        });
      } else {
        _showError(data['error'] ?? 'Registration failed');
        setState(() => _loading = false);
      }
    } catch (e) {
      // For demo: generate local verification code
      final namespace = _namespaceController.text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      final domain = _extractDomain(_websiteController.text);
      
      setState(() {
        _verificationCode = 'gns-verify-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}';
        _verificationDomain = domain;
        _registrationId = 'pending-$namespace';
        _state = _RegistrationState.verify;
        _loading = false;
      });
    }
  }

  /// Verify DNS TXT record
  Future<void> _verifyDns() async {
    setState(() {
      _verifying = true;
      _verificationError = null;
    });
    
    try {
      final response = await http.post(
        Uri.parse('$_apiBase/org/verify'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'registration_id': _registrationId,
          'domain': _verificationDomain,
          'verification_code': _verificationCode,
        }),
      ).timeout(const Duration(seconds: 30));
      
      final data = jsonDecode(response.body);
      
      if (response.statusCode == 200 && data['verified'] == true) {
        setState(() {
          _state = _RegistrationState.success;
          _verifying = false;
        });
      } else {
        setState(() {
          _verificationError = data['error'] ?? 'DNS record not found. Please wait a few minutes for DNS propagation.';
          _verifying = false;
        });
      }
    } catch (e) {
      setState(() {
        _verificationError = 'Verification failed. DNS records can take up to 24 hours to propagate. Please try again later.';
        _verifying = false;
      });
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied to clipboard!'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Register Organization'),
        centerTitle: true,
      ),
      body: switch (_state) {
        _RegistrationState.form => _buildFormView(),
        _RegistrationState.verify => _buildVerifyView(),
        _RegistrationState.success => _buildSuccessView(),
      },
    );
  }

  // ==================== FORM VIEW ====================
  
  Widget _buildFormView() {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF8B5CF6), Color(0xFF7C3AED)],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Column(
              children: [
                Text('🏢', style: TextStyle(fontSize: 48)),
                SizedBox(height: 8),
                Text(
                  'Organization Namespace',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Claim your organization\'s identity on GNS',
                  style: TextStyle(color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          // DNS Verification Notice
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue[200]!),
            ),
            child: Row(
              children: [
                Icon(Icons.verified_user, color: Colors.blue[700]),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'DNS Verification Required',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue[800],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'You\'ll need to add a TXT record to your domain to prove ownership.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.blue[700],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Namespace Input
          _buildLabel('NAMESPACE'),
          TextFormField(
            controller: _namespaceController,
            decoration: InputDecoration(
              hintText: 'yourcompany',
              suffixText: '@',
              suffixStyle: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.purple,
              ),
              prefixIcon: _checkingAvailability
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : _isAvailable == true
                      ? const Icon(Icons.check_circle, color: Colors.green)
                      : _isAvailable == false
                          ? const Icon(Icons.cancel, color: Colors.red)
                          : const Icon(Icons.business),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.grey[50],
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Required';
              if (v.length < 3) return 'At least 3 characters';
              if (v.length > 20) return 'Maximum 20 characters';
              if (!RegExp(r'^[a-zA-Z0-9]+$').hasMatch(v)) {
                return 'Letters and numbers only';
              }
              return null;
            },
            onChanged: (value) {
              Future.delayed(const Duration(milliseconds: 500), () {
                if (_namespaceController.text == value) {
                  _checkAvailability(value);
                }
              });
            },
          ),
          
          if (_isAvailable == true) ...[
            const SizedBox(height: 8),
            _buildStatusBox(
              icon: Icons.check,
              color: Colors.green,
              text: '${_namespaceController.text.toLowerCase()}@ is available!',
            ),
          ],
          
          if (_isAvailable == false) ...[
            const SizedBox(height: 8),
            _buildStatusBox(
              icon: Icons.close,
              color: Colors.red,
              text: 'This namespace is already taken',
            ),
          ],
          
          const SizedBox(height: 20),
          
          // Organization Name
          _buildLabel('ORGANIZATION NAME'),
          TextFormField(
            controller: _orgNameController,
            decoration: _inputDecoration('Your Company Inc.', Icons.badge),
            validator: (v) => v?.isEmpty == true ? 'Required' : null,
          ),
          
          const SizedBox(height: 16),
          
          // Website (Required for DNS verification)
          _buildLabel('WEBSITE (REQUIRED FOR VERIFICATION)'),
          TextFormField(
            controller: _websiteController,
            keyboardType: TextInputType.url,
            decoration: _inputDecoration('https://yourcompany.com', Icons.language),
            validator: (v) {
              if (v?.isEmpty == true) return 'Required for DNS verification';
              if (!v!.contains('.')) return 'Enter a valid domain';
              return null;
            },
          ),
          
          const SizedBox(height: 16),
          
          // Email
          _buildLabel('BUSINESS EMAIL'),
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: _inputDecoration('contact@yourcompany.com', Icons.email),
            validator: (v) {
              if (v?.isEmpty == true) return 'Required';
              if (!v!.contains('@')) return 'Invalid email';
              return null;
            },
          ),
          
          const SizedBox(height: 16),
          
          // Description
          _buildLabel('DESCRIPTION'),
          TextFormField(
            controller: _descriptionController,
            maxLines: 3,
            maxLength: 200,
            decoration: InputDecoration(
              hintText: 'Tell us about your organization...',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.grey[50],
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Pricing Tiers
          _buildLabel('SELECT PLAN'),
          const SizedBox(height: 8),
          
          ...(_tiers.map((tier) => _buildTierCard(tier))),
          
          const SizedBox(height: 24),
          
          // Submit Button
          ElevatedButton(
            onPressed: _loading ? null : _submitRegistration,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8B5CF6),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _loading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.arrow_forward),
                      SizedBox(width: 8),
                      Text('CONTINUE TO VERIFICATION', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
          ),
          
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ==================== VERIFY VIEW ====================
  
  Widget _buildVerifyView() {
    final txtRecord = 'gns-verify=$_verificationCode';
    
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Column(
            children: [
              Text('🔐', style: TextStyle(fontSize: 48)),
              SizedBox(height: 8),
              Text(
                'Verify Domain Ownership',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Add a DNS TXT record to prove you own this domain',
                style: TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 24),
        
        // Domain Info
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.language, color: Colors.purple),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Domain to verify:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    Text(
                      _verificationDomain ?? '',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 24),
        
        // Instructions
        _buildLabel('STEP 1: ADD DNS TXT RECORD'),
        const SizedBox(height: 8),
        
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Add this TXT record to your domain\'s DNS settings:',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              
              // Record Type
              _buildDnsField('Type', 'TXT'),
              const SizedBox(height: 12),
              
              // Host/Name
              _buildDnsField('Host / Name', '@  or  $_verificationDomain'),
              const SizedBox(height: 12),
              
              // Value
              _buildDnsFieldWithCopy('Value', txtRecord),
            ],
          ),
        ),
        
        const SizedBox(height: 24),
        
        // Common DNS Providers
        _buildLabel('STEP 2: WHERE TO ADD IT'),
        const SizedBox(height: 8),
        
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.blue[50],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Log in to your domain registrar or DNS provider:',
                style: TextStyle(color: Colors.blue[800]),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildProviderChip('Cloudflare'),
                  _buildProviderChip('GoDaddy'),
                  _buildProviderChip('Namecheap'),
                  _buildProviderChip('Google Domains'),
                  _buildProviderChip('Route 53'),
                  _buildProviderChip('Squarespace'),
                ],
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 24),
        
        // Propagation Notice
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.amber[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.amber[200]!),
          ),
          child: Row(
            children: [
              Icon(Icons.schedule, color: Colors.amber[800]),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'DNS Propagation',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber[900]),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'DNS changes can take 5 minutes to 24 hours to propagate. If verification fails, please wait and try again.',
                      style: TextStyle(fontSize: 13, color: Colors.amber[800]),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 24),
        
        // Verification Error
        if (_verificationError != null) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.red[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red[200]!),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red[700]),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _verificationError!,
                    style: TextStyle(color: Colors.red[700]),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        
        // Verify Button
        _buildLabel('STEP 3: VERIFY'),
        const SizedBox(height: 8),
        
        ElevatedButton(
          onPressed: _verifying ? null : _verifyDns,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF10B981),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: _verifying
              ? const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    ),
                    SizedBox(width: 12),
                    Text('CHECKING DNS...'),
                  ],
                )
              : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.verified),
                    SizedBox(width: 8),
                    Text('VERIFY DNS RECORD', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
        ),
        
        const SizedBox(height: 16),
        
        // Back button
        TextButton(
          onPressed: () => setState(() => _state = _RegistrationState.form),
          child: const Text('← Back to form'),
        ),
        
        const SizedBox(height: 32),
      ],
    );
  }

  // ==================== SUCCESS VIEW ====================
  
  Widget _buildSuccessView() {
    final namespace = _namespaceController.text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🎉', style: TextStyle(fontSize: 80)),
            const SizedBox(height: 24),
            const Text(
              'Namespace Registered!',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '$namespace@',
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Color(0xFF8B5CF6),
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.green[200]!),
              ),
              child: Column(
                children: [
                  Icon(Icons.check_circle, color: Colors.green[600], size: 48),
                  const SizedBox(height: 12),
                  Text(
                    'Your organization namespace is now active!',
                    style: TextStyle(color: Colors.green[800], fontWeight: FontWeight.w500),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'You can now add team members and create your organization\'s gSite.',
                    style: TextStyle(color: Colors.green[700], fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8B5CF6),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('DONE', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== HELPER WIDGETS ====================
  
  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      filled: true,
      fillColor: Colors.grey[50],
    );
  }

  Widget _buildStatusBox({required IconData icon, required Color color, required String text}) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildTierCard(Map<String, dynamic> tier) {
    final isSelected = _selectedTier == tier['id'];
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => setState(() => _selectedTier = tier['id'] as String),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(
              color: isSelected ? Colors.purple : Colors.grey[300]!,
              width: isSelected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(12),
            color: isSelected ? Colors.purple[50] : Colors.white,
          ),
          child: Row(
            children: [
              Text(tier['icon'] as String, style: const TextStyle(fontSize: 32)),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(tier['name'] as String, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const Spacer(),
                        Text(tier['price'] as String, style: TextStyle(color: Colors.purple[700], fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      (tier['features'] as List).join(' • '),
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              Radio<String>(
                value: tier['id'] as String,
                groupValue: _selectedTier,
                onChanged: (v) => setState(() => _selectedTier = v!),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDnsField(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
        ),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(value, style: const TextStyle(fontFamily: 'monospace')),
          ),
        ),
      ],
    );
  }

  Widget _buildDnsFieldWithCopy(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
        ),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.purple[50],
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.purple[200]!),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value,
                    style: TextStyle(fontFamily: 'monospace', color: Colors.purple[800], fontWeight: FontWeight.w500),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 18),
                  onPressed: () => _copyToClipboard(value),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  color: Colors.purple,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProviderChip(String name) {
    return Chip(
      label: Text(name, style: const TextStyle(fontSize: 12)),
      backgroundColor: Colors.white,
      side: BorderSide(color: Colors.blue[200]!),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

enum _RegistrationState { form, verify, success }
