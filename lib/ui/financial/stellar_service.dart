// ===========================================
// GNS Token Layer - Stellar Service (v3)
// ===========================================
// Full Stellar integration with transaction signing
// Uses stellar_flutter_sdk for client-side signing
// v3: Added mainnet account funding via createAccount operation

import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:stellar_flutter_sdk/stellar_flutter_sdk.dart';

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
  
  // Distribution account for funding new users (MAINNET)
  // ⚠️ This should ideally be loaded from secure storage/environment
  static const String distributionPublic = 'YOUR_DISTRIBUTION_PUBLIC_KEY';  // TODO: Set this
  static const String distributionSecret = 'YOUR_DISTRIBUTION_SECRET_KEY';  // TODO: Set this securely
  
  // Starting balance for new accounts (minimum ~1 XLM for account + 0.5 for trustline reserve)
  static const String startingBalanceXlm = '1.5';
  
  // Use testnet by default
  static bool useTestnet = false;
  
  static String get horizonUrl => useTestnet ? horizonTestnet : horizonMainnet;
  static Network get network => useTestnet ? Network.TESTNET : Network.PUBLIC;
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
  
  /// Fund account on Mainnet by creating it with XLM from distribution account
  /// This uses the createAccount operation to fund new Stellar accounts
  Future<TransactionResult> fundAccountMainnet(String newAccountPublicKey) async {
    if (StellarConfig.useTestnet) {
      debugPrint('Use fundAccountTestnet for testnet');
      return TransactionResult(success: false, error: 'Use fundAccountTestnet for testnet');
    }
    
    _ensureInitialized();
    
    try {
      debugPrint('🚀 Funding new account on Mainnet: $newAccountPublicKey');
      
      // Load distribution account keypair
      final distributionKeypair = KeyPair.fromSecretSeed(StellarConfig.distributionSecret);
      
      // Verify distribution account matches config
      if (distributionKeypair.accountId != StellarConfig.distributionPublic) {
        debugPrint('⚠️ Distribution keypair mismatch!');
      }
      
      // Load distribution account
      final distributionAccount = await _sdk.accounts.account(StellarConfig.distributionPublic);
      
      // Build createAccount transaction
      final transaction = TransactionBuilder(distributionAccount)
          .addOperation(
            CreateAccountOperationBuilder(
              newAccountPublicKey,
              StellarConfig.startingBalanceXlm,
            ).build(),
          )
          .build();
      
      // Sign with distribution key
      transaction.sign(distributionKeypair, StellarConfig.network);
      
      // Submit transaction
      final response = await _sdk.submitTransaction(transaction);
      
      if (response.success) {
        debugPrint('✅ Account created and funded with ${StellarConfig.startingBalanceXlm} XLM!');
        debugPrint('   Hash: ${response.hash}');
        return TransactionResult(success: true, hash: response.hash);
      } else {
        final error = response.extras?.resultCodes?.operationsResultCodes?.join(', ') ?? 'Unknown error';
        debugPrint('❌ Account creation failed: $error');
        return TransactionResult(success: false, error: error);
      }
    } catch (e) {
      debugPrint('❌ Fund account error: $e');
      return TransactionResult(success: false, error: e.toString());
    }
  }
  
  /// Fund account (works on both testnet and mainnet)
  Future<TransactionResult> fundAccount(String stellarPublicKey) async {
    if (StellarConfig.useTestnet) {
      final success = await fundAccountTestnet(stellarPublicKey);
      return TransactionResult(
        success: success,
        error: success ? null : 'Friendbot failed',
      );
    } else {
      return fundAccountMainnet(stellarPublicKey);
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
  
  /// Get GNS token balance specifically
  Future<double> getGnsBalance(String stellarPublicKey) async {
    final balances = await getBalances(stellarPublicKey);
    
    for (final balance in balances) {
      if (balance.assetCode == StellarConfig.gnsTokenCode &&
          balance.assetIssuer == StellarConfig.gnsIssuerPublic) {
        return balance.amount;
      }
    }
    
    return 0.0;
  }
  
  /// Check if account has GNS trustline
  Future<bool> hasGnsTrustline(String stellarPublicKey) async {
    final balances = await getBalances(stellarPublicKey);
    
    return balances.any((b) =>
      b.assetCode == StellarConfig.gnsTokenCode &&
      b.assetIssuer == StellarConfig.gnsIssuerPublic
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
        
        // Handle Asset object from SDK
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
  
  /// Get GNS claimable balances specifically
  Future<List<ClaimableBalance>> getGnsClaimableBalances(String stellarPublicKey) async {
    final all = await getClaimableBalances(stellarPublicKey);
    
    return all.where((cb) =>
      cb.assetCode == StellarConfig.gnsTokenCode &&
      cb.assetIssuer == StellarConfig.gnsIssuerPublic
    ).toList();
  }
  
  // ==================== TRANSACTION OPERATIONS ====================
  
  /// Create GNS trustline (required before receiving GNS tokens)
  Future<TransactionResult> createGnsTrustline({
    required String stellarPublicKey,
    required Uint8List privateKeyBytes,
  }) async {
    _ensureInitialized();
    
    try {
      debugPrint('Creating GNS trustline for $stellarPublicKey');
      
      // Create keypair from private key bytes (first 32 bytes = seed)
      final seedBytes = privateKeyBytes.sublist(0, 32);
      final keyPair = KeyPair.fromSecretSeedList(seedBytes);
      
      // Load account
      final account = await _sdk.accounts.account(stellarPublicKey);
      
      // Create GNS asset
      final gnsAsset = Asset.createNonNativeAsset(
        StellarConfig.gnsTokenCode,
        StellarConfig.gnsIssuerPublic,
      );
      
      // Build transaction
      final transaction = TransactionBuilder(account)
          .addOperation(ChangeTrustOperationBuilder(gnsAsset, '10000000000').build())
          .build();
      
      // Sign transaction
      transaction.sign(keyPair, StellarConfig.network);
      
      // Submit transaction
      final response = await _sdk.submitTransaction(transaction);
      
      if (response.success) {
        debugPrint('Trustline created! Hash: ${response.hash}');
        return TransactionResult(success: true, hash: response.hash);
      } else {
        final error = response.extras?.resultCodes?.operationsResultCodes?.join(', ') ?? 'Unknown error';
        debugPrint('Trustline failed: $error');
        return TransactionResult(success: false, error: error);
      }
    } catch (e) {
      debugPrint('Trustline error: $e');
      return TransactionResult(success: false, error: e.toString());
    }
  }
  
  /// Claim a claimable balance
  Future<TransactionResult> claimBalance({
    required String stellarPublicKey,
    required Uint8List privateKeyBytes,
    required String balanceId,
  }) async {
    _ensureInitialized();
    
    try {
      debugPrint('Claiming balance $balanceId for $stellarPublicKey');
      
      // Create keypair from private key bytes (first 32 bytes = seed)
      final seedBytes = privateKeyBytes.sublist(0, 32);
      final keyPair = KeyPair.fromSecretSeedList(seedBytes);
      
      // Load account
      final account = await _sdk.accounts.account(stellarPublicKey);
      
      // Build claim transaction
      final transaction = TransactionBuilder(account)
          .addOperation(ClaimClaimableBalanceOperationBuilder(balanceId).build())
          .build();
      
      // Sign transaction
      transaction.sign(keyPair, StellarConfig.network);
      
      // Submit transaction
      final response = await _sdk.submitTransaction(transaction);
      
      if (response.success) {
        debugPrint('Balance claimed! Hash: ${response.hash}');
        return TransactionResult(success: true, hash: response.hash);
      } else {
        final error = response.extras?.resultCodes?.operationsResultCodes?.join(', ') ?? 'Unknown error';
        debugPrint('Claim failed: $error');
        return TransactionResult(success: false, error: error);
      }
    } catch (e) {
      debugPrint('Claim error: $e');
      return TransactionResult(success: false, error: e.toString());
    }
  }
  
  /// Create trustline AND claim all GNS balances in one flow
  /// Now includes account funding for mainnet!
  Future<TransactionResult> claimAllGnsTokens({
    required String stellarPublicKey,
    required Uint8List privateKeyBytes,
  }) async {
    _ensureInitialized();
    
    try {
      // First check if account exists
      final exists = await accountExists(stellarPublicKey);
      
      if (!exists) {
        debugPrint('Account does not exist, funding it first...');
        final fundResult = await fundAccount(stellarPublicKey);
        
        if (!fundResult.success) {
          return TransactionResult(
            success: false,
            error: 'Failed to fund account: ${fundResult.error}',
          );
        }
        debugPrint('✅ Account funded!');
        
        // Wait a moment for the ledger to update
        await Future.delayed(const Duration(seconds: 2));
      }
      
      // Now check if trustline exists
      final hasTrustline = await hasGnsTrustline(stellarPublicKey);
      
      if (!hasTrustline) {
        debugPrint('Creating trustline...');
        final trustResult = await createGnsTrustline(
          stellarPublicKey: stellarPublicKey,
          privateKeyBytes: privateKeyBytes,
        );
        
        if (!trustResult.success) {
          return TransactionResult(
            success: false,
            error: 'Failed to create trustline: ${trustResult.error}',
          );
        }
        debugPrint('✅ Trustline created!');
      }
      
      // Get claimable balances
      final claimable = await getGnsClaimableBalances(stellarPublicKey);
      
      if (claimable.isEmpty) {
        return TransactionResult(
          success: true,
          error: 'No GNS tokens to claim',
        );
      }
      
      // Claim each balance
      double totalClaimed = 0;
      for (final balance in claimable) {
        debugPrint('Claiming ${balance.amount} GNS...');
        
        final result = await claimBalance(
          stellarPublicKey: stellarPublicKey,
          privateKeyBytes: privateKeyBytes,
          balanceId: balance.balanceId,
        );
        
        if (result.success) {
          totalClaimed += double.tryParse(balance.amount) ?? 0;
        } else {
          debugPrint('Failed to claim: ${result.error}');
        }
      }
      
      return TransactionResult(
        success: true,
        hash: 'Claimed ${totalClaimed.toStringAsFixed(2)} GNS',
      );
    } catch (e) {
      debugPrint('Claim all error: $e');
      return TransactionResult(success: false, error: e.toString());
    }
  }
  
  // ==================== SEND GNS ====================
  
  /// Send GNS tokens to another user
  /// If recipient doesn't have a trustline, uses claimable balance instead
  Future<TransactionResult> sendGns({
    required String senderStellarPublicKey,
    required Uint8List senderPrivateKeyBytes,
    required String recipientStellarPublicKey,
    required double amount,
  }) async {
    _ensureInitialized();
    
    try {
      debugPrint('Sending $amount GNS from $senderStellarPublicKey to $recipientStellarPublicKey');
      
      // Create keypair from private key bytes (first 32 bytes = seed)
      final seedBytes = senderPrivateKeyBytes.sublist(0, 32);
      final keyPair = KeyPair.fromSecretSeedList(seedBytes);
      
      // Load sender account
      final account = await _sdk.accounts.account(senderStellarPublicKey);
      
      // Check sender balance
      final balance = await getGnsBalance(senderStellarPublicKey);
      if (balance < amount) {
        return TransactionResult(
          success: false,
          error: 'Insufficient balance. You have ${balance.toStringAsFixed(2)} GNS.',
        );
      }
      
      // Check if recipient has trustline
      final recipientHasTrustline = await hasGnsTrustline(recipientStellarPublicKey);
      
      // Create GNS asset
      final gnsAsset = Asset.createNonNativeAsset(
        StellarConfig.gnsTokenCode,
        StellarConfig.gnsIssuerPublic,
      );
      
      TransactionBuilder txBuilder;
      String successMessage;
      
      if (recipientHasTrustline) {
        // ✅ Direct payment - recipient has trustline
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
        // ✅ Claimable balance - recipient doesn't have trustline yet
        debugPrint('Recipient has no trustline, using claimable balance...');
        
        // Create claimant with unconditional predicate (can claim anytime)
        final claimant = Claimant(recipientStellarPublicKey, Claimant.predicateUnconditional());
        
        txBuilder = TransactionBuilder(account)
            .addOperation(
              CreateClaimableBalanceOperationBuilder(
                [claimant],
                gnsAsset,
                amount.toStringAsFixed(7),
              ).build(),
            );
        successMessage = 'GNS sent as claimable balance! Recipient will receive when they set up their wallet.';
      }
      
      // Build and sign transaction
      final transaction = txBuilder.build();
      transaction.sign(keyPair, StellarConfig.network);
      
      // Submit transaction
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
  
  /// Send GNS to a GNS public key (converts to Stellar address automatically)
  Future<TransactionResult> sendGnsToGnsKey({
    required String senderStellarPublicKey,
    required Uint8List senderPrivateKeyBytes,
    required String recipientGnsPublicKey,
    required double amount,
  }) async {
    // Convert GNS key to Stellar address
    final recipientStellarKey = gnsKeyToStellar(recipientGnsPublicKey);
    
    return sendGns(
      senderStellarPublicKey: senderStellarPublicKey,
      senderPrivateKeyBytes: senderPrivateKeyBytes,
      recipientStellarPublicKey: recipientStellarKey,
      amount: amount,
    );
  }

  // ==================== HELPER FUNCTIONS ====================
  
  Uint8List _hexToBytes(String hex) {
    final result = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < hex.length; i += 2) {
      result[i ~/ 2] = int.parse(hex.substring(i, i + 2), radix: 16);
    }
    return result;
  }
}

/// Extension to add Stellar functionality
extension StellarWalletExtension on String {
  /// Convert GNS hex public key to Stellar address
  String toStellarAddress() {
    return StellarService().gnsKeyToStellar(this);
  }
}
