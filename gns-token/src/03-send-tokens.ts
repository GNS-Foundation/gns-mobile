// ===========================================
// GNS Token Layer - Step 3: Send Tokens
// ===========================================
// This script sends GNS tokens to any Stellar account
// 
// Key insight: GNS Identity public keys (Ed25519) can be
// converted to Stellar addresses!

import * as StellarSdk from '@stellar/stellar-sdk';
import * as dotenv from 'dotenv';

dotenv.config();

const HORIZON_URL = process.env.STELLAR_HORIZON_URL || 'https://horizon-testnet.stellar.org';
const NETWORK_PASSPHRASE = StellarSdk.Networks.TESTNET;
const FRIENDBOT_URL = 'https://friendbot.stellar.org';

/**
 * Convert GNS Ed25519 public key (hex) to Stellar public key (G...)
 * 
 * GNS uses raw Ed25519 public keys in hex format.
 * Stellar uses the same Ed25519 keys but encoded differently.
 */
function gnsPublicKeyToStellar(gnsHexPublicKey: string): string {
  // Remove 0x prefix if present
  const cleanHex = gnsHexPublicKey.replace(/^0x/, '');
  
  // Convert hex to buffer
  const publicKeyBuffer = Buffer.from(cleanHex, 'hex');
  
  if (publicKeyBuffer.length !== 32) {
    throw new Error(`Invalid public key length: ${publicKeyBuffer.length}, expected 32`);
  }
  
  // Create Stellar keypair from raw public key bytes
  const keypair = StellarSdk.Keypair.fromRawEd25519Seed(publicKeyBuffer);
  
  // Note: This creates from seed, but we want from public key
  // Stellar SDK doesn't have a direct method, so we use StrKey encoding
  const stellarPublicKey = StellarSdk.StrKey.encodeEd25519PublicKey(publicKeyBuffer);
  
  return stellarPublicKey;
}

/**
 * Send GNS tokens to a recipient
 */
async function sendGnsTokens(recipientStellarKey: string, amount: string) {
  console.log('');
  console.log('╔════════════════════════════════════════════════════════════╗');
  console.log('║           GNS TOKEN LAYER - SEND TOKENS                    ║');
  console.log('╚════════════════════════════════════════════════════════════╝');
  console.log('');

  // Load keys from environment
  const issuerPublic = process.env.GNS_ISSUER_PUBLIC;
  const distributionSecret = process.env.GNS_DISTRIBUTION_SECRET;

  if (!issuerPublic || !distributionSecret) {
    console.error('❌ Missing environment variables!');
    process.exit(1);
  }

  const distributionKeypair = StellarSdk.Keypair.fromSecret(distributionSecret);
  const gnsAsset = new StellarSdk.Asset('GNS', issuerPublic);
  const server = new StellarSdk.Horizon.Server(HORIZON_URL);

  console.log('📤 Sending GNS tokens:');
  console.log('   From: Distribution Account');
  console.log('   To:', recipientStellarKey);
  console.log('   Amount:', amount, 'GNS');
  console.log('');

  // Check if recipient account exists and has trustline
  let recipientExists = false;
  let hasTrustline = false;

  try {
    const recipientAccount = await server.loadAccount(recipientStellarKey);
    recipientExists = true;
    
    // Check for GNS trustline
    for (const balance of recipientAccount.balances) {
      if (
        (balance.asset_type === 'credit_alphanum4' || balance.asset_type === 'credit_alphanum12') &&
        balance.asset_code === 'GNS' &&
        balance.asset_issuer === issuerPublic
      ) {
        hasTrustline = true;
        break;
      }
    }
  } catch (error) {
    recipientExists = false;
  }

  console.log('🔍 Recipient status:');
  console.log('   Account exists:', recipientExists ? '✅' : '❌');
  console.log('   Has GNS trustline:', hasTrustline ? '✅' : '❌');
  console.log('');

  if (!recipientExists) {
    console.log('💰 Creating recipient account via Friendbot (testnet)...');
    try {
      const response = await fetch(
        `${FRIENDBOT_URL}?addr=${encodeURIComponent(recipientStellarKey)}`
      );
      if (response.ok) {
        console.log('✅ Account created and funded!');
        recipientExists = true;
      }
    } catch (error) {
      console.error('❌ Could not create account:', error);
      return;
    }
  }

  if (!hasTrustline) {
    console.log('');
    console.log('⚠️  Recipient needs to create a trustline for GNS tokens.');
    console.log('   They must run: createTrustline(recipientSecret)');
    console.log('');
    console.log('   Or use claimable balance (no trustline required)...');
    console.log('');
    
    // Use claimable balance instead
    return await sendViaClaimableBalance(
      server,
      distributionKeypair,
      recipientStellarKey,
      gnsAsset,
      amount
    );
  }

  // Direct payment if trustline exists
  const distributionAccount = await server.loadAccount(distributionKeypair.publicKey());
  
  const paymentTx = new StellarSdk.TransactionBuilder(distributionAccount, {
    fee: StellarSdk.BASE_FEE,
    networkPassphrase: NETWORK_PASSPHRASE,
  })
    .addOperation(
      StellarSdk.Operation.payment({
        destination: recipientStellarKey,
        asset: gnsAsset,
        amount: amount,
      })
    )
    .setTimeout(30)
    .build();

  paymentTx.sign(distributionKeypair);
  
  const result = await server.submitTransaction(paymentTx);
  
  console.log('✅ Tokens sent!');
  console.log('   Tx Hash:', result.hash);
  console.log('');
  console.log('View transaction:');
  console.log(`   https://stellar.expert/explorer/testnet/tx/${result.hash}`);
  console.log('');
}

/**
 * Send tokens via claimable balance (recipient doesn't need trustline yet)
 */
async function sendViaClaimableBalance(
  server: StellarSdk.Horizon.Server,
  senderKeypair: StellarSdk.Keypair,
  recipientKey: string,
  asset: StellarSdk.Asset,
  amount: string
) {
  console.log('📦 Creating claimable balance...');
  
  const senderAccount = await server.loadAccount(senderKeypair.publicKey());
  
  // Claimable balance: recipient can claim anytime
  const claimant = new StellarSdk.Claimant(
    recipientKey,
    StellarSdk.Claimant.predicateUnconditional()
  );

  const claimableTx = new StellarSdk.TransactionBuilder(senderAccount, {
    fee: StellarSdk.BASE_FEE,
    networkPassphrase: NETWORK_PASSPHRASE,
  })
    .addOperation(
      StellarSdk.Operation.createClaimableBalance({
        asset: asset,
        amount: amount,
        claimants: [claimant],
      })
    )
    .setTimeout(30)
    .build();

  claimableTx.sign(senderKeypair);
  
  const result = await server.submitTransaction(claimableTx);
  
  console.log('✅ Claimable balance created!');
  console.log('   Tx Hash:', result.hash);
  console.log('');
  console.log('   Recipient can claim these tokens after creating a trustline.');
  console.log('');
  console.log('View transaction:');
  console.log(`   https://stellar.expert/explorer/testnet/tx/${result.hash}`);
  console.log('');
}

/**
 * Create trustline for receiving GNS tokens
 */
async function createTrustline(recipientSecret: string) {
  const recipientKeypair = StellarSdk.Keypair.fromSecret(recipientSecret);
  const issuerPublic = process.env.GNS_ISSUER_PUBLIC!;
  const gnsAsset = new StellarSdk.Asset('GNS', issuerPublic);
  const server = new StellarSdk.Horizon.Server(HORIZON_URL);
  
  console.log('🔗 Creating GNS trustline...');
  
  const account = await server.loadAccount(recipientKeypair.publicKey());
  
  const trustTx = new StellarSdk.TransactionBuilder(account, {
    fee: StellarSdk.BASE_FEE,
    networkPassphrase: NETWORK_PASSPHRASE,
  })
    .addOperation(
      StellarSdk.Operation.changeTrust({
        asset: gnsAsset,
      })
    )
    .setTimeout(30)
    .build();

  trustTx.sign(recipientKeypair);
  
  const result = await server.submitTransaction(trustTx);
  
  console.log('✅ Trustline created!');
  console.log('   Account can now receive GNS tokens.');
  console.log('   Tx Hash:', result.hash);
}

// ===========================================
// Example usage
// ===========================================

async function main() {
  // Example: Convert @caterve's GNS public key to Stellar
  const caterveGnsKey = '26b9c6a8eda4130a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a';
  
  console.log('');
  console.log('🔄 GNS to Stellar Key Conversion:');
  console.log('   GNS (hex):', caterveGnsKey);
  
  try {
    const stellarKey = gnsPublicKeyToStellar(caterveGnsKey);
    console.log('   Stellar (G...):', stellarKey);
    console.log('');
    
    // Send tokens to this address
    // await sendGnsTokens(stellarKey, '1000');
  } catch (error) {
    console.log('   (Demo key - not a real conversion)');
  }
  
  console.log('');
  console.log('Usage:');
  console.log('  sendGnsTokens(stellarPublicKey, "1000")');
  console.log('  createTrustline(recipientSecretKey)');
  console.log('');
}

// Export functions for use as module
export { sendGnsTokens, createTrustline, gnsPublicKeyToStellar };

// Run if executed directly
main().catch(console.error);
