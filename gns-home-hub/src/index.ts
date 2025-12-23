// ===========================================
// GNS HOME HUB - MAIN SERVER
// IoT Gateway + Identity Vault
// ===========================================

import express, { Request, Response, NextFunction } from 'express';
import { WebSocketServer, WebSocket } from 'ws';
import { createServer } from 'http';
import * as crypto from './crypto';
import * as vaultStorage from './vault-storage';
import { getDeviceManager, DeviceManager } from './device-manager';
import { getRecoveryManager, RecoveryManager } from './recovery-manager';
import { HubConfig, HubIdentity, HomeCommand, DeviceConfig } from './types';
import * as fs from 'fs';
import * as path from 'path';
import * as QRCode from 'qrcode';

// ===========================================
// Configuration
// ===========================================

const DATA_DIR = process.env.GNS_DATA_DIR || './data';
const CONFIG_FILE = path.join(DATA_DIR, 'hub-config.json');
const IDENTITY_FILE = path.join(DATA_DIR, 'hub-identity.json');

const DEFAULT_CONFIG: HubConfig = {
  name: 'GNS Home Hub',
  owner: '',
  relayUrl: 'wss://gns-relay.railway.app/ws',
  localPort: 3500,
  autoSync: true,
  devices: [],
};

// ===========================================
// Hub State
// ===========================================

let config: HubConfig = DEFAULT_CONFIG;
let hubIdentity: HubIdentity | null = null;
let deviceManager: DeviceManager;
let recoveryManager: RecoveryManager;

// Connected local clients (phones on WiFi)
const localClients: Map<string, WebSocket> = new Map();

// Current PIN displayed on TV (for recovery)
let currentRecoveryDisplay: { pin: string; handle: string } | null = null;

// ===========================================
// Initialization
// ===========================================

function loadOrCreateIdentity(): HubIdentity {
  // Ensure data directory exists
  if (!fs.existsSync(DATA_DIR)) {
    fs.mkdirSync(DATA_DIR, { recursive: true });
  }

  // Load existing identity
  if (fs.existsSync(IDENTITY_FILE)) {
    try {
      const data = JSON.parse(fs.readFileSync(IDENTITY_FILE, 'utf-8'));
      console.log(`🔑 Hub identity loaded: ${data.publicKey.substring(0, 16)}...`);
      return data;
    } catch (error) {
      console.error('Failed to load identity, generating new one');
    }
  }

  // Generate new identity
  const keypair = crypto.generateKeypair();
  const identity: HubIdentity = {
    publicKey: keypair.publicKey,
    secretKey: keypair.secretKey,
    name: config.name,
    createdAt: new Date().toISOString(),
  };

  fs.writeFileSync(IDENTITY_FILE, JSON.stringify(identity, null, 2));
  console.log(`🔑 New hub identity generated: ${identity.publicKey.substring(0, 16)}...`);

  return identity;
}

function loadConfig(): HubConfig {
  if (fs.existsSync(CONFIG_FILE)) {
    try {
      const data = JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf-8'));
      console.log(`⚙️ Configuration loaded`);
      return { ...DEFAULT_CONFIG, ...data };
    } catch (error) {
      console.error('Failed to load config, using defaults');
    }
  }
  return DEFAULT_CONFIG;
}

function saveConfig(): void {
  fs.writeFileSync(CONFIG_FILE, JSON.stringify(config, null, 2));
}

// ===========================================
// Express App
// ===========================================

const app = express();
app.use(express.json());

// CORS for local development
app.use((req: Request, res: Response, next: NextFunction) => {
  res.header('Access-Control-Allow-Origin', '*');
  res.header('Access-Control-Allow-Headers', 'Origin, X-Requested-With, Content-Type, Accept, X-GNS-PublicKey, X-GNS-Signature, X-GNS-Timestamp');
  res.header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
  if (req.method === 'OPTIONS') {
    return res.sendStatus(200);
  }
  next();
});

// ===========================================
// Auth Middleware
// ===========================================

interface AuthRequest extends Request {
  gnsPublicKey?: string;
}

const verifyGnsAuth = (req: AuthRequest, res: Response, next: NextFunction) => {
  const publicKey = (req.headers['x-gns-publickey'] as string)?.toLowerCase();
  const timestamp = req.headers['x-gns-timestamp'] as string;
  const signature = req.headers['x-gns-signature'] as string;

  if (!publicKey || !crypto.isValidPublicKey(publicKey)) {
    return res.status(401).json({
      success: false,
      error: 'Missing or invalid X-GNS-PublicKey header',
    });
  }

  // For local network, we trust the public key
  // In production, verify signature
  // const message = `${timestamp}:${publicKey}`;
  // if (!crypto.verifySignature(publicKey, message, signature)) {
  //   return res.status(401).json({ success: false, error: 'Invalid signature' });
  // }

  req.gnsPublicKey = publicKey;
  next();
};

// ===========================================
// API Routes
// ===========================================

// --- Hub Info ---

app.get('/api/hub', (req: Request, res: Response) => {
  res.json({
    success: true,
    data: {
      name: config.name,
      publicKey: hubIdentity?.publicKey,
      owner: config.owner || null,
      deviceCount: config.devices.length,
      version: '0.1.0',
    },
  });
});

app.get('/api/hub/qr', async (req: Request, res: Response) => {
  // Generate QR code for pairing
  const pairingData = {
    type: 'gns-home-hub',
    publicKey: hubIdentity?.publicKey,
    name: config.name,
    localUrl: `http://${req.hostname}:${config.localPort}`,
  };

  try {
    const qr = await QRCode.toDataURL(JSON.stringify(pairingData));
    res.json({ success: true, data: { qr, pairingData } });
  } catch (error) {
    res.status(500).json({ success: false, error: 'Failed to generate QR' });
  }
});

// --- Devices ---

app.get('/api/devices', verifyGnsAuth, async (req: AuthRequest, res: Response) => {
  const devices = deviceManager.getAllDevices();
  const statuses = await deviceManager.getAllStatuses();

  res.json({
    success: true,
    data: devices.map(d => ({
      ...d,
      status: statuses[d.id],
    })),
  });
});

app.get('/api/devices/:id', verifyGnsAuth, async (req: AuthRequest, res: Response) => {
  const device = deviceManager.getDevice(req.params.id);
  if (!device) {
    return res.status(404).json({ success: false, error: 'Device not found' });
  }

  const status = await deviceManager.getDeviceStatus(req.params.id);
  res.json({ success: true, data: { ...device, status } });
});

app.post('/api/devices', verifyGnsAuth, (req: AuthRequest, res: Response) => {
  // Only owner can add devices
  if (config.owner && req.gnsPublicKey !== config.owner) {
    return res.status(403).json({ success: false, error: 'Only owner can add devices' });
  }

  const deviceConfig: DeviceConfig = req.body;
  deviceManager.registerDevice(deviceConfig);

  // Save to config
  config.devices = config.devices.filter(d => d.id !== deviceConfig.id);
  config.devices.push(deviceConfig);
  saveConfig();

  res.json({ success: true, data: deviceConfig });
});

// --- Commands ---

app.post('/api/command', verifyGnsAuth, async (req: AuthRequest, res: Response) => {
  const { device, action, value, signature } = req.body;

  // Check permission
  if (!vaultStorage.hasPermission(req.gnsPublicKey!, device, action)) {
    return res.status(403).json({ 
      success: false, 
      error: 'Permission denied for this action' 
    });
  }

  // Execute command
  const result = await deviceManager.executeCommand(device, action, value);

  res.json({
    success: result.success,
    data: result.state,
    error: result.error,
  });
});

// GNS Message format command (from relay or direct)
app.post('/api/gns/command', async (req: Request, res: Response) => {
  const command: HomeCommand = req.body;

  // Verify signature
  const dataToVerify = crypto.canonicalJson({
    device: command.payload.device,
    action: command.payload.action,
    value: command.payload.value,
    timestamp: command.timestamp,
  });

  if (!crypto.verifySignature(command.from, dataToVerify, command.signature)) {
    return res.status(401).json({ success: false, error: 'Invalid signature' });
  }

  // Check permission
  if (!vaultStorage.hasPermission(command.from, command.payload.device, command.payload.action)) {
    return res.status(403).json({ success: false, error: 'Permission denied' });
  }

  // Execute
  const result = await deviceManager.executeCommand(
    command.payload.device,
    command.payload.action,
    command.payload.value
  );

  // Sign response
  const responseData = {
    success: result.success,
    data: result.state,
    error: result.error,
  };
  const responseSignature = crypto.sign(
    hubIdentity!.secretKey,
    crypto.canonicalJson({ ...responseData, replyTo: command.id })
  );

  res.json({
    ...responseData,
    replyTo: command.id,
    signature: responseSignature,
  });
});

// --- Users & Vaults ---

app.get('/api/users', verifyGnsAuth, (req: AuthRequest, res: Response) => {
  // Only owner can list users
  if (config.owner && req.gnsPublicKey !== config.owner) {
    return res.status(403).json({ success: false, error: 'Only owner can list users' });
  }

  const vaults = vaultStorage.getAllVaults();
  res.json({
    success: true,
    data: vaults.map(v => ({
      publicKey: v.publicKey,
      handle: v.handle,
      role: v.role,
      lastSeen: v.lastSeen,
      hasBackup: !!v.backup.encryptedSeed,
    })),
  });
});

app.post('/api/users/invite', verifyGnsAuth, (req: AuthRequest, res: Response) => {
  // Only owner can invite
  if (config.owner && req.gnsPublicKey !== config.owner) {
    return res.status(403).json({ success: false, error: 'Only owner can invite users' });
  }

  const { publicKey, handle, permissions } = req.body;

  const vault = vaultStorage.upsertVault(publicKey, {
    handle,
    role: 'member',
    permissions: permissions || {},
  });

  res.json({ success: true, data: vault });
});

// --- Backup & Sync ---

app.post('/api/sync', verifyGnsAuth, async (req: AuthRequest, res: Response) => {
  const { backup, delta, lastSync } = req.body;

  // Get or create vault
  let vault = vaultStorage.getVault(req.gnsPublicKey!);
  if (!vault) {
    // First sync - create vault
    // If no owner set, this becomes the owner
    const isOwner = !config.owner;
    if (isOwner) {
      config.owner = req.gnsPublicKey!;
      saveConfig();
      console.log(`👑 Owner set: ${req.gnsPublicKey!.substring(0, 16)}...`);
    }

    vault = vaultStorage.upsertVault(req.gnsPublicKey!, {
      role: isOwner ? 'owner' : 'member',
      permissions: isOwner ? { '*': ['all'] } : {},
    });
  }

  // Update backup
  if (backup) {
    vaultStorage.updateBackup(req.gnsPublicKey!, backup);
  }

  // Touch vault
  vaultStorage.touchVault(req.gnsPublicKey!);

  res.json({
    success: true,
    data: {
      syncedAt: new Date().toISOString(),
      vaultExists: true,
    },
  });
});

app.post('/api/backup', verifyGnsAuth, (req: AuthRequest, res: Response) => {
  const backupPackage = req.body;

  try {
    vaultStorage.storeBackupPackage(req.gnsPublicKey!, backupPackage);
    res.json({ success: true, data: { storedAt: new Date().toISOString() } });
  } catch (error) {
    res.status(500).json({ 
      success: false, 
      error: error instanceof Error ? error.message : 'Backup failed' 
    });
  }
});

// --- Recovery ---

app.post('/api/recovery/initiate', (req: Request, res: Response) => {
  const { handle, newDeviceKey } = req.body;

  if (!handle || !newDeviceKey) {
    return res.status(400).json({ 
      success: false, 
      error: 'Handle and newDeviceKey required' 
    });
  }

  const result = recoveryManager.initiateRecovery(handle, newDeviceKey);
  
  if (!result.success) {
    return res.status(404).json(result);
  }

  res.json({
    success: true,
    data: {
      sessionId: result.sessionId,
      message: 'Check your TV for the recovery PIN',
      expiresIn: 300, // 5 minutes
    },
  });
});

app.post('/api/recovery/verify', (req: Request, res: Response) => {
  const { sessionId, pin } = req.body;

  if (!sessionId || !pin) {
    return res.status(400).json({ 
      success: false, 
      error: 'SessionId and PIN required' 
    });
  }

  const result = recoveryManager.verifyPin(sessionId, pin);

  if (!result.success) {
    return res.status(400).json(result);
  }

  res.json({
    success: true,
    data: {
      backup: result.backup,
      message: 'Identity recovered! Decrypt with your recovery key.',
    },
  });
});

app.get('/api/recovery/status/:sessionId', (req: Request, res: Response) => {
  const status = recoveryManager.getSessionStatus(req.params.sessionId);
  res.json({ success: true, data: status });
});

// --- TV Display (for recovery PIN) ---

app.get('/api/tv/display', (req: Request, res: Response) => {
  res.json({
    success: true,
    data: currentRecoveryDisplay,
  });
});

// ===========================================
// WebSocket Server (local connections)
// ===========================================

const server = createServer(app);
const wss = new WebSocketServer({ server, path: '/ws' });

wss.on('connection', (ws: WebSocket, req) => {
  const url = new URL(req.url || '', `http://${req.headers.host}`);
  const publicKey = url.searchParams.get('pubkey')?.toLowerCase();

  if (!publicKey || !crypto.isValidPublicKey(publicKey)) {
    ws.close(4001, 'Invalid public key');
    return;
  }

  console.log(`🔌 Local client connected: ${publicKey.substring(0, 16)}...`);
  localClients.set(publicKey, ws);

  // Touch vault
  vaultStorage.touchVault(publicKey);

  ws.on('message', async (data: Buffer) => {
    try {
      const message = JSON.parse(data.toString());
      await handleWebSocketMessage(ws, publicKey, message);
    } catch (error) {
      console.error('WebSocket message error:', error);
    }
  });

  ws.on('close', () => {
    localClients.delete(publicKey);
    console.log(`🔌 Local client disconnected: ${publicKey.substring(0, 16)}...`);
  });

  // Send welcome
  ws.send(JSON.stringify({
    type: 'connected',
    hubPublicKey: hubIdentity?.publicKey,
    hubName: config.name,
  }));
});

async function handleWebSocketMessage(
  ws: WebSocket,
  publicKey: string,
  message: any
): Promise<void> {
  switch (message.type) {
    case 'command':
      // Check permission
      if (!vaultStorage.hasPermission(publicKey, message.device, message.action)) {
        ws.send(JSON.stringify({
          type: 'command_result',
          id: message.id,
          success: false,
          error: 'Permission denied',
        }));
        return;
      }

      const result = await deviceManager.executeCommand(
        message.device,
        message.action,
        message.value
      );

      ws.send(JSON.stringify({
        type: 'command_result',
        id: message.id,
        ...result,
      }));
      break;

    case 'sync':
      // Handle backup sync
      if (message.backup) {
        vaultStorage.updateBackup(publicKey, message.backup);
      }
      
      ws.send(JSON.stringify({
        type: 'sync_ack',
        timestamp: Date.now(),
      }));
      break;

    case 'ping':
      ws.send(JSON.stringify({ type: 'pong', timestamp: Date.now() }));
      break;
  }
}

// ===========================================
// Recovery Display Callback
// ===========================================

recoveryManager = getRecoveryManager();
recoveryManager.setDisplayCallback((pin: string, handle: string) => {
  if (pin && handle) {
    currentRecoveryDisplay = { pin, handle };
    console.log(`\n${'═'.repeat(50)}`);
    console.log(`📺 RECOVERY PIN FOR @${handle}`);
    console.log(`${'═'.repeat(50)}`);
    console.log(`\n   PIN: ${pin}\n`);
    console.log(`${'═'.repeat(50)}\n`);
    
    // TODO: Actually display on Samsung TV
    // For now, this would send to a TV app or use a notification
  } else {
    currentRecoveryDisplay = null;
    console.log('📺 Recovery PIN cleared');
  }
});

// ===========================================
// Startup
// ===========================================

async function start(): Promise<void> {
  console.log('\n' + '═'.repeat(50));
  console.log('   GNS HOME HUB');
  console.log('   IoT Gateway + Identity Vault');
  console.log('═'.repeat(50) + '\n');

  // Load config
  config = loadConfig();
  
  // Load or create identity
  hubIdentity = loadOrCreateIdentity();

  // Check for simulate mode
  const simulateMode = process.argv.includes('--simulate') || 
                       process.env.GNS_SIMULATE === 'true';

  // Initialize device manager
  deviceManager = getDeviceManager(simulateMode);

  // Register devices from config
  for (const device of config.devices) {
    deviceManager.registerDevice(device);
  }

  // If no devices and in simulate mode, add a simulated TV
  if (config.devices.length === 0 && simulateMode) {
    const simulatedTV: DeviceConfig = {
      id: 'samsung_tv_living',
      name: 'Living Room TV (Simulated)',
      type: 'tv',
      brand: 'samsung',
      protocol: 'samsungtvws',
      connection: {
        ip: '192.168.1.100',
        mac: 'AA:BB:CC:DD:EE:FF',
      },
      capabilities: ['power', 'volume', 'mute', 'apps', 'navigation'],
      status: { online: false, lastSeen: '', state: {} },
    };
    
    deviceManager.registerDevice(simulatedTV);
    config.devices.push(simulatedTV);
    saveConfig();
    console.log('📺 Added simulated Samsung TV for testing');
  }

  // Start server
  const port = config.localPort;
  server.listen(port, () => {
    console.log(`\n🏠 GNS Home Hub running on port ${port}`);
    console.log(`   Local:  http://localhost:${port}`);
    console.log(`   Hub ID: ${hubIdentity!.publicKey.substring(0, 16)}...`);
    
    if (config.owner) {
      console.log(`   Owner:  ${config.owner.substring(0, 16)}...`);
    } else {
      console.log(`   Owner:  Not yet set (first sync will claim)`);
    }
    
    console.log(`\n   Devices: ${config.devices.length}`);
    config.devices.forEach(d => {
      console.log(`   - ${d.name} (${d.type})`);
    });
    
    console.log('\n' + '─'.repeat(50));
    console.log('   API Endpoints:');
    console.log('   GET  /api/hub          - Hub info');
    console.log('   GET  /api/hub/qr       - Pairing QR code');
    console.log('   GET  /api/devices      - List devices');
    console.log('   POST /api/command      - Execute command');
    console.log('   POST /api/sync         - Sync backup');
    console.log('   POST /api/recovery/*   - Identity recovery');
    console.log('─'.repeat(50) + '\n');
    
    if (simulateMode) {
      console.log('🎮 Running in SIMULATION mode');
      console.log('   Commands will be simulated, not sent to real devices\n');
    }
  });

  // Connect to devices
  if (!simulateMode) {
    await deviceManager.connectAll();
  }
}

// Run
start().catch(console.error);
