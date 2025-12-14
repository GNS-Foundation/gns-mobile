/// Welcome Screen - Initial Identity Creation
/// 
/// Allows users to create their GNS identity with a @handle.
/// 
/// Location: lib/ui/screens/welcome_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/gns/gns_api_client.dart';
import '../../core/theme/theme_service.dart';

enum HandleStatus { empty, checking, available, taken, invalid }

class WelcomeScreen extends StatefulWidget {
  final Future<void> Function(String handle) onCreateIdentity;
  
  const WelcomeScreen({super.key, required this.onCreateIdentity});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _handleController = TextEditingController();
  final _apiClient = GnsApiClient();
  
  String? _handle;
  bool _isCreating = false;
  HandleStatus _status = HandleStatus.empty;
  String? _errorMessage;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _handleController.addListener(_onHandleChanged);
  }

  @override
  void dispose() {
    _handleController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onHandleChanged() {
    final text = _handleController.text.toLowerCase().replaceAll('@', '').trim();
    
    _debounceTimer?.cancel();
    
    if (text.isEmpty) {
      setState(() {
        _handle = null;
        _status = HandleStatus.empty;
        _errorMessage = null;
      });
      return;
    }

    final validation = _validateHandle(text);
    if (validation != null) {
      setState(() {
        _handle = text;
        _status = HandleStatus.invalid;
        _errorMessage = validation;
      });
      return;
    }

    setState(() {
      _handle = text;
      _status = HandleStatus.checking;
      _errorMessage = null;
    });

    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _checkAvailability(text);
    });
  }

  String? _validateHandle(String handle) {
    if (handle.length < 3) return 'At least 3 characters';
    if (handle.length > 20) return 'Maximum 20 characters';
    if (!RegExp(r'^[a-z0-9_]+$').hasMatch(handle)) {
      return 'Only letters, numbers, underscore';
    }
    const reserved = ['admin', 'root', 'system', 'gns', 'layer', 'browser', 'support', 'help', 'official', 'verified'];
    if (reserved.contains(handle)) return 'This handle is reserved';
    return null;
  }

  Future<void> _checkAvailability(String handle) async {
    if (!mounted) return;
    
    try {
      final response = await _apiClient.checkHandle(handle);
      if (!mounted) return;
      
      if (response['success'] == true) {
        final data = response['data'] as Map<String, dynamic>?;
        final available = data?['available'] == true;
        setState(() {
          _status = available ? HandleStatus.available : HandleStatus.taken;
          _errorMessage = available ? null : '@$handle is already taken';
        });
      } else {
        setState(() => _status = HandleStatus.available);
      }
    } catch (e) {
      if (mounted) setState(() => _status = HandleStatus.available);
    }
  }

  Future<void> _createIdentity() async {
    if (_handle == null || _status != HandleStatus.available) return;
    
    setState(() => _isCreating = true);
    
    try {
      await widget.onCreateIdentity(_handle!);
    } catch (e) {
      if (mounted) {
        setState(() => _isCreating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const Spacer(flex: 2),
              
              // Logo
              const Text('🌐', style: TextStyle(fontSize: 72)),
              const SizedBox(height: 24),
              const Text('GLOBE CRUMBS', 
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 4)),
              const SizedBox(height: 8),
              Text('Identity through Presence', 
                style: TextStyle(fontSize: 16, color: AppTheme.textSecondary(context))),
              
              const Spacer(),
              
              // Handle Input
              Text('Choose your @handle',
                style: TextStyle(fontSize: 14, color: AppTheme.textSecondary(context), fontWeight: FontWeight.w500)),
              const SizedBox(height: 12),
              
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.surface(context),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _getBorderColor(), width: 2),
                ),
                child: Row(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text('@',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: _status == HandleStatus.available 
                              ? AppTheme.secondary 
                              : AppTheme.primary,
                        )),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _handleController,
                        enabled: !_isCreating,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
                        decoration: InputDecoration(
                          hintText: 'yourname',
                          hintStyle: TextStyle(color: AppTheme.textMuted(context)),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        autocorrect: false,
                        textCapitalization: TextCapitalization.none,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: _buildStatusIcon(),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 8),
              SizedBox(height: 20, child: _buildStatusMessage()),
              
              const SizedBox(height: 32),
              
              // Create Button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: (_status == HandleStatus.available && !_isCreating)
                      ? _createIdentity : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    disabledBackgroundColor: AppTheme.primary.withOpacity(0.3),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isCreating
                      ? const SizedBox(width: 24, height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('CREATE IDENTITY',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1)),
                ),
              ),
              
              const Spacer(),
              
              Text('No email. No password. No phone number.',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppTheme.textMuted(context))),
              const SizedBox(height: 4),
              Text('Your identity is earned through presence.',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppTheme.textMuted(context))),
              
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusIcon() {
    switch (_status) {
      case HandleStatus.empty:
        return const SizedBox(width: 24);
      case HandleStatus.checking:
        return SizedBox(width: 20, height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.textMuted(context)));
      case HandleStatus.available:
        return const Icon(Icons.check_circle, color: AppTheme.secondary, size: 24);
      case HandleStatus.taken:
        return const Icon(Icons.cancel, color: AppTheme.error, size: 24);
      case HandleStatus.invalid:
        return const Icon(Icons.error_outline, color: AppTheme.warning, size: 24);
    }
  }

  Widget _buildStatusMessage() {
    if (_status == HandleStatus.checking) {
      return Text('Checking availability...', 
        style: TextStyle(fontSize: 12, color: AppTheme.textMuted(context)));
    }
    if (_status == HandleStatus.available && _handle != null) {
      return Text('@$_handle is available! ✓',
        style: const TextStyle(fontSize: 12, color: AppTheme.secondary, fontWeight: FontWeight.w500));
    }
    if (_errorMessage != null) {
      return Text(_errorMessage!,
        style: TextStyle(fontSize: 12, 
          color: _status == HandleStatus.invalid ? AppTheme.warning : AppTheme.error));
    }
    return const SizedBox.shrink();
  }

  Color _getBorderColor() {
    switch (_status) {
      case HandleStatus.empty: return AppTheme.border(context);
      case HandleStatus.checking: return AppTheme.border(context);
      case HandleStatus.available: return AppTheme.secondary;
      case HandleStatus.taken: return AppTheme.error;
      case HandleStatus.invalid: return AppTheme.warning;
    }
  }
}
