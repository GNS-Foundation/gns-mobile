/// GNS Payment Received Sheet
/// 
/// Bottom sheet for incoming payment notifications.
/// Location: lib/ui/financial/payment_received_sheet.dart

import 'package:flutter/material.dart';
import '../../core/theme/theme_service.dart';
import '../../core/financial/payment_service.dart';

class PaymentReceivedSheet extends StatefulWidget {
  final IncomingPayment incomingPayment;
  final PaymentService paymentService;
  
  const PaymentReceivedSheet({
    super.key,
    required this.incomingPayment,
    required this.paymentService,
  });

  /// Show the payment received sheet
  static Future<bool?> show(
    BuildContext context, {
    required IncomingPayment incomingPayment,
    required PaymentService paymentService,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder: (ctx) => PaymentReceivedSheet(
        incomingPayment: incomingPayment,
        paymentService: paymentService,
      ),
    );
  }

  /// Show compact banner (non-modal)
  static void showBanner(
    BuildContext context, {
    required IncomingPayment incomingPayment,
    required VoidCallback onTap,
  }) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    
    entry = OverlayEntry(
      builder: (ctx) => _PaymentBanner(
        payment: incomingPayment,
        onTap: () {
          entry.remove();
          onTap();
        },
        onDismiss: () => entry.remove(),
      ),
    );
    
    overlay.insert(entry);
    
    // Auto-dismiss after 5 seconds
    Future.delayed(const Duration(seconds: 5), () {
      if (entry.mounted) entry.remove();
    });
  }

  @override
  State<PaymentReceivedSheet> createState() => _PaymentReceivedSheetState();
}

class _PaymentReceivedSheetState extends State<PaymentReceivedSheet>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  
  bool _isProcessing = false;
  String? _declineReason;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    
    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    );
    
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeIn,
    );
    
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (ctx, child) => Container(
        color: Colors.black.withOpacity(0.5 * _fadeAnimation.value),
        child: Center(
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: child,
          ),
        ),
      ),
      child: _buildContent(),
    );
  }

  Widget _buildContent() {
    return Container(
      margin: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.secondary,
                  AppTheme.secondary.withOpacity(0.8),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                // Icon
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.arrow_downward,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 16),
                
                // Title
                const Text(
                  'Payment Received',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'From ${widget.incomingPayment.senderDisplay}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          
          // Amount
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Text(
                  widget.incomingPayment.amountFormatted,
                  style: TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary(context),
                  ),
                ),
                
                if (widget.incomingPayment.memo != null &&
                    widget.incomingPayment.memo!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceLight(context),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.note_outlined,
                          size: 16,
                          color: AppTheme.textMuted(context),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            widget.incomingPayment.memo!,
                            style: TextStyle(
                              color: AppTheme.textSecondary(context),
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          
          // Actions
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              children: [
                // Accept button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isProcessing ? null : _acceptPayment,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.secondary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isProcessing
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
                              Icon(Icons.check, color: Colors.white),
                              SizedBox(width: 8),
                              Text(
                                'ACCEPT',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: 1,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                
                // Decline button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton(
                    onPressed: _isProcessing ? null : _showDeclineDialog,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.error,
                      side: const BorderSide(color: AppTheme.error),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('DECLINE'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _acceptPayment() async {
    setState(() => _isProcessing = true);
    
    final result = await widget.paymentService.acknowledgePayment(
      paymentId: widget.incomingPayment.id,
      accept: true,
    );
    
    if (mounted) {
      Navigator.pop(context, result.success);
      
      if (result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Received ${widget.incomingPayment.amountFormatted}'),
            backgroundColor: AppTheme.secondary,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.error ?? 'Failed to accept payment'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  void _showDeclineDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Decline Payment?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Are you sure you want to decline ${widget.incomingPayment.amountFormatted} from ${widget.incomingPayment.senderDisplay}?',
            ),
            const SizedBox(height: 16),
            TextField(
              decoration: const InputDecoration(
                hintText: 'Reason (optional)',
                isDense: true,
              ),
              onChanged: (value) => _declineReason = value,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _declinePayment();
            },
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: const Text('DECLINE'),
          ),
        ],
      ),
    );
  }

  Future<void> _declinePayment() async {
    setState(() => _isProcessing = true);
    
    final result = await widget.paymentService.acknowledgePayment(
      paymentId: widget.incomingPayment.id,
      accept: false,
      declineReason: _declineReason,
    );
    
    if (mounted) {
      Navigator.pop(context, false);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.success
                ? 'Payment declined'
                : (result.error ?? 'Failed to decline payment'),
          ),
          backgroundColor: result.success ? null : AppTheme.error,
        ),
      );
    }
  }
}

/// Compact banner for non-intrusive notifications
class _PaymentBanner extends StatefulWidget {
  final IncomingPayment payment;
  final VoidCallback onTap;
  final VoidCallback onDismiss;
  
  const _PaymentBanner({
    required this.payment,
    required this.onTap,
    required this.onDismiss,
  });

  @override
  State<_PaymentBanner> createState() => _PaymentBannerState();
}

class _PaymentBannerState extends State<_PaymentBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));
    
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 16,
      right: 16,
      child: SlideTransition(
        position: _slideAnimation,
        child: Material(
          color: Colors.transparent,
          child: GestureDetector(
            onTap: widget.onTap,
            onHorizontalDragEnd: (details) {
              if (details.primaryVelocity != null &&
                  details.primaryVelocity!.abs() > 300) {
                _dismiss();
              }
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surface(context),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
                border: Border.all(
                  color: AppTheme.secondary.withOpacity(0.3),
                  width: 2,
                ),
              ),
              child: Row(
                children: [
                  // Icon
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppTheme.secondary.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.arrow_downward,
                      color: AppTheme.secondary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  
                  // Content
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Payment Received',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary(context),
                          ),
                        ),
                        Text(
                          '${widget.payment.amountFormatted} from ${widget.payment.senderDisplay}',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppTheme.textSecondary(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // Dismiss button
                  IconButton(
                    icon: Icon(
                      Icons.close,
                      size: 20,
                      color: AppTheme.textMuted(context),
                    ),
                    onPressed: _dismiss,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _dismiss() async {
    await _controller.reverse();
    widget.onDismiss();
  }
}
