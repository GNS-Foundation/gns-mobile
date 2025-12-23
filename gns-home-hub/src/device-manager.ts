// ===========================================
// GNS HOME HUB - DEVICE MANAGER
// Manages all IoT devices
// ===========================================

import { EventEmitter } from 'events';
import { DeviceConfig, DeviceStatus } from './types';
import { SamsungTVController, SimulatedSamsungTV, createSamsungTV } from './samsung-tv';

// Device controllers by type
type DeviceController = SamsungTVController; // Add more as we support them

export class DeviceManager extends EventEmitter {
  private devices: Map<string, DeviceConfig> = new Map();
  private controllers: Map<string, DeviceController> = new Map();
  private simulateMode: boolean;

  constructor(simulateMode: boolean = false) {
    super();
    this.simulateMode = simulateMode;
    
    if (simulateMode) {
      console.log('🎮 Device Manager running in SIMULATION mode');
    }
  }

  // ===========================================
  // Device Registration
  // ===========================================

  /**
   * Register a device
   */
  registerDevice(config: DeviceConfig): void {
    this.devices.set(config.id, config);
    
    // Create appropriate controller
    let controller: DeviceController | null = null;
    
    switch (config.protocol) {
      case 'samsungtvws':
        if (this.simulateMode) {
          controller = new SimulatedSamsungTV(config);
        } else {
          controller = createSamsungTV(config);
        }
        break;
        
      // Add more protocols here
      case 'hue':
      case 'mqtt':
      case 'http':
        console.log(`⚠️ Protocol ${config.protocol} not yet implemented`);
        break;
    }
    
    if (controller) {
      this.controllers.set(config.id, controller);
      
      // Set up event listeners
      controller.on('connected', () => {
        this.emit('device_online', config.id);
      });
      
      controller.on('disconnected', () => {
        this.emit('device_offline', config.id);
      });
      
      controller.on('error', (error: Error) => {
        this.emit('device_error', config.id, error);
      });
    }
    
    console.log(`📱 Device registered: ${config.name} (${config.id})`);
  }

  /**
   * Unregister a device
   */
  unregisterDevice(deviceId: string): void {
    const controller = this.controllers.get(deviceId);
    if (controller) {
      controller.disconnect();
      this.controllers.delete(deviceId);
    }
    this.devices.delete(deviceId);
    console.log(`📱 Device unregistered: ${deviceId}`);
  }

  /**
   * Get device config
   */
  getDevice(deviceId: string): DeviceConfig | null {
    return this.devices.get(deviceId) || null;
  }

  /**
   * Get all devices
   */
  getAllDevices(): DeviceConfig[] {
    return Array.from(this.devices.values());
  }

  // ===========================================
  // Command Execution
  // ===========================================

  /**
   * Execute a command on a device
   */
  async executeCommand(
    deviceId: string,
    action: string,
    value?: any
  ): Promise<{ success: boolean; error?: string; state?: any }> {
    const controller = this.controllers.get(deviceId);
    const device = this.devices.get(deviceId);
    
    if (!device) {
      return { success: false, error: `Device not found: ${deviceId}` };
    }
    
    if (!controller) {
      return { success: false, error: `No controller for device: ${deviceId}` };
    }
    
    console.log(`🎮 Executing: ${deviceId}.${action}(${value !== undefined ? value : ''})`);
    
    try {
      const result = await controller.executeAction(action, value);
      
      if (result.success) {
        this.emit('command_executed', deviceId, action, value);
      }
      
      return {
        ...result,
        state: controller.getState(),
      };
    } catch (error) {
      console.error(`❌ Command error on ${deviceId}:`, error);
      return {
        success: false,
        error: error instanceof Error ? error.message : 'Unknown error',
      };
    }
  }

  // ===========================================
  // Status
  // ===========================================

  /**
   * Get device status
   */
  async getDeviceStatus(deviceId: string): Promise<DeviceStatus | null> {
    const controller = this.controllers.get(deviceId);
    if (!controller) return null;
    
    return controller.getStatus();
  }

  /**
   * Get all device statuses
   */
  async getAllStatuses(): Promise<Record<string, DeviceStatus>> {
    const statuses: Record<string, DeviceStatus> = {};
    
    for (const [id, controller] of this.controllers) {
      statuses[id] = controller.getStatus();
    }
    
    return statuses;
  }

  /**
   * Check if device is online
   */
  async isDeviceOnline(deviceId: string): Promise<boolean> {
    const controller = this.controllers.get(deviceId);
    if (!controller) return false;
    
    return await controller.isOnline();
  }

  // ===========================================
  // Connection Management
  // ===========================================

  /**
   * Connect to a device
   */
  async connectDevice(deviceId: string): Promise<boolean> {
    const controller = this.controllers.get(deviceId);
    if (!controller) return false;
    
    return await controller.connect();
  }

  /**
   * Disconnect from a device
   */
  disconnectDevice(deviceId: string): void {
    const controller = this.controllers.get(deviceId);
    if (controller) {
      controller.disconnect();
    }
  }

  /**
   * Connect to all devices
   */
  async connectAll(): Promise<void> {
    console.log('📱 Connecting to all devices...');
    
    const results = await Promise.all(
      Array.from(this.controllers.entries()).map(async ([id, controller]) => {
        const success = await controller.connect();
        return { id, success };
      })
    );
    
    const connected = results.filter(r => r.success).length;
    console.log(`📱 Connected to ${connected}/${results.length} devices`);
  }

  /**
   * Disconnect from all devices
   */
  disconnectAll(): void {
    for (const controller of this.controllers.values()) {
      controller.disconnect();
    }
    console.log('📱 Disconnected from all devices');
  }

  // ===========================================
  // Discovery (future)
  // ===========================================

  /**
   * Discover devices on the network
   * TODO: Implement SSDP/mDNS discovery
   */
  async discoverDevices(): Promise<DeviceConfig[]> {
    console.log('🔍 Device discovery not yet implemented');
    return [];
  }
}

// Singleton instance
let deviceManager: DeviceManager | null = null;

export function getDeviceManager(simulateMode: boolean = false): DeviceManager {
  if (!deviceManager) {
    deviceManager = new DeviceManager(simulateMode);
  }
  return deviceManager;
}
