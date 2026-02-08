/// Organization Namespace Registration Screen - Updated v3
/// 
/// Now uses OrgService to persist registrations locally.
/// Users can leave and return to continue verification.
/// 
/// Flow:
/// 1. User submits registration form → Saved to local storage
/// 2. Server generates verification code
/// 3. User adds TXT record to their domain
/// 4. User clicks "Verify" → Server checks DNS
/// 5. On success → Namespace verified!
/// 
/// Location: lib/ui/screens/org_registration_screen.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../../core/org/org_storage.dart';
import '../../core/org/org_service.dart';

/// Organization namespace registration with DNS verification
class OrgRegistrationScreen extends StatefulWidget {
  /// Optional: Pre-fill with existing pending registration
  final OrgRegistration? existingRegistration;
  
  const OrgRegistrationScreen({super.key, this.existingRegistration});

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
  
  final _orgService = OrgService.instance;
  
  // Registration state
  _RegistrationState _state = _RegistrationState.form;
  String _selectedTier = 'starter';
  bool _loading = false;
  bool _checkingAvailability = false;
  bool? _isAvailable;
  
  // Verification state - now from OrgRegistration
  OrgRegistration? _registration;
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
  void initState() {
    super.initState();
    _initService();
    
    // If existing registration passed, show verify state
    if (widget.existingRegistration != null) {
      _registration = widget.existingRegistration;
      _namespaceController.text = _registration!.namespace;
      _orgNameController.text = _registration!.organizationName;
      _emailController.text = _registration!.email;
      _websiteController.text = _registration!.domain;
      _selectedTier = _registration!.tier;
      _state = _RegistrationState.verify;
    }
  }

  Future<void> _initService() async {
    await _orgService.initialize();
  }

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
        Uri.parse('$_apiBase/org/check/$clean'),  // ← Use correct endpoint
      ).timeout(const Duration(seconds: 10));
      
      final data = jsonDecode(response.body);
      
      setState(() {
        _isAvailable = data['success'] == true && data['data']?['available'] == true;
        _checkingAvailability = false;
      });
    } catch (e) {
      setState(() {
        _isAvailable = null;
        _checkingAvailability = false;
      });
    }
  }

  /// Submit registration using OrgService
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
    
    final result = await _orgService.register(
      namespace: _namespaceController.text,
      organizationName: _orgNameController.text,
      email: _emailController.text,
      website: _websiteController.text,
      description: _descriptionController.text.isNotEmpty 
          ? _descriptionController.text 
          : null,
      tier: _selectedTier,
    );
    
    if (result.success && result.data != null) {
      setState(() {
        _registration = result.data;
        _state = _RegistrationState.verify;
        _loading = false;
      });
    } else {
      _showError(result.error ?? 'Registration failed');
      setState(() => _loading = false);
    }
  }

  /// Verify DNS using OrgService
  Future<void> _verifyDns() async {
    if (_registration == null) return;
    
    setState(() {
      _verifying = true;
      _verificationError = null;
    });
    
    final result = await _orgService.verifyDns(_registration!.namespace);
    
    if (result.success && result.data != null) {
      setState(() {
        _registration = result.data;
        _state = _RegistrationState.success;
        _verifying = false;
      });
    } else {
      setState(() {
        _verificationError = result.error ?? 'DNS record not found. Please wait a few minutes for DNS propagation.';
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_state == _RegistrationState.success 
            ? 'Success!' 
            : _state == _RegistrationState.verify 
                ? 'Verify Domain' 
                : 'Register Organization'),
        leading: _state != _RegistrationState.form
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  if (_state == _RegistrationState.verify) {
                    // Return to My Organizations to see pending registration
                    Navigator.pop(context);
                  } else {
                    Navigator.pop(context);
                  }
                },
              )
            : null,
      ),
      body: _state == _RegistrationState.form
          ? _buildFormView()
          : _state == _RegistrationState.verify
              ? _buildVerifyView()
              : _buildSuccessView(),
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
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.purple[700]!, Colors.purple[500]!],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                const Text('🏢', style: TextStyle(fontSize: 48)),
                const SizedBox(height: 12),
                const Text(
                  'Claim Your Namespace',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Register company@ and give your team verified identities',
                  style: TextStyle(color: Colors.white.withOpacity(0.9)),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Namespace field
          _buildLabel('NAMESPACE'),
          TextFormField(
            controller: _namespaceController,
            decoration: InputDecoration(
              hintText: 'company',
              suffixText: '@',
              suffixStyle: TextStyle(
                color: Colors.purple[700],
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
              prefixIcon: const Icon(Icons.alternate_email),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.grey[50],
            ),
            onChanged: _checkAvailability,
            validator: (v) {
              if (v == null || v.isEmpty) return 'Required';
              if (v.length < 3) return 'Min 3 characters';
              if (!RegExp(r'^[a-zA-Z0-9]+$').hasMatch(v)) return 'Letters and numbers only';
              return null;
            },
          ),
          
          // Availability indicator
          if (_checkingAvailability)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 8),
                  Text('Checking availability...'),
                ],
              ),
            )
          else if (_isAvailable == true)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    '${_namespaceController.text.toLowerCase()}@ is available!',
                    style: const TextStyle(color: Colors.green),
                  ),
                ],
              ),
            )
          else if (_isAvailable == false)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  const Icon(Icons.cancel, color: Colors.red, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    '${_namespaceController.text.toLowerCase()}@ is not available',
                    style: const TextStyle(color: Colors.red),
                  ),
                ],
              ),
            ),
          
          const SizedBox(height: 20),
          
          // Organization name
          _buildLabel('ORGANIZATION NAME'),
          TextFormField(
            controller: _orgNameController,
            decoration: _inputDecoration('Acme Corp', Icons.business),
            validator: (v) => v?.isEmpty == true ? 'Required' : null,
          ),
          
          const SizedBox(height: 20),
          
          // Website
          _buildLabel('WEBSITE (for DNS verification)'),
          TextFormField(
            controller: _websiteController,
            decoration: _inputDecoration('https://acme.com', Icons.language),
            keyboardType: TextInputType.url,
            validator: (v) => v?.isEmpty == true ? 'Required for DNS verification' : null,
          ),
          
          const SizedBox(height: 20),
          
          // Email
          _buildLabel('ADMIN EMAIL'),
          TextFormField(
            controller: _emailController,
            decoration: _inputDecoration('admin@acme.com', Icons.email),
            keyboardType: TextInputType.emailAddress,
            validator: (v) {
              if (v?.isEmpty == true) return 'Required';
              if (!v!.contains('@')) return 'Invalid email';
              return null;
            },
          ),
          
          const SizedBox(height: 20),
          
          // Description (optional)
          _buildLabel('DESCRIPTION (optional)'),
          TextFormField(
            controller: _descriptionController,
            decoration: _inputDecoration('Brief description of your organization', Icons.description),
            maxLines: 2,
          ),
          
          const SizedBox(height: 24),
          
          // Tier selection
          _buildLabel('SELECT PLAN'),
          ..._tiers.map((tier) => _buildTierCard(tier)),
          
          const SizedBox(height: 32),
          
          // Submit button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _loading ? null : _submitRegistration,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _loading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Text(
                      'CONTINUE TO VERIFICATION',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Info text
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.info, color: Colors.blue[700]),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'You\'ll need to add a DNS TXT record to verify domain ownership.',
                    style: TextStyle(color: Colors.blue[800]),
                  ),
                ),
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
    if (_registration == null) {
      return const Center(child: Text('No registration data'));
    }
    
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Status header
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.orange[50],
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.orange[200]!),
          ),
          child: Column(
            children: [
              const Text('⏳', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 12),
              const Text(
                'DNS Verification Required',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                '${_registration!.namespace}@',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.purple[700],
                ),
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 24),
        
        // Instructions
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Add this TXT record to your DNS:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 16),
              _buildDnsField('Type', 'TXT'),
              const SizedBox(height: 12),
              _buildDnsFieldWithCopy('Host', _registration!.txtRecordHost),
              const SizedBox(height: 12),
              _buildDnsFieldWithCopy('Value', _registration!.txtRecordValue),
            ],
          ),
        ),
        
        const SizedBox(height: 16),
        
        // Provider help
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.blue[50],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.help_outline, color: Colors.blue[700], size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Common DNS Providers',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue[800]),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildProviderChip('Cloudflare'),
                  _buildProviderChip('GoDaddy'),
                  _buildProviderChip('Namecheap'),
                  _buildProviderChip('Route53'),
                  _buildProviderChip('Google DNS'),
                ],
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 24),
        
        // Error message
        if (_verificationError != null)
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.red[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red[200]!),
            ),
            child: Row(
              children: [
                Icon(Icons.warning, color: Colors.red[700]),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _verificationError!,
                    style: TextStyle(color: Colors.red[800]),
                  ),
                ),
              ],
            ),
          ),
        
        // Verify button
        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: _verifying ? null : _verifyDns,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _verifying
                ? const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                      SizedBox(width: 12),
                      Text('Checking DNS...'),
                    ],
                  )
                : const Text(
                    'VERIFY DNS RECORD',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
          ),
        ),
        
        const SizedBox(height: 16),
        
        // Info about propagation
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.amber[50],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(Icons.schedule, color: Colors.amber[800]),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'DNS changes can take 5 minutes to 48 hours to propagate. You can close this screen and check back later from My Organizations.',
                  style: TextStyle(color: Colors.amber[900], fontSize: 13),
                ),
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 32),
      ],
    );
  }

  // ==================== SUCCESS VIEW ====================
  
  Widget _buildSuccessView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🎉', style: TextStyle(fontSize: 80)),
            const SizedBox(height: 24),
            const Text(
              'Namespace Verified!',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '${_registration?.namespace ?? ''}@',
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
                    'Your organization namespace is now verified!',
                    style: TextStyle(color: Colors.green[800], fontWeight: FontWeight.w500),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Go to My Organizations to activate and add team members.',
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
