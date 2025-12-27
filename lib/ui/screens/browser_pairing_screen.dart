/// Browser Pairing Screen - QR Scanner & Approval UI
/// 
/// Scan QR codes from Panthera Browser and approve/reject sessions.
/// 
/// Location: lib/screens/browser_pairing_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../core/auth/browser_pairing_service.dart';
import '../../core/gns/identity_wallet.dart';

/// Browser Pairing Screen with QR Scanner
class BrowserPairingScreen extends StatefulWidget {
  final IdentityWallet wallet;

  const BrowserPairingScreen({
    super.key,
    required this.wallet,
  });

  @override
  State<BrowserPairingScreen> createState() => _BrowserPairingScreenState();
}

class _BrowserPairingScreenState extends State<BrowserPairingScreen> {
  late final BrowserPairingService _pairingService;
  late final MobileScannerController _scannerController;
  
  BrowserAuthRequest? _pendingRequest;
  bool _isProcessing = false;
  String? _error;
  bool _scannerActive = true;

  @override
  void initState() {
    super.initState();
    _pairingService = BrowserPairingService(wallet: widget.wallet);
    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
    );
  }

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  /// Handle QR code detection
  void _onDetect(BarcodeCapture capture) {
    if (!_scannerActive || _isProcessing || _pendingRequest != null) return;

    for (final barcode in capture.barcodes) {
      final rawValue = barcode.rawValue;
      if (rawValue == null) continue;

      // Try to parse as browser auth request
      final request = _pairingService.parseQRCode(rawValue);
      
      if (request != null) {
        setState(() {
          _scannerActive = false;
          _pendingRequest = request;
          _error = null;
        });
        _scannerController.stop();
        break;
      }
    }
  }

  /// Approve the pending request
  Future<void> _approve() async {
    if (_pendingRequest == null || _isProcessing) return;

    setState(() {
      _isProcessing = true;
      _error = null;
    });

    final result = await _pairingService.approveSession(_pendingRequest!);

    if (result.success) {
      if (mounted) {
        _showSuccessDialog();
      }
    } else {
      setState(() {
        _error = result.error;
        _isProcessing = false;
      });
    }
  }

  /// Reject the pending request
  Future<void> _reject() async {
    if (_pendingRequest == null || _isProcessing) return;

    setState(() {
      _isProcessing = true;
    });

    await _pairingService.rejectSession(_pendingRequest!);

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  /// Reset scanner to scan again
  void _resetScanner() {
    setState(() {
      _pendingRequest = null;
      _scannerActive = true;
      _error = null;
      _isProcessing = false;
    });
    _scannerController.start();
  }

  /// Show success dialog
  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.green.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check_circle,
                size: 48,
                color: Colors.green.shade600,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Browser Approved!',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Panthera Browser is now securely connected to your identity.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop(); // Close dialog
                  Navigator.of(context).pop(); // Close screen
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.cyan,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Pair Browser'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _pendingRequest != null 
          ? _buildApprovalView() 
          : _buildScannerView(),
    );
  }

  /// QR Scanner view
  Widget _buildScannerView() {
    return Stack(
      children: [
        // Camera preview
        MobileScanner(
          controller: _scannerController,
          onDetect: _onDetect,
        ),
        
        // Overlay
        Container(
          decoration: ShapeDecoration(
            shape: _ScannerOverlayShape(
              borderColor: Colors.cyan,
              borderRadius: 20,
              borderLength: 40,
              borderWidth: 4,
              cutOutSize: 280,
            ),
          ),
        ),

        // Instructions
        SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 40),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 32),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.computer, color: Colors.cyan.shade300),
                        const SizedBox(width: 8),
                        const Text(
                          'Scan Browser QR Code',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Open panthera.gcrumbs.com on your computer and scan the login QR code',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              
              const Spacer(),
              
              // Security notice
              Container(
                margin: const EdgeInsets.all(32),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.cyan.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.cyan.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.shield, color: Colors.cyan.shade300),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Your private keys stay on this device. Browser receives limited access only.',
                        style: TextStyle(
                          color: Colors.cyan.shade100,
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
      ],
    );
  }

  /// Approval confirmation view
  Widget _buildApprovalView() {
    final request = _pendingRequest!;
    final timeRemaining = request.timeRemaining;
    
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Spacer(),
            
            // Browser icon
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: Colors.cyan.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.computer,
                size: 48,
                color: Colors.cyan,
              ),
            ),
            
            const SizedBox(height: 32),
            
            const Text(
              'Browser Sign-In Request',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Browser info card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey.shade900,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade800),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(Icons.language, color: Colors.grey.shade500, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Browser',
                        style: TextStyle(color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    request.browserInfo,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Icon(Icons.timer, color: Colors.grey.shade500, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Expires in ${timeRemaining.inMinutes}:${(timeRemaining.inSeconds % 60).toString().padLeft(2, '0')}',
                        style: TextStyle(
                          color: timeRemaining.inSeconds < 60 
                              ? Colors.red.shade400 
                              : Colors.grey.shade400,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Warning
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber, color: Colors.orange.shade300),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Only approve if you initiated this sign-in request',
                      style: TextStyle(
                        color: Colors.orange.shade200,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            // Error message
            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error, color: Colors.red, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            
            const Spacer(),
            
            // Action buttons
            Row(
              children: [
                // Reject button
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isProcessing ? null : _reject,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Reject',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                
                const SizedBox(width: 16),
                
                // Approve button
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _isProcessing ? null : _approve,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.cyan,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
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
                              Icon(Icons.check_circle),
                              SizedBox(width: 8),
                              Text(
                                'Approve',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Scan again button
            TextButton(
              onPressed: _isProcessing ? null : _resetScanner,
              child: Text(
                'Scan Different Code',
                style: TextStyle(color: Colors.grey.shade400),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Custom scanner overlay shape
class _ScannerOverlayShape extends ShapeBorder {
  final Color borderColor;
  final double borderWidth;
  final double borderRadius;
  final double borderLength;
  final double cutOutSize;

  const _ScannerOverlayShape({
    this.borderColor = Colors.white,
    this.borderWidth = 3.0,
    this.borderRadius = 12.0,
    this.borderLength = 32.0,
    this.cutOutSize = 250.0,
  });

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    return Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: rect.center,
            width: cutOutSize,
            height: cutOutSize,
          ),
          Radius.circular(borderRadius),
        ),
      );
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    return Path()
      ..addRect(rect)
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: rect.center,
            width: cutOutSize,
            height: cutOutSize,
          ),
          Radius.circular(borderRadius),
        ),
      )
      ..fillType = PathFillType.evenOdd;
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    final paint = Paint()
      ..color = Colors.black.withOpacity(0.5)
      ..style = PaintingStyle.fill;

    final cutOut = Rect.fromCenter(
      center: rect.center,
      width: cutOutSize,
      height: cutOutSize,
    );

    // Draw dark overlay
    canvas.drawPath(
      Path()
        ..addRect(rect)
        ..addRRect(RRect.fromRectAndRadius(cutOut, Radius.circular(borderRadius)))
        ..fillType = PathFillType.evenOdd,
      paint,
    );

    // Draw corner borders
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth
      ..strokeCap = StrokeCap.round;

    final corners = [
      // Top-left
      [Offset(cutOut.left, cutOut.top + borderLength), Offset(cutOut.left, cutOut.top + borderRadius), Offset(cutOut.left + borderRadius, cutOut.top), Offset(cutOut.left + borderLength, cutOut.top)],
      // Top-right  
      [Offset(cutOut.right - borderLength, cutOut.top), Offset(cutOut.right - borderRadius, cutOut.top), Offset(cutOut.right, cutOut.top + borderRadius), Offset(cutOut.right, cutOut.top + borderLength)],
      // Bottom-right
      [Offset(cutOut.right, cutOut.bottom - borderLength), Offset(cutOut.right, cutOut.bottom - borderRadius), Offset(cutOut.right - borderRadius, cutOut.bottom), Offset(cutOut.right - borderLength, cutOut.bottom)],
      // Bottom-left
      [Offset(cutOut.left + borderLength, cutOut.bottom), Offset(cutOut.left + borderRadius, cutOut.bottom), Offset(cutOut.left, cutOut.bottom - borderRadius), Offset(cutOut.left, cutOut.bottom - borderLength)],
    ];

    for (final corner in corners) {
      final path = Path()
        ..moveTo(corner[0].dx, corner[0].dy)
        ..lineTo(corner[1].dx, corner[1].dy)
        ..quadraticBezierTo(
          corner[1].dx == corner[2].dx ? corner[1].dx : (corner[1].dx < corner[2].dx ? cutOut.left : cutOut.right),
          corner[1].dy == corner[2].dy ? corner[1].dy : (corner[1].dy < corner[2].dy ? cutOut.top : cutOut.bottom),
          corner[2].dx,
          corner[2].dy,
        )
        ..lineTo(corner[3].dx, corner[3].dy);
      canvas.drawPath(path, borderPaint);
    }
  }

  @override
  ShapeBorder scale(double t) => this;
}

/// Active Sessions Screen - View and manage paired browsers
class ActiveSessionsScreen extends StatefulWidget {
  final IdentityWallet wallet;

  const ActiveSessionsScreen({
    super.key,
    required this.wallet,
  });

  @override
  State<ActiveSessionsScreen> createState() => _ActiveSessionsScreenState();
}

class _ActiveSessionsScreenState extends State<ActiveSessionsScreen> {
  late final BrowserPairingService _pairingService;
  List<Map<String, dynamic>> _sessions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _pairingService = BrowserPairingService(wallet: widget.wallet);
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    setState(() => _isLoading = true);
    final sessions = await _pairingService.getActiveSessions();
    setState(() {
      _sessions = sessions;
      _isLoading = false;
    });
  }

  Future<void> _revokeAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Revoke All Sessions?'),
        content: const Text(
          'This will sign out all connected browsers. You\'ll need to scan the QR code again to reconnect.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Revoke All'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _pairingService.revokeAllSessions();
      _loadSessions();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connected Browsers'),
        actions: [
          if (_sessions.isNotEmpty)
            TextButton(
              onPressed: _revokeAll,
              child: const Text('Revoke All', style: TextStyle(color: Colors.red)),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _sessions.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.computer_outlined, size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      Text(
                        'No active browser sessions',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _sessions.length,
                  itemBuilder: (context, index) {
                    final session = _sessions[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.cyan.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.computer, color: Colors.cyan),
                        ),
                        title: Text(session['browserInfo'] ?? 'Unknown Browser'),
                        subtitle: Text(
                          'Last used: ${_formatDate(session['lastUsedAt'])}',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                        trailing: session['isActive'] == true
                            ? Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'Active',
                                  style: TextStyle(color: Colors.green, fontSize: 12),
                                ),
                              )
                            : null,
                      ),
                    );
                  },
                ),
    );
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return 'Unknown';
    try {
      final date = DateTime.parse(dateStr);
      final now = DateTime.now();
      final diff = now.difference(date);
      
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inHours < 1) return '${diff.inMinutes}m ago';
      if (diff.inDays < 1) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    } catch (e) {
      return 'Unknown';
    }
  }
}
