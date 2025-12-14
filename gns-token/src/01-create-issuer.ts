// ===========================================
// GNS Token Layer - Step 1: Create Issuer Account
// ===========================================
// This script creates the GNS token issuer on Stellar Testnet
// The issuer account is the source of all GNS tokens

import * as StellarSdk from '@stellar/stellar-sdk';

const NETWORK = 'TESTNET';
const HORIZON_URL = 'https://horizon-testnet.stellar.org';
const FRIENDBOT_URL = 'https://friendbot.stellar.org';

async function createIssuerAccount() {
  console.log('🚀 GNS Token Layer - Issuer Setup\n');
  console.log('Network:', NETWORK);
  console.log('Horizon:', HORIZON_URL);
  console.log('');

  // Step 1: Generate Issuer Keypair
  console.log('📝 Step 1: Generating Issuer Keypair...');
  const issuerKeypair = StellarSdk.Keypair.random();
  
  console.log('');
  console.log('='.repeat(60));
  console.log('🔐 GNS TOKEN ISSUER ACCOUNT');
  console.log('='.repeat(60));
  console.log('Public Key (ISSUER):', issuerKeypair.publicKey());
  console.log('Secret Key (KEEP SAFE):', issuerKeypair.secret());
  console.log('='.repeat(60));
  console.log('');
  console.log('⚠️  SAVE THESE KEYS! The secret key controls all GNS tokens.');
  console.log('');

  // Step 2: Fund via Friendbot (testnet only)
  console.log('💰 Step 2: Funding via Friendbot (testnet)...');
  
  try {
    const response = await fetch(
      `${FRIENDBOT_URL}?addr=${encodeURIComponent(issuerKeypair.publicKey())}`
    );
    
    if (!response.ok) {
      throw new Error(`Friendbot error: ${response.status}`);
    }
    
    console.log('✅ Account funded with 10,000 XLM (testnet)\n');
  } catch (error) {
    console.error('❌ Friendbot failed:', error);
    return null;
  }

  // Step 3: Verify account exists
  console.log('🔍 Step 3: Verifying account on Stellar...');
  
  const server = new StellarSdk.Horizon.Server(HORIZON_URL);
  
  try {
    const account = await server.loadAccount(issuerKeypair.publicKey());
    console.log('✅ Account verified!');
    console.log('   Balance:', account.balances[0].balance, 'XLM');
    console.log('   Sequence:', account.sequence);
    console.log('');
  } catch (error) {
    console.error('❌ Account verification failed:', error);
    return null;
  }

  // Return the keypair for next steps
  return {
    publicKey: issuerKeypair.publicKey(),
    secretKey: issuerKeypair.secret(),
  };
}

// Step 4: Generate Distribution Account
async function createDistributionAccount() {
  console.log('📝 Step 4: Generating Distribution Keypair...');
  const distributionKeypair = StellarSdk.Keypair.random();
  
  console.log('');
  console.log('='.repeat(60));
  console.log('📦 GNS DISTRIBUTION ACCOUNT');
  console.log('='.repeat(60));
  console.log('Public Key (DISTRIBUTION):', distributionKeypair.publicKey());
  console.log('Secret Key (KEEP SAFE):', distributionKeypair.secret());
  console.log('='.repeat(60));
  console.log('');

  // Fund via Friendbot
  console.log('💰 Funding distribution account via Friendbot...');
  
  try {
    const response = await fetch(
      `${FRIENDBOT_URL}?addr=${encodeURIComponent(distributionKeypair.publicKey())}`
    );
    
    if (!response.ok) {
      throw new Error(`Friendbot error: ${response.status}`);
    }
    
    console.log('✅ Distribution account funded!\n');
  } catch (error) {
    console.error('❌ Friendbot failed:', error);
    return null;
  }

  return {
    publicKey: distributionKeypair.publicKey(),
    secretKey: distributionKeypair.secret(),
  };
}

// Main execution
async function main() {
  console.log('');
  console.log('╔════════════════════════════════════════════════════════════╗');
  console.log('║           GNS TOKEN LAYER - STELLAR TESTNET                ║');
  console.log('║                   Issuer Setup v1.0                        ║');
  console.log('╚════════════════════════════════════════════════════════════╝');
  console.log('');

  const issuer = await createIssuerAccount();
  if (!issuer) {
    console.error('Failed to create issuer account');
    process.exit(1);
  }

  const distribution = await createDistributionAccount();
  if (!distribution) {
    console.error('Failed to create distribution account');
    process.exit(1);
  }

  // Summary
  console.log('');
  console.log('╔════════════════════════════════════════════════════════════╗');
  console.log('║                    SETUP COMPLETE                          ║');
  console.log('╚════════════════════════════════════════════════════════════╝');
  console.log('');
  console.log('Save these for .env file:');
  console.log('');
  console.log(`GNS_ISSUER_PUBLIC=${issuer.publicKey}`);
  console.log(`GNS_ISSUER_SECRET=${issuer.secretKey}`);
  console.log(`GNS_DISTRIBUTION_PUBLIC=${distribution.publicKey}`);
  console.log(`GNS_DISTRIBUTION_SECRET=${distribution.secretKey}`);
  console.log(`STELLAR_NETWORK=TESTNET`);
  console.log(`STELLAR_HORIZON_URL=${HORIZON_URL}`);
  console.log('');
  console.log('Next step: Run 02-issue-token.ts to create the GNS asset');
  console.log('');
}

main().catch(console.error);
