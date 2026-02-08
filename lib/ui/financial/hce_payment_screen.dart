/// GNS HCE Payment Screen - Sprint 6
/// 
/// UI for using phone as contactless payment card.
/// Shows virtual card and handles tap-to-pay flow.
/// 
/// Location: lib/ui/financial/hce_payment_screen.dart

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/gns/identity_wallet.dart';
import '../../core/financial/hce_payment_service.dart';
import '../../core/theme/theme_service.dart';

class HcePaymentScreen extends StatefulWidget {
  final IdentityWallet wallet;
  
  const HcePaymentScreen({super.key, required this.wallet});
  
  @override
  State<HcePaymentScreen> createState() => _HcePaymentScreenState();
}

class _HcePaymentScreenState extends State<HcePaymentScreen>
    with TickerProviderStateMixin {
  final _hceService = HcePaymentService();
  
  HceState _state = HceState.disabled;
  HcePaymentRequest? _currentRequest;
  HceSettings _settings = HceSettings();
  String? _error;
  
  late AnimationController _pulseController;
  late AnimationController _cardController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _cardAnimation;
  
  @override
  void initState() {
    super.initState();
    
    // Pulse animation for ready state
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    
    // Card flip animation
    _cardController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    
    _cardAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _cardController, curve: Curves.easeInOut),
    );
    
    _initializeHce();
  }
  
  Future<void> _initializeHce() async {
    try {
      await _hceService.initialize(
        wallet: widget.wallet,
        settings: _settings,
      );
      
      _hceService.onStateChange = (state) {
        if (mounted) setState(() => _state = state);
      };
      
      _hceService.onPaymentRequest = (request) {
        if (mounted) {
          setState(() => _currentRequest = request);
          _showPaymentConfirmation(request);
        }
      };
      
      _hceService.onPaymentComplete = (response) {
        if (mounted) {
          _showPaymentResult(response);
        }
      };
      
      _hceService.onError = (error) {
        if (mounted) setState(() => _error = error);
      };
      
      setState(() => _state = _hceService.state);
      
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }
  
  @override
  void dispose() {
    _pulseController.dispose();
    _cardController.dispose();
    _hceService.dispose();
    super.dispose();
  }
  
  void _showPaymentConfirmation(HcePaymentRequest request) {
    HapticFeedback.mediumImpact();
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      builder: (context) => _PaymentConfirmationSheet(
        request: request,
        onApprove: () {
          Navigator.pop(context);
          _hceService.approvePayment();
        },
        onDecline: () {
          Navigator.pop(context);
          _hceService.declinePayment();
        },
      ),
    );
  }
  
  void _showPaymentResult(HcePaymentResponse response) {
    HapticFeedback.heavyImpact();
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _PaymentResultDialog(
        response: response,
        onDone: () {
          Navigator.pop(context);
          setState(() => _currentRequest = null);
        },
      ),
    );
  }
  
  void _toggleHce() async {
    HapticFeedback.lightImpact();
    
    if (_hceService.isEnabled) {
      await _hceService.disable();
    } else {
      await _hceService.enable();
    }
    
    setState(() => _state = _hceService.state);
  }
  
  void _openSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _HceSettingsSheet(
        settings: _settings,
        onSave: (newSettings) {
          setState(() => _settings = newSettings);
          _hceService.updateSettings(newSettings);
          Navigator.pop(context);
        },
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background(context),
      appBar: AppBar(
        backgroundColor: AppTheme.surface(context),
        title: const Text('Tap to Pay'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _buildContent(),
            ),
            _buildBottomSection(),
          ],
        ),
      ),
    );
  }
  
  Widget _buildContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const SizedBox(height: 20),
          
          // Virtual Card
          _buildVirtualCard(),
          
          const SizedBox(height: 40),
          
          // Status
          _buildStatusSection(),
          
          const SizedBox(height: 30),
          
          // Instructions
          _buildInstructions(),
          
          if (_error != null) ...[
            const SizedBox(height: 20),
            _buildError(),
          ],
        ],
      ),
    );
  }
  
  Widget _buildVirtualCard() {
    final card = HcePaymentCard.fromWallet(widget.wallet);
    
    return AnimatedBuilder(
      animation: _state == HceState.ready ? _pulseAnimation : const AlwaysStoppedAnimation(1.0),
      builder: (context, child) {
        return Transform.scale(
          scale: _state == HceState.ready ? _pulseAnimation.value : 1.0,
          child: Container(
            width: double.infinity,
            height: 200,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: _state == HceState.ready
                    ? [AppTheme.primary, AppTheme.primary.withOpacity(0.7)]
                    : [Colors.grey.shade700, Colors.grey.shade800],
              ),
              boxShadow: [
                BoxShadow(
                  color: (_state == HceState.ready ? AppTheme.primary : Colors.grey)
                      .withOpacity(0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Stack(
              children: [
                // Background pattern
                Positioned.fill(
                  child: CustomPaint(
                    painter: _CardPatternPainter(
                      color: Colors.white.withOpacity(0.05),
                    ),
                  ),
                ),
                
                // Card content
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            '🌐 GNS',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _state == HceState.ready ? 'READY' : 'INACTIVE',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      
                      const Spacer(),
                      
                      // Contactless icon
                      Row(
                        children: [
                          Icon(
                            Icons.contactless,
                            color: Colors.white.withOpacity(0.8),
                            size: 32,
                          ),
                          const SizedBox(width: 8),
                          if (_state == HceState.ready)
                            Text(
                              'Tap to Pay',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.8),
                                fontSize: 14,
                              ),
                            ),
                        ],
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // Card number
                      Text(
                        card.maskedNumber,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontFamily: 'monospace',
                          letterSpacing: 2,
                        ),
                      ),
                      
                      const SizedBox(height: 8),
                      
                      // Card holder
                      Text(
                        card.cardHolder,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
  
  Widget _buildStatusSection() {
    IconData icon;
    String title;
    String subtitle;
    Color color;
    
    switch (_state) {
      case HceState.disabled:
        icon = Icons.credit_card_off;
        title = 'Tap to Pay Disabled';
        subtitle = 'Enable to use your phone as a payment card';
        color = Colors.grey;
        break;
      case HceState.ready:
        icon = Icons.contactless;
        title = 'Ready to Pay';
        subtitle = 'Hold your phone near a payment terminal';
        color = AppTheme.secondary;
        break;
      case HceState.waitingForTerminal:
        icon = Icons.phone_android;
        title = 'Terminal Detected';
        subtitle = 'Hold steady...';
        color = AppTheme.primary;
        break;
      case HceState.processingPayment:
        icon = Icons.sync;
        title = 'Processing Payment';
        subtitle = 'Please wait...';
        color = AppTheme.primary;
        break;
      case HceState.awaitingApproval:
        icon = Icons.touch_app;
        title = 'Approve Payment';
        subtitle = 'Confirm the payment on your screen';
        color = AppTheme.warning;
        break;
      case HceState.completed:
        icon = Icons.check_circle;
        title = 'Payment Complete';
        subtitle = 'Transaction successful';
        color = AppTheme.secondary;
        break;
      case HceState.failed:
        icon = Icons.error;
        title = 'Payment Failed';
        subtitle = _error ?? 'Please try again';
        color = AppTheme.error;
        break;
    }
    
    return Column(
      children: [
        Icon(icon, size: 48, color: color),
        const SizedBox(height: 12),
        Text(
          title,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary(context),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(
            color: AppTheme.textSecondary(context),
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
  
  Widget _buildInstructions() {
    if (_state != HceState.ready) return const SizedBox.shrink();
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How to Pay',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary(context),
            ),
          ),
          const SizedBox(height: 12),
          _buildInstructionStep(1, 'Unlock your phone'),
          _buildInstructionStep(2, 'Hold near the payment terminal'),
          _buildInstructionStep(3, 'Approve the payment amount'),
          _buildInstructionStep(4, 'Wait for confirmation'),
        ],
      ),
    );
  }
  
  Widget _buildInstructionStep(int number, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$number',
                style: TextStyle(
                  color: AppTheme.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            text,
            style: TextStyle(color: AppTheme.textSecondary(context)),
          ),
        ],
      ),
    );
  }
  
  Widget _buildError() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.error.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.error.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppTheme.error),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _error!,
              style: const TextStyle(color: AppTheme.error),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            color: AppTheme.error,
            onPressed: () => setState(() => _error = null),
          ),
        ],
      ),
    );
  }
  
  Widget _buildBottomSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        border: Border(
          top: BorderSide(color: AppTheme.divider(context)),
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Tap limit info
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 16,
                  color: AppTheme.textMuted(context),
                ),
                const SizedBox(width: 8),
                Text(
                  'Tap & Pay limit: \$${_settings.tapAndPayLimit.toStringAsFixed(0)}',
                  style: TextStyle(
                    color: AppTheme.textMuted(context),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Enable/Disable button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _toggleHce,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _hceService.isEnabled
                      ? AppTheme.error
                      : AppTheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  _hceService.isEnabled ? 'Disable Tap to Pay' : 'Enable Tap to Pay',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Payment confirmation sheet
class _PaymentConfirmationSheet extends StatelessWidget {
  final HcePaymentRequest request;
  final VoidCallback onApprove;
  final VoidCallback onDecline;
  
  const _PaymentConfirmationSheet({
    required this.request,
    required this.onApprove,
    required this.onDecline,
  });
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.divider(context),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          
          // Merchant
          const Icon(Icons.store, size: 48, color: AppTheme.primary),
          const SizedBox(height: 12),
          Text(
            request.merchantName,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Amount
          Text(
            '\$${request.amount.toStringAsFixed(2)}',
            style: const TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.bold,
              color: AppTheme.primary,
            ),
          ),
          Text(
            request.currency,
            style: TextStyle(
              color: AppTheme.textSecondary(context),
            ),
          ),
          
          const SizedBox(height: 32),
          
          // Buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onDecline,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: const BorderSide(color: AppTheme.error),
                    foregroundColor: AppTheme.error,
                  ),
                  child: const Text('Decline'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: onApprove,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.secondary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text(
                    'Pay Now',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// Payment result dialog
class _PaymentResultDialog extends StatelessWidget {
  final HcePaymentResponse response;
  final VoidCallback onDone;
  
  const _PaymentResultDialog({
    required this.response,
    required this.onDone,
  });
  
  @override
  Widget build(BuildContext context) {
    final success = response.approved;
    
    return AlertDialog(
      backgroundColor: AppTheme.surface(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            success ? Icons.check_circle : Icons.error,
            size: 64,
            color: success ? AppTheme.secondary : AppTheme.error,
          ),
          const SizedBox(height: 16),
          Text(
            success ? 'Payment Successful!' : 'Payment Failed',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (success && response.authCode != null) ...[
            const SizedBox(height: 8),
            Text(
              'Auth Code: ${response.authCode}',
              style: TextStyle(
                color: AppTheme.textSecondary(context),
                fontFamily: 'monospace',
              ),
            ),
          ],
          if (!success && response.errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              response.errorMessage!,
              style: const TextStyle(color: AppTheme.error),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: onDone,
          child: const Text('Done'),
        ),
      ],
    );
  }
}

// HCE Settings sheet
class _HceSettingsSheet extends StatefulWidget {
  final HceSettings settings;
  final Function(HceSettings) onSave;
  
  const _HceSettingsSheet({
    required this.settings,
    required this.onSave,
  });
  
  @override
  State<_HceSettingsSheet> createState() => _HceSettingsSheetState();
}

class _HceSettingsSheetState extends State<_HceSettingsSheet> {
  late HceSettings _settings;
  
  @override
  void initState() {
    super.initState();
    _settings = widget.settings;
  }
  
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tap to Pay Settings',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          
          // Tap & Pay limit
          Text(
            'Tap & Pay Limit: \$${_settings.tapAndPayLimit.toInt()}',
            style: TextStyle(color: AppTheme.textSecondary(context)),
          ),
          Slider(
            value: _settings.tapAndPayLimit,
            min: 0,
            max: 200,
            divisions: 20,
            onChanged: (v) => setState(() {
              _settings = _settings.copyWith(tapAndPayLimit: v);
            }),
          ),
          
          const SizedBox(height: 16),
          
          // Always require biometric
          SwitchListTile(
            title: const Text('Always Require Approval'),
            subtitle: const Text('Confirm every payment'),
            value: _settings.alwaysRequireBiometric,
            onChanged: (v) => setState(() {
              _settings = _settings.copyWith(alwaysRequireBiometric: v);
            }),
          ),
          
          // Haptic feedback
          SwitchListTile(
            title: const Text('Vibration Feedback'),
            subtitle: const Text('Vibrate when terminal detected'),
            value: _settings.hapticFeedback,
            onChanged: (v) => setState(() {
              _settings = _settings.copyWith(hapticFeedback: v);
            }),
          ),
          
          const SizedBox(height: 24),
          
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => widget.onSave(_settings),
              child: const Text('Save Settings'),
            ),
          ),
        ],
      ),
    );
  }
}

// Card background pattern painter
class _CardPatternPainter extends CustomPainter {
  final Color color;
  
  _CardPatternPainter({required this.color});
  
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    
    // Draw diagonal lines
    for (var i = -size.height; i < size.width; i += 20) {
      canvas.drawLine(
        Offset(i.toDouble(), 0),
        Offset(i + size.height, size.height),
        paint,
      );
    }
  }
  
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
