/// GNS Send Money Screen
/// 
/// 3-step payment flow: Enter → Confirm → Result
/// Location: lib/ui/financial/send_money_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/theme_service.dart';
import '../../core/financial/payment_service.dart';
import '../../core/financial/payment_payload.dart';
import '../../core/financial/idup_router.dart';
import 'stellar_service.dart';  // ✅ Same folder (lib/ui/financial/)
import '../../core/discovery/discovery_service.dart';
import '../../core/gns/identity_wallet.dart';

class SendMoneyScreen extends StatefulWidget {
  final String? prefillRecipient;
  final String? prefillAmount;
  
  const SendMoneyScreen({
    super.key,
    this.prefillRecipient,
    this.prefillAmount,
  });

  @override
  State<SendMoneyScreen> createState() => _SendMoneyScreenState();
}

class _SendMoneyScreenState extends State<SendMoneyScreen> {
  // Step tracking
  int _currentStep = 0; // 0: Enter, 1: Confirm, 2: Result
  
  // Controllers
  final _recipientController = TextEditingController();
  final _amountController = TextEditingController();
  final _memoController = TextEditingController();
  
  // State
  String _selectedCurrency = 'GNS';  // ✅ Default to GNS!
  bool _isSearchingRecipient = false;
  bool _isSending = false;
  String? _recipientPk;
  String? _recipientHandle;
  String? _recipientError;
  RouteResult? _selectedRoute;
  PaymentSendResult? _sendResult;
  
  // Services
  PaymentService? _paymentService;
  IdentityWallet? _wallet;  // ✅ Keep wallet reference for Stellar signing
  final _discoveryService = DiscoveryService();
  final _stellarService = StellarService();  // ✅ Stellar service
  
  // ✅ GNS FIRST!
  static const _currencies = ['GNS', 'EUR', 'USD', 'GBP', 'BTC', 'ETH'];
  static const _currencySymbols = {
    'GNS': '✦',   // ✅ GNS Token!
    'EUR': '€',
    'USD': '\$',
    'GBP': '£',
    'BTC': '₿',
    'ETH': 'Ξ',
  };

  @override
  void initState() {
    super.initState();
    _initPaymentService();
    
    if (widget.prefillRecipient != null) {
      _recipientController.text = widget.prefillRecipient!;
      _searchRecipient(widget.prefillRecipient!);
    }
    if (widget.prefillAmount != null) {
      _amountController.text = widget.prefillAmount!;
    }
  }

  Future<void> _initPaymentService() async {
    try {
      _wallet = IdentityWallet();  // ✅ Store wallet reference
      await _wallet!.initialize();
      _paymentService = PaymentService.instance(_wallet!);
      await _paymentService!.initialize();
    } catch (e) {
      debugPrint('Error initializing payment service: $e');
    }
  }

  @override
  void dispose() {
    _recipientController.dispose();
    _amountController.dispose();
    _memoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_getStepTitle()),
        leading: _currentStep > 0 && _currentStep < 2
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _currentStep--),
              )
            : null,
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: _buildCurrentStep(),
      ),
    );
  }

  String _getStepTitle() {
    switch (_currentStep) {
      case 0: return 'Send Money';
      case 1: return 'Confirm Payment';
      case 2: return _sendResult?.success == true ? 'Payment Sent' : 'Payment Failed';
      default: return 'Send Money';
    }
  }

  Widget _buildCurrentStep() {
    switch (_currentStep) {
      case 0: return _buildEnterStep();
      case 1: return _buildConfirmStep();
      case 2: return _buildResultStep();
      default: return _buildEnterStep();
    }
  }

  // ==================== STEP 1: ENTER ====================

  Widget _buildEnterStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Recipient
          Text(
            'RECIPIENT',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppTheme.textMuted(context),
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _recipientController,
            decoration: InputDecoration(
              hintText: '@handle or public key',
              prefixIcon: const Icon(Icons.person_outline),
              suffixIcon: _isSearchingRecipient
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : _recipientPk != null
                      ? const Icon(Icons.check_circle, color: AppTheme.secondary)
                      : null,
              errorText: _recipientError,
            ),
            onChanged: _onRecipientChanged,
            textInputAction: TextInputAction.next,
          ),
          
          if (_recipientPk != null && _recipientHandle != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.secondary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.verified, size: 16, color: AppTheme.secondary),
                  const SizedBox(width: 8),
                  Text(
                    '@$_recipientHandle',
                    style: const TextStyle(
                      color: AppTheme.secondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
          
          const SizedBox(height: 24),
          
          // Amount
          Text(
            'AMOUNT',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppTheme.textMuted(context),
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Currency selector
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.surface(context),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.border(context)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedCurrency,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    items: _currencies.map((c) => DropdownMenuItem(
                      value: c,
                      child: Text(
                        '${_currencySymbols[c]} $c',
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    )).toList(),
                    onChanged: (v) => setState(() => _selectedCurrency = v!),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Amount input
              Expanded(
                child: TextField(
                  controller: _amountController,
                  decoration: InputDecoration(
                    hintText: '0.00',
                    prefixText: '${_currencySymbols[_selectedCurrency]} ',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,8}')),
                  ],
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                  onChanged: (_) => setState(() {}),  // ✅ Trigger rebuild to update button state
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 24),
          
          // Memo
          Text(
            'MEMO (OPTIONAL)',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppTheme.textMuted(context),
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _memoController,
            decoration: const InputDecoration(
              hintText: 'What is this for?',
              prefixIcon: Icon(Icons.note_outlined),
            ),
            maxLength: 140,
          ),
          
          const SizedBox(height: 32),
          
          // Continue button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _canContinue() ? _goToConfirm : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'CONTINUE',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _canContinue() {
    return _recipientPk != null &&
           _amountController.text.isNotEmpty &&
           (double.tryParse(_amountController.text) ?? 0) > 0;
  }

  void _onRecipientChanged(String value) {
    setState(() {
      _recipientError = null;
      _recipientPk = null;
      _recipientHandle = null;
    });
    
    if (value.isEmpty) return;
    
    // Debounce search
    Future.delayed(const Duration(milliseconds: 500), () {
      if (_recipientController.text == value) {
        _searchRecipient(value);
      }
    });
  }

  Future<void> _searchRecipient(String query) async {
    setState(() => _isSearchingRecipient = true);
    
    try {
      final result = await _discoveryService.search(query);
      
      if (mounted) {
        setState(() {
          _isSearchingRecipient = false;
          if (result.success && result.identity != null) {
            _recipientPk = result.identity!.publicKey;
            _recipientHandle = result.identity!.handle;
            _recipientError = null;
          } else {
            _recipientPk = null;
            _recipientHandle = null;
            _recipientError = result.error ?? 'Recipient not found';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSearchingRecipient = false;
          _recipientError = 'Search failed';
        });
      }
    }
  }

  void _goToConfirm() {
    // Calculate route
    _calculateRoute();
    setState(() => _currentStep = 1);
  }

  Future<void> _calculateRoute() async {
    if (_paymentService == null || _recipientPk == null) return;
    
    _selectedRoute = _paymentService!.calculateRoute(
      recipientPk: _recipientPk!,
      amount: _amountController.text,
      currency: _selectedCurrency,
    );
  }

  // ==================== STEP 2: CONFIRM ====================

  Widget _buildConfirmStep() {
    final amount = _amountController.text;
    final symbol = _currencySymbols[_selectedCurrency] ?? _selectedCurrency;
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const SizedBox(height: 20),
          
          // Amount display
          Text(
            '$symbol$amount',
            style: TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary(context),
            ),
          ),
          Text(
            _selectedCurrency,
            style: TextStyle(
              fontSize: 16,
              color: AppTheme.textMuted(context),
            ),
          ),
          
          const SizedBox(height: 32),
          
          // Recipient card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.surface(context),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.border(context)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: AppTheme.primary.withOpacity(0.2),
                      child: Text(
                        _recipientHandle?.substring(0, 1).toUpperCase() ?? '?',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'To',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textMuted(context),
                            ),
                          ),
                          Text(
                            _recipientHandle != null
                                ? '@$_recipientHandle'
                                : '${_recipientPk?.substring(0, 16)}...',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                
                if (_memoController.text.isNotEmpty) ...[
                  const Divider(height: 24),
                  Row(
                    children: [
                      Icon(
                        Icons.note_outlined,
                        size: 16,
                        color: AppTheme.textMuted(context),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _memoController.text,
                          style: TextStyle(
                            color: AppTheme.textSecondary(context),
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Route info
          if (_selectedRoute != null)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surfaceLight(context),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    _getRouteIcon(_selectedRoute!.route.type),
                    color: AppTheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Via ${_selectedRoute!.route.type.toUpperCase()}',
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        if (_selectedRoute!.estimatedFee != null)
                          Text(
                            'Fee: ${_selectedRoute!.estimatedFee}',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textMuted(context),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          
          const SizedBox(height: 32),
          
          // Confirm button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _isSending ? null : _sendPayment,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.secondary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isSending
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'SEND PAYMENT',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
            ),
          ),
          
          const SizedBox(height: 12),
          
          TextButton(
            onPressed: () => setState(() => _currentStep = 0),
            child: const Text('Edit Details'),
          ),
        ],
      ),
    );
  }

  IconData _getRouteIcon(String type) {
    switch (type.toLowerCase()) {
      case 'lightning': return Icons.bolt;
      case 'sepa': return Icons.account_balance;
      case 'ethereum': return Icons.currency_bitcoin;
      default: return Icons.send;
    }
  }

  Future<void> _sendPayment() async {
    if (_recipientPk == null) return;
    
    setState(() => _isSending = true);
    
    try {
      // ✅ GNS tokens go through Stellar network
      if (_selectedCurrency == 'GNS') {
        if (_wallet == null) {
          setState(() {
            _isSending = false;
            _sendResult = PaymentSendResult(
              success: false,
              error: 'Wallet not initialized',
            );
            _currentStep = 2;
          });
          return;
        }
        
        // Get sender's Stellar address from GNS key
        final senderStellarKey = _stellarService.gnsKeyToStellar(_wallet!.publicKey!);
        
        // Get private key bytes for signing
        final privateKeyBytes = _wallet!.privateKeyBytes!;
        
        // Parse amount
        final amount = double.tryParse(_amountController.text) ?? 0.0;
        
        if (amount <= 0) {
          setState(() {
            _isSending = false;
            _sendResult = PaymentSendResult(
              success: false,
              error: 'Invalid amount',
            );
            _currentStep = 2;
          });
          return;
        }
        
        // Send GNS via Stellar! 🚀
        final result = await _stellarService.sendGnsToGnsKey(
          senderStellarPublicKey: senderStellarKey,
          senderPrivateKeyBytes: privateKeyBytes,
          recipientGnsPublicKey: _recipientPk!,
          amount: amount,
        );
        
        setState(() {
          _isSending = false;
          _sendResult = PaymentSendResult(
            success: result.success,
            transactionId: result.hash,
            error: result.error,
          );
          _currentStep = 2;
        });
        return;
      }
      
      // Other currencies go through IDUP payment rails
      if (_paymentService == null) return;
      
      final result = await _paymentService!.sendPayment(
        recipientPk: _recipientPk!,
        recipientHandle: _recipientHandle,
        amount: _amountController.text,
        currency: _selectedCurrency,
        memo: _memoController.text.isEmpty ? null : _memoController.text,
        route: _selectedRoute?.route,
      );
      
      setState(() {
        _isSending = false;
        _sendResult = result;
        _currentStep = 2;
      });
    } catch (e) {
      debugPrint('Send payment error: $e');
      setState(() {
        _isSending = false;
        _sendResult = PaymentSendResult(
          success: false,
          error: e.toString(),
        );
        _currentStep = 2;
      });
    }
  }

  // ==================== STEP 3: RESULT ====================

  Widget _buildResultStep() {
    final success = _sendResult?.success == true;
    final amount = _amountController.text;
    final symbol = _currencySymbols[_selectedCurrency] ?? _selectedCurrency;
    
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Status icon
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: (success ? AppTheme.secondary : AppTheme.error).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                success ? Icons.check_circle : Icons.error,
                size: 64,
                color: success ? AppTheme.secondary : AppTheme.error,
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Status text
            Text(
              success ? 'Payment Sent!' : 'Payment Failed',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary(context),
              ),
            ),
            
            const SizedBox(height: 8),
            
            if (success) ...[
              Text(
                '$symbol$amount to ${_recipientHandle != null ? '@$_recipientHandle' : 'recipient'}',
                style: TextStyle(
                  fontSize: 16,
                  color: AppTheme.textSecondary(context),
                ),
              ),
              const SizedBox(height: 8),
              if (_sendResult?.transactionId != null)
                Text(
                  'Transaction ID: ${_sendResult!.transactionId!.length > 12 ? '${_sendResult!.transactionId!.substring(0, 12)}...' : _sendResult!.transactionId}',
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: AppTheme.textMuted(context),
                  ),
                ),
              // ✅ Stellar Explorer link for GNS transactions
              if (_selectedCurrency == 'GNS' && _sendResult?.transactionId != null) ...[
                const SizedBox(height: 16),
                TextButton.icon(
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('View on Stellar Explorer'),
                  onPressed: () {
                    final network = StellarConfig.useTestnet ? 'testnet' : 'public';
                    final url = 'https://stellar.expert/explorer/$network/tx/${_sendResult?.transactionId}';
                    debugPrint('Open: $url');
                    // TODO: Use url_launcher to open in browser
                  },
                ),
              ],
            ] else ...[
              Text(
                _sendResult?.error ?? 'Unknown error',
                style: TextStyle(
                  fontSize: 14,
                  color: AppTheme.error,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            
            const SizedBox(height: 40),
            
            // Actions
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: success ? AppTheme.primary : AppTheme.surface(context),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  success ? 'DONE' : 'CLOSE',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: success ? Colors.white : AppTheme.textPrimary(context),
                  ),
                ),
              ),
            ),
            
            if (!success) ...[
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => setState(() => _currentStep = 1),
                child: const Text('TRY AGAIN'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
