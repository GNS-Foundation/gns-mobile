/// GNS NFC Payment UI - Payment Confirmation Widget
/// 
/// Sprint 2: User interface for NFC tap-to-pay
/// 
/// Features:
/// - Payment confirmation bottom sheet
/// - Amount display with currency
/// - Merchant info display
/// - Approve/Cancel actions
/// - State feedback (scanning, processing, complete)
/// 
/// Location: lib/ui/nfc/nfc_payment_sheet.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/nfc/nfc_service.dart';

// =============================================================================
// NFC PAYMENT SHEET
// =============================================================================

/// Bottom sheet for NFC payment confirmation
class NfcPaymentSheet extends StatefulWidget {
  final NfcService nfcService;
  final VoidCallback? onComplete;
  final VoidCallback? onCancel;
  
  const NfcPaymentSheet({
    super.key,
    required this.nfcService,
    this.onComplete,
    this.onCancel,
  });
  
  /// Show the payment sheet
  static Future<bool?> show(
    BuildContext context, {
    required NfcService nfcService,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => NfcPaymentSheet(
        nfcService: nfcService,
        onComplete: () => Navigator.of(context).pop(true),
        onCancel: () => Navigator.of(context).pop(false),
      ),
    );
  }
  
  @override
  State<NfcPaymentSheet> createState() => _NfcPaymentSheetState();
}

class _NfcPaymentSheetState extends State<NfcPaymentSheet> 
    with SingleTickerProviderStateMixin {
  
  StreamSubscription<NfcEvent>? _subscription;
  late AnimationController _pulseController;
  
  NfcSessionState _state = NfcSessionState.idle;
  NfcPaymentRequestEvent? _paymentRequest;
  String? _errorMessage;
  bool _isProcessing = false;
  
  @override
  void initState() {
    super.initState();
    
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    
    _subscription = widget.nfcService.events.listen(_handleEvent);
    _startScan();
  }
  
  @override
  void dispose() {
    _pulseController.dispose();
    _subscription?.cancel();
    super.dispose();
  }
  
  void _startScan() {
    widget.nfcService.startPaymentScan();
    setState(() {
      _state = NfcSessionState.scanning;
    });
  }
  
  void _handleEvent(NfcEvent event) {
    if (event is NfcPaymentRequestEvent) {
      HapticFeedback.mediumImpact();
      setState(() {
        _paymentRequest = event;
        _state = NfcSessionState.awaitingConfirmation;
      });
    } else if (event is NfcPaymentCompleteEvent) {
      HapticFeedback.heavyImpact();
      setState(() {
        _state = NfcSessionState.complete;
      });
      Future.delayed(const Duration(seconds: 2), () {
        widget.onComplete?.call();
      });
    } else if (event is NfcErrorEvent) {
      setState(() {
        _state = NfcSessionState.error;
        _errorMessage = event.message;
        _isProcessing = false;
      });
    } else if (event is NfcStateChangeEvent) {
      setState(() {
        _state = event.newState;
      });
    }
  }
  
  Future<void> _approvePayment() async {
    setState(() {
      _isProcessing = true;
    });
    
    final success = await widget.nfcService.approvePayment();
    
    if (!success && mounted) {
      setState(() {
        _isProcessing = false;
      });
    }
  }
  
  void _cancelPayment() {
    widget.nfcService.cancelPayment();
    widget.onCancel?.call();
  }
  
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),
              
              // Content based on state
              _buildContent(),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildContent() {
    switch (_state) {
      case NfcSessionState.scanning:
        return _buildScanningState();
      case NfcSessionState.awaitingConfirmation:
        return _buildConfirmationState();
      case NfcSessionState.signing:
      case NfcSessionState.transmitting:
        return _buildProcessingState();
      case NfcSessionState.complete:
        return _buildCompleteState();
      case NfcSessionState.error:
        return _buildErrorState();
      default:
        return _buildScanningState();
    }
  }
  
  Widget _buildScanningState() {
    return Column(
      children: [
        // Animated NFC icon
        AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            return Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.blue.withOpacity(0.1 + _pulseController.value * 0.1),
              ),
              child: Icon(
                Icons.contactless,
                size: 64,
                color: Colors.blue.withOpacity(0.5 + _pulseController.value * 0.5),
              ),
            );
          },
        ),
        const SizedBox(height: 24),
        
        Text(
          'Ready to Pay',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        
        Text(
          'Hold your phone near the payment terminal',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Colors.grey[600],
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        
        // Cancel button
        TextButton(
          onPressed: _cancelPayment,
          child: const Text('Cancel'),
        ),
      ],
    );
  }
  
  Widget _buildConfirmationState() {
    final request = _paymentRequest!;
    
    return Column(
      children: [
        // Merchant icon
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.green[50],
          ),
          child: Icon(
            Icons.store,
            size: 40,
            color: Colors.green[700],
          ),
        ),
        const SizedBox(height: 16),
        
        // Merchant name
        Text(
          request.merchantName,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        
        // Amount
        Text(
          request.amountDisplay,
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: Colors.green[700],
          ),
        ),
        const SizedBox(height: 8),
        
        // Memo if present
        if (request.challenge.memo != null) ...[
          Text(
            request.challenge.memo!,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 16),
        ],
        
        // Location badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.blue[50],
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.location_on, size: 16, color: Colors.blue[700]),
              const SizedBox(width: 4),
              Text(
                'Location verified',
                style: TextStyle(
                  color: Colors.blue[700],
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        
        // Action buttons
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _isProcessing ? null : _cancelPayment,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: _isProcessing ? null : _approvePayment,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[600],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isProcessing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(Colors.white),
                        ),
                      )
                    : const Text('Pay Now'),
              ),
            ),
          ],
        ),
      ],
    );
  }
  
  Widget _buildProcessingState() {
    return Column(
      children: [
        const SizedBox(
          width: 80,
          height: 80,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
        const SizedBox(height: 24),
        
        Text(
          _state == NfcSessionState.signing ? 'Signing...' : 'Sending...',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        
        Text(
          'Keep your phone near the terminal',
          style: TextStyle(color: Colors.grey[600]),
        ),
        const SizedBox(height: 32),
      ],
    );
  }
  
  Widget _buildCompleteState() {
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.green[100],
          ),
          child: Icon(
            Icons.check,
            size: 48,
            color: Colors.green[700],
          ),
        ),
        const SizedBox(height: 24),
        
        Text(
          'Payment Complete',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: Colors.green[700],
          ),
        ),
        const SizedBox(height: 8),
        
        if (_paymentRequest != null)
          Text(
            _paymentRequest!.amountDisplay,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Colors.grey[600],
            ),
          ),
        const SizedBox(height: 32),
      ],
    );
  }
  
  Widget _buildErrorState() {
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.red[50],
          ),
          child: Icon(
            Icons.error_outline,
            size: 48,
            color: Colors.red[700],
          ),
        ),
        const SizedBox(height: 24),
        
        Text(
          'Payment Failed',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: Colors.red[700],
          ),
        ),
        const SizedBox(height: 8),
        
        Text(
          _errorMessage ?? 'Unknown error',
          style: TextStyle(color: Colors.grey[600]),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _cancelPayment,
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: ElevatedButton(
                onPressed: () {
                  setState(() {
                    _errorMessage = null;
                  });
                  _startScan();
                },
                child: const Text('Try Again'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// =============================================================================
// NFC TAP BUTTON
// =============================================================================

/// Floating action button for initiating NFC payment
class NfcTapButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool isScanning;
  
  const NfcTapButton({
    super.key,
    required this.onTap,
    this.isScanning = false,
  });
  
  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      onPressed: onTap,
      backgroundColor: isScanning ? Colors.orange : Colors.green[600],
      icon: Icon(
        isScanning ? Icons.contactless : Icons.payment,
        color: Colors.white,
      ),
      label: Text(
        isScanning ? 'Scanning...' : 'Tap to Pay',
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
      ),
    );
  }
}

// =============================================================================
// NFC STATUS INDICATOR
// =============================================================================

/// Small indicator showing NFC availability status
class NfcStatusIndicator extends StatelessWidget {
  final bool isAvailable;
  final bool isEnabled;
  
  const NfcStatusIndicator({
    super.key,
    required this.isAvailable,
    required this.isEnabled,
  });
  
  @override
  Widget build(BuildContext context) {
    final Color color;
    final IconData icon;
    final String label;
    
    if (!isAvailable) {
      color = Colors.grey;
      icon = Icons.contactless_outlined;
      label = 'NFC not available';
    } else if (!isEnabled) {
      color = Colors.orange;
      icon = Icons.contactless_outlined;
      label = 'NFC disabled';
    } else {
      color = Colors.green;
      icon = Icons.contactless;
      label = 'NFC ready';
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// ANIMATED BUILDER (Helper for pulsing animation)
// =============================================================================

/// Simple animation builder widget
class AnimatedBuilder extends StatelessWidget {
  final Animation<double> animation;
  final Widget Function(BuildContext context, Widget? child) builder;
  final Widget? child;
  
  const AnimatedBuilder({
    super.key,
    required this.animation,
    required this.builder,
    this.child,
  });
  
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder2(
      animation: animation,
      builder: builder,
      child: child,
    );
  }
}

class AnimatedBuilder2 extends AnimatedWidget {
  final Widget Function(BuildContext context, Widget? child) builder;
  final Widget? child;
  
  const AnimatedBuilder2({
    super.key,
    required Animation<double> animation,
    required this.builder,
    this.child,
  }) : super(listenable: animation);
  
  @override
  Widget build(BuildContext context) {
    return builder(context, child);
  }
}
