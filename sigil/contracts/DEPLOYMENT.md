# Sigil Protocol Deployment Guide

## Overview
This guide covers deploying the Sigil Protocol to Arbitrum Sepolia testnet.

## Prerequisites

1. **Foundry** installed and updated
   ```bash
   foundryup
   ```

2. **Environment Variables**
   Create a `.env` file in the contracts directory:
   ```bash
   cp .env.example .env
   ```

   Required variables:
   ```env
   PRIVATE_KEY=your_private_key_here
   ARBITRUM_SEPOLIA_RPC=https://sepolia-rollup.arbitrum.io/rpc
   ARBISCAN_API_KEY=your_arbiscan_api_key_here
   ```

3. **Testnet ETH**
   - Get Sepolia ETH from a faucet
   - Bridge to Arbitrum Sepolia: https://bridge.arbitrum.io/

## Deployment Steps

### 1. Run Tests
Ensure all tests pass before deployment:
```bash
forge test -vv
```

Expected output: `95 tests passed, 0 failed`

### 2. Deploy to Arbitrum Sepolia

```bash
forge script script/DeploySigil.s.sol:DeploySigil \
  --rpc-url $ARBITRUM_SEPOLIA_RPC \
  --broadcast \
  --verify \
  -vvvv
```

This will:
- Deploy all core contracts (Registry, Decomposer, WatcherRegistry, Router, Executor)
- Deploy protocol adapters (Uniswap V3, Aave V3)
- Configure all contract relationships
- Verify contracts on Arbiscan
- Save deployment addresses to `deployments/arbitrum-sepolia.json`

### 3. Verify Deployment

```bash
forge script script/VerifyDeployment.s.sol:VerifyDeployment \
  --rpc-url $ARBITRUM_SEPOLIA_RPC
```

Expected output: `✅ All verifications passed!`

## Deployed Contracts

After deployment, you'll have:

### Core Contracts
- **ERC8004Registry**: Agent identity and permissions
- **IntentDecomposer**: Entry point for all intents
- **WatcherRegistry**: Persistent watcher management (THE CORE IP)
- **IntentRouter**: Segment execution across protocols
- **TriggerExecutor**: Closes the loop by creating new intents

### Protocol Adapters
- **UniswapV3Adapter**: DEX swaps on Uniswap V3
- **AaveV3Adapter**: Lending/borrowing on Aave V3

## Protocol Addresses (Arbitrum Sepolia)

### Uniswap V3
- SwapRouter: `0x101F443B4d1b059569D643917553c771E1b9663E`

### Aave V3
- Pool: `0x6Cad12b3618A6E8638E19049E7fF94802904c1Ed`

### Chainlink Price Feeds
- ETH/USD: `0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165`
- USDC/USD: `0x0153002d20B96532C639313c2d54c3dA09109309`

## Post-Deployment Configuration

### Register Additional AI Agents
```solidity
// As deployer/owner
ERC8004Registry(registryAddress).registerAgent(
    agentAddress,
    "INTENT_DECOMPOSER",
    "ipfs://agent-metadata-hash"
);

IntentDecomposer(decomposerAddress).addAuthorizedRouter(routerAddress);
```

### Add More Protocol Adapters
```solidity
// Deploy adapter
NewProtocolAdapter adapter = new NewProtocolAdapter(protocolAddress, owner);

// Register in router
IntentRouter(routerAddress).addProtocol(
    "protocol-name",
    address(adapter),
    ProtocolCategory.DEX // or LENDING, DERIVATIVES, etc.
);
```

### Add More Price Feeds
```solidity
WatcherRegistry(watcherRegistryAddress).addPriceFeed(
    "BTC/USD",
    chainlinkFeedAddress
);
```

## Testing on Testnet

### 1. Submit a Test Intent

Create a simple DCA (Dollar Cost Averaging) intent:

```solidity
// Approve tokens
IERC20(USDC).approve(uniswapAdapter, amount);

// Create swap segment
Types.Segment memory segment = Types.Segment({
    segmentType: Types.SegmentType.SWAP,
    targetProtocol: uniswapAdapter,
    callData: abi.encode(
        USDC,           // tokenIn
        WETH,           // tokenOut
        3000,           // fee
        100e6,          // amountIn (100 USDC)
        0               // minAmountOut
    ),
    value: 0,
    minGasLimit: 300000
});

// Create time watcher (trigger every hour)
Types.WatcherConfig memory watcher = Types.WatcherConfig({
    watcherType: Types.WatcherType.TIME,
    params: abi.encode(Types.TimeParams({
        interval: 1 hours,
        nextTrigger: block.timestamp + 1 hours,
        maxTriggers: 0, // unlimited
        triggerCount: 0
    })),
    action: abi.encode(segments) // Re-create same intent
});

// Submit to decomposer
bytes32 intentId = IntentDecomposer(decomposerAddress).submitDecomposition(
    msg.sender,
    segments,
    watchers,
    block.timestamp + 30 days
);
```

### 2. Execute Intent

```solidity
IntentRouter(routerAddress).executeSegments(intentId, segments);
```

### 3. Trigger Watcher (After 1 hour)

```solidity
TriggerExecutor(executorAddress).processWatcher(watcherId);
```

**🔗 THE LOOP CLOSES!** A new intent is automatically created!

## Security Considerations

### Before Mainnet
1. ✅ Complete security audit
2. ✅ Set up multi-sig for owner operations
3. ✅ Implement timelock for critical changes
4. ✅ Set up monitoring and alerting
5. ✅ Bug bounty program

### Access Control
- Only authorized AI agents can submit decompositions
- Only approved protocols can execute segments
- Only authorized executors can trigger watchers
- Owner can pause contracts in emergencies

## Troubleshooting

### Deployment Fails
- Check you have enough testnet ETH
- Verify RPC URL is correct
- Check PRIVATE_KEY format (no 0x prefix)

### Verification Fails
- Ensure ARBISCAN_API_KEY is set
- Wait a few blocks after deployment
- Use `--verify --delay 30` for manual verification

### Transactions Revert
- Check token approvals
- Verify protocol addresses are correct
- Ensure sufficient gas limits

## Support

- Documentation: [Link to docs]
- Discord: [Link to Discord]
- GitHub Issues: [Link to GitHub]

---

**Built with ❤️ by the Sigil team**

**The Future of Persistent Intents is Here! 🚀**
