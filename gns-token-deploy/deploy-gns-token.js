/**
 * ===========================================
 * GNS TOKEN DEPLOYMENT SCRIPT - STELLAR MAINNET
 * ===========================================
 * 
 * This script deploys the GNS utility token on Stellar Mainnet.
 * 
 * Token Specifications:
 * - Asset Code: GNS
 * - Total Supply: 10,000,000,000 (10 Billion)
 * - Decimals: 7 (Stellar native)
 * - Issuer: Locked after issuance (no more minting possible)
 * 
 * IMPORTANT: Run this script ONCE. Save the issuer keys securely!
 * 
 * Usage:
 *   1. npm install stellar-sdk
 *   2. Set DISTRIBUTION_SECRET in .env or replace below
 *   3. node deploy-gns-token.js
 */

const StellarSdk = require('stellar-sdk');
const readline = require('readline');

// ===========================================
// CONFIGURATION - MAINNET
// ===========================================

const CONFIG = {
  // Stellar Mainnet
  horizonUrl: 'https://horizon.stellar.org',
  networkPassphrase: StellarSdk.Networks.PUBLIC,
  
  // GNS Token
  assetCode: 'GNS',
  totalSupply: '10000000000.0000000', // 10 billion with 7 decimals
  
  // Your distribution wallet (company wallet) - LOBSTR MAINNET
  distributionPublicKey: 'GBJDTANYZWPG7A2RFQZ5DXVAJ2SZLFLVMEQTKVZOMW3IAIP32EIVLEC7',
  
  // ⚠️ REPLACE THIS with your distribution wallet secret key
  // Format: S... (56 characters)
  distributionSecretKey: process.env.DISTRIBUTION_SECRET || 'YOUR_SECRET_KEY_HERE',
};

// ===========================================
// MAIN DEPLOYMENT FUNCTION
// ===========================================

async function deployGnsToken() {
  console.log('\n' + '='.repeat(60));
  console.log('🌐 GNS TOKEN DEPLOYMENT - STELLAR MAINNET');
  console.log('='.repeat(60));
  console.log('\n⚠️  THIS IS MAINNET - REAL MONEY/TOKENS');
  console.log('⚠️  Make sure you have saved all keys securely!\n');

  // Initialize Horizon server
  const server = new StellarSdk.Horizon.Server(CONFIG.horizonUrl);

  // Validate distribution secret key
  if (CONFIG.distributionSecretKey === 'YOUR_SECRET_KEY_HERE') {
    console.error('❌ ERROR: Please set your distribution wallet secret key!');
    console.error('   Edit this file or set DISTRIBUTION_SECRET environment variable');
    process.exit(1);
  }

  let distributionKeypair;
  try {
    distributionKeypair = StellarSdk.Keypair.fromSecret(CONFIG.distributionSecretKey);
    if (distributionKeypair.publicKey() !== CONFIG.distributionPublicKey) {
      console.error('❌ ERROR: Secret key does not match distribution public key!');
      process.exit(1);
    }
  } catch (e) {
    console.error('❌ ERROR: Invalid distribution secret key format');
    process.exit(1);
  }

  console.log('✅ Distribution wallet validated');
  console.log(`   Public: ${CONFIG.distributionPublicKey}`);

  // ===========================================
  // STEP 1: Generate Issuer Keypair
  // ===========================================
  console.log('\n' + '-'.repeat(60));
  console.log('STEP 1: Generating Issuer Keypair');
  console.log('-'.repeat(60));

  const issuerKeypair = StellarSdk.Keypair.random();
  
  console.log('\n🔐 ISSUER KEYPAIR (SAVE THIS SECURELY!)');
  console.log('═'.repeat(60));
  console.log(`   Public Key:  ${issuerKeypair.publicKey()}`);
  console.log(`   Secret Key:  ${issuerKeypair.secret()}`);
  console.log('═'.repeat(60));
  console.log('\n⚠️  WRITE DOWN THE SECRET KEY AND STORE IN A SAFE!');
  console.log('⚠️  You will need it if you ever need to modify the issuer.');
  console.log('⚠️  After locking, the secret becomes mostly ceremonial.\n');

  // Confirm to proceed
  const confirmed = await askConfirmation(
    'Have you saved the issuer keypair? Type "yes" to continue: '
  );
  if (!confirmed) {
    console.log('❌ Deployment cancelled. Save the keypair and try again.');
    process.exit(0);
  }

  // ===========================================
  // STEP 2: Fund Issuer Account
  // ===========================================
  console.log('\n' + '-'.repeat(60));
  console.log('STEP 2: Funding Issuer Account');
  console.log('-'.repeat(60));

  try {
    // Check distribution account balance
    const distAccount = await server.loadAccount(CONFIG.distributionPublicKey);
    const xlmBalance = distAccount.balances.find(b => b.asset_type === 'native');
    console.log(`   Distribution wallet XLM: ${xlmBalance?.balance || '0'}`);

    if (parseFloat(xlmBalance?.balance || '0') < 5) {
      console.error('❌ ERROR: Need at least 5 XLM in distribution wallet');
      console.error('   Current balance:', xlmBalance?.balance || '0');
      process.exit(1);
    }

    // Create and fund issuer account with 2.5 XLM
    console.log('   Creating issuer account with 2.5 XLM...');
    
    const fundTx = new StellarSdk.TransactionBuilder(distAccount, {
      fee: StellarSdk.BASE_FEE,
      networkPassphrase: CONFIG.networkPassphrase,
    })
      .addOperation(StellarSdk.Operation.createAccount({
        destination: issuerKeypair.publicKey(),
        startingBalance: '2.5',
      }))
      .setTimeout(30)
      .build();

    fundTx.sign(distributionKeypair);
    await server.submitTransaction(fundTx);
    
    console.log('✅ Issuer account created and funded');
  } catch (e) {
    console.error('❌ ERROR funding issuer:', e.message);
    if (e.response?.data?.extras?.result_codes) {
      console.error('   Stellar error:', JSON.stringify(e.response.data.extras.result_codes));
    }
    process.exit(1);
  }

  // ===========================================
  // STEP 3: Create Trustline
  // ===========================================
  console.log('\n' + '-'.repeat(60));
  console.log('STEP 3: Creating Trustline (Distribution → GNS)');
  console.log('-'.repeat(60));

  try {
    const distAccount = await server.loadAccount(CONFIG.distributionPublicKey);
    
    const gnsAsset = new StellarSdk.Asset(CONFIG.assetCode, issuerKeypair.publicKey());
    
    const trustTx = new StellarSdk.TransactionBuilder(distAccount, {
      fee: StellarSdk.BASE_FEE,
      networkPassphrase: CONFIG.networkPassphrase,
    })
      .addOperation(StellarSdk.Operation.changeTrust({
        asset: gnsAsset,
        limit: CONFIG.totalSupply,
      }))
      .setTimeout(30)
      .build();

    trustTx.sign(distributionKeypair);
    await server.submitTransaction(trustTx);
    
    console.log('✅ Trustline created');
    console.log(`   Asset: ${CONFIG.assetCode}`);
    console.log(`   Issuer: ${issuerKeypair.publicKey()}`);
    console.log(`   Limit: ${CONFIG.totalSupply}`);
  } catch (e) {
    console.error('❌ ERROR creating trustline:', e.message);
    process.exit(1);
  }

  // ===========================================
  // STEP 4: Issue Tokens
  // ===========================================
  console.log('\n' + '-'.repeat(60));
  console.log('STEP 4: Issuing 10 Billion GNS Tokens');
  console.log('-'.repeat(60));

  try {
    const issuerAccount = await server.loadAccount(issuerKeypair.publicKey());
    
    const gnsAsset = new StellarSdk.Asset(CONFIG.assetCode, issuerKeypair.publicKey());
    
    const issueTx = new StellarSdk.TransactionBuilder(issuerAccount, {
      fee: StellarSdk.BASE_FEE,
      networkPassphrase: CONFIG.networkPassphrase,
    })
      .addOperation(StellarSdk.Operation.payment({
        destination: CONFIG.distributionPublicKey,
        asset: gnsAsset,
        amount: CONFIG.totalSupply,
      }))
      .setTimeout(30)
      .build();

    issueTx.sign(issuerKeypair);
    const issueResult = await server.submitTransaction(issueTx);
    
    console.log('✅ Tokens issued!');
    console.log(`   Amount: ${CONFIG.totalSupply} GNS`);
    console.log(`   To: ${CONFIG.distributionPublicKey}`);
    console.log(`   Tx Hash: ${issueResult.hash}`);
  } catch (e) {
    console.error('❌ ERROR issuing tokens:', e.message);
    process.exit(1);
  }

  // ===========================================
  // STEP 5: Lock Issuer (IRREVERSIBLE!)
  // ===========================================
  console.log('\n' + '-'.repeat(60));
  console.log('STEP 5: Locking Issuer Account (IRREVERSIBLE!)');
  console.log('-'.repeat(60));
  console.log('\n⚠️  WARNING: This will permanently prevent minting more GNS!');
  console.log('⚠️  The total supply will be fixed at 10 billion forever.\n');

  const lockConfirmed = await askConfirmation(
    'Type "LOCK" to permanently lock the issuer: '
  );
  
  if (lockConfirmed !== 'LOCK') {
    console.log('\n⚠️  Issuer NOT locked. You can lock it manually later.');
    console.log('   To lock manually, set master weight to 0 on the issuer account.');
  } else {
    try {
      const issuerAccount = await server.loadAccount(issuerKeypair.publicKey());
      
      const lockTx = new StellarSdk.TransactionBuilder(issuerAccount, {
        fee: StellarSdk.BASE_FEE,
        networkPassphrase: CONFIG.networkPassphrase,
      })
        .addOperation(StellarSdk.Operation.setOptions({
          masterWeight: 0,  // Removes all signing authority
        }))
        .setTimeout(30)
        .build();

      lockTx.sign(issuerKeypair);
      await server.submitTransaction(lockTx);
      
      console.log('✅ Issuer account LOCKED!');
      console.log('   No more GNS tokens can ever be minted.');
      console.log('   Total supply is fixed at 10,000,000,000 GNS');
    } catch (e) {
      console.error('❌ ERROR locking issuer:', e.message);
      console.log('   You may need to lock manually later.');
    }
  }

  // ===========================================
  // DEPLOYMENT COMPLETE
  // ===========================================
  console.log('\n' + '='.repeat(60));
  console.log('🎉 GNS TOKEN DEPLOYMENT COMPLETE!');
  console.log('='.repeat(60));
  
  console.log('\n📋 TOKEN DETAILS:');
  console.log('─'.repeat(40));
  console.log(`   Asset Code:     ${CONFIG.assetCode}`);
  console.log(`   Issuer:         ${issuerKeypair.publicKey()}`);
  console.log(`   Total Supply:   10,000,000,000 GNS`);
  console.log(`   Distribution:   ${CONFIG.distributionPublicKey}`);
  console.log('─'.repeat(40));

  console.log('\n🔗 VIEW ON STELLAR EXPERT:');
  console.log(`   https://stellar.expert/explorer/public/asset/${CONFIG.assetCode}-${issuerKeypair.publicKey()}`);

  console.log('\n📝 UPDATE YOUR CODE:');
  console.log('   In stellar_service.dart, update:');
  console.log(`   static const String gnsIssuerPublic = '${issuerKeypair.publicKey()}';`);
  console.log(`   static bool useTestnet = false;  // Switch to mainnet!`);

  console.log('\n✅ All done! Your GNS tokens are ready.\n');
}

// ===========================================
// HELPER FUNCTIONS
// ===========================================

function askConfirmation(question) {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });

  return new Promise((resolve) => {
    rl.question(question, (answer) => {
      rl.close();
      if (question.includes('LOCK')) {
        resolve(answer.trim());
      } else {
        resolve(answer.trim().toLowerCase() === 'yes');
      }
    });
  });
}

// ===========================================
// RUN
// ===========================================

deployGnsToken().catch((e) => {
  console.error('\n❌ DEPLOYMENT FAILED:', e.message);
  process.exit(1);
});
