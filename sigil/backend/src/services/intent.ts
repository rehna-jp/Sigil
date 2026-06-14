/**
 * Intent Submission Service
 * Handles on-chain submission of decomposed intents
 */

import { ethers } from 'ethers';
import { ContractService } from '../contracts';
import { Segment, WatcherConfig, AIDecomposedIntent } from '../contracts/types';

export interface SubmitIntentResult {
  intentId: string;
  txHash: string;
  segments: number;
  watchers: number;
  gasUsed?: bigint;
}

export class IntentService {
  constructor(private contracts: ContractService) {}

  /**
   * Submit a decomposed intent to the blockchain
   */
  async submitIntent(
    userAddress: string,
    segments: Segment[],
    watchers: WatcherConfig[]
  ): Promise<SubmitIntentResult> {
    try {
      // Call IntentDecomposer.submitDecomposition()
      const tx = await this.contracts.decomposer.submitDecomposition(
        userAddress,
        segments,
        watchers
      );

      console.log(`Intent submitted: ${tx.hash}`);

      // Wait for transaction confirmation
      const receipt = await tx.wait();

      // Extract intentId from event logs
      const intentId = this.extractIntentIdFromReceipt(receipt);

      // Execute segments immediately after registration
      console.log(`Executing ${segments.length} segments for intent ${intentId}`);
      try {
        await this.executeSegments(intentId, segments);
      } catch (execError: any) {
        console.error('⚠️ Execution failed but intent is registered:', execError?.reason || execError?.message);
      }

      return {
        intentId,
        txHash: tx.hash,
        segments: segments.length,
        watchers: watchers.length,
        gasUsed: receipt.gasUsed
      };
    } catch (error) {
      console.error('Failed to submit intent:', error);
      throw new Error(`Intent submission failed: ${error}`);
    }
  }

  /**
   * Get intent details from blockchain
   */
  async getIntent(intentId: string) {
    try {
      const intent = await this.contracts.decomposer.intents(intentId);
      return {
        intentId: intent.intentId,
        user: intent.user,
        timestamp: intent.timestamp,
        status: intent.status,
        segmentCount: intent.immediateSegments?.length || 0,
        watcherCount: intent.watchers?.length || 0
      };
    } catch (error) {
      console.error('Failed to get intent:', error);
      return null;
    }
  }

  /**
   * Get all intents for a user
   */
  async getUserIntents(userAddress: string): Promise<string[]> {
    try {
      const intentIds = await this.contracts.decomposer.getUserIntents(userAddress);
      return intentIds;
    } catch (error) {
      console.error('Failed to get user intents:', error);
      return [];
    }
  }

  /**
   * Get active watchers for a user
   */
  async getUserWatchers(userAddress: string): Promise<any[]> {
    try {
      const watcherIds = await this.contracts.watcherRegistry.getUserActiveWatchers(userAddress);

      const watchers = await Promise.all(
        watcherIds.map(async (id: string) => {
          const watcher = await this.contracts.watcherRegistry.watchers(id);
          return {
            watcherId: watcher.watcherId,
            parentIntentId: watcher.parentIntentId,
            owner: watcher.owner,
            type: watcher.watcherType,
            status: watcher.status,
            createdAt: watcher.createdAt,
            expiresAt: watcher.expiresAt,
            lastChecked: watcher.lastChecked
          };
        })
      );

      return watchers;
    } catch (error) {
      console.error('Failed to get user watchers:', error);
      return [];
    }
  }

  /**
   * Check if a specific watcher should trigger
   */
  async checkWatcher(watcherId: string): Promise<boolean> {
    try {
      const watcher = await this.contracts.watcherRegistry.watchers(watcherId);

      // Check based on watcher type
      switch (watcher.watcherType) {
        case 0: // PRICE
          return await this.contracts.watcherRegistry.checkPriceWatcher(watcherId);

        case 3: // TIME
          return await this.contracts.watcherRegistry.checkTimeWatcher(watcherId);

        default:
          console.log(`Watcher type ${watcher.watcherType} not implemented yet`);
          return false;
      }
    } catch (error) {
      console.error('Failed to check watcher:', error);
      return false;
    }
  }

  /**
   * Execute intent segments through the router
   */
  async executeSegments(intentId: string, segments: Segment[]): Promise<string> {
    try {
      // Calculate total ETH value to send
      const totalValue = segments.reduce((sum, s) => sum + s.value, 0n);

      // Pass segments as tuple array (matches IntentRouter.executeSegments signature)
      const tx = await this.contracts.router.executeSegments(
        intentId,
        segments,
        { value: totalValue }
      );

      console.log(`Segments executed: ${tx.hash}`);
      await tx.wait();
      return tx.hash;
    
      } catch (error: any) {
      console.error('Failed to execute segments:', error?.message);
      console.error('Error data:', error?.data);
      console.error('Error reason:', error?.reason);
      console.error('Segments passed:', JSON.stringify(segments, (_, v) =>
        typeof v === 'bigint' ? v.toString() : v, 2));
      throw error;
    
    }
  }

  /**
   * Extract intentId from transaction receipt
   */
  private extractIntentIdFromReceipt(receipt: any): string {
    // Look for IntentDecomposed event
    const event = receipt.logs.find((log: any) => {
      try {
        const parsed = this.contracts.decomposer.interface.parseLog(log);
        return parsed?.name === 'IntentDecomposed';
      } catch {
        return false;
      }
    });

    if (event) {
      const parsed = this.contracts.decomposer.interface.parseLog(event);
      return parsed?.args?.intentId || ethers.ZeroHash;
    }

    return ethers.ZeroHash;
  }

  /**
   * Cancel an intent
   */
  async cancelIntent(intentId: string): Promise<string> {
    try {
      const tx = await this.contracts.decomposer.cancelIntent(intentId);
      await tx.wait();
      return tx.hash;
    } catch (error) {
      console.error('Failed to cancel intent:', error);
      throw error;
    }
  }

  /**
   * Cancel a watcher
   */
  async cancelWatcher(watcherId: string): Promise<string> {
    try {
      const tx = await this.contracts.watcherRegistry.cancelWatcher(watcherId);
      await tx.wait();
      return tx.hash;
    } catch (error) {
      console.error('Failed to cancel watcher:', error);
      throw error;
    }
  }
}
