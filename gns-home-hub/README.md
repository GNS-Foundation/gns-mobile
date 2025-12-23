# GNS Home Hub

**IoT Gateway + Identity Vault for GNS (Globe Crumbs)**

The GNS Home Hub is a Raspberry Pi (or Mac/PC) server that:
1. 🏠 **Controls IoT devices** - Samsung TV, lights, etc. via GNS commands
2. 🔐 **Backs up identity** - Encrypted vault for your Ed25519 keypair
3. 📺 **Enables recovery** - PIN-on-TV for secure identity recovery

## Quick Start

### Prerequisites
- Node.js 18+ 
- npm or yarn

### Installation

```bash
# Clone/download the gns-home-hub folder
cd gns-home-hub

# Install dependencies
npm install

# Run in simulation mode (no real devices)
npm run dev -- --simulate

# Or build and run
npm run build
npm start -- --simulate
```

### First Run

On first run, the hub will:
1. Generate its own Ed25519 identity
2. Create a `data/` folder for storage
3. Start the HTTP server on port 3500
4. Start the WebSocket server on `/ws`

The first user to sync becomes the **owner**.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        GNS HOME HUB                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐              │
│  │   Device    │  │   Vault     │  │  Recovery   │              │
│  │   Manager   │  │   Storage   │  │  Manager    │              │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘              │
│         │                │                │                     │
│  ┌──────┴────────────────┴────────────────┴──────┐              │
│  │                  Express API                   │              │
│  │              + WebSocket Server                │              │
│  └───────────────────────┬───────────────────────┘              │
│                          │                                      │
└──────────────────────────┼──────────────────────────────────────┘
                           │
           ┌───────────────┼───────────────┐
           │               │               │
           ▼               ▼               ▼
      ┌─────────┐    ┌─────────┐    ┌─────────┐
      │ GNS App │    │ Samsung │    │  Other  │
      │ (Phone) │    │   TV    │    │ Devices │
      └─────────┘    └─────────┘    └─────────┘
```

## API Endpoints

### Hub Info
- `GET /api/hub` - Get hub info
- `GET /api/hub/qr` - Get pairing QR code

### Devices
- `GET /api/devices` - List all devices
- `GET /api/devices/:id` - Get device status
- `POST /api/devices` - Register device (owner only)
- `POST /api/command` - Execute device command

### Backup & Sync
- `POST /api/sync` - Sync backup from phone
- `POST /api/backup` - Store full backup package

### Recovery
- `POST /api/recovery/initiate` - Start recovery (shows PIN on TV)
- `POST /api/recovery/verify` - Verify PIN, get backup
- `GET /api/recovery/status/:id` - Check session status

## Device Control

### Samsung TV

Commands via `/api/command`:

```json
{
  "device": "samsung_tv_living",
  "action": "power",
  "value": "on"
}
```

Available actions:
- `power` - Toggle or set ("on"/"off")
- `volume_up` / `volume_down` - Adjust volume
- `mute` - Toggle mute
- `app` - Launch app (value: "netflix", "youtube", etc.)
- `key` - Send remote key (value: "home", "back", "enter", etc.)

### Adding Your Samsung TV

1. Find your TV's IP address (Settings > Network > Network Status)
2. Find MAC address (for Wake-on-LAN)
3. Add device:

```bash
curl -X POST http://localhost:3500/api/devices \
  -H "Content-Type: application/json" \
  -H "X-GNS-PublicKey: YOUR_PUBLIC_KEY" \
  -d '{
    "id": "samsung_tv_living",
    "name": "Living Room TV",
    "type": "tv",
    "brand": "samsung",
    "protocol": "samsungtvws",
    "connection": {
      "ip": "192.168.1.XXX",
      "mac": "AA:BB:CC:DD:EE:FF"
    },
    "capabilities": ["power", "volume", "mute", "apps", "navigation"]
  }'
```

## Identity Recovery Flow

```
┌──────────────────────────────────────────────────────────────┐
│                     RECOVERY FLOW                             │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  1. User loses phone                                         │
│                                                              │
│  2. Gets new phone, installs GNS app                         │
│                                                              │
│  3. Taps "Recover Identity"                                  │
│     → Enters: @camiloayerbe                                  │
│     → App connects to Home Hub on local WiFi                 │
│                                                              │
│  4. Hub generates 6-digit PIN                                │
│     → Displays on Samsung TV: "847291"                       │
│     → PIN expires in 5 minutes                               │
│                                                              │
│  5. User reads PIN from TV, enters in app                    │
│                                                              │
│  6. Hub verifies PIN → sends encrypted backup                │
│                                                              │
│  7. App decrypts with recovery key → Identity restored!      │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

## Security Model

- **All commands must be signed** with Ed25519 (or trusted on local network)
- **Backups are encrypted** with user's key - hub can't read them
- **Recovery requires physical presence** - must see TV PIN
- **Permissions per device** - guests can control some things, not others

## Running on Raspberry Pi

```bash
# SSH to your Pi
ssh pi@raspberrypi.local

# Install Node.js 18
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs

# Clone and run
git clone <repo> gns-home-hub
cd gns-home-hub
npm install
npm run build

# Run as service (optional)
sudo npm install -g pm2
pm2 start dist/index.js --name gns-home-hub
pm2 save
pm2 startup
```

### Recommended Pi Model

- **Raspberry Pi 4 (2GB+)** - Best performance
- **Raspberry Pi Zero 2 W** - Budget option, adequate for basic use
- **Raspberry Pi 3B+** - Good middle ground

## Test CLI

```bash
npm run dev:cli
```

Commands:
- `devices` - List devices
- `tv power` - Toggle TV power
- `tv volume_up` - Volume up
- `tv app netflix` - Launch Netflix
- `recovery testuser` - Test recovery flow
- `users` - List registered users

## Environment Variables

- `GNS_DATA_DIR` - Data directory (default: `./data`)
- `GNS_SIMULATE` - Run in simulation mode (`true`/`false`)
- `PORT` - Server port (default: `3500`)

## File Structure

```
gns-home-hub/
├── src/
│   ├── index.ts          # Main server
│   ├── crypto.ts         # Ed25519 + encryption
│   ├── types.ts          # TypeScript types
│   ├── vault-storage.ts  # Identity backup storage
│   ├── device-manager.ts # IoT device orchestration
│   ├── samsung-tv.ts     # Samsung TV controller
│   ├── recovery-manager.ts # PIN-based recovery
│   └── test-cli.ts       # Test CLI
├── data/                 # Runtime data (git-ignored)
│   ├── hub-identity.json # Hub's Ed25519 keypair
│   ├── hub-config.json   # Configuration
│   └── vaults.json       # User encrypted backups
├── package.json
├── tsconfig.json
└── README.md
```

## Next Steps

- [ ] Real Samsung TV testing
- [ ] Philips Hue integration
- [ ] GNS Relay connection for remote access
- [ ] TV app for PIN display
- [ ] Multi-hub support (vacation home, etc.)
- [ ] Flutter integration for home@ facet

## License

MIT - Part of the GNS (Globe Crumbs) project
