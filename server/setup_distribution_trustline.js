// Setup GNS Trustline for Distribution Wallet
// Run: node setup_distribution_trustline.js

const StellarSdk = require('@stellar/stellar-sdk');

const CONFIG = {
  horizonUrl: 'https://horizon.stellar.org',
  networkPassphrase: StellarSdk.Networks.PUBLIC,
  gnsAssetCode: 'GNS',
  gnsIssuer: 'GBVZTFST4PIPV5C3APDIVULNZYZENQSLGDSOKOVQI77GSMT6WVYGF5GL',
};

// Distribution wallet secret (from Railway env)
const DISTRIBUTION_SECRET = 'SDPBNTDVSNSJFCTB5PZDYIED7GZQBEYL7KMKEXI4IMZYOSBTBHIQZMBU';

async function setupTrustline() {
  const server = new StellarSdk.Horizon.Server(CONFIG.horizonUrl);
  const keypair = StellarSdk.Keypair.fromSecret(DISTRIBUTION_SECRET);
  const gnsAsset = new StellarSdk.Asset(CONFIG.gnsAssetCode, CONFIG.gnsIssuer);
  
  console.log('Distribution Wallet:', keypair.publicKey());
  console.log('');
  
  try {
    // Load account
    const account = await server.loadAccount(keypair.publicKey());
    console.log('✅ Account loaded');
    
    // Check if trustline already exists
    const hasTrustline = account.balances.some(b => 
      b.asset_code === CONFIG.gnsAssetCode && 
      b.asset_issuer === CONFIG.gnsIssuer
    );
    
    if (hasTrustline) {
      console.log('✅ GNS Trustline already exists!');
      return;
    }
    
    console.log('Creating GNS trustline...');
    
    // Create trustline transaction
    const transaction = new StellarSdk.TransactionBuilder(account, {
      fee: StellarSdk.BASE_FEE,
      networkPassphrase: CONFIG.networkPassphrase,
    })
      .addOperation(StellarSdk.Operation.changeTrust({
        asset: gnsAsset,
      }))
      .setTimeout(30)
      .build();
    
    // Sign
    transaction.sign(keypair);
    
    // Submit
    const result = await server.submitTransaction(transaction);
    console.log('✅ Trustline created!');
    console.log('Transaction:', result.hash);
    console.log('');
    console.log('Now send GNS from LOBSTR to:', keypair.publicKey());
    
  } catch (error) {
    console.error('❌ Error:', error.message);
    if (error.response?.data?.extras?.result_codes) {
      console.error('Details:', error.response.data.extras.result_codes);
    }
  }
}

setupTrustline();
