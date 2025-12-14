# 🌍 GNS Browser

**Identity through Presence**

- Identity = Public Key (Ed25519)
- Trust = Proof-of-Trajectory (breadcrumbs over time)
- No DNS, no passwords, no phone numbers

## Setup
```bash
flutter pub get
flutter run
```

## Architecture

- `lib/core/crypto/` - Ed25519 keys, secure storage
- `lib/core/privacy/` - H3 location quantization
- `lib/core/chain/` - Breadcrumb blockchain
- `lib/core/gns/` - GNS records, identity wallet
