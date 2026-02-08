/// GNS Currency Swap Screen - Sprint 8
/// 
/// UI for swapping between Stellar assets via DEX.
/// 
/// Features:
/// - Asset selection with balance display
/// - Real-time rate quotes
/// - Slippage settings
/// - Swap confirmation
/// - Transaction status
/// 
/// Location: lib/screens/financial/currency_swap_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Import services (adjust path as needed)
// import '../../core/financial/multi_currency_service.dart';

class CurrencySwapScreen extends StatefulWidget {
  const CurrencySwapScreen({super.key});

  @override
  State<CurrencySwapScreen> createState() => _CurrencySwapScreenState();
}

class _CurrencySwapScreenState extends State<CurrencySwapScreen> {
  // final _currencyService = MultiCurrencyService();
  
  final _fromController = TextEditingController();
  final _toController = TextEditingController();
  
  String _fromAsset = 'XLM';
  String _toAsset = 'USDC';
  
  double? _fromBalance;
  double? _toBalance;
  
  // Quote state
  bool _isLoadingQuote = false;
  SwapQuoteData? _quote;
  String? _quoteError;
  
  // Swap state
  bool _isSwapping = false;
  
  // Settings
  double _slippageTolerance = 0.5; // 0.5%
  
  @override
  void initState() {
    super.initState();
    _loadBalances();
  }
  
  Future<void> _loadBalances() async {
    // Mock data - replace with actual service call
    setState(() {
      _fromBalance = 1000.0;
      _toBalance = 50.0;
    });
  }
  
  Future<void> _getQuote() async {
    final amount = double.tryParse(_fromController.text);
    if (amount == null || amount <= 0) {
      setState(() {
        _quote = null;
        _quoteError = null;
      });
      return;
    }
    
    setState(() {
      _isLoadingQuote = true;
      _quoteError = null;
    });
    
    try {
      // Mock quote - replace with actual service call
      await Future.delayed(const Duration(milliseconds: 500));
      
      final rate = _fromAsset == 'XLM' ? 0.12 : 8.33;
      final toAmount = amount * rate;
      final fee = amount * 0.001;
      
      setState(() {
        _quote = SwapQuoteData(
          quoteId: 'quote_${DateTime.now().millisecondsSinceEpoch}',
          fromAmount: amount,
          toAmount: toAmount,
          rate: rate,
          fee: fee,
          slippage: 0.1,
          expiresAt: DateTime.now().add(const Duration(seconds: 30)),
        );
        _toController.text = toAmount.toStringAsFixed(4);
        _isLoadingQuote = false;
      });
    } catch (e) {
      setState(() {
        _quoteError = 'Failed to get quote';
        _isLoadingQuote = false;
      });
    }
  }
  
  void _swapAssets() {
    HapticFeedback.lightImpact();
    
    final tempAsset = _fromAsset;
    final tempBalance = _fromBalance;
    final tempAmount = _fromController.text;
    
    setState(() {
      _fromAsset = _toAsset;
      _toAsset = tempAsset;
      _fromBalance = _toBalance;
      _toBalance = tempBalance;
      _fromController.text = _toController.text;
      _toController.text = tempAmount;
      _quote = null;
    });
    
    if (_fromController.text.isNotEmpty) {
      _getQuote();
    }
  }
  
  Future<void> _executeSwap() async {
    if (_quote == null) return;
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _SwapConfirmationDialog(
        fromAsset: _fromAsset,
        toAsset: _toAsset,
        fromAmount: _quote!.fromAmount,
        toAmount: _quote!.toAmount,
        rate: _quote!.rate,
        fee: _quote!.fee,
      ),
    );
    
    if (confirmed != true) return;
    
    setState(() => _isSwapping = true);
    
    try {
      // Mock swap - replace with actual service call
      await Future.delayed(const Duration(seconds: 2));
      
      HapticFeedback.heavyImpact();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 12),
                Text('Swapped ${_quote!.fromAmount} $_fromAsset → ${_quote!.toAmount.toStringAsFixed(4)} $_toAsset'),
              ],
            ),
            backgroundColor: Colors.green,
          ),
        );
        
        // Reset form
        _fromController.clear();
        _toController.clear();
        setState(() => _quote = null);
        
        // Reload balances
        _loadBalances();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Swap failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSwapping = false);
      }
    }
  }
  
  void _showSlippageSettings() {
    showModalBottomSheet(
      context: context,
      builder: (context) => _SlippageSettingsSheet(
        currentSlippage: _slippageTolerance,
        onSlippageChanged: (value) {
          setState(() => _slippageTolerance = value);
          Navigator.pop(context);
        },
      ),
    );
  }
  
  @override
  void dispose() {
    _fromController.dispose();
    _toController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Swap'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _showSlippageSettings,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // From asset
            _AssetInputCard(
              label: 'From',
              asset: _fromAsset,
              balance: _fromBalance,
              controller: _fromController,
              onAssetTap: () => _showAssetPicker(true),
              onChanged: (_) => _getQuote(),
              onMaxTap: () {
                _fromController.text = _fromBalance?.toString() ?? '0';
                _getQuote();
              },
            ),
            
            const SizedBox(height: 8),
            
            // Swap button
            Center(
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: IconButton(
                  icon: const Icon(Icons.swap_vert),
                  onPressed: _swapAssets,
                ),
              ),
            ),
            
            const SizedBox(height: 8),
            
            // To asset
            _AssetInputCard(
              label: 'To',
              asset: _toAsset,
              balance: _toBalance,
              controller: _toController,
              onAssetTap: () => _showAssetPicker(false),
              readOnly: true,
            ),
            
            const SizedBox(height: 24),
            
            // Quote details
            if (_isLoadingQuote)
              const Center(child: CircularProgressIndicator())
            else if (_quoteError != null)
              Text(
                _quoteError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
                textAlign: TextAlign.center,
              )
            else if (_quote != null)
              _QuoteDetailsCard(
                quote: _quote!,
                fromAsset: _fromAsset,
                toAsset: _toAsset,
              ),
            
            const SizedBox(height: 24),
            
            // Swap button
            FilledButton(
              onPressed: _quote != null && !_isSwapping ? _executeSwap : null,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isSwapping
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Swap'),
            ),
            
            const SizedBox(height: 16),
            
            // Slippage warning
            if (_quote != null && _quote!.slippage > _slippageTolerance)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber, color: Colors.orange),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Price impact is ${(_quote!.slippage * 100).toStringAsFixed(2)}%, '
                        'higher than your ${(_slippageTolerance * 100).toStringAsFixed(1)}% tolerance',
                        style: const TextStyle(color: Colors.orange),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
  
  void _showAssetPicker(bool isFrom) {
    showModalBottomSheet(
      context: context,
      builder: (context) => _AssetPickerSheet(
        selectedAsset: isFrom ? _fromAsset : _toAsset,
        excludeAsset: isFrom ? _toAsset : _fromAsset,
        onAssetSelected: (asset) {
          setState(() {
            if (isFrom) {
              _fromAsset = asset;
            } else {
              _toAsset = asset;
            }
            _quote = null;
          });
          Navigator.pop(context);
          if (_fromController.text.isNotEmpty) {
            _getQuote();
          }
        },
      ),
    );
  }
}

// Asset input card widget
class _AssetInputCard extends StatelessWidget {
  final String label;
  final String asset;
  final double? balance;
  final TextEditingController controller;
  final VoidCallback onAssetTap;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onMaxTap;
  final bool readOnly;
  
  const _AssetInputCard({
    required this.label,
    required this.asset,
    this.balance,
    required this.controller,
    required this.onAssetTap,
    this.onChanged,
    this.onMaxTap,
    this.readOnly = false,
  });
  
  String _getAssetSymbol(String code) {
    switch (code) {
      case 'XLM': return '✨';
      case 'USDC': return '\$';
      case 'EURC': return '€';
      case 'GNS': return '🌐';
      default: return code;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (balance != null)
                  Row(
                    children: [
                      Text(
                        'Balance: ${balance!.toStringAsFixed(2)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (onMaxTap != null) ...[
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: onMaxTap,
                          child: Text(
                            'MAX',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                // Asset selector
                GestureDetector(
                  onTap: onAssetTap,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _getAssetSymbol(asset),
                          style: const TextStyle(fontSize: 20),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          asset,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.keyboard_arrow_down, size: 20),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(width: 16),
                
                // Amount input
                Expanded(
                  child: TextField(
                    controller: controller,
                    readOnly: readOnly,
                    onChanged: onChanged,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                    decoration: const InputDecoration(
                      hintText: '0.00',
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// Quote details card
class _QuoteDetailsCard extends StatelessWidget {
  final SwapQuoteData quote;
  final String fromAsset;
  final String toAsset;
  
  const _QuoteDetailsCard({
    required this.quote,
    required this.fromAsset,
    required this.toAsset,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _DetailRow(
              label: 'Rate',
              value: '1 $fromAsset = ${quote.rate.toStringAsFixed(4)} $toAsset',
            ),
            const Divider(),
            _DetailRow(
              label: 'Network Fee',
              value: '${quote.fee.toStringAsFixed(6)} $fromAsset',
            ),
            const Divider(),
            _DetailRow(
              label: 'Price Impact',
              value: '${(quote.slippage * 100).toStringAsFixed(2)}%',
              valueColor: quote.slippage > 0.01 ? Colors.orange : null,
            ),
            const Divider(),
            _DetailRow(
              label: 'You Receive',
              value: '${quote.toAmount.toStringAsFixed(4)} $toAsset',
              isBold: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool isBold;
  
  const _DetailRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.isBold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}

// Asset picker bottom sheet
class _AssetPickerSheet extends StatelessWidget {
  final String selectedAsset;
  final String excludeAsset;
  final ValueChanged<String> onAssetSelected;
  
  const _AssetPickerSheet({
    required this.selectedAsset,
    required this.excludeAsset,
    required this.onAssetSelected,
  });
  
  static const _assets = [
    {'code': 'XLM', 'name': 'Stellar Lumens', 'symbol': '✨'},
    {'code': 'USDC', 'name': 'USD Coin', 'symbol': '\$'},
    {'code': 'EURC', 'name': 'Euro Coin', 'symbol': '€'},
    {'code': 'GNS', 'name': 'GNS Token', 'symbol': '🌐'},
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Select Asset',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          ..._assets
              .where((a) => a['code'] != excludeAsset)
              .map((asset) => ListTile(
                    leading: Text(
                      asset['symbol']!,
                      style: const TextStyle(fontSize: 24),
                    ),
                    title: Text(asset['code']!),
                    subtitle: Text(asset['name']!),
                    trailing: asset['code'] == selectedAsset
                        ? const Icon(Icons.check, color: Colors.green)
                        : null,
                    onTap: () => onAssetSelected(asset['code']!),
                  )),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// Slippage settings bottom sheet
class _SlippageSettingsSheet extends StatefulWidget {
  final double currentSlippage;
  final ValueChanged<double> onSlippageChanged;
  
  const _SlippageSettingsSheet({
    required this.currentSlippage,
    required this.onSlippageChanged,
  });

  @override
  State<_SlippageSettingsSheet> createState() => _SlippageSettingsSheetState();
}

class _SlippageSettingsSheetState extends State<_SlippageSettingsSheet> {
  late double _slippage;
  final _customController = TextEditingController();
  
  @override
  void initState() {
    super.initState();
    _slippage = widget.currentSlippage;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Slippage Tolerance',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Your transaction will revert if the price changes unfavorably by more than this percentage.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              for (final value in [0.1, 0.5, 1.0])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text('${value}%'),
                    selected: _slippage == value,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() => _slippage = value);
                      }
                    },
                  ),
                ),
              Expanded(
                child: TextField(
                  controller: _customController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    hintText: 'Custom',
                    suffixText: '%',
                    isDense: true,
                  ),
                  onChanged: (value) {
                    final parsed = double.tryParse(value);
                    if (parsed != null) {
                      setState(() => _slippage = parsed);
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => widget.onSlippageChanged(_slippage),
              child: const Text('Save'),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// Swap confirmation dialog
class _SwapConfirmationDialog extends StatelessWidget {
  final String fromAsset;
  final String toAsset;
  final double fromAmount;
  final double toAmount;
  final double rate;
  final double fee;
  
  const _SwapConfirmationDialog({
    required this.fromAsset,
    required this.toAsset,
    required this.fromAmount,
    required this.toAmount,
    required this.rate,
    required this.fee,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Confirm Swap'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$fromAmount $fromAsset',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Icon(Icons.arrow_downward, size: 32),
          Text(
            '${toAmount.toStringAsFixed(4)} $toAsset',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Rate: 1 $fromAsset = ${rate.toStringAsFixed(4)} $toAsset',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Text(
            'Fee: ${fee.toStringAsFixed(6)} $fromAsset',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Confirm'),
        ),
      ],
    );
  }
}

// Mock quote data class
class SwapQuoteData {
  final String quoteId;
  final double fromAmount;
  final double toAmount;
  final double rate;
  final double fee;
  final double slippage;
  final DateTime expiresAt;
  
  SwapQuoteData({
    required this.quoteId,
    required this.fromAmount,
    required this.toAmount,
    required this.rate,
    required this.fee,
    required this.slippage,
    required this.expiresAt,
  });
}
