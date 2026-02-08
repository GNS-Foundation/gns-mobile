/// Merchant Terminal Screen - Sprint 3
/// 
/// POS terminal simulator for testing NFC payments.
/// Allows creating payment requests and receiving customer responses.
/// 
/// Features:
/// - Create payment challenges with custom amounts
/// - Display QR code fallback for non-NFC devices
/// - Receive and verify customer NFC responses
/// - Transaction history logging
/// 
/// Location: lib/ui/merchant/merchant_terminal_screen.dart

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:nfc_manager/nfc_manager.dart';
import '../../core/nfc/nfc_protocol.dart' as protocol;
import '../../core/nfc/nfc_service.dart';
import '../../core/crypto/secure_storage.dart';
import '../../core/privacy/h3_quantizer.dart';
import '../../core/theme/theme_service.dart';

/// Merchant terminal for accepting NFC payments
class MerchantTerminalScreen extends StatefulWidget {
  const MerchantTerminalScreen({super.key});

  @override
  State<MerchantTerminalScreen> createState() => _MerchantTerminalScreenState();
}

class _MerchantTerminalScreenState extends State<MerchantTerminalScreen> {
  final _amountController = TextEditingController(text: '10.00');
  final _memoController = TextEditingController();
  final _crypto = protocol.NfcCryptoService();
  final _storage = SecureStorageService();
  final _nonceTracker = protocol.NonceTracker();
  
  // Merchant identity
  Uint8List? _merchantPrivateKey;
  Uint8List? _merchantPublicKey;
  String? _merchantHandle;
  
  // Terminal state
  _TerminalState _state = _TerminalState.idle;
  String _currency = 'EUR';
  protocol.NfcChallenge? _currentChallenge;
  String? _currentH3Cell;
  
  // Transaction log
  final List<_Transaction> _transactions = [];
  
  // NFC
  bool _nfcAvailable = false;
  bool _isScanning = false;
  
  @override
  void initState() {
    super.initState();
    _initMerchant();
    _checkNfc();
  }
  
  Future<void> _initMerchant() async {
    try {
      final privateKeyHex = await _storage.readPrivateKey();
      final publicKeyHex = await _storage.readPublicKey();
      final handle = await _storage.readClaimedHandle();
      
      if (privateKeyHex != null && publicKeyHex != null) {
        setState(() {
          _merchantPrivateKey = _hexToBytes(privateKeyHex);
          _merchantPublicKey = _hexToBytes(publicKeyHex);
          _merchantHandle = handle ?? 'Merchant';
        });
      }
      
      // Get current location for geo-auth
      // In production, use Geolocator package
      _currentH3Cell = '8a1f0a1c6007fff'; // Placeholder - Rome area
      
    } catch (e) {
      debugPrint('Merchant init error: $e');
    }
  }
  
  Future<void> _checkNfc() async {
    _nfcAvailable = await NfcManager.instance.isAvailable();
    if (mounted) setState(() {});
  }
  
  Uint8List _hexToBytes(String hex) {
    final result = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < hex.length; i += 2) {
      result[i ~/ 2] = int.parse(hex.substring(i, i + 2), radix: 16);
    }
    return result;
  }
  
  int _parseAmount() {
    final text = _amountController.text.replaceAll(',', '.');
    final amount = double.tryParse(text) ?? 0;
    return (amount * 100).round(); // Convert to minor units (cents)
  }
  
  void _createChallenge() {
    if (_merchantPublicKey == null) {
      _showError('Merchant identity not loaded');
      return;
    }
    
    final amountMinorUnits = _parseAmount();
    if (amountMinorUnits <= 0) {
      _showError('Please enter a valid amount');
      return;
    }
    
    HapticFeedback.mediumImpact();
    
    final challenge = _crypto.createChallenge(
      merchantPublicKey: _merchantPublicKey!,
      amountMinorUnits: amountMinorUnits,
      currency: _currency,
      h3Cell: _currentH3Cell ?? '8a1f0a1c6007fff',
      memo: _memoController.text.isEmpty ? null : _memoController.text,
    );
    
    setState(() {
      _currentChallenge = challenge;
      _state = _TerminalState.waitingForPayment;
    });
    
    // Start NFC scan for response
    _startNfcScan();
  }
  
  Future<void> _startNfcScan() async {
    if (!_nfcAvailable) return;
    
    setState(() => _isScanning = true);
    
    try {
      await NfcManager.instance.startSession(
        alertMessage: 'Waiting for customer payment...',
        onDiscovered: _onNfcDiscovered,
      );
    } catch (e) {
      debugPrint('NFC scan error: $e');
    }
  }
  
  Future<void> _stopNfcScan() async {
    try {
      await NfcManager.instance.stopSession();
    } catch (e) {
      // Ignore
    }
    if (mounted) setState(() => _isScanning = false);
  }
  
  Future<void> _onNfcDiscovered(NfcTag tag) async {
    try {
      final ndef = Ndef.from(tag);
      if (ndef == null) return;
      
      final message = await ndef.read();
      if (message == null || message.records.isEmpty) return;
      
      // Look for GNS response
      for (final record in message.records) {
        if (record.typeNameFormat == NdefTypeNameFormat.media) {
          final typeStr = utf8.decode(record.type);
          if (typeStr == protocol.kNdefTypeGnsResponse) {
            await _processPaymentResponse(record.payload);
            return;
          }
        }
      }
      
      _showError('Invalid payment response');
      
    } catch (e) {
      _showError('Error reading NFC: $e');
    }
  }
  
  Future<void> _processPaymentResponse(Uint8List payload) async {
    if (_currentChallenge == null || _merchantPrivateKey == null) return;
    
    setState(() => _state = _TerminalState.verifying);
    
    try {
      final jsonStr = utf8.decode(payload);
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      final response = protocol.NfcResponse.fromJson(json);
      
      // Verify the response
      final verified = await _crypto.verifyChallengeResponse(
        challenge: _currentChallenge!,
        response: response,
        nonceTracker: _nonceTracker,
      );
      
      if (verified) {
        HapticFeedback.heavyImpact();
        
        // Log transaction
        final tx = _Transaction(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          amount: _currentChallenge!.amountMinorUnits / 100,
          currency: _currentChallenge!.currency,
          customerPublicKey: base64Encode(response.userPublicKey),
          timestamp: DateTime.now(),
          status: 'complete',
        );
        
        setState(() {
          _transactions.insert(0, tx);
          _state = _TerminalState.success;
        });
        
        // Auto-reset after 3 seconds
        Future.delayed(const Duration(seconds: 3), _reset);
        
      } else {
        setState(() => _state = _TerminalState.failed);
        _showError('Payment verification failed');
      }
      
    } catch (e) {
      setState(() => _state = _TerminalState.failed);
      _showError('Invalid response format: $e');
    }
    
    await _stopNfcScan();
  }
  
  void _reset() {
    _stopNfcScan();
    setState(() {
      _state = _TerminalState.idle;
      _currentChallenge = null;
    });
  }
  
  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red[600],
      ),
    );
  }
  
  String _formatAmount(int minorUnits, String currency) {
    final symbols = {'EUR': '€', 'USD': '\$', 'GBP': '£'};
    final symbol = symbols[currency] ?? currency;
    return '$symbol${(minorUnits / 100).toStringAsFixed(2)}';
  }

  @override
  void dispose() {
    _amountController.dispose();
    _memoController.dispose();
    _stopNfcScan();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Merchant Terminal'),
        actions: [
          if (_transactions.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.receipt_long),
              onPressed: _showTransactionLog,
              tooltip: 'Transaction Log',
            ),
        ],
      ),
      body: _merchantPublicKey == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Merchant info
                  _buildMerchantCard(),
                  const SizedBox(height: 16),
                  
                  // Terminal display
                  _buildTerminalDisplay(),
                  const SizedBox(height: 16),
                  
                  // Amount input (only in idle state)
                  if (_state == _TerminalState.idle) ...[
                    _buildAmountInput(),
                    const SizedBox(height: 16),
                    _buildChargeButton(),
                  ],
                  
                  // Waiting/QR display
                  if (_state == _TerminalState.waitingForPayment)
                    _buildWaitingDisplay(),
                  
                  // Verifying
                  if (_state == _TerminalState.verifying)
                    _buildVerifyingDisplay(),
                  
                  // Success
                  if (_state == _TerminalState.success)
                    _buildSuccessDisplay(),
                  
                  // Failed
                  if (_state == _TerminalState.failed)
                    _buildFailedDisplay(),
                ],
              ),
            ),
    );
  }
  
  Widget _buildMerchantCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border(context)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.green[100],
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(Icons.store, color: Colors.green[700]),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _merchantHandle ?? 'Merchant',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Row(
                  children: [
                    Icon(
                      _nfcAvailable ? Icons.contactless : Icons.contactless_outlined,
                      size: 14,
                      color: _nfcAvailable ? Colors.green : Colors.grey,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _nfcAvailable ? 'NFC Ready' : 'NFC Unavailable',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildTerminalDisplay() {
    return Container(
      height: 120,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.grey[900]!,
            Colors.grey[800]!,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: _state == _TerminalState.idle
            ? Text(
                _formatAmount(_parseAmount(), _currency),
                style: const TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              )
            : _currentChallenge != null
                ? Text(
                    _formatAmount(
                      _currentChallenge!.amountMinorUnits,
                      _currentChallenge!.currency,
                    ),
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                    ),
                  )
                : const Text(
                    '---',
                    style: TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 48,
                    ),
                  ),
      ),
    );
  }
  
  Widget _buildAmountInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Amount field
        TextField(
          controller: _amountController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            labelText: 'Amount',
            prefixText: _currency == 'EUR' ? '€ ' : '\$ ',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        
        // Currency selector
        Row(
          children: ['EUR', 'USD', 'GBP'].map((c) {
            final selected = _currency == c;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(c),
                selected: selected,
                onSelected: (_) => setState(() => _currency = c),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        
        // Memo field
        TextField(
          controller: _memoController,
          decoration: InputDecoration(
            labelText: 'Memo (optional)',
            hintText: 'e.g., Coffee order #42',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }
  
  Widget _buildChargeButton() {
    return ElevatedButton(
      onPressed: _createChallenge,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.green[600],
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.contactless, size: 28),
          SizedBox(width: 12),
          Text(
            'CHARGE',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildWaitingDisplay() {
    return Column(
      children: [
        const SizedBox(height: 16),
        
        // NFC animation
        Container(
          width: 200,
          height: 200,
          decoration: BoxDecoration(
            color: Colors.green[50],
            shape: BoxShape.circle,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Pulse animation
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.8, end: 1.2),
                duration: const Duration(milliseconds: 1000),
                builder: (context, value, child) {
                  return Transform.scale(
                    scale: value,
                    child: Container(
                      width: 150,
                      height: 150,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.green.withOpacity(0.3),
                          width: 3,
                        ),
                      ),
                    ),
                  );
                },
              ),
              Icon(
                Icons.contactless,
                size: 80,
                color: Colors.green[600],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        
        const Text(
          'Waiting for Payment',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Customer should tap their phone here',
          style: TextStyle(color: Colors.grey[600]),
        ),
        const SizedBox(height: 24),
        
        // QR Code fallback
        ExpansionTile(
          title: const Text('Show QR Code (fallback)'),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: _currentChallenge != null
                  ? QrImageView(
                      data: jsonEncode(_currentChallenge!.toJson()),
                      size: 200,
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
        const SizedBox(height: 24),
        
        // Cancel button
        OutlinedButton(
          onPressed: _reset,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
          ),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
  
  Widget _buildVerifyingDisplay() {
    return Column(
      children: [
        const SizedBox(height: 48),
        const CircularProgressIndicator(),
        const SizedBox(height: 24),
        const Text(
          'Verifying Payment...',
          style: TextStyle(fontSize: 18),
        ),
      ],
    );
  }
  
  Widget _buildSuccessDisplay() {
    return Column(
      children: [
        const SizedBox(height: 24),
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            color: Colors.green[100],
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.check,
            size: 64,
            color: Colors.green[700],
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Payment Complete!',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.green[700],
          ),
        ),
        const SizedBox(height: 8),
        if (_currentChallenge != null)
          Text(
            _formatAmount(
              _currentChallenge!.amountMinorUnits,
              _currentChallenge!.currency,
            ),
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
        const SizedBox(height: 32),
        ElevatedButton(
          onPressed: _reset,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green[600],
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 48),
          ),
          child: const Text('New Transaction'),
        ),
      ],
    );
  }
  
  Widget _buildFailedDisplay() {
    return Column(
      children: [
        const SizedBox(height: 24),
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            color: Colors.red[100],
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.close,
            size: 64,
            color: Colors.red[700],
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Payment Failed',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.red[700],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Verification failed. Please try again.',
          style: TextStyle(color: Colors.grey[600]),
        ),
        const SizedBox(height: 32),
        ElevatedButton(
          onPressed: _reset,
          child: const Text('Try Again'),
        ),
      ],
    );
  }
  
  void _showTransactionLog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return Container(
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Text(
                        'Transaction Log',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${_transactions.length} transactions',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: _transactions.length,
                    itemBuilder: (context, index) {
                      final tx = _transactions[index];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.green[100],
                          child: Icon(Icons.check, color: Colors.green[700]),
                        ),
                        title: Text(
                          _formatAmount((tx.amount * 100).round(), tx.currency),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          '${tx.timestamp.hour}:${tx.timestamp.minute.toString().padLeft(2, '0')}',
                        ),
                        trailing: Text(
                          tx.customerPublicKey.substring(0, 8) + '...',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontFamily: 'monospace',
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// =============================================================================
// SUPPORTING TYPES
// =============================================================================

enum _TerminalState {
  idle,
  waitingForPayment,
  verifying,
  success,
  failed,
}

class _Transaction {
  final String id;
  final double amount;
  final String currency;
  final String customerPublicKey;
  final DateTime timestamp;
  final String status;
  
  _Transaction({
    required this.id,
    required this.amount,
    required this.currency,
    required this.customerPublicKey,
    required this.timestamp,
    required this.status,
  });
}
