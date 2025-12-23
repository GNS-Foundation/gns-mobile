#!/usr/bin/env ts-node
// ===========================================
// GNS HOME HUB - TEST CLI
// Quick tests and demos
// ===========================================

import * as readline from 'readline';
import { getDeviceManager } from './device-manager';
import { getRecoveryManager } from './recovery-manager';
import * as vaultStorage from './vault-storage';
import * as crypto from './crypto';
import { DeviceConfig } from './types';

// ===========================================
// Test Setup
// ===========================================

const deviceManager = getDeviceManager(true); // Simulate mode

// Add a simulated TV
const testTV: DeviceConfig = {
  id: 'samsung_tv_test',
  name: 'Test Samsung TV',
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

deviceManager.registerDevice(testTV);

// Create a test user vault
const testUserKey = crypto.generateKeypair();
console.log(`\n🧪 Test user public key: ${testUserKey.publicKey.substring(0, 32)}...`);

vaultStorage.upsertVault(testUserKey.publicKey, {
  handle: 'testuser',
  role: 'owner',
  permissions: {
    'samsung_tv_test': ['power', 'volume', 'mute', 'apps'],
  },
  backup: {
    version: 1,
    encryptedSeed: 'mock_encrypted_seed_data',
    nonce: 'mock_nonce',
    lastSync: new Date().toISOString(),
  },
});

// ===========================================
// CLI Interface
// ===========================================

const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout,
});

function prompt(): void {
  rl.question('\n🏠 home> ', async (input) => {
    const [cmd, ...args] = input.trim().split(' ');
    
    switch (cmd?.toLowerCase()) {
      case 'help':
        console.log(`
Available commands:
  devices              - List all devices
  status <device_id>   - Get device status
  tv <action> [value]  - Control TV (power, volume_up, volume_down, mute, app <name>)
  recovery <handle>    - Start recovery for handle
  verify <session> <pin> - Verify recovery PIN
  users                - List users
  quit                 - Exit
        `);
        break;

      case 'devices':
        const devices = deviceManager.getAllDevices();
        console.log('\n📱 Registered Devices:');
        for (const d of devices) {
          const status = await deviceManager.getDeviceStatus(d.id);
          console.log(`  - ${d.name} (${d.id})`);
          console.log(`    Type: ${d.type}, Protocol: ${d.protocol}`);
          console.log(`    Status:`, status?.state || 'unknown');
        }
        break;

      case 'status':
        if (!args[0]) {
          console.log('Usage: status <device_id>');
          break;
        }
        const deviceStatus = await deviceManager.getDeviceStatus(args[0]);
        if (deviceStatus) {
          console.log(`\n📊 Status for ${args[0]}:`);
          console.log(JSON.stringify(deviceStatus, null, 2));
        } else {
          console.log('Device not found');
        }
        break;

      case 'tv':
        if (!args[0]) {
          console.log('Usage: tv <action> [value]');
          console.log('Actions: power, volume_up, volume_down, mute, app <name>');
          break;
        }
        const tvAction = args[0];
        const tvValue = args[1];
        
        console.log(`\n📺 Sending to TV: ${tvAction}${tvValue ? ` (${tvValue})` : ''}`);
        const tvResult = await deviceManager.executeCommand('samsung_tv_test', tvAction, tvValue);
        
        if (tvResult.success) {
          console.log('✅ Command executed');
          console.log('   State:', tvResult.state);
        } else {
          console.log('❌ Command failed:', tvResult.error);
        }
        break;

      case 'recovery':
        if (!args[0]) {
          console.log('Usage: recovery <handle>');
          break;
        }
        const handle = args[0].replace('@', '');
        const newDeviceKey = crypto.generateKeypair().publicKey;
        
        const recoveryResult = getRecoveryManager().initiateRecovery(handle, newDeviceKey);
        if (recoveryResult.success) {
          console.log(`\n🔐 Recovery initiated for @${handle}`);
          console.log(`   Session ID: ${recoveryResult.sessionId}`);
          console.log(`   Check your TV for the PIN!`);
        } else {
          console.log(`❌ Recovery failed: ${recoveryResult.error}`);
        }
        break;

      case 'verify':
        if (!args[0] || !args[1]) {
          console.log('Usage: verify <session_id> <pin>');
          break;
        }
        const verifyResult = getRecoveryManager().verifyPin(args[0], args[1]);
        if (verifyResult.success) {
          console.log('\n✅ PIN verified! Backup retrieved:');
          console.log('   Encrypted seed available:', !!verifyResult.backup?.encryptedSeed);
        } else {
          console.log(`❌ Verification failed: ${verifyResult.error}`);
        }
        break;

      case 'users':
        const vaults = vaultStorage.getAllVaults();
        console.log('\n👥 Registered Users:');
        for (const v of vaults) {
          console.log(`  - @${v.handle || 'unknown'} (${v.role})`);
          console.log(`    Public Key: ${v.publicKey.substring(0, 32)}...`);
          console.log(`    Has Backup: ${!!v.backup.encryptedSeed}`);
          console.log(`    Last Seen: ${v.lastSeen}`);
        }
        break;

      case 'quit':
      case 'exit':
        console.log('👋 Goodbye!');
        rl.close();
        process.exit(0);

      case '':
        break;

      default:
        console.log(`Unknown command: ${cmd}. Type 'help' for available commands.`);
    }
    
    prompt();
  });
}

// ===========================================
// Run
// ===========================================

console.log('\n' + '═'.repeat(50));
console.log('   GNS HOME HUB - TEST CLI');
console.log('   Type "help" for available commands');
console.log('═'.repeat(50));

prompt();
