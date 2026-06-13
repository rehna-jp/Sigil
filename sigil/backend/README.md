# Sigil Backend

The backend service for the Sigil Protocol - a persistent intent engine on Arbitrum.

## Overview

The Sigil backend provides:
1. **AI Intent Decomposition** - Claude-powered natural language parsing into structured on-chain actions
2. **Smart Contract Integration** - Direct interaction with deployed Sigil contracts on Arbitrum Sepolia
3. **Keeper Service** - Automated watcher monitoring that **closes the loop** by triggering new intents
4. **REST API** - Endpoints for intent submission, watcher management, and status tracking

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    REST API Server                       │
│                   (Express + TypeScript)                 │
└──────────────┬──────────────────────────────────────────┘
               │
       ┌───────┴────────┬─────────────┬───────────────┐
       │                │             │               │
       ▼                ▼             ▼               ▼
┌──────────┐   ┌──────────────┐   ┌─────────┐   ┌─────────┐
│  Claude  │   │   Contract   │   │ Intent  │   │ Keeper  │
│   AI     │   │   Service    │   │ Service │   │ Service │
│Decomposer│   │  (ethers.js) │   │         │   │         │
└──────────┘   └──────────────┘   └─────────┘   └─────────┘
     │                │                 │             │
     │                │                 │             │
     │                └─────────────────┴─────────────┘
     │                            │
     ▼                            ▼
Claude API              Arbitrum Sepolia
(Intent → Segments)     (Deployed Contracts)
```

## Setup

### Prerequisites

1. **Node.js** v18+ and npm
2. **Arbitrum Sepolia ETH** in your wallet
3. **Anthropic API Key** for Claude AI
4. **Deployed contracts** on Arbitrum Sepolia

### Installation

```bash
cd sigil/backend
npm install
```

### Configuration

Copy `.env.example` to `.env` and fill in your credentials:

```bash
cp .env.example .env
```

Required environment variables:

```env
# Anthropic API Key (get from https://console.anthropic.com/)
ANTHROPIC_API_KEY=sk-ant-...

# Your wallet private key (must have Sepolia ETH)
PRIVATE_KEY=0x...

# Arbitrum Sepolia RPC URL
ARBITRUM_SEPOLIA_RPC_URL=https://sepolia-rollup.arbitrum.io/rpc

# Server port (default: 3001)
PORT=3001

# Auto-start keeper service (default: false)
AUTO_START_KEEPER=true
```

## Running

### Development Mode

```bash
npm run dev
```

### Production Build

```bash
npm run build
npm start
```

The server will start on `http://localhost:3001`

## API Endpoints

### Health Check

```http
GET /health
```

Returns service status and configuration.

### Intent Management

#### Decompose Natural Language Intent

```http
POST /decompose
Content-Type: application/json

{
  "text": "Swap 1 ETH for USDC and watch the price, if ETH drops below $3000 swap back",
  "userAddress": "0x...",
  "context": {
    "balances": {
      "ETH": "5.2",
      "USDC": "10000"
    }
  }
}
```

Response:
```json
{
  "success": true,
  "decomposed": {
    "segments": [
      {
        "type": 0,
        "protocol": "uniswap-v3",
        "description": "Swap 1 ETH to USDC",
        "data": {
          "tokenIn": "0x...",
          "tokenOut": "0x...",
          "amountIn": "1",
          "minAmountOut": "2900"
        }
      }
    ],
    "watchers": [
      {
        "type": 0,
        "description": "Monitor ETH/USD price below $3000",
        "params": {
          "pair": "ETH/USD",
          "threshold": "3000",
          "comparison": "LT"
        }
      }
    ],
    "reasoning": "User wants to swap ETH to USDC with downside protection..."
  }
}
```

#### Submit Intent to Blockchain

```http
POST /submit-intent
Content-Type: application/json

{
  "userAddress": "0x...",
  "segments": [...],
  "watchers": [...]
}
```

#### Decompose AND Submit (One-Shot)

```http
POST /decompose-and-submit
Content-Type: application/json

{
  "text": "Put 5000 USDC into the best yield on Arbitrum, exit if TVL drops 20%",
  "userAddress": "0x..."
}
```

This is the recommended endpoint - it handles the full flow from NL → decomposition → on-chain submission.

#### Get User Intents

```http
GET /intents/:address
```

Returns all intents for a user address.

#### Get Intent Details

```http
GET /intent/:intentId
```

#### Cancel Intent

```http
DELETE /intent/:intentId
```

### Watcher Management

#### Get User Watchers

```http
GET /watchers/:address
```

Returns all active watchers for a user.

#### Check Watcher Status

```http
GET /watcher/:watcherId/check
```

Check if a watcher condition is met (without triggering it).

#### Manually Trigger Watcher

```http
POST /watcher/:watcherId/trigger
```

Manually trigger a watcher (useful for testing).

#### Cancel Watcher

```http
DELETE /watcher/:watcherId
```

### Keeper Service

#### Start Keeper

```http
POST /keeper/start
```

Start the keeper service to monitor watchers.

#### Stop Keeper

```http
POST /keeper/stop
```

Stop the keeper service.

#### Get Keeper Stats

```http
GET /keeper/stats
```

Returns keeper status and statistics:

```json
{
  "success": true,
  "stats": {
    "isRunning": true,
    "blockNumber": 12345678,
    "gasPrice": "0.05 gwei",
    "activeWatchers": 42,
    "config": {
      "pollingInterval": 12000,
      "batchSize": 50,
      "maxGasPrice": "100000000"
    }
  }
}
```

### Contract Information

#### Get Contract Addresses

```http
GET /contracts
```

Returns all deployed contract addresses on Arbitrum Sepolia.

#### Get Current Block

```http
GET /block
```

Returns the current block number.

## Services

### 1. Intent Decomposer Service

**File:** `src/services/decomposer.ts`

Uses Claude Sonnet 4.5 to parse natural language into structured intents:

```typescript
const decomposer = new IntentDecomposerService(ANTHROPIC_API_KEY);

const result = await decomposer.decomposeIntent({
  userInput: "Swap 1 ETH to USDC",
  userAddress: "0x..."
});
```

### 2. Intent Service

**File:** `src/services/intent.ts`

Handles on-chain intent submission and querying:

```typescript
const intentService = new IntentService(contractService);

const result = await intentService.submitIntent(
  userAddress,
  segments,
  watchers
);
```

### 3. Keeper Service

**File:** `src/services/keeper.ts`

**THE CRITICAL COMPONENT** - Monitors watchers and triggers new intents, closing the persistent intent loop:

```typescript
const keeper = new KeeperService(contractService);
keeper.start(); // Begin monitoring

// The keeper will:
// 1. Poll active watchers every 12 seconds
// 2. Check if conditions are met (price, time, etc.)
// 3. Trigger watchers when conditions match
// 4. Create NEW intents → CLOSES THE LOOP
```

Configuration:
- `pollingInterval`: How often to check watchers (default: 12000ms = 1 block)
- `batchSize`: Max watchers to check per batch (default: 50)
- `maxGasPrice`: Max gas price willing to pay (default: 0.1 gwei)
- `enablePriceWatchers`: Enable price watcher monitoring (default: true)
- `enableTimeWatchers`: Enable time watcher monitoring (default: true)

### 4. Contract Service

**File:** `src/contracts/index.ts`

Provides typed ethers.js contract instances for all deployed contracts:

```typescript
const contracts = new ContractService(RPC_URL, PRIVATE_KEY);

// Access contract instances
await contracts.decomposer.submitDecomposition(...);
await contracts.watcherRegistry.checkPriceWatcher(watcherId);
await contracts.executor.processWatcher(watcherId);
```

## The Persistent Intent Loop

This is what makes Sigil unique:

```
1. User submits intent: "Swap 1 ETH to USDC, watch price, if < $3000 swap back"
   ↓
2. Claude decomposes into:
   - Segment: Swap 1 ETH → USDC
   - Watcher: Price ETH/USD < $3000 → Swap USDC → ETH
   ↓
3. Backend submits to IntentDecomposer contract
   ↓
4. Router executes swap segment
   ↓
5. Watcher registered in WatcherRegistry
   ↓
6. **Keeper monitors watcher** ←────────────┐
   ↓                                        │
7. When ETH price drops below $3000:       │
   ↓                                        │
8. Keeper calls TriggerExecutor            │
   ↓                                        │
9. TriggerExecutor creates NEW intent      │
   ↓                                        │
10. New intent gets executed ──────────────┘
    THE LOOP CLOSES!
```

## Testing

### Test Decomposition

```bash
curl -X POST http://localhost:3001/decompose \
  -H "Content-Type: application/json" \
  -d '{
    "text": "Swap 1 ETH for USDC",
    "userAddress": "0x1234567890123456789012345678901234567890"
  }'
```

### Test Full Flow

```bash
curl -X POST http://localhost:3001/decompose-and-submit \
  -H "Content-Type: application/json" \
  -d '{
    "text": "Swap 0.1 ETH for USDC and watch price",
    "userAddress": "0xYourWalletAddress"
  }'
```

### Check Keeper Status

```bash
curl http://localhost:3001/keeper/stats
```

### Start Keeper

```bash
curl -X POST http://localhost:3001/keeper/start
```

## Deployed Contracts

The backend automatically connects to these contracts on Arbitrum Sepolia:

- **ERC8004Registry**: `0x239F7823CeA86DF8BF1cC5680a3f78c12592ab76`
- **IntentDecomposer**: `0xDaf6B30C15a0Ce8501A685f0606154F517b8d62a`
- **WatcherRegistry**: `0xB3073A12EBD1ffE05B9Bd530A50625779AB8E93d`
- **IntentRouter**: `0x2D514AB7E8C2F05FA82Bb4885de00Da933501022`
- **TriggerExecutor**: `0xE80dd053081b941FBfF60eB8b105bBF4f971327a`
- **UniswapV3Adapter**: `0x315bbDFE5Ea6F2083c554612D2F339a47afC0605`
- **AaveV3Adapter**: `0x64D41E4D849b83aA1870f30B148a94A2F01a300A`

## Troubleshooting

### "AI decomposer not available"

Make sure `ANTHROPIC_API_KEY` is set in your `.env` file.

### "Intent submission not available"

Make sure `PRIVATE_KEY` is set in your `.env` file and the wallet has Arbitrum Sepolia ETH.

### Keeper not triggering watchers

1. Check keeper is running: `GET /keeper/stats`
2. Verify watchers exist: `GET /watchers/:address`
3. Check gas price isn't too high
4. View keeper logs in console

### RPC errors

Try using a different Arbitrum Sepolia RPC:
- `https://sepolia-rollup.arbitrum.io/rpc`
- `https://arbitrum-sepolia.blockpi.network/v1/rpc/public`

## Development

### Project Structure

```
backend/
├── src/
│   ├── contracts/
│   │   ├── addresses.ts      # Deployed contract addresses
│   │   ├── types.ts          # TypeScript type definitions
│   │   ├── abis.ts           # Contract ABI loaders
│   │   └── index.ts          # Contract service
│   ├── services/
│   │   ├── decomposer.ts     # Claude AI decomposition
│   │   ├── intent.ts         # Intent submission & queries
│   │   └── keeper.ts         # Watcher monitoring (THE LOOP)
│   └── index.ts              # Express API server
├── package.json
├── tsconfig.json
└── .env
```

### Adding New Watchers

To add support for a new watcher type (e.g., GOVERNANCE, RISK):

1. Update `src/services/keeper.ts` in the `checkAndTrigger()` method
2. Implement the specific check logic
3. Enable in keeper config

### Adding New Protocol Adapters

When new adapters are deployed:

1. Add address to `src/contracts/addresses.ts`
2. Load ABI in `src/contracts/abis.ts`
3. Add instance in `src/contracts/index.ts`

## Production Deployment

For production use:

1. Use a secure key management system (not plain text `.env`)
2. Run keeper service in redundant infrastructure
3. Set up monitoring and alerting
4. Use rate limiting on API endpoints
5. Enable CORS properly for frontend
6. Use a load balancer for multiple keeper instances

## License

MIT
