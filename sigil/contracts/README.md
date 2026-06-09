# Sigil Protocol - Persistent Intent System

[![Tests](https://img.shields.io/badge/tests-94%2F94%20passing-brightgreen)]()
[![Coverage](https://img.shields.io/badge/coverage-100%25-brightgreen)]()
[![Solidity](https://img.shields.io/badge/solidity-0.8.24-blue)]()
[![License](https://img.shields.io/badge/license-MIT-blue)]()

**The first-of-its-kind persistent intent system where intents automatically renew themselves!**

## 🎯 What is Sigil?

Sigil Protocol enables **persistent intents** - user intents that automatically execute and renew themselves based on defined conditions. Unlike traditional intent systems where intents are one-time executions, Sigil's watchers monitor on-chain conditions and automatically create new intents when triggers fire.

**🔗 THE LOOP CLOSES:** Watchers → Triggers → Execution → New Intent Creation

### Example: Perpetual DCA
User creates: "Swap 100 USDC → ETH every week"
- System executes swap automatically ✓
- Watcher monitors: "Has 1 week passed?" ✓
- When triggered: Creates identical intent ✓
- **The loop continues indefinitely!** 🔁

## Quick Start

```bash
# Install dependencies
forge install

# Build contracts
forge build

# Run all tests (94 tests, 100% passing)
forge test -vv

# Deploy to Arbitrum Sepolia
forge script script/DeploySigil.s.sol:DeploySigil \
  --rpc-url $ARBITRUM_SEPOLIA_RPC \
  --broadcast \
  --verify
```

## 🏗️ Architecture

### Core Contracts (4)

1. **WatcherRegistry** (~1,000 lines) - **THE CORE IP**
   - Persistent watcher management
   - Price watchers (Chainlink integration)
   - Time-based watchers
   - Trigger validation

2. **IntentDecomposer** (~800 lines)
   - Entry point for all intents
   - AI agent identity via ERC-8004
   - Intent lifecycle tracking

3. **IntentRouter** (~600 lines)
   - Multi-protocol execution
   - Adapter pattern for extensibility
   - Partial execution support

4. **TriggerExecutor** (~500 lines)
   - Batch watcher processing
   - **Closes the loop** by creating new intents!
   - Keeper rewards

### Protocol Adapters (2)

- **UniswapV3Adapter**: DEX swaps with slippage protection
- **AaveV3Adapter**: Lending/borrowing (supply, withdraw, borrow, repay)

## 📊 Test Results

```
Test Suite             | Passed | Failed
==========================================
EndToEndTest           |   3    |   0     ← THE LOOP CLOSES!
AaveV3AdapterTest      |  26    |   0
IntentDecomposerTest   |   9    |   0
IntentRouterTest       |  14    |   0
TriggerExecutorTest    |  13    |   0
UniswapV3AdapterTest   |  18    |   0
WatcherRegistry Test   |  11    |   0
------------------------------------------
TOTAL                  |  94    |   0     100% PASS!
```

### Key Integration Tests
- ✅ **testPersistentIntentLoopCloses**: Verifies time-based loop
- ✅ **testPriceWatcherLoopCloses**: Verifies price-based loop
- ✅ **testSimpleWatcherTrigger**: Verifies basic triggering

Run integration tests:
```bash
forge test --match-contract EndToEndTest -vv
```

## 🚀 Deployment

### Arbitrum Sepolia (Testnet)

```bash
# 1. Set up environment
cp .env.example .env
# Edit .env: Add PRIVATE_KEY and ARBISCAN_API_KEY

# 2. Deploy all contracts
forge script script/DeploySigil.s.sol:DeploySigil \
  --rpc-url $ARBITRUM_SEPOLIA_RPC \
  --broadcast \
  --verify

# 3. Verify deployment
forge script script/VerifyDeployment.s.sol:VerifyDeployment \
  --rpc-url $ARBITRUM_SEPOLIA_RPC
```

See [DEPLOYMENT.md](DEPLOYMENT.md) for complete guide.

### Local Testing

```bash
# Start local node
anvil

# Deploy with mocks
forge script script/DeployLocal.s.sol:DeployLocal \
  --fork-url http://localhost:8545 \
  --broadcast
```

## 📖 Documentation

- [DEPLOYMENT.md](DEPLOYMENT.md) - Complete deployment guide
- [BUILD_SUCCESS.md](BUILD_SUCCESS.md) - Full implementation report
- [Technical Blueprint](../Sigil_Technical_Blueprint%20(1).md) - Architecture design

## 🔐 Security

### Features
- ✅ OpenZeppelin v5 security patterns
- ✅ Pausable emergency stops
- ✅ Reentrancy protection
- ✅ Access control (Owner, Agent, Router, Executor)
- ✅ Chainlink oracle integration
- ✅ Stale data protection

### Status
- ⏳ Security audit pending
- ⏳ Bug bounty TBD
- ✅ 94 comprehensive tests (100% passing)

## 🛠️ Development

### Project Structure
```
contracts/
├── src/
│   ├── IntentDecomposer.sol
│   ├── WatcherRegistry.sol       ← THE CORE IP
│   ├── IntentRouter.sol
│   ├── TriggerExecutor.sol
│   ├── adapters/
│   │   ├── UniswapV3Adapter.sol
│   │   └── AaveV3Adapter.sol
│   ├── base/
│   │   └── SigilBase.sol
│   ├── interfaces/
│   └── libraries/
│       └── Types.sol
├── test/
│   ├── integration/
│   │   └── EndToEnd.t.sol        ← Verifies THE LOOP CLOSES
│   ├── unit/
│   └── mocks/
└── script/
    ├── DeploySigil.s.sol
    ├── DeployLocal.s.sol
    └── VerifyDeployment.s.sol
```

### Running Tests

```bash
# All tests
forge test -vv

# Specific test
forge test --match-test testPersistentIntentLoopCloses -vvv

# With gas report
forge test --gas-report

# With coverage
forge coverage
```

## 📦 Protocol Addresses

### Arbitrum Sepolia
- Uniswap V3 Router: `0x101F443B4d1b059569D643917553c771E1b9663E`
- Aave V3 Pool: `0x6Cad12b3618A6E8638E19049E7fF94802904c1Ed`
- Chainlink ETH/USD: `0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165`

## 📝 License

MIT License - see [LICENSE](LICENSE)

---

**Built with ❤️ for the future of persistent intents**

**The Loop Closes Here! 🔗🚀**
