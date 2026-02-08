/// Organization Verification Test Screen
/// 
/// Diagnostic tool for testing the organization DNS verification flow.
/// Helps debug and verify that the DNS TXT record verification works correctly.
/// 
/// Features:
/// - Test domain ownership verification
/// - Check DNS propagation status
/// - Manual verification code testing
/// - View pending registrations
/// 
/// Location: lib/ui/debug/org_verification_test_screen.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

class OrgVerificationTestScreen extends StatefulWidget {
  const OrgVerificationTestScreen({super.key});

  @override
  State<OrgVerificationTestScreen> createState() => _OrgVerificationTestScreenState();
}

class _OrgVerificationTestScreenState extends State<OrgVerificationTestScreen> {
  final _domainController = TextEditingController();
  final _namespaceController = TextEditingController();
  final _verificationCodeController = TextEditingController();
  
  static const _apiBase = 'https://gns-browser-production.up.railway.app';
  
  bool _loading = false;
  String? _result;
  Map<String, dynamic>? _registrationData;
  List<Map<String, dynamic>> _dnsRecords = [];
  
  // Test steps status
  bool _step1Complete = false; // Check namespace
  bool _step2Complete = false; // Register
  bool _step3Complete = false; // DNS propagation
  bool _step4Complete = false; // Verify

  @override
  void dispose() {
    _domainController.dispose();
    _namespaceController.dispose();
    _verificationCodeController.dispose();
    super.dispose();
  }

  void _log(String message, {bool isError = false}) {
    setState(() {
      _result = '${_result ?? ''}${isError ? '❌ ' : '✅ '}$message\n';
    });
  }

  void _clearLog() {
    setState(() {
      _result = null;
      _step1Complete = false;
      _step2Complete = false;
      _step3Complete = false;
      _step4Complete = false;
    });
  }

  /// Step 1: Check if namespace is available
  Future<void> _checkNamespace() async {
    final namespace = _namespaceController.text.trim().toLowerCase();
    if (namespace.isEmpty) {
      _showError('Please enter a namespace');
      return;
    }

    setState(() {
      _loading = true;
      _result = 'Checking namespace availability...\n';
    });

    try {
      final response = await http.get(
        Uri.parse('$_apiBase/org/check/$namespace'),
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);
      
      if (data['success'] == true && data['data'] != null) {
        final available = data['data']['available'] == true;
        final reason = data['data']['reason'] ?? data['data']['message'] ?? '';
        
        if (available) {
          _log('Namespace "$namespace@" is AVAILABLE! $reason');
          setState(() => _step1Complete = true);
        } else {
          _log('Namespace "$namespace@" is NOT available: $reason', isError: true);
        }
      } else {
        _log('Check failed: ${data['error'] ?? 'Unknown error'}', isError: true);
      }
    } catch (e) {
      _log('Request failed: $e', isError: true);
    }

    setState(() => _loading = false);
  }

  /// Step 2: Register organization (get verification code)
  Future<void> _registerOrganization() async {
    final namespace = _namespaceController.text.trim().toLowerCase();
    final domain = _domainController.text.trim().toLowerCase();
    
    if (namespace.isEmpty || domain.isEmpty) {
      _showError('Please enter namespace and domain');
      return;
    }

    setState(() {
      _loading = true;
      _result = '${_result ?? ''}Registering organization...\n';
    });

    try {
      final response = await http.post(
        Uri.parse('$_apiBase/org/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'namespace': namespace,
          'organization_name': 'Test Organization',
          'email': 'test@$domain',
          'website': 'https://$domain',
          'domain': domain,
          'description': 'Test registration',
          'tier': 'starter',
        }),
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        final regData = data['data'] ?? data;
        final verificationCode = regData['verification_code'];
        final txtRecord = regData['txt_record'] ?? 'gns-verify=$verificationCode';
        final instructions = regData['instructions'];
        
        setState(() {
          _registrationData = regData;
          _verificationCodeController.text = verificationCode ?? '';
          _step2Complete = true;
        });
        
        _log('Registration successful!');
        _log('Verification Code: $verificationCode');
        _log('');
        _log('📋 DNS TXT Record Instructions:');
        _log('Host: _gns.$domain');
        _log('Type: TXT');
        _log('Value: $txtRecord');
        _log('TTL: 3600');
        _log('');
        _log('Alternative hosts that work:');
        _log('  • _gns.$domain');
        _log('  • $domain (root)');
        _log('  • gns-verify.$domain');
        
      } else {
        _log('Registration failed: ${data['error'] ?? 'Unknown error'}', isError: true);
      }
    } catch (e) {
      _log('Request failed: $e', isError: true);
    }

    setState(() => _loading = false);
  }

  /// Step 3: Check DNS propagation (using public DNS-over-HTTPS)
  Future<void> _checkDnsPropagation() async {
    final domain = _domainController.text.trim().toLowerCase();
    if (domain.isEmpty) {
      _showError('Please enter a domain');
      return;
    }

    setState(() {
      _loading = true;
      _result = '${_result ?? ''}Checking DNS propagation...\n';
      _dnsRecords = [];
    });

    // Check multiple DNS locations
    final domainsToCheck = [
      '_gns.$domain',
      domain,
      'gns-verify.$domain',
    ];

    for (final checkDomain in domainsToCheck) {
      try {
        // Use Google's DNS-over-HTTPS API
        final response = await http.get(
          Uri.parse('https://dns.google/resolve?name=$checkDomain&type=TXT'),
        ).timeout(const Duration(seconds: 10));

        final data = jsonDecode(response.body);
        final answers = data['Answer'] as List? ?? [];
        
        if (answers.isNotEmpty) {
          _log('Found TXT records at $checkDomain:');
          for (final answer in answers) {
            final txtData = answer['data'] as String? ?? '';
            _log('  → $txtData');
            _dnsRecords.add({
              'domain': checkDomain,
              'value': txtData,
            });
            
            // Check if it contains our verification code
            final expectedCode = _verificationCodeController.text;
            if (expectedCode.isNotEmpty && txtData.contains(expectedCode)) {
              _log('  ✅ VERIFICATION CODE FOUND!');
              setState(() => _step3Complete = true);
            }
          }
        } else {
          _log('No TXT records at $checkDomain');
        }
      } catch (e) {
        _log('DNS check failed for $checkDomain: $e', isError: true);
      }
    }

    setState(() => _loading = false);
  }

  /// Step 4: Verify with backend
  Future<void> _verifyWithBackend() async {
    final domain = _domainController.text.trim().toLowerCase();
    final verificationCode = _verificationCodeController.text.trim();
    
    if (domain.isEmpty) {
      _showError('Please enter a domain');
      return;
    }

    setState(() {
      _loading = true;
      _result = '${_result ?? ''}Verifying with GNS backend...\n';
    });

    try {
      final body = {
        'domain': domain,
      };
      
      if (verificationCode.isNotEmpty) {
        body['verification_code'] = verificationCode;
      }
      
      if (_registrationData?['registration_id'] != null) {
        body['registration_id'] = _registrationData!['registration_id'].toString();
      }

      final response = await http.post(
        Uri.parse('$_apiBase/org/verify'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 30));

      final data = jsonDecode(response.body);
      
      if (data['success'] == true && data['data'] != null) {
        final verified = data['data']['verified'] == true;
        final namespace = data['data']['namespace'] ?? '';
        final message = data['data']['message'] ?? '';
        
        if (verified) {
          _log('🎉 VERIFICATION SUCCESSFUL!');
          _log('Namespace: $namespace');
          _log('Message: $message');
          setState(() => _step4Complete = true);
        } else {
          _log('Verification pending: $message', isError: true);
          if (data['data']['expected'] != null) {
            final expected = data['data']['expected'];
            _log('Expected DNS record:', isError: true);
            _log('  Host: ${expected['host']}', isError: true);
            _log('  Type: ${expected['type']}', isError: true);
            _log('  Value: ${expected['value']}', isError: true);
          }
        }
      } else {
        _log('Verification failed: ${data['error'] ?? 'Unknown error'}', isError: true);
      }
    } catch (e) {
      _log('Request failed: $e', isError: true);
    }

    setState(() => _loading = false);
  }

  /// Run full test flow
  Future<void> _runFullTest() async {
    _clearLog();
    
    _log('═══════════════════════════════════════');
    _log('GNS Organization Verification Test');
    _log('═══════════════════════════════════════\n');
    
    // Step 1
    _log('📝 STEP 1: Check Namespace Availability\n');
    await _checkNamespace();
    if (!_step1Complete) {
      _log('\n⛔ Test stopped: Namespace not available');
      return;
    }
    
    await Future.delayed(const Duration(milliseconds: 500));
    
    // Step 2
    _log('\n📝 STEP 2: Register Organization\n');
    await _registerOrganization();
    if (!_step2Complete) {
      _log('\n⛔ Test stopped: Registration failed');
      return;
    }
    
    await Future.delayed(const Duration(milliseconds: 500));
    
    // Step 3
    _log('\n📝 STEP 3: Check DNS Propagation\n');
    await _checkDnsPropagation();
    
    await Future.delayed(const Duration(milliseconds: 500));
    
    // Step 4
    _log('\n📝 STEP 4: Verify with Backend\n');
    await _verifyWithBackend();
    
    // Summary
    _log('\n═══════════════════════════════════════');
    _log('TEST SUMMARY');
    _log('═══════════════════════════════════════');
    _log('Step 1 (Namespace Check): ${_step1Complete ? "✅ PASS" : "❌ FAIL"}');
    _log('Step 2 (Registration): ${_step2Complete ? "✅ PASS" : "❌ FAIL"}');
    _log('Step 3 (DNS Propagation): ${_step3Complete ? "✅ PASS" : "⏳ PENDING"}');
    _log('Step 4 (Verification): ${_step4Complete ? "✅ PASS" : "⏳ PENDING"}');
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
        title: const Text('Org Verification Test'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _clearLog,
            tooltip: 'Clear Log',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Progress indicator
            _buildProgressIndicator(),
            const SizedBox(height: 16),
            
            // Input fields
            _buildInputSection(),
            const SizedBox(height: 16),
            
            // Action buttons
            _buildActionButtons(),
            const SizedBox(height: 16),
            
            // Quick DNS record copy
            if (_verificationCodeController.text.isNotEmpty)
              _buildDnsInstructions(),
            
            const SizedBox(height: 16),
            
            // Results log
            _buildResultsLog(),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressIndicator() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStepIndicator(1, 'Check', _step1Complete),
          _buildStepConnector(_step1Complete),
          _buildStepIndicator(2, 'Register', _step2Complete),
          _buildStepConnector(_step2Complete),
          _buildStepIndicator(3, 'DNS', _step3Complete),
          _buildStepConnector(_step3Complete),
          _buildStepIndicator(4, 'Verify', _step4Complete),
        ],
      ),
    );
  }

  Widget _buildStepIndicator(int step, String label, bool complete) {
    return Column(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: complete ? Colors.green : Colors.grey[300],
            shape: BoxShape.circle,
          ),
          child: Center(
            child: complete
                ? const Icon(Icons.check, color: Colors.white, size: 18)
                : Text(
                    '$step',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: complete ? Colors.green : Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildStepConnector(bool active) {
    return Container(
      width: 24,
      height: 2,
      color: active ? Colors.green : Colors.grey[300],
    );
  }

  Widget _buildInputSection() {
    return Column(
      children: [
        TextField(
          controller: _namespaceController,
          decoration: InputDecoration(
            labelText: 'Namespace',
            hintText: 'e.g., acmecorp',
            suffixText: '@',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _domainController,
          decoration: InputDecoration(
            labelText: 'Domain',
            hintText: 'e.g., acmecorp.com',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _verificationCodeController,
          decoration: InputDecoration(
            labelText: 'Verification Code (auto-filled)',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            suffixIcon: IconButton(
              icon: const Icon(Icons.copy),
              onPressed: () => _copyToClipboard(_verificationCodeController.text),
            ),
          ),
          readOnly: true,
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        // Full test button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _loading ? null : _runFullTest,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Run Full Test'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
        const SizedBox(height: 12),
        
        // Individual step buttons
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _loading ? null : _checkNamespace,
                child: const Text('1. Check'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: _loading ? null : _registerOrganization,
                child: const Text('2. Register'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: _loading ? null : _checkDnsPropagation,
                child: const Text('3. DNS'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: _loading ? null : _verifyWithBackend,
                child: const Text('4. Verify'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDnsInstructions() {
    final domain = _domainController.text.trim();
    final code = _verificationCodeController.text;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.dns, color: Colors.blue[700]),
              const SizedBox(width: 8),
              Text(
                'DNS TXT Record',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue[700],
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _copyToClipboard('gns-verify=$code'),
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copy'),
              ),
            ],
          ),
          const Divider(),
          _buildDnsRow('Host', '_gns.$domain'),
          _buildDnsRow('Type', 'TXT'),
          _buildDnsRow('Value', 'gns-verify=$code'),
          _buildDnsRow('TTL', '3600'),
        ],
      ),
    );
  }

  Widget _buildDnsRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsLog() {
    return Container(
      constraints: const BoxConstraints(minHeight: 200),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.terminal, color: Colors.green, size: 16),
              const SizedBox(width: 8),
              const Text(
                'Test Log',
                style: TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              if (_loading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Colors.green),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            _result ?? 'Press "Run Full Test" to begin...',
            style: const TextStyle(
              color: Colors.white,
              fontFamily: 'monospace',
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
