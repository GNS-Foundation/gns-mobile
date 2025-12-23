// ===========================================
// GNS HOME HUB - SAMSUNG TV CONTROLLER
// Controls Samsung Smart TVs via local network
// ===========================================

import { EventEmitter } from 'events';
import * as net from 'net';
import * as dgram from 'dgram';
import { DeviceConfig, DeviceStatus, SamsungTVState, SamsungTVAction } from './types';

// Samsung TV WebSocket API keys
const SAMSUNG_KEYS: Record<string, string> = {
  'power': 'KEY_POWER',
  'volume_up': 'KEY_VOLUP',
  'volume_down': 'KEY_VOLDOWN',
  'mute': 'KEY_MUTE',
  'channel_up': 'KEY_CHUP',
  'channel_down': 'KEY_CHDOWN',
  'home': 'KEY_HOME',
  'back': 'KEY_RETURN',
  'enter': 'KEY_ENTER',
  'up': 'KEY_UP',
  'down': 'KEY_DOWN',
  'left': 'KEY_LEFT',
  'right': 'KEY_RIGHT',
  'play': 'KEY_PLAY',
  'pause': 'KEY_PAUSE',
  'stop': 'KEY_STOP',
  'source': 'KEY_SOURCE',
  'menu': 'KEY_MENU',
  'tools': 'KEY_TOOLS',
  'info': 'KEY_INFO',
  'guide': 'KEY_GUIDE',
  'exit': 'KEY_EXIT',
  '0': 'KEY_0',
  '1': 'KEY_1',
  '2': 'KEY_2',
  '3': 'KEY_3',
  '4': 'KEY_4',
  '5': 'KEY_5',
  '6': 'KEY_6',
  '7': 'KEY_7',
  '8': 'KEY_8',
  '9': 'KEY_9',
};

// Samsung TV Apps (common ones)
const SAMSUNG_APPS: Record<string, string> = {
  'netflix': 'Netflix',
  'youtube': 'YouTube',
  'prime': 'Amazon Prime Video',
  'disney': 'Disney+',
  'spotify': 'Spotify',
  'apple_tv': 'Apple TV',
  'plex': 'Plex',
};

export class SamsungTVController extends EventEmitter {
  private config: DeviceConfig;
  private ws: any = null;
  private connected: boolean = false;
  private state: SamsungTVState = {
    power: 'unknown',
    volume: 0,
    muted: false,
  };

  constructor(config: DeviceConfig) {
    super();
    this.config = config;
  }

  // ===========================================
  // Connection Management
  // ===========================================

  /**
   * Connect to the TV via WebSocket
   * Samsung 2021+ TVs use wss://<ip>:8002 (secure)
   * Older TVs use ws://<ip>:8001
   */
  async connect(): Promise<boolean> {
    const ip = this.config.connection.ip;
    if (!ip) {
      console.error('❌ Samsung TV: No IP configured');
      return false;
    }

    try {
      // Dynamic import for WebSocket
      const WebSocket = (await import('ws')).default;
      
      // Use secure port 8002 if specified, otherwise try 8001
      const port = this.config.connection.port || 8002;
      const secure = (this.config.connection as any).secure !== false; // Default to secure
      const protocol = secure ? 'wss' : 'ws';
      
      const wsUrl = `${protocol}://${ip}:${port}/api/v2/channels/samsung.remote.control`;
      const token = this.config.connection.token || '';
      
      console.log(`📺 Connecting to Samsung TV at ${ip}:${port} (${secure ? 'secure' : 'insecure'})...`);
      
      // For newer TVs, we need to provide a name (base64 encoded)
      const appName = Buffer.from('GNS-Home-Hub').toString('base64');
      const url = token 
        ? `${wsUrl}?name=${appName}&token=${token}`
        : `${wsUrl}?name=${appName}`;

      return new Promise((resolve) => {
        // For secure connections, we need to ignore self-signed certs
        const wsOptions = secure ? { rejectUnauthorized: false } : {};
        this.ws = new WebSocket(url, wsOptions);
        
        const timeout = setTimeout(() => {
          console.log('❌ Samsung TV: Connection timeout');
          this.ws?.close();
          resolve(false);
        }, 10000);

        this.ws.on('open', () => {
          clearTimeout(timeout);
          this.connected = true;
          this.state.power = 'on';
          console.log('✅ Samsung TV: Connected');
          this.emit('connected');
          resolve(true);
        });

        this.ws.on('message', (data: Buffer) => {
          this.handleMessage(data.toString());
        });

        this.ws.on('close', () => {
          this.connected = false;
          this.state.power = 'unknown';
          console.log('📺 Samsung TV: Disconnected');
          this.emit('disconnected');
        });

        this.ws.on('error', (error: Error) => {
          clearTimeout(timeout);
          console.error('❌ Samsung TV error:', error.message);
          this.emit('error', error);
          resolve(false);
        });
      });
    } catch (error) {
      console.error('❌ Samsung TV: Failed to connect:', error);
      return false;
    }
  }

  /**
   * Disconnect from the TV
   */
  disconnect(): void {
    if (this.ws) {
      this.ws.close();
      this.ws = null;
    }
    this.connected = false;
  }

  /**
   * Check if TV is online (ping test)
   */
  async isOnline(): Promise<boolean> {
    const ip = this.config.connection.ip;
    if (!ip) return false;

    const port = this.config.connection.port || 8002;

    return new Promise((resolve) => {
      const socket = new net.Socket();
      const timeout = 2000;

      socket.setTimeout(timeout);
      
      socket.on('connect', () => {
        socket.destroy();
        resolve(true);
      });

      socket.on('timeout', () => {
        socket.destroy();
        resolve(false);
      });

      socket.on('error', () => {
        socket.destroy();
        resolve(false);
      });

      socket.connect(port, ip);
    });
  }

  // ===========================================
  // Wake-on-LAN
  // ===========================================

  /**
   * Turn on TV using Wake-on-LAN
   */
  async wakeOnLan(): Promise<boolean> {
    const mac = this.config.connection.mac;
    if (!mac) {
      console.log('⚠️ Samsung TV: No MAC address configured for WoL');
      return false;
    }

    return new Promise((resolve) => {
      try {
        // Create magic packet
        const macBytes = mac.split(':').map(hex => parseInt(hex, 16));
        const magicPacket = Buffer.alloc(102);
        
        // 6 bytes of 0xFF
        for (let i = 0; i < 6; i++) {
          magicPacket[i] = 0xff;
        }
        
        // MAC address repeated 16 times
        for (let i = 0; i < 16; i++) {
          for (let j = 0; j < 6; j++) {
            magicPacket[6 + i * 6 + j] = macBytes[j];
          }
        }

        const socket = dgram.createSocket('udp4');
        
        socket.on('error', (err) => {
          console.error('❌ WoL error:', err);
          socket.close();
          resolve(false);
        });

        socket.bind(() => {
          socket.setBroadcast(true);
          socket.send(magicPacket, 0, magicPacket.length, 9, '255.255.255.255', (err) => {
            socket.close();
            if (err) {
              console.error('❌ WoL send error:', err);
              resolve(false);
            } else {
              console.log('📺 WoL packet sent to', mac);
              resolve(true);
            }
          });
        });
      } catch (error) {
        console.error('❌ WoL error:', error);
        resolve(false);
      }
    });
  }

  // ===========================================
  // Command Execution
  // ===========================================

  /**
   * Send a key command to the TV
   */
  async sendKey(key: string): Promise<boolean> {
    if (!this.connected || !this.ws) {
      // Try to connect first
      const connected = await this.connect();
      if (!connected) {
        return false;
      }
    }

    const samsungKey = SAMSUNG_KEYS[key.toLowerCase()] || key;
    
    const command = {
      method: 'ms.remote.control',
      params: {
        Cmd: 'Click',
        DataOfCmd: samsungKey,
        Option: 'false',
        TypeOfRemote: 'SendRemoteKey',
      },
    };

    return new Promise((resolve) => {
      try {
        this.ws.send(JSON.stringify(command), (err: Error | undefined) => {
          if (err) {
            console.error('❌ Send key error:', err);
            resolve(false);
          } else {
            console.log(`📺 Sent key: ${samsungKey}`);
            resolve(true);
          }
        });
      } catch (error) {
        console.error('❌ Send key error:', error);
        resolve(false);
      }
    });
  }

  /**
   * Launch an app
   */
  async launchApp(appId: string): Promise<boolean> {
    if (!this.connected || !this.ws) {
      const connected = await this.connect();
      if (!connected) return false;
    }

    const appName = SAMSUNG_APPS[appId.toLowerCase()] || appId;
    
    // Samsung uses a different method for launching apps
    const command = {
      method: 'ms.channel.emit',
      params: {
        event: 'ed.apps.launch',
        to: 'host',
        data: {
          appId: appId,
          action_type: 'DEEP_LINK',
        },
      },
    };

    return new Promise((resolve) => {
      try {
        this.ws.send(JSON.stringify(command), (err: Error | undefined) => {
          if (err) {
            console.error('❌ Launch app error:', err);
            resolve(false);
          } else {
            console.log(`📺 Launching app: ${appName}`);
            this.state.currentApp = appName;
            resolve(true);
          }
        });
      } catch (error) {
        console.error('❌ Launch app error:', error);
        resolve(false);
      }
    });
  }

  /**
   * Execute a home@ command
   */
  async executeAction(action: string, value?: any): Promise<{ success: boolean; error?: string }> {
    console.log(`📺 Samsung TV action: ${action}`, value !== undefined ? `(${value})` : '');

    switch (action.toLowerCase()) {
      case 'power':
        if (value === 'on') {
          const wolResult = await this.wakeOnLan();
          // Wait a bit for TV to wake up
          if (wolResult) {
            await new Promise(r => setTimeout(r, 5000));
            await this.connect();
          }
          return { success: wolResult };
        } else {
          return { success: await this.sendKey('power') };
        }

      case 'volume':
        if (typeof value === 'number') {
          // Set specific volume (need to implement state tracking)
          // For now, just adjust relative
          return { success: await this.sendKey(value > this.state.volume ? 'volume_up' : 'volume_down') };
        }
        return { success: false, error: 'Volume value required' };

      case 'volume_up':
        return { success: await this.sendKey('volume_up') };

      case 'volume_down':
        return { success: await this.sendKey('volume_down') };

      case 'mute':
        this.state.muted = !this.state.muted;
        return { success: await this.sendKey('mute') };

      case 'app':
        if (typeof value === 'string') {
          return { success: await this.launchApp(value) };
        }
        return { success: false, error: 'App ID required' };

      case 'key':
        if (typeof value === 'string') {
          return { success: await this.sendKey(value) };
        }
        return { success: false, error: 'Key name required' };

      case 'input':
      case 'source':
        return { success: await this.sendKey('source') };

      default:
        // Try as raw key
        if (SAMSUNG_KEYS[action.toLowerCase()]) {
          return { success: await this.sendKey(action) };
        }
        return { success: false, error: `Unknown action: ${action}` };
    }
  }

  // ===========================================
  // Message Handling
  // ===========================================

  private handleMessage(data: string): void {
    try {
      const message = JSON.parse(data);
      
      if (message.event === 'ms.channel.connect') {
        console.log('📺 Samsung TV: Channel connected');
        // Save token for future connections if provided
        if (message.data?.token) {
          this.config.connection.token = message.data.token;
          console.log('📺 Samsung TV: Token received:', message.data.token);
        }
      }
      
      this.emit('message', message);
    } catch (error) {
      console.error('Failed to parse TV message:', error);
    }
  }

  // ===========================================
  // Status
  // ===========================================

  getStatus(): DeviceStatus {
    return {
      online: this.connected,
      lastSeen: new Date().toISOString(),
      state: this.state,
    };
  }

  getState(): SamsungTVState {
    return { ...this.state };
  }
}

// ===========================================
// Factory function
// ===========================================

export function createSamsungTV(config: DeviceConfig): SamsungTVController {
  return new SamsungTVController(config);
}

// ===========================================
// Simulated TV for testing
// ===========================================

export class SimulatedSamsungTV extends SamsungTVController {
  private simState: SamsungTVState = {
    power: 'off',
    volume: 20,
    muted: false,
    currentApp: undefined,
  };

  async connect(): Promise<boolean> {
    console.log('📺 [SIMULATED] Samsung TV connected');
    this.simState.power = 'on';
    return true;
  }

  async isOnline(): Promise<boolean> {
    return true;
  }

  async wakeOnLan(): Promise<boolean> {
    console.log('📺 [SIMULATED] Wake-on-LAN sent');
    this.simState.power = 'on';
    return true;
  }

  async sendKey(key: string): Promise<boolean> {
    console.log(`📺 [SIMULATED] Key pressed: ${key}`);
    
    if (key === 'KEY_POWER' || key === 'power') {
      this.simState.power = this.simState.power === 'on' ? 'off' : 'on';
    } else if (key === 'KEY_VOLUP' || key === 'volume_up') {
      this.simState.volume = Math.min(100, this.simState.volume + 1);
    } else if (key === 'KEY_VOLDOWN' || key === 'volume_down') {
      this.simState.volume = Math.max(0, this.simState.volume - 1);
    } else if (key === 'KEY_MUTE' || key === 'mute') {
      this.simState.muted = !this.simState.muted;
    }
    
    return true;
  }

  async launchApp(appId: string): Promise<boolean> {
    console.log(`📺 [SIMULATED] Launching app: ${appId}`);
    this.simState.currentApp = appId;
    return true;
  }

  async executeAction(action: string, value?: any): Promise<{ success: boolean; error?: string }> {
    console.log(`📺 [SIMULATED] Action: ${action}`, value);
    
    switch (action.toLowerCase()) {
      case 'power':
        if (value === 'on') {
          this.simState.power = 'on';
        } else if (value === 'off') {
          this.simState.power = 'off';
        } else {
          this.simState.power = this.simState.power === 'on' ? 'off' : 'on';
        }
        return { success: true };
        
      case 'volume':
        if (typeof value === 'number') {
          this.simState.volume = Math.max(0, Math.min(100, value));
        }
        return { success: true };
        
      case 'volume_up':
        this.simState.volume = Math.min(100, this.simState.volume + 5);
        return { success: true };
        
      case 'volume_down':
        this.simState.volume = Math.max(0, this.simState.volume - 5);
        return { success: true };
        
      case 'mute':
        this.simState.muted = !this.simState.muted;
        return { success: true };
        
      case 'app':
        this.simState.currentApp = value;
        return { success: true };
        
      default:
        return { success: true };
    }
  }

  getState(): SamsungTVState {
    return { ...this.simState };
  }

  getStatus(): DeviceStatus {
    return {
      online: this.simState.power === 'on',
      lastSeen: new Date().toISOString(),
      state: this.simState,
    };
  }
}
