/// Send GNS Sheet
/// 
/// Bottom sheet for sending GNS tokens to another user.
/// 
/// Location: lib/ui/widgets/send_gns_sheet.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/gns/identity_wallet.dart';
import '../../core/theme/theme_service.dart';
import '../financial/stellar_service.dart';

class SendGnsSheet extends StatefulWidget {
  final IdentityWallet wallet;
  final String recipientPublicKey;
  final String? recipientHandle;
  final VoidCallback? onSuccess;

  const SendGnsSheet({
    super.key,
    required this.wallet,
    required this.recipientPublicKey,
    this.recipientHandle,
    this.onSuccess,
  });

  /// Show the send sheet
  static Future<bool?> show({
    required BuildContext context,
    required IdentityWallet wallet,
    required String recipientPublicKey,
    String? recipientHandle,
    VoidCallback? onSuccess,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SendGnsSheet(
        wallet: wallet,
        recipientPublicKey: recipientPublicKey,
        recipientHandle: recipientHandle,
        onSuccess: onSuccess,
      ),
    );
  }

  @override
  State<SendGnsSheet> createState() => _SendGnsSheetState();
}

class _SendGnsSheetState extends State<SendGnsSheet> {
  final _amountController = TextEditingController();
  final _stellar = StellarService();
  
  double _balance = 0;
  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadBalance();
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _loadBalance() async {
    try {
      final publicKey = widget.wallet.publicKey;
      if (publicKey == null) return;
      
      final stellarAddress = _stellar.gnsKeyToStellar(publicKey);
      final balance = await _stellar.getGnsBalance(stellarAddress);
      
      if (mounted) {
        setState(() {
          _balance = balance;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Failed to load balance';
        });
      }
    }
  }

  Future<void> _send() async {
    final amountText = _amountController.text.trim();
    final amount = double.tryParse(amountText);
    
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter a valid amount');
      return;
    }
    
    if (amount > _balance) {
      setState(() => _error = 'Insufficient balance');
      return;
    }
    
    setState(() {
      _sending = true;
      _error = null;
    });
    
    try {
      final senderPublicKey = widget.wallet.publicKey;
      final privateKeyBytes = widget.wallet.privateKeyBytes;
      
      if (senderPublicKey == null || privateKeyBytes == null) {
        setState(() {
          _sending = false;
          _error = 'Wallet not initialized';
        });
        return;
      }
      
      final senderStellarKey = _stellar.gnsKeyToStellar(senderPublicKey);
      
      final result = await _stellar.sendGnsToGnsKey(
        senderStellarPublicKey: senderStellarKey,
        senderPrivateKeyBytes: privateKeyBytes,
        recipientGnsPublicKey: widget.recipientPublicKey,
        amount: amount,
      );
      
      if (mounted) {
        if (result.success) {
          widget.onSuccess?.call();
          Navigator.pop(context, true);
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✓ Sent ${amount.toStringAsFixed(2)} GNS'),
              backgroundColor: AppTheme.secondary,
            ),
          );
        } else {
          setState(() {
            _sending = false;
            _error = result.error ?? 'Transaction failed';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = e.toString();
        });
      }
    }
  }

  void _setMax() {
    _amountController.text = _balance.toStringAsFixed(2);
    setState(() => _error = null);
  }

  @override
  Widget build(BuildContext context) {
    final recipientDisplay = widget.recipientHandle != null 
        ? '@${widget.recipientHandle}' 
        : '${widget.recipientPublicKey.substring(0, 8)}...';
    
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF4CAF50), Color(0xFF2196F3)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Center(
                    child: Text('G', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Send GNS',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'To $recipientDisplay',
                        style: TextStyle(fontSize: 14, color: AppTheme.textSecondary(context)),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            
            const SizedBox(height: 24),
            
            // Balance
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surfaceLight(context),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Your Balance',
                    style: TextStyle(color: AppTheme.textSecondary(context)),
                  ),
                  _loading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          '${_balance.toStringAsFixed(2)} GNS',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Amount Input
            Text(
              'Amount',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: AppTheme.textSecondary(context),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _amountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                    ],
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      hintText: '0.00',
                      suffixText: 'GNS',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    ),
                    onChanged: (_) => setState(() => _error = null),
                  ),
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: _loading ? null : _setMax,
                  child: const Text('MAX'),
                ),
              ],
            ),
            
            // Error
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.error.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: AppTheme.error, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(color: AppTheme.error, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            
            const SizedBox(height: 24),
            
            // Send Button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: (_loading || _sending) ? null : _send,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4CAF50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _sending
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(
                        'Send ${_amountController.text.isEmpty ? "" : "${_amountController.text} "}GNS',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
