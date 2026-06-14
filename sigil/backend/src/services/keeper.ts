/**
 * Keeper Service for Watcher Monitoring
 * THE COMPONENT THAT CLOSES THE LOOP
 *
 * Continuously monitors active watchers and triggers them when conditions are met.
 * When a watcher triggers, it creates a new intent, closing the persistent intent loop.
 */

import { ethers } from 'ethers';
import { ContractService } from '../contracts';
import { WatcherType, WatcherStatus } from '../contracts/types';

export interface KeeperConfig {
  pollingInterval: number; // milliseconds
  batchSize: number; // max watchers to check per batch
  maxGasPrice: bigint; // max gas price willing to pay
  enablePriceWatchers: boolean;
  enableTimeWatchers: boolean;
  enableRiskWatchers: boolean;
  enableGovernanceWatchers: boolean;
}

export interface WatcherCheckResult {
  watcherId: string;
  shouldTrigger: boolean;
  triggered: boolean;
  error?: string;
}

export class KeeperService {
  private isRunning: boolean = false;
  private pollingTimer?: NodeJS.Timeout;
  private config: KeeperConfig;

  constructor(
    private contracts: ContractService,
    config?: Partial<KeeperConfig>
  ) {
    this.config = {
      pollingInterval: config?.pollingInterval || 12000, // 12 seconds (1 block on Arbitrum)
      batchSize: config?.batchSize || 50,
      maxGasPrice: config?.maxGasPrice || ethers.parseUnits('0.1', 'gwei'),
      enablePriceWatchers: config?.enablePriceWatchers ?? true,
      enableTimeWatchers: config?.enableTimeWatchers ?? true,
      enableRiskWatchers: config?.enableRiskWatchers ?? false, // Not implemented yet
      enableGovernanceWatchers: config?.enableGovernanceWatchers ?? false // Not implemented yet
    };
  }

  /**
   * Start the keeper service
   */
  start() {
    if (this.isRunning) {
      console.log('Keeper service already running');
      return;
    }

    console.log('🤖 Starting Keeper Service...');
    console.log(`   Polling interval: ${this.config.pollingInterval}ms`);
    console.log(`   Batch size: ${this.config.batchSize}`);
    console.log(`   Max gas price: ${ethers.formatUnits(this.config.maxGasPrice, 'gwei')} gwei`);

    this.isRunning = true;
    this.poll();
  }

  /**
   * Stop the keeper service
   */
  stop() {
    console.log('🛑 Stopping Keeper Service...');
    this.isRunning = false;

    if (this.pollingTimer) {
      clearTimeout(this.pollingTimer);
      this.pollingTimer = undefined;
    }
  }

  /**
   * Main polling loop
   */
  private async poll() {
    if (!this.isRunning) return;

    try {
      await this.checkAndTriggerWatchers();
    } catch (error) {
      console.error('Keeper error:', error);
    }

    // Schedule next poll
    this.pollingTimer = setTimeout(() => this.poll(), this.config.pollingInterval);
  }

  /**
   * Check all active watchers and trigger those with met conditions
   */
  private async checkAndTriggerWatchers(): Promise<void> {
    const blockNumber = await this.contracts.getBlockNumber();
    const gasPrice = await this.contracts.getGasPrice();

    // Check gas price limit
    if (gasPrice > this.config.maxGasPrice) {
      console.log(`⛽ Gas price too high: ${ethers.formatUnits(gasPrice, 'gwei')} gwei, skipping...`);
      return;
    }

    console.log(`\n🔍 Checking watchers at block ${blockNumber}...`);

    // Get all active watcher IDs
    const activeWatcherIds = await this.getActiveWatcherIds();

    if (activeWatcherIds.length === 0) {
      console.log('   No active watchers found');
      return;
    }

    console.log(`   Found ${activeWatcherIds.length} active watchers`);

    // Process in batches
    const batches = this.createBatches(activeWatcherIds, this.config.batchSize);

    for (let i = 0; i < batches.length; i++) {
      const batch = batches[i];
      console.log(`   Processing batch ${i + 1}/${batches.length} (${batch.length} watchers)...`);

      const results = await this.processBatch(batch);

      // Log results
      const triggered = results.filter(r => r.triggered).length;
      const errors = results.filter(r => r.error).length;

      if (triggered > 0) {
        console.log(`   ✅ Triggered ${triggered} watchers`);
      }

      if (errors > 0) {
        console.log(`   ⚠️  ${errors} errors encountered`);
      }
    }
  }

  /**
   * Process a batch of watchers
   */
  private async processBatch(watcherIds: string[]): Promise<WatcherCheckResult[]> {
    const results: WatcherCheckResult[] = [];

    for (const watcherId of watcherIds) {
      try {
        const result = await this.checkAndTrigger(watcherId);
        results.push(result);

        if (result.triggered) {
          console.log(`      🎯 Triggered watcher: ${watcherId}`);
        }
      } catch (error: any) {
        console.error(`      ❌ Error checking watcher ${watcherId}:`, error.message);
        results.push({
          watcherId,
          shouldTrigger: false,
          triggered: false,
          error: error.message
        });
      }
    }

    return results;
  }

  /**
   * Check and trigger a single watcher
   */
  private async checkAndTrigger(watcherId: string): Promise<WatcherCheckResult> {
    // Get watcher details
    const watcher = await this.contracts.watcherRegistry.watchers(watcherId);

    // Skip if not active
    if (watcher.status !== WatcherStatus.ACTIVE) {
      return { watcherId, shouldTrigger: false, triggered: false };
    }

    // Check based on type
    let shouldTrigger = false;

    switch (Number(watcher.watcherType)) {
      case WatcherType.PRICE:
        if (this.config.enablePriceWatchers) {
          shouldTrigger = await this.contracts.watcherRegistry.checkPriceWatcher(watcherId);
        }
        break;

      case WatcherType.TIME:
        if (this.config.enableTimeWatchers) {
          shouldTrigger = await this.contracts.watcherRegistry.checkTimeWatcher(watcherId);
        }
        break;

      case WatcherType.RISK:
        if (this.config.enableRiskWatchers) {
          // Risk watchers not yet implemented
          shouldTrigger = false;
        }
        break;

      case WatcherType.GOVERNANCE:
        if (this.config.enableGovernanceWatchers) {
          // Governance watchers not yet implemented
          shouldTrigger = false;
        }
        break;

      default:
        console.warn(`Unknown watcher type: ${watcher.watcherType}`);
        return { watcherId, shouldTrigger: false, triggered: false };
    }

    // If should trigger, execute it
    if (shouldTrigger) {
      try {
        const tx = await this.contracts.executor.processWatcher(watcherId);
        await tx.wait();

        return {
          watcherId,
          shouldTrigger: true,
          triggered: true
        };
      } catch (error: any) {
        return {
          watcherId,
          shouldTrigger: true,
          triggered: false,
          error: `Trigger failed: ${error.message}`
        };
      }
    }

    return { watcherId, shouldTrigger: false, triggered: false };
  }

  /**
   * Get all active watcher IDs from the registry
   */
  private async getActiveWatcherIds(): Promise<string[]> {
    try {
      // Get active watcher IDs directly
      const ids = await this.contracts.watcherRegistry.getActiveWatcherIds();
      return ids;
    } catch (error) {
      console.error('Failed to get active watcher IDs:', error);
      return [];
    }
  }

  /**
   * Create batches from array
   */
  private createBatches<T>(array: T[], batchSize: number): T[][] {
    const batches: T[][] = [];

    for (let i = 0; i < array.length; i += batchSize) {
      batches.push(array.slice(i, i + batchSize));
    }

    return batches;
  }

  /**
   * Manually trigger a specific watcher (for testing)
   */
  async manualTrigger(watcherId: string): Promise<boolean> {
    try {
      console.log(`Manually triggering watcher: ${watcherId}`);

      const tx = await this.contracts.executor.processWatcher(watcherId);
      const receipt = await tx.wait();

      console.log(`Watcher triggered successfully: ${tx.hash}`);
      return true;
    } catch (error) {
      console.error('Manual trigger failed:', error);
      return false;
    }
  }

  /**
   * Get keeper statistics
   */
  async getStats() {
    const blockNumber = await this.contracts.getBlockNumber();
    const gasPrice = await this.contracts.getGasPrice();
    const activeWatchers = await this.getActiveWatcherIds();

    return {
      isRunning: this.isRunning,
      blockNumber,
      gasPrice: ethers.formatUnits(gasPrice, 'gwei') + ' gwei',
      activeWatchers: activeWatchers.length,
      config: this.config
    };
  }
}
