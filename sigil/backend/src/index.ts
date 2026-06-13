/**
 * Sigil Backend API Server
 * Provides REST API for intent decomposition, submission, and monitoring
 */

import express from 'express';
import dotenv from 'dotenv';
import { ContractService } from './contracts';
import { IntentDecomposerService } from './services/decomposer';
import { IntentService } from './services/intent';
import { KeeperService } from './services/keeper';
import { AIDecompositionRequest } from './contracts/types';

dotenv.config();

const app = express();
app.use(express.json());

// Configuration
const PORT = process.env.PORT || 3001;
const GROQ_API_KEY = process.env.GROQ_API_KEY;
const PRIVATE_KEY = process.env.PRIVATE_KEY;
const RPC_URL = process.env.ARBITRUM_SEPOLIA_RPC_URL || 'https://sepolia-rollup.arbitrum.io/rpc';

if (!GROQ_API_KEY) {
  console.warn('⚠️  GROQ_API_KEY not set - AI decomposition will fail');
}

if (!PRIVATE_KEY) {
  console.warn('⚠️  PRIVATE_KEY not set - intent submission will fail');
}

// Initialize services
console.log('🚀 Initializing Sigil Backend Services...\n');

const contractService = new ContractService(RPC_URL, PRIVATE_KEY);
const decomposerService = GROQ_API_KEY ? new IntentDecomposerService(GROQ_API_KEY) : null;
const intentService = new IntentService(contractService);
const keeperService = new KeeperService(contractService);

// Health check
app.get('/health', (req, res) => {
  res.json({
    status: 'ok',
    services: {
      contracts: true,
      decomposer: !!decomposerService,
      keeper: true
    },
    timestamp: new Date().toISOString()
  });
});

// ====================
// INTENT ENDPOINTS
// ====================

/**
 * POST /decompose
 * Decompose natural language intent into structured segments and watchers
 */
app.post('/decompose', async (req, res) => {
  if (!decomposerService) {
    return res.status(503).json({
      error: 'AI decomposer not available - GROQ_API_KEY not configured'
    });
  }

  const { text, userAddress, context } = req.body;

  if (!text || typeof text !== 'string') {
    return res.status(400).json({ error: 'text is required' });
  }

  if (!userAddress || typeof userAddress !== 'string') {
    return res.status(400).json({ error: 'userAddress is required' });
  }

  try {
    const request: AIDecompositionRequest = { userInput: text, userAddress, context };
    const decomposed = await decomposerService.decomposeIntent(request);

    res.json({
      success: true,
      decomposed,
      timestamp: new Date().toISOString()
    });
  } catch (error: any) {
    console.error('Decomposition error:', error);
    res.status(500).json({
      error: 'Failed to decompose intent',
      details: error.message
    });
  }
});

/**
 * POST /submit-intent
 * Submit a decomposed intent to the blockchain
 */
app.post('/submit-intent', async (req, res) => {
  if (!PRIVATE_KEY) {
    return res.status(503).json({
      error: 'Intent submission not available - PRIVATE_KEY not configured'
    });
  }

  const { userAddress, segments, watchers } = req.body;

  if (!userAddress) {
    return res.status(400).json({ error: 'userAddress is required' });
  }

  if (!segments || !Array.isArray(segments)) {
    return res.status(400).json({ error: 'segments array is required' });
  }

  try {
    const result = await intentService.submitIntent(
      userAddress,
      segments,
      watchers || []
    );

    res.json({
      success: true,
      ...result,
      timestamp: new Date().toISOString()
    });
  } catch (error: any) {
    console.error('Submit intent error:', error);
    res.status(500).json({
      error: 'Failed to submit intent',
      details: error.message
    });
  }
});

/**
 * POST /decompose-and-submit
 * One-shot: decompose natural language and submit to blockchain
 */
app.post('/decompose-and-submit', async (req, res) => {
  if (!decomposerService) {
    return res.status(503).json({
      error: 'AI decomposer not available - GROQ_API_KEY not configured'
    });
  }

  if (!PRIVATE_KEY) {
    return res.status(503).json({
      error: 'Intent submission not available - PRIVATE_KEY not configured'
    });
  }

  const { text, userAddress, context } = req.body;

  if (!text || !userAddress) {
    return res.status(400).json({ error: 'text and userAddress are required' });
  }

  try {
    // Step 1: Decompose with Claude
    console.log(`Decomposing intent for ${userAddress}: "${text}"`);
    const request: AIDecompositionRequest = { userInput: text, userAddress, context };
    const decomposed = await decomposerService.decomposeIntent(request);

    // Step 2: Encode segments
    const segments = decomposed.segments.map(seg =>
      decomposerService.encodeSegment(seg, seg.protocol)
    );

    // Step 3: Encode watchers
    const watchers = decomposed.watchers.map(w =>
      decomposerService.encodeWatcher(w)
    );

    // Step 4: Submit to blockchain
    console.log(`Submitting intent with ${segments.length} segments and ${watchers.length} watchers`);
    const result = await intentService.submitIntent(userAddress, segments, watchers);

    res.json({
      success: true,
      decomposed,
      ...result,
      timestamp: new Date().toISOString()
    });
  } catch (error: any) {
    console.error('Decompose and submit error:', error);
    res.status(500).json({
      error: 'Failed to decompose and submit intent',
      details: error.message
    });
  }
});

/**
 * GET /intents/:address
 * Get all intents for a user address
 */
app.get('/intents/:address', async (req, res) => {
  const { address } = req.params;

  try {
    const intentIds = await intentService.getUserIntents(address);

    const intents = await Promise.all(
      intentIds.map(id => intentService.getIntent(id))
    );

    res.json({
      success: true,
      address,
      count: intents.length,
      intents: intents.filter(i => i !== null)
    });
  } catch (error: any) {
    console.error('Get intents error:', error);
    res.status(500).json({
      error: 'Failed to get intents',
      details: error.message
    });
  }
});

/**
 * GET /intent/:intentId
 * Get details of a specific intent
 */
app.get('/intent/:intentId', async (req, res) => {
  const { intentId } = req.params;

  try {
    const intent = await intentService.getIntent(intentId);

    if (!intent) {
      return res.status(404).json({ error: 'Intent not found' });
    }

    res.json({
      success: true,
      intent
    });
  } catch (error: any) {
    console.error('Get intent error:', error);
    res.status(500).json({
      error: 'Failed to get intent',
      details: error.message
    });
  }
});

/**
 * DELETE /intent/:intentId
 * Cancel an intent
 */
app.delete('/intent/:intentId', async (req, res) => {
  if (!PRIVATE_KEY) {
    return res.status(503).json({
      error: 'Intent cancellation not available - PRIVATE_KEY not configured'
    });
  }

  const { intentId } = req.params;

  try {
    const txHash = await intentService.cancelIntent(intentId);

    res.json({
      success: true,
      intentId,
      txHash
    });
  } catch (error: any) {
    console.error('Cancel intent error:', error);
    res.status(500).json({
      error: 'Failed to cancel intent',
      details: error.message
    });
  }
});

// ====================
// WATCHER ENDPOINTS
// ====================

/**
 * GET /watchers/:address
 * Get all active watchers for a user
 */
app.get('/watchers/:address', async (req, res) => {
  const { address } = req.params;

  try {
    const watchers = await intentService.getUserWatchers(address);

    res.json({
      success: true,
      address,
      count: watchers.length,
      watchers
    });
  } catch (error: any) {
    console.error('Get watchers error:', error);
    res.status(500).json({
      error: 'Failed to get watchers',
      details: error.message
    });
  }
});

/**
 * GET /watcher/:watcherId/check
 * Check if a watcher should trigger (without triggering it)
 */
app.get('/watcher/:watcherId/check', async (req, res) => {
  const { watcherId } = req.params;

  try {
    const shouldTrigger = await intentService.checkWatcher(watcherId);

    res.json({
      success: true,
      watcherId,
      shouldTrigger
    });
  } catch (error: any) {
    console.error('Check watcher error:', error);
    res.status(500).json({
      error: 'Failed to check watcher',
      details: error.message
    });
  }
});

/**
 * POST /watcher/:watcherId/trigger
 * Manually trigger a watcher
 */
app.post('/watcher/:watcherId/trigger', async (req, res) => {
  if (!PRIVATE_KEY) {
    return res.status(503).json({
      error: 'Watcher triggering not available - PRIVATE_KEY not configured'
    });
  }

  const { watcherId } = req.params;

  try {
    const success = await keeperService.manualTrigger(watcherId);

    res.json({
      success,
      watcherId
    });
  } catch (error: any) {
    console.error('Trigger watcher error:', error);
    res.status(500).json({
      error: 'Failed to trigger watcher',
      details: error.message
    });
  }
});

/**
 * DELETE /watcher/:watcherId
 * Cancel a watcher
 */
app.delete('/watcher/:watcherId', async (req, res) => {
  if (!PRIVATE_KEY) {
    return res.status(503).json({
      error: 'Watcher cancellation not available - PRIVATE_KEY not configured'
    });
  }

  const { watcherId } = req.params;

  try {
    const txHash = await intentService.cancelWatcher(watcherId);

    res.json({
      success: true,
      watcherId,
      txHash
    });
  } catch (error: any) {
    console.error('Cancel watcher error:', error);
    res.status(500).json({
      error: 'Failed to cancel watcher',
      details: error.message
    });
  }
});

// ====================
// KEEPER ENDPOINTS
// ====================

/**
 * POST /keeper/start
 * Start the keeper service
 */
app.post('/keeper/start', (req, res) => {
  try {
    keeperService.start();

    res.json({
      success: true,
      message: 'Keeper service started'
    });
  } catch (error: any) {
    res.status(500).json({
      error: 'Failed to start keeper',
      details: error.message
    });
  }
});

/**
 * POST /keeper/stop
 * Stop the keeper service
 */
app.post('/keeper/stop', (req, res) => {
  try {
    keeperService.stop();

    res.json({
      success: true,
      message: 'Keeper service stopped'
    });
  } catch (error: any) {
    res.status(500).json({
      error: 'Failed to stop keeper',
      details: error.message
    });
  }
});

/**
 * GET /keeper/stats
 * Get keeper service statistics
 */
app.get('/keeper/stats', async (req, res) => {
  try {
    const stats = await keeperService.getStats();

    res.json({
      success: true,
      stats
    });
  } catch (error: any) {
    res.status(500).json({
      error: 'Failed to get keeper stats',
      details: error.message
    });
  }
});

// ====================
// CONTRACT INFO ENDPOINTS
// ====================

/**
 * GET /contracts
 * Get deployed contract addresses
 */
app.get('/contracts', async (req, res) => {
  const { ARBITRUM_SEPOLIA_ADDRESSES, PROTOCOL_ADDRESSES } = await import('./contracts/addresses');

  res.json({
    success: true,
    network: 'Arbitrum Sepolia',
    contracts: ARBITRUM_SEPOLIA_ADDRESSES,
    protocols: PROTOCOL_ADDRESSES
  });
});

/**
 * GET /block
 * Get current block number
 */
app.get('/block', async (req, res) => {
  try {
    const blockNumber = await contractService.getBlockNumber();

    res.json({
      success: true,
      blockNumber
    });
  } catch (error: any) {
    res.status(500).json({
      error: 'Failed to get block number',
      details: error.message
    });
  }
});

// Error handler
app.use((err: any, req: express.Request, res: express.Response, next: express.NextFunction) => {
  console.error('Unhandled error:', err);
  res.status(500).json({
    error: 'Internal server error',
    details: err.message
  });
});

// Start server
app.listen(PORT, async () => {
  console.log(`\n✅ Sigil Backend API listening on port ${PORT}`);
  console.log(`   Network: Arbitrum Sepolia`);
  console.log(`   RPC URL: ${RPC_URL}`);

  if (PRIVATE_KEY) {
    const signerAddress = await contractService.getSignerAddress();
    console.log(`   Signer: ${signerAddress}`);
  }

  console.log('\n📡 API Endpoints:');
  console.log(`   POST   http://localhost:${PORT}/decompose`);
  console.log(`   POST   http://localhost:${PORT}/submit-intent`);
  console.log(`   POST   http://localhost:${PORT}/decompose-and-submit`);
  console.log(`   GET    http://localhost:${PORT}/intents/:address`);
  console.log(`   GET    http://localhost:${PORT}/watchers/:address`);
  console.log(`   POST   http://localhost:${PORT}/keeper/start`);
  console.log(`   GET    http://localhost:${PORT}/keeper/stats`);
  console.log(`   GET    http://localhost:${PORT}/contracts`);
  console.log(`   GET    http://localhost:${PORT}/health`);

  console.log('\n🔗 The Persistent Intent Loop is ready!\n');

  // Auto-start keeper if enabled
  if (process.env.AUTO_START_KEEPER === 'true') {
    console.log('🤖 Auto-starting keeper service...\n');
    keeperService.start();
  }
});