// ===========================================
// GNS Token Layer - Stellar Service (v5 - STABLECOINS)
// ===========================================
// Full Stellar integration with transaction signing
// v5: Added USDC/EURC stablecoin support for payments
//
// Supported Assets:
// - XLM (native)
// - GNS (GNS Protocol token)
// - USDC (Circle USD stablecoin)
// - EURC (Circle EUR stablecoin)

import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:stellar_flutter_sdk/stellar_flutter_sdk.dart';

/// Supported stablecoin types
enum Stablecoin {
  usdc,
  eurc,
}

/// Stellar network configuration
class StellarConfig {
  // Testnet
  static const String horizonTestnet = 'https://horizon-testnet.stellar.org';
  static const String networkPassphraseTestnet = 'Test SDF Network ; September 2015';
  
  // Mainnet (for production)
  static const String horizonMainnet = 'https://horizon.stellar.org';
  static const String networkPassphraseMainnet = 'Public Global Stellar Network ; September 2015';
  
  // GNS Token Configuration (MAINNET)
  static const String gnsTokenCode = 'GNS';
  static const String gnsIssuerPublic = 'GBVZTFST4PIPV5C3APDIVULNZYZENQSLGDSOKOVQI77GSMT6WVYGF5GL';
  
  // ===========================================
  // STABLECOIN CONFIGURATION (Circle on Stellar)
  // ===========================================
  
  // USDC - Circle USD Coin on Stellar (MAINNET)
  static const String usdcCode = 'USDC';
  static const String usdcIssuer = 'GA5ZSEJYB37JRC5AVCIA5MOP4RHTM335X2KGX3IHOJAPP5RE34K4KZVN';
  
  // EURC - Circle Euro Coin on Stellar (MAINNET)
  static const String eurcCode = 'EURC';
  static const String eurcIssuer = 'GDHU6WRG4IEQXM5NZ4BMPKOXHW76MZM4Y2IEMFDVXBSDP6SJY4ITNPP2';
  
  // USDC on Testnet (different issuer)
  static const String usdcIssuerTestnet = 'GBBD47IF6LWK7P7MDEVSCWR7DPUWV3NY3DTQEVFL4NAT4AQH3ZLLFLA5';
  
  // Starting balance for new accounts
  static const String startingBalanceXlm = '1.5';
  
  // Network selection - FALSE = MAINNET
  static bool useTestnet = false;
  
  static String get horizonUrl => useTestnet ? horizonTestnet : horizonMainnet;
  static Network get network => useTestnet ? Network.TESTNET : Network.PUBLIC;
  
  /// Get USDC issuer based on network
  static String get usdcIssuerAddress => useTestnet ? usdcIssuerTestnet : usdcIssuer;
  
  /// Get asset code and issuer for a stablecoin
  static (String code, String issuer) getStablecoinConfig(Stablecoin coin) {
    switch (coin) {
      case Stablecoin.usdc:
        return (usdcCode, usdcIssuerAddress);
      case Stablecoin.eurc:
        return (eurcCode, eurcIssuer);
    }
  }
  
  /// Get stablecoin from string code
  static Stablecoin? stablecoinFromCode(String code) {
    switch (code.toUpperCase()) {
      case 'USDC':
        return Stablecoin.usdc;
      case 'EURC':
        return Stablecoin.eurc;
      default:
        return null;
    }
  }
}

/// Result classes
class StellarBalance {
  final String assetCode;
  final String assetIssuer;
  final String balance;
  final bool isNative;
  
  StellarBalance({
    required this.assetCode,
    this.assetIssuer = '',
    required this.balance,
    this.isNative = false,
  });
  
  double get amount => double.tryParse(balance) ?? 0.0;
  
  /// Check if this is a USDC balance
  bool get isUsdc => assetCode == StellarConfig.usdcCode && 
    (assetIssuer == StellarConfig.usdcIssuer || assetIssuer == StellarConfig.usdcIssuerTestnet);
  
  /// Check if this is a EURC balance
  bool get isEurc => assetCode == StellarConfig.eurcCode && assetIssuer == StellarConfig.eurcIssuer;
  
  /// Check if this is a GNS balance
  bool get isGns => assetCode == StellarConfig.gnsTokenCode && assetIssuer == StellarConfig.gnsIssuerPublic;
  
  /// Get currency symbol for display
  String get symbol {
    if (isNative) return 'XLM';
    if (isUsdc) return '\$';
    if (isEurc) return '€';
    if (isGns) return 'GNS';
    return assetCode;
  }
  
  /// Format balance for display
  String get displayBalance {
    if (isUsdc || isEurc) {
      return '$symbol${amount.toStringAsFixed(2)}';
    }
    return '${amount.toStringAsFixed(2)} $assetCode';
  }
  
  @override
  String toString() => '$assetCode: $balance';
}

class ClaimableBalance {
  final String balanceId;
  final String assetCode;
  final String assetIssuer;
  final String amount;
  final String sponsor;
  
  ClaimableBalance({
    required this.balanceId,
    required this.assetCode,
    required this.assetIssuer,
    required this.amount,
    required this.sponsor,
  });
}

class TransactionResult {
  final bool success;
  final String? hash;
  final String? error;
  
  TransactionResult({required this.success, this.hash, this.error});
}

/// Payment result with additional details
class PaymentResult extends TransactionResult {
  final String? senderAddress;
  final String? recipientAddress;
  final double? amount;
  final String? assetCode;
  final DateTime? timestamp;
  
  PaymentResult({
    required bool success,
    String? hash,
    String? error,
    this.senderAddress,
    this.recipientAddress,
    this.amount,
    this.assetCode,
    this.timestamp,
  }) : super(success: success, hash: hash, error: error);
}

class StellarService {
  static final StellarService _instance = StellarService._internal();
  factory StellarService() => _instance;
  StellarService._internal();
  
  late final StellarSDK _sdk;
  bool _initialized = false;
  
  /// Initialize the SDK
  void _ensureInitialized() {
    if (!_initialized) {
      _sdk = StellarSDK(StellarConfig.horizonUrl);
      _initialized = true;
    }
  }
  
  /// Convert GNS hex public key to Stellar G... format
  String gnsKeyToStellar(String gnsHexPublicKey) {
    final cleanHex = gnsHexPublicKey.replaceAll('0x', '').toLowerCase();
    
    if (cleanHex.length != 64) {
      throw ArgumentError('Invalid GNS public key length: ${cleanHex.length}, expected 64');
    }
    
    final publicKeyBytes = _hexToBytes(cleanHex);
    return KeyPair.fromPublicKey(publicKeyBytes).accountId;
  }
  
  /// Convert GNS hex private key to Stellar KeyPair
  KeyPair gnsPrivateKeyToStellarKeyPair(String gnsHexPrivateKey) {
    final cleanHex = gnsHexPrivateKey.replaceAll('0x', '').toLowerCase();
    
    // GNS stores 64-byte private key (seed + public), Stellar needs 32-byte seed
    final privateKeyBytes = _hexToBytes(cleanHex);
    final seedBytes = privateKeyBytes.sublist(0, 32);
    
    return KeyPair.fromSecretSeedList(seedBytes);
  }
  
  // ==================== ACCOUNT OPERATIONS ====================
  
  /// Check if Stellar account exists
  Future<bool> accountExists(String stellarPublicKey) async {
    _ensureInitialized();
    try {
      await _sdk.accounts.account(stellarPublicKey);
      return true;
    } catch (e) {
      return false;
    }
  }
  
  /// Fund account via Friendbot (testnet only)
  Future<bool> fundAccountTestnet(String stellarPublicKey) async {
    if (!StellarConfig.useTestnet) {
      throw Exception('Friendbot only works on testnet');
    }
    
    _ensureInitialized();
    try {
      final funded = await FriendBot.fundTestAccount(stellarPublicKey);
      debugPrint('Account funded via Friendbot: $funded');
      return funded;
    } catch (e) {
      debugPrint('Friendbot failed: $e');
      return false;
    }
  }
  
  /// Fund account - TESTNET ONLY
  Future<TransactionResult> fundAccount(String stellarPublicKey) async {
    if (StellarConfig.useTestnet) {
      final success = await fundAccountTestnet(stellarPublicKey);
      return TransactionResult(
        success: success,
        error: success ? null : 'Friendbot failed',
      );
    } else {
      debugPrint('❌ Cannot fund account on mainnet from client');
      return TransactionResult(
        success: false,
        error: 'Claim a @handle to activate your wallet with XLM',
      );
    }
  }
  
  /// Get account balances
  Future<List<StellarBalance>> getBalances(String stellarPublicKey) async {
    _ensureInitialized();
    try {
      final account = await _sdk.accounts.account(stellarPublicKey);
      
      return account.balances.map((b) {
        if (b.assetType == Asset.TYPE_NATIVE) {
          return StellarBalance(
            assetCode: 'XLM',
            balance: b.balance,
            isNative: true,
          );
        } else {
          return StellarBalance(
            assetCode: b.assetCode ?? '',
            assetIssuer: b.assetIssuer ?? '',
            balance: b.balance,
          );
        }
      }).toList();
    } catch (e) {
      debugPrint('Failed to get balances: $e');
      return [];
    }
  }
  
  // ==================== GNS TOKEN OPERATIONS ====================
  
  /// Get GNS token balance
  Future<double> getGnsBalance(String stellarPublicKey) async {
    final balances = await getBalances(stellarPublicKey);
    
    for (final balance in balances) {
      if (balance.isGns) {
        return balance.amount;
      }
    }
    
    return 0.0;
  }
  
  /// Check if account has GNS trustline
  Future<bool> hasGnsTrustline(String stellarPublicKey) async {
    final balances = await getBalances(stellarPublicKey);
    return balances.any((b) => b.isGns);
  }
  
  /// Create GNS trustline
  Future<TransactionResult> createGnsTrustline({
    required String stellarPublicKey,
    required Uint8List privateKeyBytes,
  }) async {
    return _createTrustline(
      stellarPublicKey: stellarPublicKey,
      privateKeyBytes: privateKeyBytes,
      assetCode: StellarConfig.gnsTokenCode,
      assetIssuer: StellarConfig.gnsIssuerPublic,
    );
  }
  
  // ===========================================
  // STABLECOIN OPERATIONS (USDC/EURC)
  // ===========================================
  
  /// Get stablecoin balance (USDC or EURC)
  Future<double> getStablecoinBalance(String stellarPublicKey, Stablecoin coin) async {
    final balances = await getBalances(stellarPublicKey);
    final (code, issuer) = StellarConfig.getStablecoinConfig(coin);
    
    for (final balance in balances) {
      if (balance.assetCode == code && balance.assetIssuer == issuer) {
        return balance.amount;
      }
    }
    
    return 0.0;
  }
  
  /// Get USDC balance specifically
  Future<double> getUsdcBalance(String stellarPublicKey) async {
    return getStablecoinBalance(stellarPublicKey, Stablecoin.usdc);
  }
  
  /// Get EURC balance specifically
  Future<double> getEurcBalance(String stellarPublicKey) async {
    return getStablecoinBalance(stellarPublicKey, Stablecoin.eurc);
  }
  
  /// Get all stablecoin balances
  Future<Map<Stablecoin, double>> getAllStablecoinBalances(String stellarPublicKey) async {
    final balances = await getBalances(stellarPublicKey);
    
    return {
      Stablecoin.usdc: balances.where((b) => b.isUsdc).fold(0.0, (sum, b) => sum + b.amount),
      Stablecoin.eurc: balances.where((b) => b.isEurc).fold(0.0, (sum, b) => sum + b.amount),
    };
  }
  
  /// Check if account has stablecoin trustline
  Future<bool> hasStablecoinTrustline(String stellarPublicKey, Stablecoin coin) async {
    final balances = await getBalances(stellarPublicKey);
    final (code, issuer) = StellarConfig.getStablecoinConfig(coin);
    
    return balances.any((b) => b.assetCode == code && b.assetIssuer == issuer);
  }
  
  /// Check if account has USDC trustline
  Future<bool> hasUsdcTrustline(String stellarPublicKey) async {
    return hasStablecoinTrustline(stellarPublicKey, Stablecoin.usdc);
  }
  
  /// Check if account has EURC trustline
  Future<bool> hasEurcTrustline(String stellarPublicKey) async {
    return hasStablecoinTrustline(stellarPublicKey, Stablecoin.eurc);
  }
  
  /// Create stablecoin trustline (USDC or EURC)
  Future<TransactionResult> createStablecoinTrustline({
    required String stellarPublicKey,
    required Uint8List privateKeyBytes,
    required Stablecoin coin,
  }) async {
    final (code, issuer) = StellarConfig.getStablecoinConfig(coin);
    
    debugPrint('Creating ${coin.name.toUpperCase()} trustline...');
    
    return _createTrustline(
      stellarPublicKey: stellarPublicKey,
      privateKeyBytes: privateKeyBytes,
      assetCode: code,
      assetIssuer: issuer,
    );
  }
  
  /// Create USDC trustline
  Future<TransactionResult> createUsdcTrustline({
    required String stellarPublicKey,
    required Uint8List privateKeyBytes,
  }) async {
    return createStablecoinTrustline(
      stellarPublicKey: stellarPublicKey,
      privateKeyBytes: privateKeyBytes,
      coin: Stablecoin.usdc,
    );
  }
  
  /// Create EURC trustline
  Future<TransactionResult> createEurcTrustline({
    required String stellarPublicKey,
    required Uint8List privateKeyBytes,
  }) async {
    return createStablecoinTrustline(
      stellarPublicKey: stellarPublicKey,
      privateKeyBytes: privateKeyBytes,
      coin: Stablecoin.eurc,
    );
  }
  
  /// Create all payment trustlines (USDC + EURC + GNS)
  Future<TransactionResult> createAllPaymentTrustlines({
    required String stellarPublicKey,
    required Uint8List privateKeyBytes,
  }) async {
    _ensureInitialized();
    
    try {
      // Check which trustlines are needed
      final hasUsdc = await hasUsdcTrustline(stellarPublicKey);
      final hasEurc = await hasEurcTrustline(stellarPublicKey);
      final hasGns = await hasGnsTrustline(stellarPublicKey);
      
      if (hasUsdc && hasEurc && hasGns) {
        return TransactionResult(success: true, hash: 'All trustlines already exist');
      }
      
      // Create keypair
      final seedBytes = privateKeyBytes.sublist(0, 32);
      final keyPair = KeyPair.fromSecretSeedList(seedBytes);
      
      // Load account
      final account = await _sdk.accounts.account(stellarPublicKey);
      
      // Build transaction with all needed trustlines
      final txBuilder = TransactionBuilder(account);
      
      if (!hasUsdc) {
        final (usdcCode, usdcIssuer) = StellarConfig.getStablecoinConfig(Stablecoin.usdc);
        final usdcAsset = Asset.createNonNativeAsset(usdcCode, usdcIssuer);
        txBuilder.addOperation(ChangeTrustOperationBuilder(usdcAsset, '922337203685.4775807').build());
        debugPrint('Adding USDC trustline...');
      }
      
      if (!hasEurc) {
        final (eurcCode, eurcIssuer) = StellarConfig.getStablecoinConfig(Stablecoin.eurc);
        final eurcAsset = Asset.createNonNativeAsset(eurcCode, eurcIssuer);
        txBuilder.addOperation(ChangeTrustOperationBuilder(eurcAsset, '922337203685.4775807').build());
        debugPrint('Adding EURC trustline...');
      }
      
      if (!hasGns) {
        final gnsAsset = Asset.createNonNativeAsset(StellarConfig.gnsTokenCode, StellarConfig.gnsIssuerPublic);
        txBuilder.addOperation(ChangeTrustOperationBuilder(gnsAsset, '922337203685.4775807').build());
        debugPrint('Adding GNS trustline...');
      }
      
      // Build and sign
      final transaction = txBuilder.build();
      transaction.sign(keyPair, StellarConfig.network);
      
      // Submit
      final response = await _sdk.submitTransaction(transaction);
      
      if (response.success) {
        debugPrint('✅ All trustlines created! Hash: ${response.hash}');
        return TransactionResult(success: true, hash: response.hash);
      } else {
        final error = response.extras?.resultCodes?.operationsResultCodes?.join(', ') ?? 'Unknown error';
        debugPrint('❌ Trustline creation failed: $error');
        return TransactionResult(success: false, error: error);
      }
    } catch (e) {
      debugPrint('❌ Trustline error: $e');
      return TransactionResult(success: false, error: e.toString());
    }
  }
  
  /// Send stablecoin (USDC or EURC) to another user
  /// This is the main payment method for GNS payments!
  Future<PaymentResult> sendStablecoin({
    required String senderStellarPublicKey,
    required Uint8List senderPrivateKeyBytes,
    required String recipientStellarPublicKey,
    required double amount,
    required Stablecoin coin,
    String? memo,
  }) async {
    _ensureInitialized();
    
    final (assetCode, assetIssuer) = StellarConfig.getStablecoinConfig(coin);
    final symbol = coin == Stablecoin.usdc ? '\$' : '€';
    
    try {
      debugPrint('💸 Sending $symbol${amount.toStringAsFixed(2)} ${coin.name.toUpperCase()}');
      debugPrint('   From: $senderStellarPublicKey');
      debugPrint('   To: $recipientStellarPublicKey');
      
      // Create keypair from private key bytes
      final seedBytes = senderPrivateKeyBytes.sublist(0, 32);
      final keyPair = KeyPair.fromSecretSeedList(seedBytes);
      
      // Load sender account
      final account = await _sdk.accounts.account(senderStellarPublicKey);
      
      // Check sender balance
      final balance = await getStablecoinBalance(senderStellarPublicKey, coin);
      if (balance < amount) {
        return PaymentResult(
          success: false,
          error: 'Insufficient ${coin.name.toUpperCase()} balance. You have $symbol${balance.toStringAsFixed(2)}.',
        );
      }
      
      // Check if recipient exists
      final recipientExists = await accountExists(recipientStellarPublicKey);
      if (!recipientExists) {
        return PaymentResult(
          success: false,
          error: 'Recipient account does not exist. They need to claim a @handle first.',
        );
      }
      
      // Check if recipient has trustline
      final recipientHasTrustline = await hasStablecoinTrustline(recipientStellarPublicKey, coin);
      
      // Create asset
      final asset = Asset.createNonNativeAsset(assetCode, assetIssuer);
      
      TransactionBuilder txBuilder;
      String successMessage;
      
      if (recipientHasTrustline) {
        // ✅ Direct payment - recipient has trustline
        txBuilder = TransactionBuilder(account)
            .addOperation(
              PaymentOperationBuilder(
                recipientStellarPublicKey,
                asset,
                amount.toStringAsFixed(7),
              ).build(),
            );
        successMessage = '${coin.name.toUpperCase()} sent!';
      } else {
        // ✅ Claimable balance - recipient doesn't have trustline yet
        debugPrint('Recipient has no ${coin.name.toUpperCase()} trustline, using claimable balance...');
        
        final claimant = Claimant(recipientStellarPublicKey, Claimant.predicateUnconditional());
        
        txBuilder = TransactionBuilder(account)
            .addOperation(
              CreateClaimableBalanceOperationBuilder(
                [claimant],
                asset,
                amount.toStringAsFixed(7),
              ).build(),
            );
        successMessage = '${coin.name.toUpperCase()} sent as claimable balance!';
      }
      
      // Add memo if provided
      if (memo != null && memo.isNotEmpty) {
        txBuilder.addMemo(MemoText(memo.length > 28 ? memo.substring(0, 28) : memo));
      }
      
      // Build and sign transaction
      final transaction = txBuilder.build();
      transaction.sign(keyPair, StellarConfig.network);
      
      // Submit transaction
      final response = await _sdk.submitTransaction(transaction);
      
      if (response.success) {
        debugPrint('✅ $successMessage Hash: ${response.hash}');
        return PaymentResult(
          success: true,
          hash: response.hash,
          senderAddress: senderStellarPublicKey,
          recipientAddress: recipientStellarPublicKey,
          amount: amount,
          assetCode: assetCode,
          timestamp: DateTime.now(),
        );
      } else {
        final error = response.extras?.resultCodes?.operationsResultCodes?.join(', ') ?? 'Unknown error';
        debugPrint('❌ Payment failed: $error');
        return PaymentResult(success: false, error: error);
      }
    } catch (e) {
      debugPrint('❌ Send stablecoin error: $e');
      return PaymentResult(success: false, error: e.toString());
    }
  }
  
  /// Send USDC specifically
  Future<PaymentResult> sendUsdc({
    required String senderStellarPublicKey,
    required Uint8List senderPrivateKeyBytes,
    required String recipientStellarPublicKey,
    required double amount,
    String? memo,
  }) async {
    return sendStablecoin(
      senderStellarPublicKey: senderStellarPublicKey,
      senderPrivateKeyBytes: senderPrivateKeyBytes,
      recipientStellarPublicKey: recipientStellarPublicKey,
      amount: amount,
      coin: Stablecoin.usdc,
      memo: memo,
    );
  }
  
  /// Send EURC specifically
  Future<PaymentResult> sendEurc({
    required String senderStellarPublicKey,
    required Uint8List senderPrivateKeyBytes,
    required String recipientStellarPublicKey,
    required double amount,
    String? memo,
  }) async {
    return sendStablecoin(
      senderStellarPublicKey: senderStellarPublicKey,
      senderPrivateKeyBytes: senderPrivateKeyBytes,
      recipientStellarPublicKey: recipientStellarPublicKey,
      amount: amount,
      coin: Stablecoin.eurc,
      memo: memo,
    );
  }
  
  /// Send stablecoin to a GNS public key (hex) - converts automatically
  Future<PaymentResult> sendStablecoinToGnsKey({
    required String senderStellarPublicKey,
    required Uint8List senderPrivateKeyBytes,
    required String recipientGnsPublicKey,
    required double amount,
    required Stablecoin coin,
    String? memo,
  }) async {
    // Convert GNS key to Stellar address
    final recipientStellarKey = gnsKeyToStellar(recipientGnsPublicKey);
    
    return sendStablecoin(
      senderStellarPublicKey: senderStellarPublicKey,
      senderPrivateKeyBytes: senderPrivateKeyBytes,
      recipientStellarPublicKey: recipientStellarKey,
      amount: amount,
      coin: coin,
      memo: memo,
    );
  }
  
  /// Send payment by currency code string (for UI convenience)
  /// Accepts "USDC", "EURC", "EUR", "USD"
  Future<PaymentResult> sendPayment({
    required String senderStellarPublicKey,
    required Uint8List senderPrivateKeyBytes,
    required String recipientStellarPublicKey,
    required double amount,
    required String currency,
    String? memo,
  }) async {
    // Map common currency codes to stablecoins
    Stablecoin coin;
    switch (currency.toUpperCase()) {
      case 'USDC':
      case 'USD':
      case '\$':
        coin = Stablecoin.usdc;
        break;
      case 'EURC':
      case 'EUR':
      case '€':
        coin = Stablecoin.eurc;
        break;
      default:
        return PaymentResult(
          success: false,
          error: 'Unsupported currency: $currency. Use USDC or EURC.',
        );
    }
    
    return sendStablecoin(
      senderStellarPublicKey: senderStellarPublicKey,
      senderPrivateKeyBytes: senderPrivateKeyBytes,
      recipientStellarPublicKey: recipientStellarPublicKey,
      amount: amount,
      coin: coin,
      memo: memo,
    );
  }
  
  // ==================== CLAIMABLE BALANCES ====================
  
  /// Get claimable balances for an account
  Future<List<ClaimableBalance>> getClaimableBalances(String stellarPublicKey) async {
    _ensureInitialized();
    try {
      final response = await _sdk.claimableBalances
          .forClaimant(stellarPublicKey)
          .execute();
      
      return response.records.map((r) {
        String assetCode = 'XLM';
        String assetIssuer = '';
        
        final asset = r.asset;
        if (asset is AssetTypeCreditAlphaNum) {
          assetCode = asset.code;
          assetIssuer = asset.issuerId;
        }
        
        return ClaimableBalance(
          balanceId: r.balanceId,
          assetCode: assetCode,
          assetIssuer: assetIssuer,
          amount: r.amount,
          sponsor: r.sponsor ?? '',
        );
      }).toList();
    } catch (e) {
      debugPrint('Failed to get claimable balances: $e');
      return [];
    }
  }
  
  /// Get GNS claimable balances
  Future<List<ClaimableBalance>> getGnsClaimableBalances(String stellarPublicKey) async {
    final all = await getClaimableBalances(stellarPublicKey);
    return all.where((b) =>
      b.assetCode == StellarConfig.gnsTokenCode &&
      b.assetIssuer == StellarConfig.gnsIssuerPublic
    ).toList();
  }
  
  /// Get stablecoin claimable balances
  Future<List<ClaimableBalance>> getStablecoinClaimableBalances(String stellarPublicKey, Stablecoin coin) async {
    final all = await getClaimableBalances(stellarPublicKey);
    final (code, issuer) = StellarConfig.getStablecoinConfig(coin);
    return all.where((b) => b.assetCode == code && b.assetIssuer == issuer).toList();
  }
  
  /// Claim a claimable balance
  Future<TransactionResult> claimBalance({
    required String stellarPublicKey,
    required Uint8List privateKeyBytes,
    required String balanceId,
  }) async {
    _ensureInitialized();
    
    try {
      final seedBytes = privateKeyBytes.sublist(0, 32);
      final keyPair = KeyPair.fromSecretSeedList(seedBytes);
      
      final account = await _sdk.accounts.account(stellarPublicKey);
      
      final transaction = TransactionBuilder(account)
          .addOperation(ClaimClaimableBalanceOperationBuilder(balanceId).build())
          .build();
      
      transaction.sign(keyPair, StellarConfig.network);
      
      final response = await _sdk.submitTransaction(transaction);
      
      if (response.success) {
        debugPrint('✅ Balance claimed! Hash: ${response.hash}');
        return TransactionResult(success: true, hash: response.hash);
      } else {
        final error = response.extras?.resultCodes?.operationsResultCodes?.join(', ') ?? 'Unknown error';
        debugPrint('❌ Claim failed: $error');
        return TransactionResult(success: false, error: error);
      }
    } catch (e) {
      debugPrint('❌ Claim error: $e');
      return TransactionResult(success: false, error: e.toString());
    }
  }
  
  /// Claim all GNS tokens (alias for claimAllPendingBalances)
  /// Kept for backward compatibility with existing screens
  Future<TransactionResult> claimAllGnsTokens({
    required String stellarPublicKey,
    required Uint8List privateKeyBytes,
  }) async {
    return claimAllPendingBalances(
      stellarPublicKey: stellarPublicKey,
      privateKeyBytes: privateKeyBytes,
    );
  }
  
  /// Claim all pending stablecoin and GNS balances
  Future<TransactionResult> claimAllPendingBalances({
    required String stellarPublicKey,
    required Uint8List privateKeyBytes,
  }) async {
    _ensureInitialized();
    
    try {
      // First ensure all trustlines exist
      await createAllPaymentTrustlines(
        stellarPublicKey: stellarPublicKey,
        privateKeyBytes: privateKeyBytes,
      );
      
      // Get all claimable balances
      final claimable = await getClaimableBalances(stellarPublicKey);
      
      if (claimable.isEmpty) {
        return TransactionResult(success: true, hash: 'No balances to claim');
      }
      
      int claimed = 0;
      for (final balance in claimable) {
        final result = await claimBalance(
          stellarPublicKey: stellarPublicKey,
          privateKeyBytes: privateKeyBytes,
          balanceId: balance.balanceId,
        );
        
        if (result.success) {
          claimed++;
          debugPrint('Claimed ${balance.amount} ${balance.assetCode}');
        }
      }
      
      return TransactionResult(
        success: claimed > 0,
        hash: 'Claimed $claimed balances',
      );
    } catch (e) {
      return TransactionResult(success: false, error: e.toString());
    }
  }
  
  // ==================== SEND GNS (existing) ====================
  
  /// Send GNS tokens to another user
  Future<TransactionResult> sendGns({
    required String senderStellarPublicKey,
    required Uint8List senderPrivateKeyBytes,
    required String recipientStellarPublicKey,
    required double amount,
  }) async {
    _ensureInitialized();
    
    try {
      debugPrint('Sending $amount GNS from $senderStellarPublicKey to $recipientStellarPublicKey');
      
      final seedBytes = senderPrivateKeyBytes.sublist(0, 32);
      final keyPair = KeyPair.fromSecretSeedList(seedBytes);
      
      final account = await _sdk.accounts.account(senderStellarPublicKey);
      
      final balance = await getGnsBalance(senderStellarPublicKey);
      if (balance < amount) {
        return TransactionResult(
          success: false,
          error: 'Insufficient balance. You have ${balance.toStringAsFixed(2)} GNS.',
        );
      }
      
      final recipientHasTrustline = await hasGnsTrustline(recipientStellarPublicKey);
      
      final gnsAsset = Asset.createNonNativeAsset(
        StellarConfig.gnsTokenCode,
        StellarConfig.gnsIssuerPublic,
      );
      
      TransactionBuilder txBuilder;
      String successMessage;
      
      if (recipientHasTrustline) {
        txBuilder = TransactionBuilder(account)
            .addOperation(
              PaymentOperationBuilder(
                recipientStellarPublicKey,
                gnsAsset,
                amount.toStringAsFixed(7),
              ).build(),
            );
        successMessage = 'GNS sent!';
      } else {
        debugPrint('Recipient has no trustline, using claimable balance...');
        
        final claimant = Claimant(recipientStellarPublicKey, Claimant.predicateUnconditional());
        
        txBuilder = TransactionBuilder(account)
            .addOperation(
              CreateClaimableBalanceOperationBuilder(
                [claimant],
                gnsAsset,
                amount.toStringAsFixed(7),
              ).build(),
            );
        successMessage = 'GNS sent as claimable balance!';
      }
      
      final transaction = txBuilder.build();
      transaction.sign(keyPair, StellarConfig.network);
      
      final response = await _sdk.submitTransaction(transaction);
      
      if (response.success) {
        debugPrint('$successMessage Hash: ${response.hash}');
        return TransactionResult(success: true, hash: response.hash);
      } else {
        final error = response.extras?.resultCodes?.operationsResultCodes?.join(', ') ?? 'Unknown error';
        debugPrint('Send failed: $error');
        return TransactionResult(success: false, error: error);
      }
    } catch (e) {
      debugPrint('Send GNS error: $e');
      return TransactionResult(success: false, error: e.toString());
    }
  }
  
  /// Send GNS to a GNS public key
  Future<TransactionResult> sendGnsToGnsKey({
    required String senderStellarPublicKey,
    required Uint8List senderPrivateKeyBytes,
    required String recipientGnsPublicKey,
    required double amount,
  }) async {
    final recipientStellarKey = gnsKeyToStellar(recipientGnsPublicKey);
    
    return sendGns(
      senderStellarPublicKey: senderStellarPublicKey,
      senderPrivateKeyBytes: senderPrivateKeyBytes,
      recipientStellarPublicKey: recipientStellarKey,
      amount: amount,
    );
  }
  
  // ==================== INTERNAL HELPERS ====================
  
  /// Create a trustline for any asset
  Future<TransactionResult> _createTrustline({
    required String stellarPublicKey,
    required Uint8List privateKeyBytes,
    required String assetCode,
    required String assetIssuer,
  }) async {
    _ensureInitialized();
    
    try {
      final seedBytes = privateKeyBytes.sublist(0, 32);
      final keyPair = KeyPair.fromSecretSeedList(seedBytes);
      
      final account = await _sdk.accounts.account(stellarPublicKey);
      
      final asset = Asset.createNonNativeAsset(assetCode, assetIssuer);
      
      final transaction = TransactionBuilder(account)
          .addOperation(
            ChangeTrustOperationBuilder(asset, '922337203685.4775807').build(),
          )
          .build();
      
      transaction.sign(keyPair, StellarConfig.network);
      
      final response = await _sdk.submitTransaction(transaction);
      
      if (response.success) {
        debugPrint('✅ Trustline created for $assetCode! Hash: ${response.hash}');
        return TransactionResult(success: true, hash: response.hash);
      } else {
        final error = response.extras?.resultCodes?.operationsResultCodes?.join(', ') ?? 'Unknown error';
        debugPrint('❌ Trustline failed: $error');
        return TransactionResult(success: false, error: error);
      }
    } catch (e) {
      debugPrint('❌ Trustline error: $e');
      return TransactionResult(success: false, error: e.toString());
    }
  }
  
  Uint8List _hexToBytes(String hex) {
    final result = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < hex.length; i += 2) {
      result[i ~/ 2] = int.parse(hex.substring(i, i + 2), radix: 16);
    }
    return result;
  }
}

/// Extension to add Stellar functionality to strings
extension StellarWalletExtension on String {
  /// Convert GNS hex public key to Stellar address
  String toStellarAddress() {
    return StellarService().gnsKeyToStellar(this);
  }
}
