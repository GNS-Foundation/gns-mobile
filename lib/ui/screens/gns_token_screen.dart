// ===========================================
// GNS Token Screen - View and Claim Tokens (v3)
// ===========================================
// Full claim functionality with transaction signing
// v3: Added USDC/EURC balance display and claiming

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/gns/identity_wallet.dart';
import '../financial/stellar_service.dart';

class GnsTokenScreen extends StatefulWidget {
  const GnsTokenScreen({super.key});

  @override
  State<GnsTokenScreen> createState() => _GnsTokenScreenState();
}

class _GnsTokenScreenState extends State<GnsTokenScreen> {
  final _wallet = IdentityWallet();
  final _stellar = StellarService();
  
  bool _loading = true;
  bool _claiming = false;
  bool _accountExists = false;
  bool _hasTrustline = false;
  
  // Balances
  double _gnsBalance = 0.0;
  double _xlmBalance = 0.0;
  double _usdcBalance = 0.0;
  double _eurcBalance = 0.0;
  
  // Trustline status
  bool _hasUsdcTrustline = false;
  bool _hasEurcTrustline = false;
  
  List<ClaimableBalance> _claimableBalances = [];
  String? _stellarAddress;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final publicKey = _wallet.publicKey;
      if (publicKey == null) {
        setState(() {
          _error = 'No identity found. Create an identity first.';
          _loading = false;
        });
        return;
      }

      // Convert GNS key to Stellar address
      _stellarAddress = _stellar.gnsKeyToStellar(publicKey);
      debugPrint('Stellar address: $_stellarAddress');

      // Check if account exists on Stellar
      _accountExists = await _stellar.accountExists(_stellarAddress!);
      debugPrint('Account exists: $_accountExists');

      if (_accountExists) {
        // Get balances
        final balances = await _stellar.getBalances(_stellarAddress!);
        
        _hasTrustline = false;
        _hasUsdcTrustline = false;
        _hasEurcTrustline = false;
        _gnsBalance = 0.0;
        _xlmBalance = 0.0;
        _usdcBalance = 0.0;
        _eurcBalance = 0.0;
        
        for (final balance in balances) {
          if (balance.isNative) {
            _xlmBalance = balance.amount;
          } else if (balance.isGns) {
            _gnsBalance = balance.amount;
            _hasTrustline = true;
          } else if (balance.isUsdc) {
            _usdcBalance = balance.amount;
            _hasUsdcTrustline = true;
          } else if (balance.isEurc) {
            _eurcBalance = balance.amount;
            _hasEurcTrustline = true;
          }
        }
      }

      // Get ALL claimable balances (GNS, USDC, EURC)
      if (_stellarAddress != null) {
        _claimableBalances = await _stellar.getClaimableBalances(_stellarAddress!);
        debugPrint('Claimable balances: ${_claimableBalances.length}');
      }

      setState(() {
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load token data: $e';
        _loading = false;
      });
    }
  }

  Future<void> _fundAccount() async {
    if (_stellarAddress == null) return;

    setState(() => _loading = true);

    try {
      final success = await _stellar.fundAccountTestnet(_stellarAddress!);
      
      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Account funded with 10,000 XLM (testnet)'),
              backgroundColor: Colors.green,
            ),
          );
        }
        await _loadData();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ Failed to fund account'),
              backgroundColor: Colors.red,
            ),
          );
        }
        setState(() => _loading = false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      setState(() => _loading = false);
    }
  }

  Future<void> _claimTokens() async {
    if (_stellarAddress == null) return;
    
    final privateKey = _wallet.privateKeyBytes;
    if (privateKey == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Private key not available'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _claiming = true);

    try {
      // First create any missing trustlines
      debugPrint('🔐 Ensuring payment trustlines exist...');
      final trustResult = await _stellar.createAllPaymentTrustlines(
        stellarPublicKey: _stellarAddress!,
        privateKeyBytes: privateKey,
      );
      
      if (!trustResult.success && !trustResult.hash!.contains('already exist')) {
        debugPrint('⚠️ Trustline warning: ${trustResult.error}');
      }
      
      // Then claim all balances
      final result = await _stellar.claimAllGnsTokens(
        stellarPublicKey: _stellarAddress!,
        privateKeyBytes: privateKey,
      );

      if (result.success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ ${result.hash ?? "Tokens claimed!"}'),
              backgroundColor: Colors.green,
            ),
          );
        }
        await _loadData();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ ${result.error ?? "Claim failed"}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _claiming = false);
    }
  }

  void _copyAddress() {
    if (_stellarAddress != null) {
      Clipboard.setData(ClipboardData(text: _stellarAddress!));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Stellar address copied!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('GNS Tokens'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _loadData,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildErrorState()
              : _buildContent(),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loadData,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Stellar Address Card
          _buildAddressCard(),
          const SizedBox(height: 16),
          
          // Balance Card
          _buildBalanceCard(),
          const SizedBox(height: 16),
          
          // Claimable Balances
          if (_claimableBalances.isNotEmpty) ...[
            _buildClaimableCard(),
            const SizedBox(height: 16),
          ],
          
          // Actions
          _buildActionsCard(),
          
          // Network Info
          const SizedBox(height: 24),
          _buildNetworkInfo(),
        ],
      ),
    );
  }

  Widget _buildAddressCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.account_balance_wallet, color: Colors.blue),
                const SizedBox(width: 8),
                const Text(
                  'Your Stellar Wallet',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _accountExists ? Colors.green : Colors.orange,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _accountExists ? 'Active' : 'Inactive',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Same key as your GNS identity!',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: _copyAddress,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _stellarAddress ?? '',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(Icons.copy, size: 16, color: Colors.grey),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBalanceCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Balances',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            
            // GNS Balance
            _buildBalanceRow(
              icon: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF4CAF50), Color(0xFF2196F3)],
                  ),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Center(
                  child: Text('G', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 24)),
                ),
              ),
              code: 'GNS',
              name: _hasTrustline ? 'GNS Token' : 'No trustline',
              balance: _gnsBalance,
            ),
            
            const Divider(height: 32),
            
            // XLM Balance
            _buildBalanceRow(
              icon: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Center(
                  child: Text('XLM', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ),
              code: 'XLM',
              name: 'Stellar Lumens',
              balance: _xlmBalance,
            ),
            
            const Divider(height: 32),
            
            // USDC Balance
            _buildBalanceRow(
              icon: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFF2775CA),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Center(
                  child: Text('\$', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 24)),
                ),
              ),
              code: 'USDC',
              name: _hasUsdcTrustline ? 'USD Coin' : 'No trustline',
              balance: _usdcBalance,
              symbol: '\$',
            ),
            
            const Divider(height: 32),
            
            // EURC Balance
            _buildBalanceRow(
              icon: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFF1434CB),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Center(
                  child: Text('€', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 24)),
                ),
              ),
              code: 'EURC',
              name: _hasEurcTrustline ? 'Euro Coin' : 'No trustline',
              balance: _eurcBalance,
              symbol: '€',
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildBalanceRow({
    required Widget icon,
    required String code,
    required String name,
    required double balance,
    String? symbol,
  }) {
    return Row(
      children: [
        icon,
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(code, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Text(name, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
            ],
          ),
        ),
        Text(
          symbol != null ? '$symbol${balance.toStringAsFixed(2)}' : balance.toStringAsFixed(2),
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildClaimableCard() {
    // Group claimable balances by asset
    final Map<String, double> claimableByAsset = {};
    for (final cb in _claimableBalances) {
      final key = cb.assetCode;
      claimableByAsset[key] = (claimableByAsset[key] ?? 0) + (double.tryParse(cb.amount) ?? 0);
    }
    
    // Build summary string
    final summaryParts = <String>[];
    claimableByAsset.forEach((code, amount) {
      if (code == 'USDC') {
        summaryParts.add('\$${amount.toStringAsFixed(2)}');
      } else if (code == 'EURC') {
        summaryParts.add('€${amount.toStringAsFixed(2)}');
      } else {
        summaryParts.add('${amount.toStringAsFixed(0)} $code');
      }
    });
    final summaryText = summaryParts.join(' + ');

    return Card(
      color: Colors.amber[50],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.card_giftcard, color: Colors.amber),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Claimable Tokens',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.amber,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    summaryText,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '${_claimableBalances.length} pending claim(s)',
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _claiming ? null : _claimTokens,
                icon: _claiming 
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black,
                        ),
                      )
                    : const Icon(Icons.download),
                label: Text(_claiming ? 'Claiming...' : 'Claim Tokens'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Actions',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            
            if (!_accountExists) ...[
              if (StellarConfig.useTestnet) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _fundAccount,
                    icon: const Icon(Icons.account_balance),
                    label: const Text('Fund Account (Testnet)'),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Get 10,000 XLM to activate your Stellar wallet',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange[200]!),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.info_outline, color: Colors.orange[700]),
                      const SizedBox(height: 8),
                      Text(
                        'Account needs XLM to activate',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange[700]),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Claim a @handle to receive 2 XLM + 200 GNS airdrop',
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ],
            ] else ...[
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _copyAddress,
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy Stellar Address'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildNetworkInfo() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.circle,
            size: 8,
            color: StellarConfig.useTestnet ? Colors.orange : Colors.green,
          ),
          const SizedBox(width: 8),
          Text(
            StellarConfig.useTestnet ? 'Stellar Testnet' : 'Stellar Mainnet',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
