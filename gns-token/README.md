# GNS Token Layer

Native token for the Global Navigation & Settlement (GNS) Protocol, built on Stellar.

## Why Stellar?

| Feature | Benefit for GNS |
|---------|-----------------|
| **Ed25519 keys** | Same as GNS identity keys - direct mapping |
| **$0.000001 fees** | Micro-rewards for validators viable |
| **3-5 sec finality** | Real-time reward distribution |
| **Built-in DEX** | GNS ↔ XLM ↔ USDC trading |
| **Anchors** | Maps to IDUP multi-rail routing |

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    GNS Protocol                             │
│  (Identity, Messaging, Presence, GeoAuth, IDUP)            │
└─────────────────────────┬───────────────────────────────────┘
                          │
                          │ Attestations / Validations
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                  GNS Token (Stellar)                        │
│                                                             │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐     │
│  │   ISSUER    │───▶│ DISTRIBUTION│───▶│  VALIDATORS │     │
│  │   (locked)  │    │   (hot)     │    │   (users)   │     │
│  └─────────────┘    └─────────────┘    └─────────────┘     │
│                                                             │
│  Asset: GNS                                                 │
│  Supply: 10 billion (fixed)                                 │
│  Decimals: 7                                                │
└─────────────────────────────────────────────────────────────┘
```

## Token Economics

### Supply Distribution

| Allocation | Percentage | Amount | Purpose |
|------------|------------|--------|---------|
| Network Rewards | 40% | 4B GNS | Validator rewards over 10+ years |
| Development | 20% | 2B GNS | Protocol development, team |
| Early Adopters | 20% | 2B GNS | First users, handle registration |
| Ecosystem | 15% | 1.5B GNS | Partnerships, integrations |
| Liquidity | 5% | 0.5B GNS | DEX, exchanges |

### Reward Schedule

| Action | Reward |
|--------|--------|
| Breadcrumb witness | 0.001 GNS |
| Transaction validation | 0.01 GNS |
| GeoAuth verification | 0.005 GNS |
| Daily node uptime | 1.0 GNS |
| Handle registration lock | 100-500 GNS |

### Value Drivers

1. **Fee burns** - Portion of each fee burned
2. **Staking locks** - Validators must lock tokens
3. **Handle registration** - Users lock tokens for @handles
4. **Network growth** - More usage = more demand

## Quick Start

### 1. Install Dependencies

```bash
npm install
```

### 2. Create Issuer Account (Testnet)

```bash
npm run 01:create-issuer
```

This creates:
- Issuer account (source of all GNS tokens)
- Distribution account (hot wallet for rewards)

Save the output to `.env`:

```env
GNS_ISSUER_PUBLIC=GXXXX...
GNS_ISSUER_SECRET=SXXXX...
GNS_DISTRIBUTION_PUBLIC=GXXXX...
GNS_DISTRIBUTION_SECRET=SXXXX...
STELLAR_NETWORK=TESTNET
STELLAR_HORIZON_URL=https://horizon-testnet.stellar.org
```

### 3. Issue GNS Token

```bash
npm run 02:issue-token
```

This:
- Creates trustline from distribution → issuer
- Mints 4 billion GNS to distribution account

### 4. Send Tokens

```bash
npm run 03:send-tokens
```

### 5. Distribute Validator Rewards

```bash
npm run 04:validator-rewards
```

## Key Insight: GNS Identity = Stellar Wallet

Your GNS identity public key (Ed25519) maps directly to a Stellar account:

```
@caterve GNS identity: 26b9c6a8eda4130a...
                       ↓
@caterve Stellar key:  GXXXXXXXXXXXXXXXXX...
```

No separate wallet needed. Your identity IS your wallet.

## Files

```
gns-token/
├── src/
│   ├── 01-create-issuer.ts    # Create issuer + distribution accounts
│   ├── 02-issue-token.ts      # Issue GNS token, mint to distribution
│   ├── 03-send-tokens.ts      # Send tokens to users
│   └── 04-validator-rewards.ts # Reward distribution system
├── .env.example               # Environment template
├── package.json
├── tsconfig.json
└── README.md
```

## Testnet vs Mainnet

| | Testnet | Mainnet |
|--|---------|---------|
| Horizon | horizon-testnet.stellar.org | horizon.stellar.org |
| Funding | Friendbot (free) | Real XLM required |
| Purpose | Development | Production |

## View Your Token

After issuing on testnet:

```
https://stellar.expert/explorer/testnet/asset/GNS-{ISSUER_PUBLIC_KEY}
```

## Security Notes

- **Issuer secret key**: Store offline (cold wallet). Can be locked permanently.
- **Distribution secret**: Hot wallet, multi-sig recommended.
- **User keys**: Same as GNS identity keys - user controls.

## Integration with GNS Browser App

```dart
// In Flutter app, convert GNS keypair to Stellar
final gnsKeypair = identityWallet.keypair;
final stellarPublicKey = gnsPublicKeyToStellar(gnsKeypair.publicKey);

// Check GNS balance
final balance = await stellarService.getBalance(stellarPublicKey, 'GNS');
```

## Next Steps

1. [ ] Lock issuer account (no more minting)
2. [ ] Implement staking contracts
3. [ ] Add fee burns
4. [ ] DEX liquidity pool
5. [ ] Mainnet deployment
