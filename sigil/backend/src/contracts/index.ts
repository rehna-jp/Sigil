/**
 * Contract service for interacting with deployed Sigil contracts
 */

import { ethers } from 'ethers';
import { ARBITRUM_SEPOLIA_ADDRESSES } from './addresses';
import {
  IntentDecomposerABI,
  WatcherRegistryABI,
  IntentRouterABI,
  TriggerExecutorABI,
  UniswapV3AdapterABI,
  AaveV3AdapterABI,
  ERC8004RegistryABI
} from './abis';

export class ContractService {
  private provider: ethers.Provider;
  private signer?: ethers.Signer;

  // Contract instances
  public decomposer: ethers.Contract;
  public watcherRegistry: ethers.Contract;
  public router: ethers.Contract;
  public executor: ethers.Contract;
  public uniswapAdapter: ethers.Contract;
  public aaveAdapter: ethers.Contract;
  public registry: ethers.Contract;

  constructor(rpcUrl: string, privateKey?: string) {
    // Setup provider
    this.provider = new ethers.JsonRpcProvider(rpcUrl);

    // Setup signer if private key provided
    if (privateKey) {
      this.signer = new ethers.Wallet(privateKey, this.provider);
    }

    // Initialize contract instances
    const signerOrProvider = this.signer || this.provider;

    this.decomposer = new ethers.Contract(
      ARBITRUM_SEPOLIA_ADDRESSES.decomposer,
      IntentDecomposerABI,
      signerOrProvider
    );

    this.watcherRegistry = new ethers.Contract(
      ARBITRUM_SEPOLIA_ADDRESSES.watcherRegistry,
      WatcherRegistryABI,
      signerOrProvider
    );

    this.router = new ethers.Contract(
      ARBITRUM_SEPOLIA_ADDRESSES.router,
      IntentRouterABI,
      signerOrProvider
    );

    this.executor = new ethers.Contract(
      ARBITRUM_SEPOLIA_ADDRESSES.executor,
      TriggerExecutorABI,
      signerOrProvider
    );

    this.uniswapAdapter = new ethers.Contract(
      ARBITRUM_SEPOLIA_ADDRESSES.uniswapAdapter,
      UniswapV3AdapterABI,
      signerOrProvider
    );

    this.aaveAdapter = new ethers.Contract(
      ARBITRUM_SEPOLIA_ADDRESSES.aaveAdapter,
      AaveV3AdapterABI,
      signerOrProvider
    );

    this.registry = new ethers.Contract(
      ARBITRUM_SEPOLIA_ADDRESSES.registry,
      ERC8004RegistryABI,
      signerOrProvider
    );
  }

  /**
   * Get the current block number
   */
  async getBlockNumber(): Promise<number> {
    return await this.provider.getBlockNumber();
  }

  /**
   * Get gas price
   */
  async getGasPrice(): Promise<bigint> {
    const feeData = await this.provider.getFeeData();
    return feeData.gasPrice || 0n;
  }

  /**
   * Wait for transaction confirmation
   */
  async waitForTransaction(txHash: string, confirmations: number = 1): Promise<ethers.TransactionReceipt | null> {
    return await this.provider.waitForTransaction(txHash, confirmations);
  }

  /**
   * Get signer address
   */
  async getSignerAddress(): Promise<string | null> {
    if (!this.signer) return null;
    return await this.signer.getAddress();
  }
}

// Export contract addresses and types
export * from './addresses';
export * from './types';
export * from './abis';
