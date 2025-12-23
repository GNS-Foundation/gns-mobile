/// Home Recovery Screen - Identity Recovery via Home Hub
/// 
/// Allows users to recover their identity using the Home Hub's
/// PIN-on-TV verification system.
/// 
/// Flow:
/// 1. Enter handle (@username)
/// 2. Connect to Home Hub on local network
/// 3. Read PIN from TV
/// 4. Enter PIN to retrieve encrypted backup
/// 5. Decrypt and restore identity
/// 
/// Location: lib/ui/screens/home_recovery_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/home/home_service.dart';

class HomeRecoveryScreen extends StatefulWidget {
  final Function(String encryptedSeed, String nonce)? onRecoveryComplete;

  const HomeRecoveryScreen({
    super.key,
    this.onRecoveryComplete,
  });

  @override
  State<HomeRecoveryScreen> createState() => _HomeRecoveryScreenState();
}

class _HomeRecoveryScreenState extends State<HomeRecoveryScreen> {
  final _hubUrlController = TextEditingController(text: 'http://localhost:3500');
  final _handleController = TextEditingController();
  final _pinController = TextEditingController();
  
  int _currentStep = 0;
  bool _isLoading = false;
  String? _error;
  
  RecoverySession? _session;
  int _timeRemaining = 300;
  Timer? _countdownTimer;

  @override
  void dispose() {
    _hubUrlController.dispose();
    _handleController.dispose();
    _pinController.dispose();
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    _timeRemaining = _session?.expiresIn ?? 300;
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _timeRemaining--;
        if (_timeRemaining <= 0) {
          timer.cancel();
          _error = 'PIN expired. Please try again.';
          _currentStep = 1;
        }
      });
    });
  }

  String _formatTime(int seconds) {
    final min = seconds ~/ 60;
    final sec = seconds % 60;
    return '$min:${sec.toString().padLeft(2, '0')}';
  }

  Future<void> _initiateRecovery() async {
    final handle = _handleController.text.trim().replaceAll('@', '');
    if (handle.isEmpty) {
      setState(() => _error = 'Please enter your handle');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // First, connect to the hub
      final connected = await homeService.initialize(
        hubUrl: _hubUrlController.text.trim(),
        userPublicKey: 'recovery_temp_key', // Temporary key for recovery
      );

      if (!connected) {
        setState(() {
          _isLoading = false;
          _error = 'Cannot connect to Home Hub. Check the URL and try again.';
        });
        return;
      }

      // Generate a temporary key for the new device
      // In real app, this would be a proper Ed25519 keypair
      final newDeviceKey = 'temp_${DateTime.now().millisecondsSinceEpoch}';

      // Initiate recovery
      final session = await homeService.initiateRecovery(
        handle: handle,
        newDeviceKey: newDeviceKey.padRight(64, '0'),
      );

      if (session != null) {
        setState(() {
          _isLoading = false;
          _session = session;
          _currentStep = 2;
        });
        _startCountdown();
      } else {
        setState(() {
          _isLoading = false;
          _error = 'No backup found for @$handle on this hub';
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'Recovery failed: $e';
      });
    }
  }

  Future<void> _verifyPin() async {
    final pin = _pinController.text.trim();
    if (pin.length != 6) {
      setState(() => _error = 'Please enter the 6-digit PIN');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final backup = await homeService.verifyRecoveryPin(
        sessionId: _session!.sessionId,
        pin: pin,
      );

      if (backup != null) {
        _countdownTimer?.cancel();
        
        setState(() {
          _isLoading = false;
          _currentStep = 3;
        });

        // Call the completion callback
        if (widget.onRecoveryComplete != null) {
          widget.onRecoveryComplete!(
            backup['encryptedSeed'] ?? '',
            backup['nonce'] ?? '',
          );
        }
      } else {
        setState(() {
          _isLoading = false;
          _error = 'Wrong PIN. Please check your TV and try again.';
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'Verification failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0a0a0a),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white70),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Recover Identity',
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // Progress indicator
            _buildProgressIndicator(),
            const SizedBox(height: 40),
            
            // Step content
            if (_currentStep == 0) _buildStep0_HubUrl(),
            if (_currentStep == 1) _buildStep1_Handle(),
            if (_currentStep == 2) _buildStep2_Pin(),
            if (_currentStep == 3) _buildStep3_Success(),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressIndicator() {
    return Row(
      children: [
        _buildStepDot(0, 'Hub'),
        _buildStepLine(0),
        _buildStepDot(1, 'Handle'),
        _buildStepLine(1),
        _buildStepDot(2, 'PIN'),
        _buildStepLine(2),
        _buildStepDot(3, 'Done'),
      ],
    );
  }

  Widget _buildStepDot(int step, String label) {
    final isActive = _currentStep >= step;
    final isCurrent = _currentStep == step;
    
    return Column(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: isActive
                ? const Color(0xFF6366f1)
                : Colors.white.withOpacity(0.1),
            shape: BoxShape.circle,
            border: isCurrent
                ? Border.all(color: Colors.white, width: 2)
                : null,
          ),
          child: Center(
            child: isActive && !isCurrent
                ? const Icon(Icons.check, color: Colors.white, size: 18)
                : Text(
                    '${step + 1}',
                    style: TextStyle(
                      color: isActive ? Colors.white : Colors.white38,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: isActive ? Colors.white70 : Colors.white38,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildStepLine(int afterStep) {
    final isActive = _currentStep > afterStep;
    return Expanded(
      child: Container(
        height: 2,
        margin: const EdgeInsets.only(bottom: 20),
        color: isActive
            ? const Color(0xFF6366f1)
            : Colors.white.withOpacity(0.1),
      ),
    );
  }

  Widget _buildStep0_HubUrl() {
    return Column(
      children: [
        // Icon
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: const Color(0xFF6366f1).withOpacity(0.2),
            shape: BoxShape.circle,
          ),
          child: const Center(
            child: Text('🏠', style: TextStyle(fontSize: 40)),
          ),
        ),
        const SizedBox(height: 24),
        
        const Text(
          'Connect to Home Hub',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Enter the URL of your GNS Home Hub',
          style: TextStyle(
            color: Colors.white.withOpacity(0.6),
          ),
        ),
        const SizedBox(height: 32),
        
        // URL input
        _buildTextField(
          controller: _hubUrlController,
          hint: 'http://192.168.1.100:3500',
          icon: Icons.link,
        ),
        
        if (_error != null) ...[
          const SizedBox(height: 16),
          _buildErrorMessage(),
        ],
        
        const SizedBox(height: 24),
        
        _buildButton(
          label: 'Continue',
          onPressed: () {
            if (_hubUrlController.text.trim().isNotEmpty) {
              setState(() {
                _currentStep = 1;
                _error = null;
              });
            }
          },
        ),
      ],
    );
  }

  Widget _buildStep1_Handle() {
    return Column(
      children: [
        // Icon
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: const Color(0xFF6366f1).withOpacity(0.2),
            shape: BoxShape.circle,
          ),
          child: const Center(
            child: Text('👤', style: TextStyle(fontSize: 40)),
          ),
        ),
        const SizedBox(height: 24),
        
        const Text(
          'Enter Your Handle',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'The @username you want to recover',
          style: TextStyle(
            color: Colors.white.withOpacity(0.6),
          ),
        ),
        const SizedBox(height: 32),
        
        // Handle input
        _buildTextField(
          controller: _handleController,
          hint: '@camiloayerbe',
          icon: Icons.alternate_email,
          prefix: '@',
        ),
        
        if (_error != null) ...[
          const SizedBox(height: 16),
          _buildErrorMessage(),
        ],
        
        const SizedBox(height: 24),
        
        _buildButton(
          label: 'Request Recovery',
          isLoading: _isLoading,
          onPressed: _initiateRecovery,
        ),
        
        const SizedBox(height: 16),
        
        TextButton(
          onPressed: () => setState(() => _currentStep = 0),
          child: Text(
            'Change Hub URL',
            style: TextStyle(color: Colors.white.withOpacity(0.5)),
          ),
        ),
      ],
    );
  }

  Widget _buildStep2_Pin() {
    return Column(
      children: [
        // TV icon with animation
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            color: const Color(0xFF6366f1).withOpacity(0.2),
            shape: BoxShape.circle,
          ),
          child: const Center(
            child: Text('📺', style: TextStyle(fontSize: 50)),
          ),
        ),
        const SizedBox(height: 24),
        
        const Text(
          'Check Your TV',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'A 6-digit PIN is displayed on your TV',
          style: TextStyle(
            color: Colors.white.withOpacity(0.6),
          ),
        ),
        const SizedBox(height: 16),
        
        // Countdown
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: _timeRemaining < 60
                ? Colors.red.withOpacity(0.2)
                : Colors.orange.withOpacity(0.2),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.timer,
                color: _timeRemaining < 60 ? Colors.red : Colors.orange,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'Expires in ${_formatTime(_timeRemaining)}',
                style: TextStyle(
                  color: _timeRemaining < 60 ? Colors.red : Colors.orange,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        
        // PIN input
        _buildPinInput(),
        
        if (_error != null) ...[
          const SizedBox(height: 16),
          _buildErrorMessage(),
        ],
        
        const SizedBox(height: 24),
        
        _buildButton(
          label: 'Verify PIN',
          isLoading: _isLoading,
          onPressed: _verifyPin,
        ),
        
        const SizedBox(height: 16),
        
        TextButton(
          onPressed: () {
            _countdownTimer?.cancel();
            setState(() {
              _currentStep = 1;
              _session = null;
              _pinController.clear();
            });
          },
          child: Text(
            'Try Again',
            style: TextStyle(color: Colors.white.withOpacity(0.5)),
          ),
        ),
      ],
    );
  }

  Widget _buildStep3_Success() {
    return Column(
      children: [
        // Success icon
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            color: Colors.green.withOpacity(0.2),
            shape: BoxShape.circle,
          ),
          child: const Center(
            child: Icon(
              Icons.check_circle,
              color: Colors.green,
              size: 60,
            ),
          ),
        ),
        const SizedBox(height: 24),
        
        const Text(
          'Identity Recovered!',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Your encrypted backup has been retrieved',
          style: TextStyle(
            color: Colors.white.withOpacity(0.6),
          ),
        ),
        const SizedBox(height: 32),
        
        // Info box
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.green.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.green.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline, color: Colors.green),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Your identity will be decrypted using your recovery key',
                  style: TextStyle(
                    color: Colors.green.shade300,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        
        _buildButton(
          label: 'Continue',
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    String? prefix,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: TextField(
        controller: controller,
        style: const TextStyle(color: Colors.white, fontSize: 16),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
          prefixIcon: Icon(icon, color: Colors.white.withOpacity(0.5)),
          prefixText: prefix,
          prefixStyle: const TextStyle(color: Colors.white70, fontSize: 16),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(16),
        ),
      ),
    );
  }

  Widget _buildPinInput() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: TextField(
        controller: _pinController,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 32,
          fontWeight: FontWeight.bold,
          letterSpacing: 16,
        ),
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        maxLength: 6,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          hintText: '• • • • • •',
          hintStyle: TextStyle(
            color: Colors.white.withOpacity(0.2),
            fontSize: 32,
            letterSpacing: 16,
          ),
          counterText: '',
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 20),
        ),
        onChanged: (value) {
          if (value.length == 6) {
            _verifyPin();
          }
        },
      ),
    );
  }

  Widget _buildErrorMessage() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _error!,
              style: const TextStyle(color: Colors.red, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildButton({
    required String label,
    required VoidCallback onPressed,
    bool isLoading = false,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF6366f1),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }
}
