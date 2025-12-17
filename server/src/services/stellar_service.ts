// ===========================================
// GNS NODE - STELLAR SERVICE
// Backend service for GNS token airdrops
// ===========================================
// Location: src/services/stellar_service.ts

import * as StellarSdk from '@stellar/stellar-sdk';

// ===========================================
// CONFIGURATION
// ===========================================

const CONFIG = {
  // Network
  useTestnet: false,  // MAINNET
  horizonUrl: 'https://horizon.stellar.org',
  networkPassphrase: StellarSdk.Networks.PUBLIC,
  
  // GNS Token
  gnsAssetCode: 'GNS',
  gnsIssuer: 'GBVZTFST4PIPV5C3APDIVULNZYZENQSLGDSOKOVQI77GSMT6WVYGF5GL',
  
  // Airdrop amounts
  xlmAirdropAmount: '2',      // 2 XLM to activate account
  gnsAirdropAmount: '200',    // 200 GNS welcome bonus
  
  // Claimable balance expiry (30 days)
  claimableExpiryDays: 30,
};

// Distribution wallet (loaded from environment)
const DISTRIBUTION_SECRET = process.env.GNS_DISTRIBUTION_SECRET;

// ===========================================
// STELLAR SERVICE CLASS
// ===========================================

class StellarService {
  private server: StellarSdk.Horizon.Server;
  private gnsAsset: StellarSdk.Asset;
  private distributionKeypair: StellarSdk.Keypair | null = null;
  
  constructor() {
    this.server = new StellarSdk.Horizon.Server(CONFIG.horizonUrl);
    this.gnsAsset = new StellarSdk.Asset(CONFIG.gnsAssetCode, CONFIG.gnsIssuer);
    
    if (DISTRIBUTION_SECRET) {
      try {
        this.distributionKeypair = StellarSdk.Keypair.fromSecret(DISTRIBUTION_SECRET);
        console.log(`[Stellar] Distribution wallet loaded: ${this.distributionKeypair.publicKey().substring(0, 8)}...`);
      } catch (e) {
        console.error('[Stellar] Invalid distribution secret key');
      }
    } else {
      console.warn('[Stellar] GNS_DISTRIBUTION_SECRET not set - airdrops disabled');
    }
  }
  
  // ===========================================
  // KEY CONVERSION
  // ===========================================
  
  /**
   * Convert GNS hex public key to Stellar G... address
   */
  gnsKeyToStellar(gnsHexKey: string): string {
    const bytes = Buffer.from(gnsHexKey, 'hex');
    return StellarSdk.StrKey.encodeEd25519PublicKey(bytes);
  }
  
  /**
   * Convert Stellar G... address to GNS hex public key
   */
  stellarToGnsKey(stellarAddress: string): string {
    const bytes = StellarSdk.StrKey.decodeEd25519PublicKey(stellarAddress);
    return Buffer.from(bytes).toString('hex');
  }
  
  // ===========================================
  // ACCOUNT QUERIES
  // ===========================================
  
  /**
   * Check if a Stellar account exists (is funded)
   */
  async accountExists(stellarAddress: string): Promise<boolean> {
    try {
      await this.server.loadAccount(stellarAddress);
      return true;
    } catch (e: any) {
      if (e.response?.status === 404) {
        return false;
      }
      throw e;
    }
  }
  
  /**
   * Check if account has GNS trustline
   */
  async hasGnsTrustline(stellarAddress: string): Promise<boolean> {
    try {
      const account = await this.server.loadAccount(stellarAddress);
      return account.balances.some((b: any) => 
        b.asset_type !== 'native' && 
        b.asset_code === CONFIG.gnsAssetCode && 
        b.asset_issuer === CONFIG.gnsIssuer
      );
    } catch {
      return false;
    }
  }
  
  // ===========================================
  // AIRDROP FUNCTIONS
  // ===========================================
  
  /**
   * Send XLM to activate a new account
   */
  async sendXlmAirdrop(destinationStellarAddress: string): Promise<{ success: boolean; txHash?: string; error?: string }> {
    if (!this.distributionKeypair) {
      return { success: false, error: 'Distribution wallet not configured' };
    }
    
    try {
      const sourceAccount = await this.server.loadAccount(this.distributionKeypair.publicKey());
      
      // Check if destination already exists
      const exists = await this.accountExists(destinationStellarAddress);
      
      let transaction: StellarSdk.Transaction;
      
      if (exists) {
        // Account exists - just send payment
        transaction = new StellarSdk.TransactionBuilder(sourceAccount, {
          fee: StellarSdk.BASE_FEE,
          networkPassphrase: CONFIG.networkPassphrase,
        })
          .addOperation(StellarSdk.Operation.payment({
            destination: destinationStellarAddress,
            asset: StellarSdk.Asset.native(),
            amount: CONFIG.xlmAirdropAmount,
          }))
          .setTimeout(30)
          .build();
      } else {
        // Account doesn't exist - use createAccount
        transaction = new StellarSdk.TransactionBuilder(sourceAccount, {
          fee: StellarSdk.BASE_FEE,
          networkPassphrase: CONFIG.networkPassphrase,
        })
          .addOperation(StellarSdk.Operation.createAccount({
            destination: destinationStellarAddress,
            startingBalance: CONFIG.xlmAirdropAmount,
          }))
          .setTimeout(30)
          .build();
      }
      
      transaction.sign(this.distributionKeypair);
      const result = await this.server.submitTransaction(transaction);
      
      console.log(`[Stellar] XLM airdrop sent: ${CONFIG.xlmAirdropAmount} XLM → ${destinationStellarAddress.substring(0, 8)}...`);
      
      return { success: true, txHash: result.hash };
    } catch (e: any) {
      console.error('[Stellar] XLM airdrop failed:', e.message);
      console.error('[Stellar] Full error:', JSON.stringify({
        status: e.response?.status,
        data: e.response?.data,
        extras: e.response?.data?.extras,
      }, null, 2));
      return { success: false, error: e.message };
    }
  }
  
  /**
   * Send GNS tokens as claimable balance
   * (Recipient doesn't need trustline yet)
   */
  async sendGnsClaimableBalance(destinationStellarAddress: string, amount?: string): Promise<{ success: boolean; balanceId?: string; error?: string }> {
    if (!this.distributionKeypair) {
      return { success: false, error: 'Distribution wallet not configured' };
    }
    
    const gnsAmount = amount || CONFIG.gnsAirdropAmount;
    
    try {
      const sourceAccount = await this.server.loadAccount(this.distributionKeypair.publicKey());
      
      // Calculate expiry (30 days from now)
      const expiryDate = Math.floor(Date.now() / 1000) + (CONFIG.claimableExpiryDays * 24 * 60 * 60);
      
      const transaction = new StellarSdk.TransactionBuilder(sourceAccount, {
        fee: StellarSdk.BASE_FEE,
        networkPassphrase: CONFIG.networkPassphrase,
      })
        .addOperation(StellarSdk.Operation.createClaimableBalance({
          asset: this.gnsAsset,
          amount: gnsAmount,
          claimants: [
            new StellarSdk.Claimant(
              destinationStellarAddress,
              StellarSdk.Claimant.predicateBeforeAbsoluteTime(expiryDate.toString())
            ),
          ],
        }))
        .setTimeout(30)
        .build();
      
      transaction.sign(this.distributionKeypair);
      const result = await this.server.submitTransaction(transaction);
      
      console.log(`[Stellar] GNS claimable balance created: ${gnsAmount} GNS for ${destinationStellarAddress.substring(0, 8)}...`);
      
      // Extract balance ID from result
      const balanceId = (result as any).result_xdr; // Would need to parse for actual ID
      
      return { success: true, balanceId: result.hash };
    } catch (e: any) {
      console.error('[Stellar] GNS claimable balance failed:', e.message);
      return { success: false, error: e.message };
    }
  }
  
  /**
   * Send GNS tokens directly (requires recipient to have trustline)
   */
  async sendGnsDirectly(destinationStellarAddress: string, amount?: string): Promise<{ success: boolean; txHash?: string; error?: string }> {
    if (!this.distributionKeypair) {
      return { success: false, error: 'Distribution wallet not configured' };
    }
    
    const gnsAmount = amount || CONFIG.gnsAirdropAmount;
    
    try {
      const sourceAccount = await this.server.loadAccount(this.distributionKeypair.publicKey());
      
      const transaction = new StellarSdk.TransactionBuilder(sourceAccount, {
        fee: StellarSdk.BASE_FEE,
        networkPassphrase: CONFIG.networkPassphrase,
      })
        .addOperation(StellarSdk.Operation.payment({
          destination: destinationStellarAddress,
          asset: this.gnsAsset,
          amount: gnsAmount,
        }))
        .setTimeout(30)
        .build();
      
      transaction.sign(this.distributionKeypair);
      const result = await this.server.submitTransaction(transaction);
      
      console.log(`[Stellar] GNS sent directly: ${gnsAmount} GNS → ${destinationStellarAddress.substring(0, 8)}...`);
      
      return { success: true, txHash: result.hash };
    } catch (e: any) {
      console.error('[Stellar] GNS direct send failed:', e.message);
      return { success: false, error: e.message };
    }
  }
  
  // ===========================================
  // MAIN AIRDROP FUNCTION
  // ===========================================
  
  /**
   * Complete airdrop for new user:
   * 1. Send XLM to activate account
   * 2. Send GNS as claimable balance
   */
  async airdropToNewUser(gnsPublicKey: string): Promise<{ 
    success: boolean; 
    stellarAddress?: string;
    xlmTx?: string; 
    gnsTx?: string; 
    error?: string 
  }> {
    // Convert GNS key to Stellar address
    const stellarAddress = this.gnsKeyToStellar(gnsPublicKey);
    
    console.log(`[Stellar] Starting airdrop for ${gnsPublicKey.substring(0, 16)}... → ${stellarAddress.substring(0, 8)}...`);
    
    // Step 1: Send XLM
    const xlmResult = await this.sendXlmAirdrop(stellarAddress);
    if (!xlmResult.success) {
      return { success: false, stellarAddress, error: `XLM airdrop failed: ${xlmResult.error}` };
    }
    
    // Small delay to ensure account is active
    await new Promise(resolve => setTimeout(resolve, 2000));
    
    // Step 2: Send GNS as claimable balance
    const gnsResult = await this.sendGnsClaimableBalance(stellarAddress);
    if (!gnsResult.success) {
      // XLM was sent but GNS failed - partial success
      console.warn(`[Stellar] XLM sent but GNS failed for ${stellarAddress}`);
      return { 
        success: false, 
        stellarAddress,
        xlmTx: xlmResult.txHash,
        error: `GNS airdrop failed: ${gnsResult.error}` 
      };
    }
    
    console.log(`[Stellar] ✅ Airdrop complete: ${CONFIG.xlmAirdropAmount} XLM + ${CONFIG.gnsAirdropAmount} GNS → ${stellarAddress.substring(0, 8)}...`);
    
    return {
      success: true,
      stellarAddress,
      xlmTx: xlmResult.txHash,
      gnsTx: gnsResult.balanceId,
    };
  }
  
  // ===========================================
  // STATUS
  // ===========================================
  
  /**
   * Check if airdrop service is ready
   */
  isConfigured(): boolean {
    return this.distributionKeypair !== null;
  }
  
  /**
   * Get distribution wallet public key (for monitoring)
   */
  getDistributionAddress(): string | null {
    return this.distributionKeypair?.publicKey() || null;
  }
  
  /**
   * Get distribution wallet balances
   */
  async getDistributionBalances(): Promise<{ xlm: string; gns: string } | null> {
    if (!this.distributionKeypair) return null;
    
    try {
      const account = await this.server.loadAccount(this.distributionKeypair.publicKey());
      
      let xlm = '0';
      let gns = '0';
      
      for (const balance of account.balances) {
        if (balance.asset_type === 'native') {
          xlm = balance.balance;
        } else if (
          (balance as any).asset_code === CONFIG.gnsAssetCode && 
          (balance as any).asset_issuer === CONFIG.gnsIssuer
        ) {
          gns = balance.balance;
        }
      }
      
      return { xlm, gns };
    } catch {
      return null;
    }
  }
}

// ===========================================
// SINGLETON EXPORT
// ===========================================

const stellarService = new StellarService();
export default stellarService;

export { StellarService, CONFIG as StellarConfig };
