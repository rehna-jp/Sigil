/**
 * Contract ABIs extracted from compiled artifacts
 * These are loaded from the contracts/out folder
 */

import * as fs from 'fs';
import * as path from 'path';

// Path to compiled contracts
// In production (Docker), contracts are at /app/contracts/out
// In local dev, contracts are at ../../../contracts/out (from src/contracts/)
const CONTRACTS_OUT_DIR = fs.existsSync(path.join(__dirname, '../../contracts/out'))
  ? path.join(__dirname, '../../contracts/out')  // Docker/production
  : path.join(__dirname, '../../../contracts/out'); // Local development

/**
 * Load ABI from compiled contract artifact
 */
function loadABI(contractName: string): any[] {
  try {
    const artifactPath = path.join(CONTRACTS_OUT_DIR, `${contractName}.sol`, `${contractName}.json`);
    const artifact = JSON.parse(fs.readFileSync(artifactPath, 'utf-8'));
    return artifact.abi;
  } catch (error) {
    console.error(`Failed to load ABI for ${contractName}:`, error);
    throw new Error(`Could not load ABI for ${contractName}`);
  }
}

// Export ABIs for all contracts
export const IntentDecomposerABI = loadABI('IntentDecomposer');
export const WatcherRegistryABI = loadABI('WatcherRegistry');
export const IntentRouterABI = loadABI('IntentRouter');
export const TriggerExecutorABI = loadABI('TriggerExecutor');
export const UniswapV3AdapterABI = loadABI('UniswapV3Adapter');
export const AaveV3AdapterABI = loadABI('AaveV3Adapter');

// ERC8004Registry is in IERC8004.sol directory
const registryPath = path.join(CONTRACTS_OUT_DIR, 'IERC8004.sol', 'ERC8004Registry.json');
export const ERC8004RegistryABI = JSON.parse(fs.readFileSync(registryPath, 'utf-8')).abi;

// Helper to get ABI by name
export function getABI(contractName: string): any[] {
  const abis: Record<string, any[]> = {
    IntentDecomposer: IntentDecomposerABI,
    WatcherRegistry: WatcherRegistryABI,
    IntentRouter: IntentRouterABI,
    TriggerExecutor: TriggerExecutorABI,
    UniswapV3Adapter: UniswapV3AdapterABI,
    AaveV3Adapter: AaveV3AdapterABI,
    ERC8004Registry: ERC8004RegistryABI
  };

  if (!abis[contractName]) {
    throw new Error(`Unknown contract: ${contractName}`);
  }

  return abis[contractName];
}
