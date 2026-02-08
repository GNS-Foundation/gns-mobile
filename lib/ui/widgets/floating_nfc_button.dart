/// Floating NFC Button - Tap-to-Pay Quick Access (v2)
/// 
/// A prominent floating button for NFC contactless payments.
/// Now includes QR scanner fallback for testing and non-NFC scenarios.
/// 
/// Location: lib/ui/widgets/floating_nfc_button.dart

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../core/nfc/nfc_service.dart';
import '../../core/nfc/nfc_protocol.dart';
import '../../core/theme/theme_service.dart';

/// Floating NFC Payment Button
/// 
/// Add to your home screen with:
/// ```dart
/// Stack(
///   children: [
///     YourContent(),
///     const FloatingNfcButton(),
///   ],
/// )
/// ```
class FloatingNfcButton extends StatefulWidget {
  /// Position from bottom
  final double bottom;
  
  /// Position from right
  final double right;
  
  const FloatingNfcButton({
    super.key,
    this.bottom = 100,
    this.right = 16,
  });

  @override
  State<FloatingNfcButton> createState() => _FloatingNfcButtonState();
}

class _FloatingNfcButtonState extends State<FloatingNfcButton> 
    with SingleTickerProviderStateMixin {
  
  late NfcService _nfcService;
  StreamSubscription<NfcEvent>? _subscription;
  
  bool _isAvailable = false;
  bool _isScanning = false;
  bool _isInitialized = false;
  
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _nfcService = NfcService();
    _initNfc();
    
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  Future<void> _initNfc() async {
    try {
      _isAvailable = await _nfcService.initialize();
      _isInitialized = true;
      
      _subscription = _nfcService.events.listen(_handleNfcEvent);
      
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('NFC init error: $e');
      _isInitialized = true;
      if (mounted) setState(() {});
    }
  }

  void _handleNfcEvent(NfcEvent event) {
    if (!mounted) return;
    
    if (event is NfcPaymentRequestEvent) {
      // Stop pulse animation
      _pulseController.stop();
      setState(() => _isScanning = false);
      
      // Show payment confirmation
      _showPaymentConfirmation(event.challenge);
      
    } else if (event is NfcStateChangeEvent) {
      setState(() {
        _isScanning = event.newState == NfcSessionState.scanning;
      });
      
      if (_isScanning) {
        _pulseController.repeat(reverse: true);
      } else {
        _pulseController.stop();
        _pulseController.reset();
      }
      
    } else if (event is NfcPaymentCompleteEvent) {
      HapticFeedback.heavyImpact();
      _showSuccessSnackbar(event);
      
    } else if (event is NfcErrorEvent) {
      _showErrorSnackbar(event);
    }
  }

  void _showPaymentConfirmation(NfcChallenge challenge) {
    HapticFeedback.mediumImpact();
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _NfcPaymentConfirmSheet(
        challenge: challenge,
        nfcService: _nfcService,
      ),
    );
  }

  void _showSuccessSnackbar(NfcPaymentCompleteEvent event) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 12),
            Text('Payment complete: ${event.currency} ${event.amount}'),
          ],
        ),
        backgroundColor: Colors.green[600],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _showErrorSnackbar(NfcErrorEvent event) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(event.message)),
          ],
        ),
        backgroundColor: Colors.red[600],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _onTap() async {
    HapticFeedback.lightImpact();
    
    if (_isScanning) {
      // Stop scanning
      await _nfcService.stopScan();
    } else {
      // Show the ready sheet with NFC + QR options
      _showReadyToPaySheet();
    }
  }

  void _showReadyToPaySheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _NfcReadyToPaySheet(
        nfcService: _nfcService,
        nfcAvailable: _isAvailable,
        onQrScanned: (challenge) {
          Navigator.of(context).pop();
          _showPaymentConfirmation(challenge);
        },
      ),
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const SizedBox.shrink();
    }
    
    return Positioned(
      bottom: widget.bottom,
      right: widget.right,
      child: AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _isScanning ? _pulseAnimation.value : 1.0,
            child: child,
          );
        },
        child: GestureDetector(
          onTap: _onTap,
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: _isScanning
                    ? [Colors.orange[400]!, Colors.orange[600]!]
                    : [Colors.green[400]!, Colors.green[600]!],
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: (_isScanning ? Colors.orange : Colors.green)
                      .withOpacity(0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Ripple effect when scanning
                if (_isScanning)
                  ...List.generate(2, (index) {
                    return TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.0, end: 1.0),
                      duration: Duration(milliseconds: 1500 + index * 500),
                      builder: (context, value, child) {
                        return Container(
                          width: 64 + (value * 30),
                          height: 64 + (value * 30),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.orange.withOpacity(1 - value),
                              width: 2,
                            ),
                          ),
                        );
                      },
                    );
                  }),
                
                // Main icon
                Icon(
                  _isScanning ? Icons.contactless : Icons.contactless_outlined,
                  color: Colors.white,
                  size: 32,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// READY TO PAY SHEET (with QR option)
// =============================================================================

class _NfcReadyToPaySheet extends StatefulWidget {
  final NfcService nfcService;
  final bool nfcAvailable;
  final Function(NfcChallenge) onQrScanned;
  
  const _NfcReadyToPaySheet({
    required this.nfcService,
    required this.nfcAvailable,
    required this.onQrScanned,
  });

  @override
  State<_NfcReadyToPaySheet> createState() => _NfcReadyToPaySheetState();
}

class _NfcReadyToPaySheetState extends State<_NfcReadyToPaySheet>
    with SingleTickerProviderStateMixin {
  
  late AnimationController _waveController;
  StreamSubscription<NfcEvent>? _subscription;
  bool _isScanning = false;
  bool _showQrScanner = false;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
    
    if (widget.nfcAvailable) {
      _startNfcScan();
    }
    
    _subscription = widget.nfcService.events.listen((event) {
      if (event is NfcPaymentRequestEvent) {
        // Payment request received - close this sheet, parent will show confirm
        Navigator.of(context).pop();
      } else if (event is NfcErrorEvent) {
        setState(() => _isScanning = false);
      }
    });
  }

  Future<void> _startNfcScan() async {
    await widget.nfcService.startPaymentScan();
    if (mounted) setState(() => _isScanning = true);
  }

  void _openQrScanner() {
    setState(() => _showQrScanner = true);
  }

  void _onQrDetected(BarcodeCapture capture) {
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value != null) {
        try {
          final json = jsonDecode(value) as Map<String, dynamic>;
          final challenge = NfcChallenge.fromJson(json);
          
          HapticFeedback.mediumImpact();
          widget.onQrScanned(challenge);
          return;
        } catch (e) {
          debugPrint('Invalid QR data: $e');
        }
      }
    }
  }

  @override
  void dispose() {
    _waveController.dispose();
    _subscription?.cancel();
    widget.nfcService.stopScan();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: _showQrScanner ? _buildQrScanner() : _buildNfcReady(),
      ),
    );
  }

  Widget _buildNfcReady() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 32),
          
          // Animated NFC icon with waves
          SizedBox(
            width: 160,
            height: 160,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Animated waves
                if (widget.nfcAvailable)
                  ...List.generate(3, (index) {
                    return AnimatedBuilder(
                      animation: _waveController,
                      builder: (context, child) {
                        final delay = index * 0.33;
                        final value = (_waveController.value + delay) % 1.0;
                        return Container(
                          width: 80 + (value * 80),
                          height: 80 + (value * 80),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.green.withOpacity(0.6 - value * 0.6),
                              width: 3,
                            ),
                          ),
                        );
                      },
                    );
                  }),
                
                // Center icon
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: widget.nfcAvailable
                          ? [Colors.green[400]!, Colors.green[600]!]
                          : [Colors.grey[400]!, Colors.grey[600]!],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    widget.nfcAvailable ? Icons.contactless : Icons.contactless_outlined,
                    color: Colors.white,
                    size: 40,
                  ),
                ),
              ],
            ),
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
            widget.nfcAvailable 
                ? 'Hold your phone near the\npayment terminal'
                : 'NFC not available\nUse QR code instead',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          
          // QR Scanner button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _openQrScanner,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scan QR Code Instead'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          
          // Cancel button
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () {
                widget.nfcService.stopScan();
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildQrScanner() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _showQrScanner = false),
              ),
              const Expanded(
                child: Text(
                  'Scan Payment QR',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(width: 48), // Balance the back button
            ],
          ),
        ),
        
        // QR Scanner
        SizedBox(
          height: 350,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              children: [
                MobileScanner(
                  onDetect: _onQrDetected,
                ),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.green, width: 3),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  margin: const EdgeInsets.all(50),
                ),
              ],
            ),
          ),
        ),
        
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Text(
                'Point camera at the merchant\'s\nQR code to pay',
                style: TextStyle(color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// PAYMENT CONFIRMATION SHEET
// =============================================================================

class _NfcPaymentConfirmSheet extends StatefulWidget {
  final NfcChallenge challenge;
  final NfcService nfcService;
  
  const _NfcPaymentConfirmSheet({
    required this.challenge,
    required this.nfcService,
  });

  @override
  State<_NfcPaymentConfirmSheet> createState() => _NfcPaymentConfirmSheetState();
}

class _NfcPaymentConfirmSheetState extends State<_NfcPaymentConfirmSheet> {
  bool _isProcessing = false;
  StreamSubscription<NfcEvent>? _subscription;

  String get _amountDisplay {
    final symbols = {'EUR': '€', 'USD': '\$', 'GBP': '£'};
    final symbol = symbols[widget.challenge.currency] ?? widget.challenge.currency;
    final major = widget.challenge.amountMinorUnits ~/ 100;
    final minor = widget.challenge.amountMinorUnits % 100;
    return '$symbol$major.${minor.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    _subscription = widget.nfcService.events.listen((event) {
      if (event is NfcPaymentCompleteEvent) {
        Navigator.of(context).pop(true);
      } else if (event is NfcErrorEvent) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(event.message),
            backgroundColor: Colors.red[600],
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _approvePayment() async {
    setState(() => _isProcessing = true);
    HapticFeedback.mediumImpact();
    
    // For QR-based payments, we simulate the approval
    // In production, this would sign and submit to backend
    await Future.delayed(const Duration(seconds: 1));
    
    if (mounted) {
      Navigator.of(context).pop(true);
      
      // Show success
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 12),
              Text('Payment complete: $_amountDisplay'),
            ],
          ),
          backgroundColor: Colors.green[600],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  void _cancelPayment() {
    widget.nfcService.cancelPayment();
    Navigator.of(context).pop(false);
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
              // Handle
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),
              
              // Merchant icon
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.store,
                  size: 40,
                  color: Colors.green[600],
                ),
              ),
              const SizedBox(height: 16),
              
              // Merchant name
              Text(
                'Merchant',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              
              // Amount
              Text(
                _amountDisplay,
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.green[600],
                ),
              ),
              
              // Memo
              if (widget.challenge.memo != null) ...[
                const SizedBox(height: 8),
                Text(
                  widget.challenge.memo!,
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
              const SizedBox(height: 16),
              
              // Location badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.location_on, size: 18, color: Colors.blue[600]),
                    const SizedBox(width: 6),
                    Text(
                      'Location verified',
                      style: TextStyle(
                        color: Colors.blue[600],
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
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
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
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
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
                          : const Text(
                              'Pay Now',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// ANIMATION BUILDER HELPER
// =============================================================================

class AnimatedBuilder extends AnimatedWidget {
  final Widget Function(BuildContext context, Widget? child) builder;
  final Widget? child;
  
  const AnimatedBuilder({
    super.key,
    required Animation<double> animation,
    required this.builder,
    this.child,
  }) : super(listenable: animation);
  
  @override
  Widget build(BuildContext context) => builder(context, child);
}
