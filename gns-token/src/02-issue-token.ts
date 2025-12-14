// ===========================================
// GNS Token Layer - Step 2: Issue GNS Token
// ===========================================
// This script:
// 1. Creates the GNS asset definition
// 2. Sets up trustline from distribution → issuer
// 3. Mints initial supply to distribution account

import * as StellarSdk from '@stellar/stellar-sdk';
import * as dotenv from 'dotenv';

dotenv.config();

const HORIZON_URL = process.env.STELLAR_HORIZON_URL || 'https://horizon-testnet.stellar.org';
const NETWORK_PASSPHRASE = StellarSdk.Networks.TESTNET;

// Token configuration
const TOKEN_CONFIG = {
  code: 'GNS',
  totalSupply: '10000000000', // 10 billion GNS
  initialDistribution: '4000000000', // 4 billion to distribution (40%)
};

async function issueGnsToken() {
  console.log('');
  console.log('╔════════════════════════════════════════════════════════════╗');
  console.log('║           GNS TOKEN LAYER - ISSUE TOKEN                    ║');
  console.log('╚════════════════════════════════════════════════════════════╝');
  console.log('');

  // Load keys from environment
  const issuerSecret = process.env.GNS_ISSUER_SECRET;
  const distributionSecret = process.env.GNS_DISTRIBUTION_SECRET;

  if (!issuerSecret || !distributionSecret) {
    console.error('❌ Missing environment variables!');
    console.error('   Run 01-create-issuer.ts first and save keys to .env');
    process.exit(1);
  }

  const issuerKeypair = StellarSdk.Keypair.fromSecret(issuerSecret);
  const distributionKeypair = StellarSdk.Keypair.fromSecret(distributionSecret);

  console.log('🔐 Issuer Account:', issuerKeypair.publicKey());
  console.log('📦 Distribution Account:', distributionKeypair.publicKey());
  console.log('');

  // Create GNS asset
  const gnsAsset = new StellarSdk.Asset(TOKEN_CONFIG.code, issuerKeypair.publicKey());
  
  console.log('💎 GNS Asset Definition:');
  console.log('   Code:', gnsAsset.code);
  console.log('   Issuer:', gnsAsset.issuer);
  console.log('   Total Supply:', TOKEN_CONFIG.totalSupply, 'GNS');
  console.log('');

  const server = new StellarSdk.Horizon.Server(HORIZON_URL);

  // Step 1: Distribution account trusts GNS
  console.log('📝 Step 1: Creating trustline (Distribution → Issuer)...');
  
  try {
    const distributionAccount = await server.loadAccount(distributionKeypair.publicKey());
    
    const trustTransaction = new StellarSdk.TransactionBuilder(distributionAccount, {
      fee: StellarSdk.BASE_FEE,
      networkPassphrase: NETWORK_PASSPHRASE,
    })
      .addOperation(
        StellarSdk.Operation.changeTrust({
          asset: gnsAsset,
          limit: TOKEN_CONFIG.totalSupply, // Max tokens this account can hold
        })
      )
      .setTimeout(30)
      .build();

    trustTransaction.sign(distributionKeypair);
    
    const trustResult = await server.submitTransaction(trustTransaction);
    console.log('✅ Trustline created!');
    console.log('   Tx Hash:', trustResult.hash);
    console.log('');
  } catch (error: any) {
    if (error.response?.data?.extras?.result_codes) {
      console.log('   Result codes:', error.response.data.extras.result_codes);
    }
    // If trustline already exists, continue
    if (error.message?.includes('op_already_exists')) {
      console.log('   (Trustline already exists, continuing...)');
    } else {
      throw error;
    }
  }

  // Step 2: Mint tokens to distribution account
  console.log('🏭 Step 2: Minting GNS tokens to distribution account...');
  
  try {
    const issuerAccount = await server.loadAccount(issuerKeypair.publicKey());
    
    const mintTransaction = new StellarSdk.TransactionBuilder(issuerAccount, {
      fee: StellarSdk.BASE_FEE,
      networkPassphrase: NETWORK_PASSPHRASE,
    })
      .addOperation(
        StellarSdk.Operation.payment({
          destination: distributionKeypair.publicKey(),
          asset: gnsAsset,
          amount: TOKEN_CONFIG.initialDistribution,
        })
      )
      .setTimeout(30)
      .build();

    mintTransaction.sign(issuerKeypair);
    
    const mintResult = await server.submitTransaction(mintTransaction);
    console.log('✅ Tokens minted!');
    console.log('   Tx Hash:', mintResult.hash);
    console.log('   Amount:', TOKEN_CONFIG.initialDistribution, 'GNS');
    console.log('');
  } catch (error: any) {
    console.error('❌ Minting failed:', error.message);
    if (error.response?.data?.extras?.result_codes) {
      console.log('   Result codes:', error.response.data.extras.result_codes);
    }
    throw error;
  }

  // Step 3: Verify balances
  console.log('🔍 Step 3: Verifying balances...');
  
  const distributionAccount = await server.loadAccount(distributionKeypair.publicKey());
  
  console.log('');
  console.log('📊 Distribution Account Balances:');
  for (const balance of distributionAccount.balances) {
    if (balance.asset_type === 'native') {
      console.log(`   XLM: ${balance.balance}`);
    } else if (balance.asset_type === 'credit_alphanum4' || balance.asset_type === 'credit_alphanum12') {
      console.log(`   ${balance.asset_code}: ${balance.balance}`);
    }
  }
  console.log('');

  // Summary
  console.log('╔════════════════════════════════════════════════════════════╗');
  console.log('║                 GNS TOKEN ISSUED! 🎉                       ║');
  console.log('╚════════════════════════════════════════════════════════════╝');
  console.log('');
  console.log('Token Details:');
  console.log(`  Asset: ${TOKEN_CONFIG.code}`);
  console.log(`  Issuer: ${issuerKeypair.publicKey()}`);
  console.log(`  Distribution: ${distributionKeypair.publicKey()}`);
  console.log(`  Initial Supply: ${TOKEN_CONFIG.initialDistribution} GNS`);
  console.log('');
  console.log('View on Stellar Expert:');
  console.log(`  https://stellar.expert/explorer/testnet/asset/${TOKEN_CONFIG.code}-${issuerKeypair.publicKey()}`);
  console.log('');
  console.log('Next step: Run 03-send-tokens.ts to send GNS to a user');
  console.log('');
}

issueGnsToken().catch(console.error);
