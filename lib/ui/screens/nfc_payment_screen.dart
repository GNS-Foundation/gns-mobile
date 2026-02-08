/// GNS NFC Payment Screen - Sprint 5
/// 
/// User interface for NFC tap-to-pay at merchant terminals.
/// Shows payment request details and confirmation.
/// 
/// Location: lib/ui/screens/nfc_payment_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/financial/nfc_merchant_service.dart';
import '../../core/financial/payment_receipt.dart';

/// NFC Payment Screen
class NfcPaymentScreen extends StatefulWidget {
  const NfcPaymentScreen({super.key});

  @override
  State<NfcPaymentScreen> createState() => _NfcPaymentScreenState();
}

class _NfcPaymentScreenState extends State<NfcPaymentScreen>
    with SingleTickerProviderStateMixin {
  final _nfcService = NfcMerchantService();
  
  StreamSubscription? _stateSubscription;
  StreamSubscription? _requestSubscription;
  StreamSubscription? _resultSubscription;
  
  NfcPaymentState _state = NfcPaymentState.idle;
  NfcPaymentRequest? _request;
  NfcPaymentResult? _result;
  
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  
  @override
  void initState() {
    super.initState();
    
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    
    _setupListeners();
    _startScanning();
  }
  
  void _setupListeners() {
    _stateSubscription = _nfcService.stateStream.listen((state) {
      setState(() => _state = state);
    });
    
    _requestSubscription = _nfcService.requestStream.listen((request) {
      setState(() => _request = request);
      HapticFeedback.mediumImpact();
    });
    
    _resultSubscription = _nfcService.resultStream.listen((result) {
      setState(() => _result = result);
      if (result.success) {
        HapticFeedback.heavyImpact();
      } else {
        HapticFeedback.vibrate();
      }
    });
  }
  
  Future<void> _startScanning() async {
    try {
      await _nfcService.startScanning();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('NFC error: $e')),
        );
      }
    }
  }
  
  Future<void> _confirmPayment() async {
    if (_request == null) return;
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => _PaymentConfirmDialog(request: _request!),
    );
    
    if (confirmed == true) {
      await _nfcService.executePayment();
    }
  }
  
  void _cancelPayment() {
    _nfcService.cancelPayment();
    Navigator.pop(context);
  }
  
  void _viewReceipt() {
    if (_result?.receipt != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ReceiptDetailScreen(receipt: _result!.receipt!),
        ),
      );
    }
  }
  
  @override
  void dispose() {
    _stateSubscription?.cancel();
    _requestSubscription?.cancel();
    _resultSubscription?.cancel();
    _pulseController.dispose();
    _nfcService.stopScanning();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E14),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Tap to Pay'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _cancelPayment,
        ),
      ),
      body: SafeArea(
        child: _buildContent(),
      ),
    );
  }
  
  Widget _buildContent() {
    switch (_state) {
      case NfcPaymentState.idle:
      case NfcPaymentState.scanning:
        return _buildScanningView();
        
      case NfcPaymentState.requestReceived:
        return _buildRequestView();
        
      case NfcPaymentState.processing:
      case NfcPaymentState.awaitingConfirmation:
        return _buildProcessingView();
        
      case NfcPaymentState.completed:
        return _buildSuccessView();
        
      case NfcPaymentState.failed:
        return _buildFailedView();
    }
  }
  
  Widget _buildScanningView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Animated NFC icon
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _pulseAnimation.value,
                child: Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFF00D9FF).withOpacity(0.3),
                        const Color(0xFF00D9FF).withOpacity(0.0),
                      ],
                    ),
                  ),
                  child: const Icon(
                    Icons.contactless,
                    size: 80,
                    color: Color(0xFF00D9FF),
                  ),
                ),
              );
            },
          ),
          
          const SizedBox(height: 40),
          
          const Text(
            'Ready to Pay',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          
          const SizedBox(height: 16),
          
          Text(
            'Hold your phone near the\npayment terminal',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: Colors.white.withOpacity(0.7),
            ),
          ),
          
          const SizedBox(height: 60),
          
          if (!_nfcService.isAvailable)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.warning_amber, color: Colors.orange),
                  SizedBox(width: 8),
                  Text(
                    'NFC not available on this device',
                    style: TextStyle(color: Colors.orange),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
  
  Widget _buildRequestView() {
    if (_request == null) return _buildScanningView();
    
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Spacer(),
          
          // Merchant info
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withOpacity(0.1),
              ),
            ),
            child: Column(
              children: [
                // Merchant icon/logo
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: const Color(0xFF00D9FF).withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.store,
                    color: Color(0xFF00D9FF),
                    size: 32,
                  ),
                ),
                
                const SizedBox(height: 16),
                
                Text(
                  _request!.merchantName,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                
                if (_request!.orderId != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Order #${_request!.orderId}',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                    ),
                  ),
                ],
                
                const SizedBox(height: 24),
                
                // Amount
                Text(
                  _request!.formattedAmount,
                  style: const TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                
                const SizedBox(height: 8),
                
                Text(
                  _request!.currency,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),
          
          const Spacer(),
          
          // Confirm button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _confirmPayment,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00D9FF),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text(
                'Confirm Payment',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Cancel button
          TextButton(
            onPressed: _cancelPayment,
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildProcessingView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 80,
            height: 80,
            child: CircularProgressIndicator(
              strokeWidth: 4,
              color: Color(0xFF00D9FF),
            ),
          ),
          
          const SizedBox(height: 32),
          
          const Text(
            'Processing Payment',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          
          const SizedBox(height: 16),
          
          Text(
            'Please wait...',
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildSuccessView() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Spacer(),
          
          // Success animation
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle,
              size: 80,
              color: Colors.green,
            ),
          ),
          
          const SizedBox(height: 32),
          
          const Text(
            'Payment Successful!',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          
          const SizedBox(height: 16),
          
          if (_request != null)
            Text(
              '${_request!.formattedAmount} to ${_request!.merchantName}',
              style: TextStyle(
                fontSize: 18,
                color: Colors.white.withOpacity(0.7),
              ),
            ),
          
          const SizedBox(height: 8),
          
          if (_result?.processingTime != null)
            Text(
              'Completed in ${_result!.processingTime!.inMilliseconds}ms',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withOpacity(0.5),
              ),
            ),
          
          const Spacer(),
          
          // Transaction hash
          if (_result?.transactionHash != null)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.tag, color: Colors.white54, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _result!.transactionHash!,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, color: Colors.white54, size: 20),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _result!.transactionHash!));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Transaction hash copied')),
                      );
                    },
                  ),
                ],
              ),
            ),
          
          const SizedBox(height: 24),
          
          // View Receipt button
          if (_result?.receipt != null)
            SizedBox(
              width: double.infinity,
              height: 56,
              child: OutlinedButton.icon(
                onPressed: _viewReceipt,
                icon: const Icon(Icons.receipt_long),
                label: const Text('View Receipt'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white30),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          
          const SizedBox(height: 16),
          
          // Done button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00D9FF),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text(
                'Done',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildFailedView() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Spacer(),
          
          // Error icon
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.error,
              size: 80,
              color: Colors.red,
            ),
          ),
          
          const SizedBox(height: 32),
          
          const Text(
            'Payment Failed',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          
          const SizedBox(height: 16),
          
          Text(
            _result?.error ?? 'An error occurred',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: Colors.white.withOpacity(0.7),
            ),
          ),
          
          const Spacer(),
          
          // Retry button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: () {
                _nfcService.reset();
                _startScanning();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00D9FF),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text(
                'Try Again',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }
}

/// Payment confirmation dialog
class _PaymentConfirmDialog extends StatelessWidget {
  final NfcPaymentRequest request;
  
  const _PaymentConfirmDialog({required this.request});
  
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1F2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text(
        'Confirm Payment',
        style: TextStyle(color: Colors.white),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            request.formattedAmount,
            style: const TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'to ${request.merchantName}',
            style: const TextStyle(color: Colors.white70),
          ),
          if (request.orderId != null) ...[
            const SizedBox(height: 4),
            Text(
              'Order #${request.orderId}',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00D9FF),
            foregroundColor: Colors.black,
          ),
          child: const Text('Pay'),
        ),
      ],
    );
  }
}

/// Receipt detail screen
class ReceiptDetailScreen extends StatelessWidget {
  final PaymentReceipt receipt;
  
  const ReceiptDetailScreen({super.key, required this.receipt});
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E14),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Receipt'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () {
              // Share receipt
              Clipboard.setData(ClipboardData(text: receipt.generateTextReceipt()));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Receipt copied to clipboard')),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Receipt card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  // GNS logo
                  Container(
                    width: 60,
                    height: 60,
                    decoration: const BoxDecoration(
                      color: Color(0xFF0A0E14),
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Text(
                        '🌐',
                        style: TextStyle(fontSize: 30),
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  const Text(
                    'PAYMENT RECEIPT',
                    style: TextStyle(
                      fontSize: 12,
                      letterSpacing: 2,
                      color: Colors.black54,
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Merchant
                  Text(
                    receipt.merchantName,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Amount
                  Text(
                    receipt.formattedAmount,
                    style: const TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Divider
                  const Divider(),
                  
                  const SizedBox(height: 16),
                  
                  // Details
                  _buildDetailRow('Date', receipt.formattedDate),
                  _buildDetailRow('Order ID', receipt.orderId ?? 'N/A'),
                  _buildDetailRow('Status', receipt.status.name.toUpperCase()),
                  
                  const SizedBox(height: 16),
                  
                  // Transaction hash
                  const Text(
                    'Transaction',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    receipt.shortTransactionHash,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Verify on Explorer button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: OutlinedButton.icon(
                onPressed: () {
                  // Open Stellar Explorer
                  // Would use url_launcher in production
                },
                icon: const Icon(Icons.open_in_new),
                label: const Text('Verify on Stellar Explorer'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF00D9FF),
                  side: const BorderSide(color: Color(0xFF00D9FF)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.black54,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w500,
              color: Colors.black,
            ),
          ),
        ],
      ),
    );
  }
}
