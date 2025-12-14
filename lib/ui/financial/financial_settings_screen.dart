/// GNS Financial Settings Screen
/// 
/// Payment endpoints, limits, and preferences configuration.
/// Location: lib/ui/financial/financial_settings_screen.dart

import 'package:flutter/material.dart';
import '../../core/theme/theme_service.dart';
import '../../core/financial/payment_service.dart';
import '../../core/financial/financial_module.dart';
import '../../core/gns/identity_wallet.dart';

class FinancialSettingsScreen extends StatefulWidget {
  const FinancialSettingsScreen({super.key});

  @override
  State<FinancialSettingsScreen> createState() => _FinancialSettingsScreenState();
}

class _FinancialSettingsScreenState extends State<FinancialSettingsScreen> {
  PaymentService? _paymentService;
  FinancialData? _financialData;
  bool _isLoading = true;
  bool _isSaving = false;
  
  // Track which endpoint is default (by index)
  int _defaultEndpointIndex = 0;

  @override
  void initState() {
    super.initState();
    _initAndLoad();
  }

  Future<void> _initAndLoad() async {
    try {
      final wallet = IdentityWallet();
      await wallet.initialize();
      _paymentService = PaymentService.instance(wallet);
      await _paymentService!.initialize();
      
      _financialData = _paymentService!.myFinancialData ?? FinancialData();
      
      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('Error initializing: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payment Settings'),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            TextButton(
              onPressed: _saveSettings,
              child: const Text('SAVE'),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Payment Endpoints Section
                _buildEndpointsSection(),
                const SizedBox(height: 24),
                
                // Limits Section
                _buildLimitsSection(),
                const SizedBox(height: 24),
                
                // Preferences Section
                _buildPreferencesSection(),
              ],
            ),
    );
  }

  Widget _buildEndpointsSection() {
    final endpoints = _financialData?.paymentEndpoints ?? [];
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.credit_card, color: AppTheme.primary),
                    const SizedBox(width: 12),
                    const Text(
                      'PAYMENT METHODS',
                      style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle, color: AppTheme.primary),
                  onPressed: _addEndpoint,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Configure how you can send and receive payments',
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.textMuted(context),
              ),
            ),
            const SizedBox(height: 16),
            
            if (endpoints.isEmpty)
              _buildEmptyEndpoints()
            else
              ...endpoints.asMap().entries.map((entry) => 
                _buildEndpointTile(entry.value, entry.key)),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyEndpoints() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.warning.withOpacity(0.3),
          style: BorderStyle.solid,
        ),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.warning_amber,
            size: 32,
            color: AppTheme.warning,
          ),
          const SizedBox(height: 12),
          const Text(
            'No payment methods configured',
            style: TextStyle(fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 4),
          Text(
            'Add at least one method to receive payments',
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.textMuted(context),
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _addEndpoint,
            icon: const Icon(Icons.add),
            label: const Text('Add Payment Method'),
          ),
        ],
      ),
    );
  }

  Widget _buildEndpointTile(PaymentEndpoint endpoint, int index) {
    final isDefault = index == _defaultEndpointIndex;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border(context)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _getEndpointColor(endpoint.type).withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              endpoint.icon,
              style: const TextStyle(fontSize: 20),
            ),
          ),
        ),
        title: Text(
          endpoint.displayName,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          _formatEndpointValue(endpoint),
          style: TextStyle(
            fontSize: 12,
            color: AppTheme.textMuted(context),
            fontFamily: 'monospace',
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isDefault)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.secondary,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'DEFAULT',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            PopupMenuButton<String>(
              onSelected: (value) => _handleEndpointAction(value, index),
              itemBuilder: (context) => [
                if (!isDefault)
                  const PopupMenuItem(
                    value: 'default',
                    child: Text('Set as Default'),
                  ),
                const PopupMenuItem(
                  value: 'edit',
                  child: Text('Edit'),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete', style: TextStyle(color: AppTheme.error)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _getEndpointColor(String type) {
    switch (type.toLowerCase()) {
      case 'sepa_iban':
      case 'swift_account':
        return AppTheme.primary;
      case 'lightning_lnurl':
      case 'lightning_address':
        return AppTheme.warning;
      case 'eth_address':
      case 'evm_token':
        return const Color(0xFF627EEA);
      case 'sol_address':
        return const Color(0xFF9945FF);
      case 'btc_address':
        return const Color(0xFFF7931A);
      default:
        return AppTheme.textMuted(context);
    }
  }

  String _formatEndpointValue(PaymentEndpoint endpoint) {
    final value = endpoint.value;
    if (value.length > 24) {
      return '${value.substring(0, 12)}...${value.substring(value.length - 8)}';
    }
    return value;
  }

  void _handleEndpointAction(String action, int index) {
    switch (action) {
      case 'default':
        setState(() => _defaultEndpointIndex = index);
        break;
      case 'edit':
        _editEndpoint(index);
        break;
      case 'delete':
        _deleteEndpoint(index);
        break;
    }
  }

  void _editEndpoint(int index) {
    final endpoint = _financialData!.paymentEndpoints[index];
    _showEndpointEditor(existingEndpoint: endpoint, index: index);
  }

  void _deleteEndpoint(int index) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Payment Method?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                _financialData = _financialData!.removeEndpoint(
                  _financialData!.paymentEndpoints[index].id,
                );
                if (_defaultEndpointIndex >= _financialData!.paymentEndpoints.length) {
                  _defaultEndpointIndex = 0;
                }
              });
            },
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
  }

  void _addEndpoint() {
    _showEndpointEditor();
  }

  void _showEndpointEditor({PaymentEndpoint? existingEndpoint, int? index}) {
    final valueController = TextEditingController(text: existingEndpoint?.value ?? '');
    final labelController = TextEditingController(text: existingEndpoint?.label ?? '');
    String selectedType = existingEndpoint?.type ?? PaymentEndpointType.sepaIban;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.fromLTRB(
            24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                existingEndpoint != null ? 'Edit Payment Method' : 'Add Payment Method',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 24),
              
              // Type selector
              Text(
                'TYPE',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textMuted(ctx),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  PaymentEndpointType.sepaIban,
                  PaymentEndpointType.lightningAddress,
                  PaymentEndpointType.ethAddress,
                  PaymentEndpointType.solAddress,
                  PaymentEndpointType.btcAddress,
                ].map((type) =>
                  ChoiceChip(
                    label: Text(PaymentEndpointType.displayName(type)),
                    selected: selectedType == type,
                    onSelected: (selected) {
                      if (selected) {
                        setModalState(() => selectedType = type);
                      }
                    },
                    avatar: Text(
                      PaymentEndpointType.icon(type),
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ).toList(),
              ),
              const SizedBox(height: 16),
              
              // Value input
              Text(
                _getValueLabel(selectedType),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textMuted(ctx),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: valueController,
                decoration: InputDecoration(
                  hintText: _getValueHint(selectedType),
                ),
              ),
              const SizedBox(height: 16),
              
              // Label input
              Text(
                'LABEL (OPTIONAL)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textMuted(ctx),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: labelController,
                decoration: const InputDecoration(
                  hintText: 'e.g., Personal Account',
                ),
              ),
              const SizedBox(height: 24),
              
              // Save button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () {
                    final value = valueController.text.trim();
                    if (value.isEmpty) {
                      Navigator.pop(ctx);
                      return;
                    }
                    
                    final label = labelController.text.trim().isEmpty 
                        ? null 
                        : labelController.text.trim();
                    final currency = _getCurrencyForType(selectedType);
                    
                    final newEndpoint = PaymentEndpoint(
                      id: existingEndpoint?.id ?? '${selectedType}_${value.hashCode.abs()}',
                      type: selectedType,
                      currency: currency,
                      value: value,
                      label: label,
                      chain: selectedType == PaymentEndpointType.ethAddress ? 'ethereum' : null,
                    );
                    
                    setState(() {
                      if (index != null) {
                        // Update existing - remove old, add new
                        _financialData = _financialData!
                            .removeEndpoint(existingEndpoint!.id)
                            .addEndpoint(newEndpoint);
                      } else {
                        // Add new
                        _financialData = _financialData!.addEndpoint(newEndpoint);
                      }
                    });
                    
                    Navigator.pop(ctx);
                  },
                  child: Text(existingEndpoint != null ? 'UPDATE' : 'ADD'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getValueLabel(String type) {
    switch (type) {
      case PaymentEndpointType.sepaIban:
        return 'IBAN';
      case PaymentEndpointType.lightningAddress:
        return 'LIGHTNING ADDRESS';
      case PaymentEndpointType.ethAddress:
        return 'ETH ADDRESS';
      case PaymentEndpointType.solAddress:
        return 'SOL ADDRESS';
      case PaymentEndpointType.btcAddress:
        return 'BTC ADDRESS';
      default:
        return 'ADDRESS';
    }
  }

  String _getValueHint(String type) {
    switch (type) {
      case PaymentEndpointType.sepaIban:
        return 'DE89 3704 0044 0532 0130 00';
      case PaymentEndpointType.lightningAddress:
        return 'username@wallet.com';
      case PaymentEndpointType.ethAddress:
        return '0x...';
      case PaymentEndpointType.solAddress:
        return 'So1...';
      case PaymentEndpointType.btcAddress:
        return 'bc1...';
      default:
        return 'Enter address';
    }
  }

  String _getCurrencyForType(String type) {
    switch (type) {
      case PaymentEndpointType.sepaIban:
        return 'EUR';
      case PaymentEndpointType.lightningAddress:
      case PaymentEndpointType.btcAddress:
        return 'BTC';
      case PaymentEndpointType.ethAddress:
        return 'ETH';
      case PaymentEndpointType.solAddress:
        return 'SOL';
      default:
        return 'EUR';
    }
  }

  Widget _buildLimitsSection() {
    final limits = _financialData?.limits ?? PaymentLimits();
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.speed, color: AppTheme.primary),
                const SizedBox(width: 12),
                const Text(
                  'DAILY LIMITS',
                  style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Soft limit
            _buildLimitTile(
              label: 'Soft Limit (Warning)',
              value: limits.dailySoftLimit,
              onChanged: (value) {
                setState(() {
                  _financialData = _financialData!.copyWith(
                    limits: limits.copyWith(dailySoftLimit: value ?? 200.0),
                  );
                });
              },
            ),
            const SizedBox(height: 12),
            
            // Hard limit
            _buildLimitTile(
              label: 'Hard Limit (Block)',
              value: limits.dailyHardLimit,
              onChanged: (value) {
                setState(() {
                  _financialData = _financialData!.copyWith(
                    limits: limits.copyWith(dailyHardLimit: value ?? 1000.0),
                  );
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLimitTile({
    required String label,
    required double value,
    required Function(double?) onChanged,
  }) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
              Text(
                '€${value.toStringAsFixed(0)}',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textMuted(context),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          width: 120,
          child: TextField(
            decoration: const InputDecoration(
              prefixText: '€ ',
              isDense: true,
            ),
            keyboardType: TextInputType.number,
            controller: TextEditingController(
              text: value.toStringAsFixed(0),
            ),
            onChanged: (text) {
              final newValue = double.tryParse(text);
              onChanged(newValue);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPreferencesSection() {
    final settings = _financialData?.settings ?? PaymentSettings();
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.tune, color: AppTheme.primary),
                const SizedBox(width: 12),
                const Text(
                  'PREFERENCES',
                  style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Auto-accept
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Auto-accept small payments'),
              subtitle: Text(
                settings.autoAcceptSmallPayments
                    ? 'Up to €${settings.smallPaymentThreshold.toStringAsFixed(0)}'
                    : 'All payments require manual approval',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textMuted(context),
                ),
              ),
              value: settings.autoAcceptSmallPayments,
              onChanged: (enabled) {
                setState(() {
                  _financialData = _financialData!.copyWith(
                    settings: PaymentSettings(
                      autoAcceptSmallPayments: enabled,
                      smallPaymentThreshold: settings.smallPaymentThreshold,
                      requirePresence: settings.requirePresence,
                      presenceRadiusMeters: settings.presenceRadiusMeters,
                    ),
                  );
                });
              },
            ),
            
            if (settings.autoAcceptSmallPayments) ...[
              Slider(
                value: settings.smallPaymentThreshold,
                min: 1,
                max: 100,
                divisions: 99,
                label: '€${settings.smallPaymentThreshold.toStringAsFixed(0)}',
                onChanged: (value) {
                  setState(() {
                    _financialData = _financialData!.copyWith(
                      settings: PaymentSettings(
                        autoAcceptSmallPayments: settings.autoAcceptSmallPayments,
                        smallPaymentThreshold: value,
                        requirePresence: settings.requirePresence,
                        presenceRadiusMeters: settings.presenceRadiusMeters,
                      ),
                    );
                  });
                },
              ),
            ],
            
            const Divider(),
            
            // Require presence
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Require presence for large payments'),
              subtitle: Text(
                'Must drop breadcrumb to authorize',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textMuted(context),
                ),
              ),
              value: settings.requirePresence,
              onChanged: (enabled) {
                setState(() {
                  _financialData = _financialData!.copyWith(
                    settings: PaymentSettings(
                      autoAcceptSmallPayments: settings.autoAcceptSmallPayments,
                      smallPaymentThreshold: settings.smallPaymentThreshold,
                      requirePresence: enabled,
                      presenceRadiusMeters: settings.presenceRadiusMeters,
                    ),
                  );
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveSettings() async {
    if (_paymentService == null || _financialData == null) return;
    
    setState(() => _isSaving = true);
    
    try {
      await _paymentService!.saveFinancialData(_financialData!);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Settings saved'),
            backgroundColor: AppTheme.secondary,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
    
    setState(() => _isSaving = false);
  }
}
