/// Pay by Handle Screen - Phase 5
/// 
/// Send payments to any GNS @handle.
/// Resolves handle → public key → Stellar address.
/// 
/// Location: lib/ui/screens/pay_by_handle_screen.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

/// Payment screen for sending crypto by @handle
class PayByHandleScreen extends StatefulWidget {
  final String? initialHandle;  // Pre-filled handle (from deep link)
  
  const PayByHandleScreen({super.key, this.initialHandle});

  @override
  State<PayByHandleScreen> createState() => _PayByHandleScreenState();
}

class _PayByHandleScreenState extends State<PayByHandleScreen> {
  final _handleController = TextEditingController();
  final _amountController = TextEditingController();
  final _memoController = TextEditingController();
  
  String _selectedCurrency = 'XLM';
  bool _loading = false;
  bool _resolving = false;
  String? _resolvedName;
  String? _resolvedPublicKey;
  String? _error;
  
  static const _apiBase = 'https://gns-browser-production.up.railway.app';
  
  final _currencies = [
    {'code': 'XLM', 'name': 'Stellar Lumens', 'icon': '✨'},
    {'code': 'GNS', 'name': 'GNS Token', 'icon': '🌐'},
    {'code': 'USDC', 'name': 'USD Coin', 'icon': '💵'},
  ];

  @override
  void initState() {
    super.initState();
    if (widget.initialHandle != null) {
      _handleController.text = widget.initialHandle!;
      _resolveHandle(widget.initialHandle!);
    }
  }

  @override
  void dispose() {
    _handleController.dispose();
    _amountController.dispose();
    _memoController.dispose();
    super.dispose();
  }

  /// Resolve @handle to public key
  Future<void> _resolveHandle(String handle) async {
    if (handle.isEmpty) {
      setState(() {
        _resolvedName = null;
        _resolvedPublicKey = null;
        _error = null;
      });
      return;
    }
    
    // Clean handle
    String cleanHandle = handle.trim();
    if (cleanHandle.startsWith('@')) {
      cleanHandle = cleanHandle.substring(1);
    }
    
    setState(() {
      _resolving = true;
      _error = null;
    });
    
    try {
      // First try gSite endpoint for full profile
      final gsiteResponse = await http.get(
        Uri.parse('$_apiBase/gsite/@$cleanHandle'),
      ).timeout(const Duration(seconds: 10));
      
      if (gsiteResponse.statusCode == 200) {
        final data = jsonDecode(gsiteResponse.body);
        if (data['success'] == true && data['data'] != null) {
          setState(() {
            _resolvedName = data['data']['name'] ?? '@$cleanHandle';
            _resolvedPublicKey = data['data']['publicKey'];
            _resolving = false;
          });
          return;
        }
      }
      
      // Fallback to handles endpoint
      final handleResponse = await http.get(
        Uri.parse('$_apiBase/handles/$cleanHandle'),
      ).timeout(const Duration(seconds: 10));
      
      if (handleResponse.statusCode == 200) {
        final data = jsonDecode(handleResponse.body);
        if (data['success'] == true && data['data'] != null) {
          setState(() {
            _resolvedName = '@$cleanHandle';
            _resolvedPublicKey = data['data']['public_key'];
            _resolving = false;
          });
          return;
        }
      }
      
      setState(() {
        _error = 'Handle not found';
        _resolvedName = null;
        _resolvedPublicKey = null;
        _resolving = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to resolve handle';
        _resolving = false;
      });
    }
  }

  /// Send payment
  Future<void> _sendPayment() async {
    if (_resolvedPublicKey == null) {
      _showError('Please enter a valid @handle');
      return;
    }
    
    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      _showError('Please enter a valid amount');
      return;
    }
    
    setState(() => _loading = true);
    
    try {
      // TODO: Integrate with actual wallet and Stellar SDK
      // For now, show confirmation dialog
      
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Confirm Payment'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildConfirmRow('To:', _resolvedName ?? _handleController.text),
              _buildConfirmRow('Amount:', '${_amountController.text} $_selectedCurrency'),
              if (_memoController.text.isNotEmpty)
                _buildConfirmRow('Memo:', _memoController.text),
              const SizedBox(height: 16),
              Text(
                'Public Key:\n${_resolvedPublicKey!.substring(0, 16)}...',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('CANCEL'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
              ),
              child: const Text('CONFIRM'),
            ),
          ],
        ),
      );
      
      if (confirmed == true) {
        // TODO: Execute Stellar transaction
        await Future.delayed(const Duration(seconds: 2)); // Simulate
        
        if (mounted) {
          _showSuccess(
            'Payment Sent!',
            '${_amountController.text} $_selectedCurrency sent to ${_resolvedName}',
          );
          // Clear form
          _handleController.clear();
          _amountController.clear();
          _memoController.clear();
          setState(() {
            _resolvedName = null;
            _resolvedPublicKey = null;
          });
        }
      }
    } catch (e) {
      _showError('Payment failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _buildConfirmRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _showSuccess(String title, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Text('✅', style: TextStyle(fontSize: 48)),
        title: Text(title),
        content: Text(message),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pay by @handle'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF10B981), Color(0xFF059669)],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Column(
                children: [
                  Text('💳', style: TextStyle(fontSize: 48)),
                  SizedBox(height: 8),
                  Text(
                    'Send Payment',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Pay anyone with their @handle',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Recipient Handle
            const Text(
              'RECIPIENT',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _handleController,
              decoration: InputDecoration(
                hintText: '@handle',
                prefixIcon: const Icon(Icons.alternate_email),
                suffixIcon: _resolving 
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : _resolvedPublicKey != null
                        ? const Icon(Icons.check_circle, color: Colors.green)
                        : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.grey[50],
              ),
              onChanged: (value) {
                // Debounce handle resolution
                Future.delayed(const Duration(milliseconds: 500), () {
                  if (_handleController.text == value) {
                    _resolveHandle(value);
                  }
                });
              },
            ),
            
            // Resolved recipient info
            if (_resolvedName != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green[200]!),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.person, color: Colors.green),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _resolvedName!,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            
            if (_error != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red[700]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(color: Colors.red[700]),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            
            const SizedBox(height: 24),
            
            // Amount
            const Text(
              'AMOUNT',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _amountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                    ],
                    decoration: InputDecoration(
                      hintText: '0.00',
                      prefixIcon: const Icon(Icons.attach_money),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.grey[50],
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedCurrency,
                        isExpanded: true,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        items: _currencies.map((c) => DropdownMenuItem(
                          value: c['code'] as String,
                          child: Row(
                            children: [
                              Text(c['icon'] as String),
                              const SizedBox(width: 4),
                              Text(c['code'] as String),
                            ],
                          ),
                        )).toList(),
                        onChanged: (v) => setState(() => _selectedCurrency = v!),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            
            // Quick amounts
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: ['5', '10', '25', '50', '100'].map((amount) {
                return ActionChip(
                  label: Text('\$$amount'),
                  onPressed: () => _amountController.text = amount,
                );
              }).toList(),
            ),
            
            const SizedBox(height: 24),
            
            // Memo
            const Text(
              'MEMO (OPTIONAL)',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _memoController,
              maxLength: 28,  // Stellar memo limit
              decoration: InputDecoration(
                hintText: 'What\'s this for?',
                prefixIcon: const Icon(Icons.note),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.grey[50],
              ),
            ),
            
            const SizedBox(height: 32),
            
            // Send Button
            ElevatedButton(
              onPressed: _loading || _resolvedPublicKey == null 
                  ? null 
                  : _sendPayment,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                disabledBackgroundColor: Colors.grey[300],
              ),
              child: _loading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.send),
                        SizedBox(width: 8),
                        Text(
                          'SEND PAYMENT',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
            ),
            
            const SizedBox(height: 16),
            
            // Info
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue[700]),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Payments are instant and final. Your GNS identity key is also your Stellar wallet.',
                      style: TextStyle(
                        color: Colors.blue[700],
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
