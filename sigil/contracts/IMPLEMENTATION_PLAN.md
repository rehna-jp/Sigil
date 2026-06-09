# Sigil Smart Contracts Implementation Plan

## Overview
Implement all 4 core smart contracts for the Sigil Persistent Intent Engine on Arbitrum. This plan builds the complete on-chain infrastructure for persistent intents with watchers that create new intents when conditions trigger.

## User Requirements
- ✅ All 4 core contracts (IntentDecomposer, WatcherRegistry, TriggerExecutor, IntentRouter)
- ✅ Remove/deprecate existing SigilEngine.sol
- ✅ Real protocol integrations (Uniswap V3, Aave V3, GMX V2, Camelot)
- ✅ Full ERC-8004 implementation for AI agent identity
- ✅ Chainlink price feed integration
- ✅ Comprehensive testing suite

## Build Order & Dependencies

```
1. Foundation Layer (Dependencies: None)
   ├── Install: OpenZeppelin, Chainlink, Forge-std
   ├── Create: Types.sol (shared types library)
   ├── Create: SigilBase.sol (base contract patterns)
   └── Create: All interfaces (IERC8004, IIntentDecomposer, IWatcherRegistry, etc.)

2. IntentDecomposer.sol (Dependencies: IERC8004, Types.sol)
   └── Entry point for all intents, manages lifecycle

3. WatcherRegistry.sol (Dependencies: IntentDecomposer, Chainlink, Types.sol)
   └── THE CORE IP - persistent watchers monitoring on-chain state

4. IntentRouter.sol (Dependencies: Types.sol, Protocol interfaces)
   ├── Protocol adapters (Uniswap V3, Aave V3, GMX, Camelot)
   └── Segment execution engine

5. TriggerExecutor.sol (Dependencies: WatcherRegistry, IntentDecomposer)
   └── Closes the loop - triggers create new intents
```

## Critical Files to Create

### Interfaces & Libraries (Week 1, Day 1)
1. `contracts/src/libraries/Types.sol` - All shared types and enums
2. `contracts/src/base/SigilBase.sol` - Base contract (Ownable, ReentrancyGuard, Pausable)
3. `contracts/src/interfaces/IERC8004.sol` - ERC-8004 interface + minimal implementation
4. `contracts/src/interfaces/IIntentDecomposer.sol`
5. `contracts/src/interfaces/IWatcherRegistry.sol`
6. `contracts/src/interfaces/IIntentRouter.sol`
7. `contracts/src/interfaces/ITriggerExecutor.sol`
8. `contracts/src/interfaces/IProtocolAdapter.sol`

### Core Contracts (Week 1-2)
9. `contracts/src/IntentDecomposer.sol` - Intent registry and decomposition storage
10. `contracts/src/WatcherRegistry.sol` - Persistent watchers (Price, Time, Risk, Governance)
11. `contracts/src/TriggerExecutor.sol` - Watcher triggering and loop closure
12. `contracts/src/IntentRouter.sol` - Protocol routing and execution

### Protocol Adapters (Week 2)
13. `contracts/src/adapters/UniswapV3Adapter.sol` - Uniswap V3 swaps
14. `contracts/src/adapters/AaveV3Adapter.sol` - Aave V3 supply/withdraw
15. `contracts/src/adapters/GMXAdapter.sol` - GMX V2 perpetuals
16. `contracts/src/adapters/CamelotAdapter.sol` - Camelot DEX

### Protocol Interfaces (Week 2)
17. `contracts/src/interfaces/protocols/IUniswapV3Router.sol`
18. `contracts/src/interfaces/protocols/IAaveV3Pool.sol`
19. `contracts/src/interfaces/protocols/IGMXV2Router.sol`
20. `contracts/src/interfaces/protocols/ICamelotRouter.sol`

### Testing (Week 1-3)
21. `contracts/test/unit/IntentDecomposer.t.sol`
22. `contracts/test/unit/WatcherRegistry.t.sol`
23. `contracts/test/unit/TriggerExecutor.t.sol`
24. `contracts/test/unit/IntentRouter.t.sol`
25. `contracts/test/integration/EndToEnd.t.sol` - **Critical: Verify loop closes**
26. `contracts/test/mocks/MockChainlinkFeed.sol`
27. `contracts/test/mocks/MockUniswapRouter.sol`
28. `contracts/test/mocks/MockAavePool.sol`

### Deployment (Week 3)
29. `contracts/script/Deploy.s.sol` - Deployment script for all contracts
30. `contracts/script/Verify.s.sol` - Post-deployment verification
31. `contracts/deployments/arbitrum-sepolia.json` - Deployed addresses

## Detailed Contract Specifications

### 1. IntentDecomposer.sol

**Purpose:** On-chain registry for AI agent identity (ERC-8004) and decomposed intent storage.

**Key Components:**
- AI agent authorization via ERC-8004
- Intent storage with segments and watcher references
- Status tracking (PENDING → EXECUTING → ACTIVE → TRIGGERED → COMPLETED)
- Segment execution reporting
- User intent management

**State Variables:**
```solidity
address public aiAgent;
IERC8004Registry public agentRegistry;
mapping(bytes32 => DecomposedIntent) public intents;
mapping(address => bytes32[]) public userIntents;
mapping(address => bool) public authorizedRouters;
uint256 public intentNonce;
```

**Critical Functions:**
- `submitDecomposition(user, segments, watchers, expiresAt)` → intentId
- `reportSegmentExecution(intentId, segmentIndex, success, returnData)`
- `cancelIntent(intentId)`
- `getIntentSegments(intentId)` → Segment[]
- `getUserIntents(user)` → bytes32[]

### 2. WatcherRegistry.sol (THE CORE IP)

**Purpose:** Persistent watcher storage and condition monitoring.

**Watcher Types:**
1. **PRICE** - Chainlink oracle thresholds (GT, LT, GTE, LTE)
2. **TIME** - Interval-based triggers
3. **RISK** - TVL drops, protocol upgrades
4. **GOVERNANCE** - Proposal monitoring

**Key Components:**
- Watcher lifecycle management
- Batch condition checking (gas efficiency)
- Chainlink price feed integration
- Active watcher tracking (array + index mapping)

**State Variables:**
```solidity
mapping(bytes32 => Watcher) public watchers;
mapping(address => bytes32[]) public userWatchers;
bytes32[] public activeWatcherIds;
mapping(address => bool) public authorizedExecutors;
mapping(string => address) public priceFeeds; // "ETH/USD" => Chainlink feed
```

**Critical Functions:**
- `registerWatcher(parentIntentId, owner, type, params, action, expiry)` → watcherId
- `checkWatchers(watcherIds[])` → bool[] shouldTrigger
- `checkPriceWatcher(watcherId)` → bool
- `checkTimeWatcher(watcherId)` → bool
- `triggerWatcher(watcherId)` → (action, owner)
- `getUserActiveWatchers(user)` → bytes32[]

### 3. TriggerExecutor.sol

**Purpose:** Monitor watchers, trigger when conditions met, create new intents (closes the loop).

**Key Components:**
- Batch watcher checking
- Trigger execution and new intent creation
- Failed trigger retry logic
- Executor reward mechanism
- Audit trail (trigger history)

**State Variables:**
```solidity
IWatcherRegistry public watcherRegistry;
IIntentDecomposer public intentDecomposer;
address public aiAgent;
mapping(bytes32 => TriggerEvent[]) public triggerHistory;
uint256 public maxBatchSize = 50;
```

**Critical Functions:**
- `checkAndExecuteBatch(watcherIds[])` → triggeredCount
- `processWatcher(watcherId)` → triggered
- `createIntentFromTrigger(watcherId, action, owner)` → newIntentId
- `getTriggerHistory(watcherId)` → TriggerEvent[]

### 4. IntentRouter.sol

**Purpose:** Route segments to protocol adapters and execute atomically.

**Key Components:**
- Protocol adapter registry
- Atomic segment execution (all-or-nothing)
- Protocol categorization (DEX, LENDING, DERIVATIVES, YIELD)
- Execution history tracking

**State Variables:**
```solidity
mapping(string => address) public protocolAdapters; // "uniswap-v3" => adapter
mapping(address => bool) public approvedProtocols;
mapping(bytes32 => SegmentExecution[]) public executionHistory;
address public intentDecomposer;
```

**Critical Functions:**
- `executeSegments(intentId, segments[])` → bool[] results
- `addProtocol(name, adapter, category)`
- `getExecutionHistory(intentId)` → SegmentExecution[]

## Protocol Integration Strategy

### Adapter Pattern
Each protocol has a dedicated adapter implementing `IProtocolAdapter`:

```solidity
interface IProtocolAdapter {
    function execute(bytes calldata segmentData, address user, uint256 value)
        external payable returns (bool success, bytes memory returnData);

    function simulate(bytes calldata segmentData, address user)
        external view returns (bool canExecute, string memory reason);

    function getProtocolName() external pure returns (string memory);
    function getSupportedSegmentTypes() external pure returns (uint8[] memory);
}
```

### Priority Adapters
1. **UniswapV3Adapter** - Essential for swaps (high priority)
2. **AaveV3Adapter** - Essential for lending/yield (high priority)
3. **CamelotAdapter** - Arbitrum-native DEX (medium priority)
4. **GMXAdapter** - Perpetuals, complex (low priority/stretch goal)

### Arbitrum Protocol Addresses
**Mainnet (Arbitrum One):**
- Uniswap V3 Router: `0xE592427A0AEce92De3Edee1F18E0157C05861564`
- Aave V3 Pool: `0x794a61358D6845594F94dc1DB02A252b5b4814aD`
- GMX V2 Router: `0x7C68C7866A64FA2160F78EEaE12217FFbf871fa8`
- Camelot Router: `0xc873fEcbd354f5A56E00E710B90EF4201db2448d`
- Chainlink ETH/USD: (testnet: `0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165`)

## Testing Strategy

### Unit Tests (>80% coverage minimum)
- Test each contract in isolation with mocks
- Cover all functions, edge cases, access control
- Test state transitions and status enums
- Gas benchmarking for batch operations

### Integration Tests (Critical)
**EndToEnd.t.sol must verify:**
1. AI agent submits decomposed intent
2. Router executes immediate segments
3. Watchers register successfully
4. Conditions trigger (price change, time elapsed)
5. TriggerExecutor creates NEW intent from trigger
6. **THE LOOP CLOSES** - new intent executes

### Mock Contracts
- `MockChainlinkFeed` - Price manipulation for testing
- `MockUniswapRouter` - Swap simulation
- `MockAavePool` - Lending simulation
- Mock all external dependencies

## Deployment Sequence

```bash
# 1. Install dependencies
forge install OpenZeppelin/openzeppelin-contracts@v5.0.0
forge install smartcontractkit/chainlink@v2.9.0
forge install foundry-rs/forge-std@v1.7.0

# 2. Build all contracts
forge build

# 3. Run tests
forge test -vvv

# 4. Deploy to Arbitrum Sepolia
forge script script/Deploy.s.sol:DeployScript \
  --rpc-url $ARBITRUM_SEPOLIA_RPC_URL \
  --broadcast \
  --verify

# 5. Verify deployment
forge script script/Verify.s.sol:VerifyScript \
  --rpc-url $ARBITRUM_SEPOLIA_RPC_URL
```

**Deployment Order:**
1. ERC8004Registry (or use existing)
2. IntentDecomposer (needs: ERC8004Registry, AI agent address)
3. WatcherRegistry (needs: IntentDecomposer)
4. TriggerExecutor (needs: WatcherRegistry, AI agent)
5. IntentRouter (standalone)
6. Protocol Adapters (need: protocol addresses)
7. Wire contracts (authorize executors, routers, set references)

## Migration: Removing SigilEngine.sol

1. **Preserve patterns:** Extract Ownable + ReentrancyGuard + Pausable into `SigilBase.sol`
2. **Deprecation:** Rename to `SigilEngine.deprecated.sol` during development (keep as reference)
3. **Test migration:** Port useful patterns from `SigilEngine.t.sol` to new tests
4. **Complete removal:** Delete deprecated files at end of Week 3 after all new contracts tested

**Why deprecate:** SigilEngine.sol is a simple text-based intent store. The new architecture uses structured segments and watchers, making the old contract incompatible.

## Risk Mitigation

### Technical Risks
| Risk | Mitigation |
|------|-----------|
| Dependencies fail to install | Pre-install on Day 1, use specific versions |
| Chainlink feeds unavailable on Sepolia | Deploy MockChainlinkFeed, use mainnet fork |
| Protocol adapters too complex | Start with Uniswap only, others as stretch goals |
| Gas costs too high | Batch operations, optimize storage, benchmark early |
| ERC-8004 standard immature | Implement minimal version ourselves |

### Integration Risks
| Risk | Mitigation |
|------|-----------|
| Intent loop doesn't close | Integration test by Day 11, prioritize TriggerExecutor |
| Watcher triggers fail | Try-catch on external calls, retry logic, failure events |
| Cross-contract errors | Interface-driven development, mock dependencies |
| Reentrancy vulnerabilities | Use ReentrancyGuard everywhere, Slither analysis |

### Demo Risks
| Risk | Mitigation |
|------|-----------|
| Live demo fails | Pre-recorded backup video, dry runs |
| Testnet RPC issues | Local fork fallback, multiple RPC endpoints |
| Gas runs out | Fund multiple wallets early |

## Success Criteria

### Minimum Viable Product (Must Have)
- [ ] IntentDecomposer deployed and working
- [ ] WatcherRegistry with price watchers functional
- [ ] At least 1 protocol adapter (Uniswap V3)
- [ ] TriggerExecutor triggers watchers and creates new intents
- [ ] **The loop closes** (verified in integration test)
- [ ] All contracts deployed to Arbitrum Sepolia
- [ ] >80% test coverage on core contracts

### Target (Should Have)
- [ ] All 4 watcher types (Price, Time, Risk, Governance)
- [ ] 2+ protocol adapters (Uniswap + Aave minimum)
- [ ] >90% test coverage
- [ ] Gas optimized (<2M gas for batch operations)
- [ ] SigilEngine.sol removed
- [ ] Deployment scripts automated

### Stretch Goals
- [ ] 4 protocol adapters (add GMX + Camelot)
- [ ] Deployment to Robinhood Chain testnet
- [ ] Stylus watcher engine port (Rust/WASM)
- [ ] Frontend integration complete

## Implementation Timeline

### Week 1: Foundation + IntentDecomposer + WatcherRegistry Start
**Day 1-2:** Setup, interfaces, Types.sol, IntentDecomposer
**Day 3-5:** WatcherRegistry structure, price watchers, time watchers
**Day 6-7:** Risk watchers, governance watchers, batch operations

### Week 2: Complete Watchers + Execution Layer
**Day 8-9:** WatcherRegistry testing, integration with IntentDecomposer
**Day 10-12:** Protocol adapters (Uniswap, Aave)
**Day 13-14:** IntentRouter, TriggerExecutor

### Week 3: Integration + Deployment
**Day 15-17:** End-to-end integration testing (verify loop closes)
**Day 18-19:** Security testing (Slither), gas optimization
**Day 20:** Deploy to Arbitrum Sepolia, verify contracts
**Day 21:** Demo preparation, backup video

## Files to Modify/Delete

### Create (30+ new files)
- All contracts listed in "Critical Files to Create" section above
- Interfaces, libraries, adapters, tests, deployment scripts

### Modify
- `contracts/foundry.toml` - Already configured (no changes needed)
- `contracts/remappings.txt` - Already configured (verify after forge install)

### Delete (End of Week 3)
- `contracts/src/SigilEngine.sol` → Replaced by IntentDecomposer
- `contracts/test/SigilEngine.t.sol` → Replaced by new test suite

## Key Architecture Decisions

1. **Modular Design:** 4 separate contracts instead of monolithic (easier testing, upgradeability)
2. **Interface-Driven:** All cross-contract calls via interfaces (mockable, flexible)
3. **Batch Operations:** WatcherRegistry supports batch checking (gas efficiency)
4. **Adapter Pattern:** Protocol integrations isolated (easy to add new protocols)
5. **Event-Driven:** Heavy event usage for off-chain keeper coordination
6. **Status State Machines:** Clear state transitions prevent invalid operations
7. **Access Control:** Multi-tier (owner, authorized executors, AI agent, users)

## Critical Implementation Notes

1. **Intent ID Generation:** Use `keccak256(abi.encodePacked(user, nonce, block.timestamp))` for collision resistance
2. **Watcher ID Generation:** Use `keccak256(abi.encodePacked(intentId, watcherType, params, nonce))`
3. **Active Watcher Array:** Maintain index mapping for O(1) removal when watchers trigger/expire
4. **Chainlink Integration:** Check for stale data (updatedAt timestamp), handle reverts
5. **Protocol Adapter Safety:** All external calls in try-catch, validate return data
6. **Expiry Enforcement:** Max watcher lifetime prevents perpetual obligations
7. **Reentrancy Protection:** Use OpenZeppelin's ReentrancyGuard on all state-changing functions

## Next Steps

1. Install dependencies (`forge install`)
2. Create directory structure (`mkdir -p src/interfaces src/adapters test/mocks`)
3. Implement in build order (Types.sol → Interfaces → IntentDecomposer → WatcherRegistry → IntentRouter → TriggerExecutor)
4. Test continuously (write tests alongside implementation)
5. Deploy to Arbitrum Sepolia
6. Verify the persistent intent loop works end-to-end
