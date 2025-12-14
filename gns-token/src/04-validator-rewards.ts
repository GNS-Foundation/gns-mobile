// ===========================================
// GNS Token Layer - Step 4: Validator Rewards
// ===========================================
// This script demonstrates how GNS rewards validators
// (mobile devices that verify breadcrumbs/transactions)

import * as StellarSdk from '@stellar/stellar-sdk';
import * as dotenv from 'dotenv';

dotenv.config();

const HORIZON_URL = process.env.STELLAR_HORIZON_URL || 'https://horizon-testnet.stellar.org';
const NETWORK_PASSPHRASE = StellarSdk.Networks.TESTNET;

// Reward configuration
const REWARDS = {
  breadcrumbWitness: '0.001',     // Witnessing a breadcrumb
  transactionValidation: '0.01', // Validating a payment
  geoAuthVerification: '0.005',  // GeoAuth presence proof
  uptimeBonus: '1.0',            // Daily uptime reward for nodes
};

interface ValidatorAction {
  validatorKey: string;  // Stellar public key of validator
  actionType: 'breadcrumb' | 'transaction' | 'geoauth' | 'uptime';
  details: string;
  timestamp: Date;
}

/**
 * Calculate reward amount for an action
 */
function getRewardAmount(actionType: ValidatorAction['actionType']): string {
  switch (actionType) {
    case 'breadcrumb':
      return REWARDS.breadcrumbWitness;
    case 'transaction':
      return REWARDS.transactionValidation;
    case 'geoauth':
      return REWARDS.geoAuthVerification;
    case 'uptime':
      return REWARDS.uptimeBonus;
    default:
      return '0';
  }
}

/**
 * Distribute rewards to multiple validators in a single transaction
 * Stellar supports up to 100 operations per transaction
 */
async function distributeRewards(actions: ValidatorAction[]) {
  console.log('');
  console.log('╔════════════════════════════════════════════════════════════╗');
  console.log('║           GNS TOKEN - VALIDATOR REWARDS                    ║');
  console.log('╚════════════════════════════════════════════════════════════╝');
  console.log('');

  const issuerPublic = process.env.GNS_ISSUER_PUBLIC;
  const distributionSecret = process.env.GNS_DISTRIBUTION_SECRET;

  if (!issuerPublic || !distributionSecret) {
    console.error('❌ Missing environment variables!');
    process.exit(1);
  }

  const distributionKeypair = StellarSdk.Keypair.fromSecret(distributionSecret);
  const gnsAsset = new StellarSdk.Asset('GNS', issuerPublic);
  const server = new StellarSdk.Horizon.Server(HORIZON_URL);

  console.log(`📊 Processing ${actions.length} validator rewards...\n`);

  // Group rewards by validator (aggregate multiple actions)
  const rewardsByValidator = new Map<string, number>();
  
  for (const action of actions) {
    const amount = parseFloat(getRewardAmount(action.actionType));
    const current = rewardsByValidator.get(action.validatorKey) || 0;
    rewardsByValidator.set(action.validatorKey, current + amount);
    
    console.log(`   ${action.actionType}: ${amount} GNS → ${action.validatorKey.slice(0, 8)}...`);
  }

  console.log('');
  console.log('📦 Aggregated rewards:');
  
  // Build transaction with all payments
  const distributionAccount = await server.loadAccount(distributionKeypair.publicKey());
  
  let txBuilder = new StellarSdk.TransactionBuilder(distributionAccount, {
    fee: StellarSdk.BASE_FEE,
    networkPassphrase: NETWORK_PASSPHRASE,
  });

  let totalRewards = 0;
  
  for (const [validatorKey, amount] of rewardsByValidator) {
    console.log(`   ${validatorKey.slice(0, 12)}...: ${amount.toFixed(7)} GNS`);
    totalRewards += amount;
    
    // Note: In production, check if validator has trustline first
    // For now, we assume they do
    txBuilder = txBuilder.addOperation(
      StellarSdk.Operation.payment({
        destination: validatorKey,
        asset: gnsAsset,
        amount: amount.toFixed(7),
      })
    );
  }

  console.log('');
  console.log(`💰 Total rewards: ${totalRewards.toFixed(7)} GNS`);
  console.log('');

  // In demo mode, don't actually submit
  console.log('🔸 Demo mode - transaction not submitted');
  console.log('   In production, this would send rewards to all validators');
  console.log('');

  // Uncomment to actually send:
  // const tx = txBuilder.setTimeout(30).build();
  // tx.sign(distributionKeypair);
  // const result = await server.submitTransaction(tx);
  // console.log('✅ Rewards distributed! Tx:', result.hash);
}

/**
 * Example: Reward a single validator for witnessing a breadcrumb
 */
async function rewardBreadcrumbWitness(
  witnessKey: string,
  breadcrumbHash: string,
  witnessedIdentity: string
) {
  console.log('🥖 Breadcrumb Witness Reward');
  console.log(`   Witness: ${witnessKey.slice(0, 12)}...`);
  console.log(`   Breadcrumb: ${breadcrumbHash.slice(0, 16)}...`);
  console.log(`   Identity: ${witnessedIdentity}`);
  console.log(`   Reward: ${REWARDS.breadcrumbWitness} GNS`);
  console.log('');
  
  // In production: verify the witness actually saw this breadcrumb
  // Then pay the reward
}

/**
 * Calculate daily uptime rewards for all active nodes
 */
async function calculateDailyUptimeRewards() {
  console.log('');
  console.log('📅 Daily Uptime Reward Calculation');
  console.log('');
  
  // In production, this would:
  // 1. Query all registered nodes
  // 2. Check their uptime percentage
  // 3. Calculate pro-rata rewards
  // 4. Distribute via batch transaction
  
  const mockNodes = [
    { key: 'GABCD...', uptime: 99.9, reward: 1.0 },
    { key: 'GEFGH...', uptime: 95.0, reward: 0.95 },
    { key: 'GIJKL...', uptime: 80.0, reward: 0.80 },
  ];
  
  console.log('   Node             Uptime    Reward');
  console.log('   ─────────────────────────────────');
  
  for (const node of mockNodes) {
    console.log(`   ${node.key}    ${node.uptime.toFixed(1)}%    ${node.reward.toFixed(2)} GNS`);
  }
  
  console.log('');
}

// ===========================================
// Demo execution
// ===========================================

async function main() {
  console.log('');
  console.log('═══════════════════════════════════════════════════════════════');
  console.log('   GNS VALIDATOR REWARDS DEMO');
  console.log('═══════════════════════════════════════════════════════════════');
  
  // Example validator actions
  const mockActions: ValidatorAction[] = [
    {
      validatorKey: 'GABCDEFGHIJKLMNOPQRSTUVWXYZ234567ABCDEFGHIJKLMNOP',
      actionType: 'breadcrumb',
      details: 'Witnessed @alice at H3 cell 8a2a1072b59ffff',
      timestamp: new Date(),
    },
    {
      validatorKey: 'GABCDEFGHIJKLMNOPQRSTUVWXYZ234567ABCDEFGHIJKLMNOP',
      actionType: 'transaction',
      details: 'Validated payment @alice → @bob',
      timestamp: new Date(),
    },
    {
      validatorKey: 'GEFGHIJKLMNOPQRSTUVWXYZ234567ABCDEFGHIJKLMNOPQRST',
      actionType: 'geoauth',
      details: 'Verified @merchant GeoAuth challenge',
      timestamp: new Date(),
    },
    {
      validatorKey: 'GABCDEFGHIJKLMNOPQRSTUVWXYZ234567ABCDEFGHIJKLMNOP',
      actionType: 'breadcrumb',
      details: 'Witnessed @bob at H3 cell 8a2a1072b59ffff',
      timestamp: new Date(),
    },
  ];
  
  await distributeRewards(mockActions);
  
  await rewardBreadcrumbWitness(
    'GXYZABC...',
    'abc123def456...',
    '@caterve'
  );
  
  await calculateDailyUptimeRewards();
  
  console.log('');
  console.log('═══════════════════════════════════════════════════════════════');
  console.log('   Reward Types & Amounts');
  console.log('═══════════════════════════════════════════════════════════════');
  console.log('');
  console.log(`   Breadcrumb witness:     ${REWARDS.breadcrumbWitness} GNS`);
  console.log(`   Transaction validation: ${REWARDS.transactionValidation} GNS`);
  console.log(`   GeoAuth verification:   ${REWARDS.geoAuthVerification} GNS`);
  console.log(`   Daily uptime bonus:     ${REWARDS.uptimeBonus} GNS`);
  console.log('');
}

export { distributeRewards, rewardBreadcrumbWitness, getRewardAmount };

main().catch(console.error);
