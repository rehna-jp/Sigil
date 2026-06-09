# Sigil — Persistent Intent Engine on Arbitrum

## Technical Blueprint for Arbitrum Open House London Buildathon

---

## The Problem

Every intent system today follows the same lifecycle:

**User signs intent → Solver competes → Execution → Intent dies.**

But real financial goals aren't one-shot. "Hedge my ETH 30% and exit if any protocol I'm in gets a risky governance proposal" is not one transaction — it's an **ongoing commitment** that needs to react to future on-chain events.

The trigger layer — the thing that watches conditions and fires new actions — remains entirely off-chain, dependent on centralized keepers, cron jobs, and bots that can fail, be censored, or go offline.

**Sigil solves this by making intents persistent.** After execution, the intent stays alive. Watchers monitor on-chain state. When conditions change, the system autonomously creates and executes new intents — closing the loop.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    USER LAYER                                │
│  Natural language input → "Hedge my ETH 30%, exit if..."    │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│              AI INTENT DECOMPOSER                            │
│  ERC-8004 identity | NL → atomic segments + watcher config  │
│                                                              │
│  Output:                                                     │
│  ├── Swap Segment: ETH → stETH (70%)                       │
│  ├── Hedge Segment: Open perp short (30%)                   │
│  └── Watcher Segment: Monitor conditions (PERSISTENT)       │
└──────────────────────┬──────────────────────────────────────┘
                       │
            ┌──────────┴──────────┐
            ▼                     ▼
┌───────────────────┐  ┌─────────────────────────┐
│  SOLVER NETWORK   │  │  WATCHER REGISTRY       │
│  Competitive      │  │  On-chain contract       │
│  auction for      │  │                          │
│  immediate        │  │  ├── Price watchers      │
│  segments         │  │  ├── Governance watchers  │
│                   │  │  ├── Risk watchers        │
│  Routes through:  │  │  └── Time watchers        │
│  GMX, Camelot,    │  │                          │
│  Aave, Uniswap   │  │  Monitors on-chain state  │
└────────┬──────────┘  │  continuously             │
         │             └────────────┬──────────────┘
         ▼                          │
┌───────────────────┐               │ Condition met?
│  ON-CHAIN         │               │
│  EXECUTION        │               ▼
│  (Arbitrum One)   │  ┌─────────────────────────┐
└───────────────────┘  │  TRIGGER EXECUTOR       │
                       │  Creates NEW intent      │
                       │  → loops back to         │
                       │    AI Decomposer         │
                       └──────────┬───────────────┘
                                  │
                                  └──→ (back to top)
```

---

## Smart Contract Architecture

### Contract 1: IntentDecomposer.sol

**Purpose:** On-chain registry for the AI agent's identity and authorization.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IERC8004Registry {
    function registerAgent(address agent, bytes32 capabilities) external;
    function getReputation(address agent) external view returns (uint256);
}

contract IntentDecomposer {
    // The AI agent's on-chain identity (ERC-8004)
    address public aiAgent;
    IERC8004Registry public agentRegistry;

    // Intent structure after decomposition
    struct DecomposedIntent {
        bytes32 intentId;
        address user;
        Segment[] immediateSegments;
        WatcherConfig[] watchers;
        uint256 timestamp;
        bool active;
    }

    struct Segment {
        uint8 segmentType;    // 0=swap, 1=deposit, 2=withdraw, 3=hedge
        address protocol;      // Target protocol address
        bytes callData;        // Encoded function call
        uint256 value;         // ETH value if needed
    }

    struct WatcherConfig {
        uint8 watcherType;     // 0=price, 1=governance, 2=risk, 3=time
        bytes parameters;      // ABI-encoded watcher params
        Segment[] triggerActions; // What to do when triggered
        uint256 expiry;        // When watcher expires
    }

    mapping(bytes32 => DecomposedIntent) public intents;
    mapping(address => bytes32[]) public userIntents;

    event IntentDecomposed(
        bytes32 indexed intentId,
        address indexed user,
        uint256 segmentCount,
        uint256 watcherCount
    );

    event IntentExecuted(bytes32 indexed intentId);
    event WatcherRegistered(bytes32 indexed intentId, uint8 watcherType);

    modifier onlyAgent() {
        require(msg.sender == aiAgent, "Only AI agent");
        _;
    }

    constructor(address _aiAgent, address _registry) {
        aiAgent = _aiAgent;
        agentRegistry = IERC8004Registry(_registry);
    }

    /// @notice AI agent submits decomposed intent after NL processing
    function submitDecomposition(
        address user,
        Segment[] calldata segments,
        WatcherConfig[] calldata watchers
    ) external onlyAgent returns (bytes32 intentId) {
        intentId = keccak256(abi.encodePacked(user, block.timestamp, segments.length));

        DecomposedIntent storage intent = intents[intentId];
        intent.intentId = intentId;
        intent.user = user;
        intent.timestamp = block.timestamp;
        intent.active = true;

        // Store segments
        for (uint i = 0; i < segments.length; i++) {
            intent.immediateSegments.push(segments[i]);
        }

        // Store watcher configs
        for (uint i = 0; i < watchers.length; i++) {
            intent.watchers.push(watchers[i]);
        }

        userIntents[user].push(intentId);

        emit IntentDecomposed(intentId, user, segments.length, watchers.length);
        return intentId;
    }
}
```

---

### Contract 2: WatcherRegistry.sol (THE CORE IP)

**Purpose:** On-chain registry of persistent watchers that monitor conditions and trigger new intents.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract WatcherRegistry {
    enum WatcherType { PRICE, GOVERNANCE, RISK, TIME }
    enum WatcherStatus { ACTIVE, TRIGGERED, EXPIRED, CANCELLED }
    enum ComparisonOp { GT, LT, GTE, LTE }

    struct Watcher {
        bytes32 watcherId;
        bytes32 parentIntentId;
        address owner;
        WatcherType watcherType;
        WatcherStatus status;
        bytes parameters;          // Type-specific encoded params
        bytes triggerAction;       // Encoded action to execute
        uint256 createdAt;
        uint256 expiresAt;
        uint256 lastChecked;
    }

    // Price watcher parameters
    struct PriceParams {
        address priceFeed;         // Chainlink oracle address
        int256 threshold;          // Price threshold
        ComparisonOp comparison;   // GT, LT, GTE, LTE
    }

    // Governance watcher parameters
    struct GovernanceParams {
        address governanceContract;  // Protocol's governance contract
        bytes4 proposalSelector;     // Function selector to monitor
        bytes32[] watchedParamKeys;  // Which params to watch for changes
    }

    // Risk watcher parameters
    struct RiskParams {
        address protocol;           // Protocol to monitor
        uint256 tvlDropThreshold;   // % drop that triggers (basis points)
        uint256 baselineTVL;        // TVL at watcher creation
        bool watchUpgrades;         // Monitor contract upgrades
    }

    // Time watcher parameters
    struct TimeParams {
        uint256 interval;           // Seconds between triggers
        uint256 nextTrigger;        // Next trigger timestamp
        uint256 maxTriggers;        // Max times to trigger (0 = unlimited)
        uint256 triggerCount;       // Times triggered so far
    }

    // Storage
    mapping(bytes32 => Watcher) public watchers;
    mapping(address => bytes32[]) public userWatchers;
    bytes32[] public activeWatcherIds;

    // Authorized trigger executors (keeper network)
    mapping(address => bool) public authorizedExecutors;

    address public owner;
    address public intentDecomposer;

    event WatcherCreated(
        bytes32 indexed watcherId,
        bytes32 indexed parentIntentId,
        address indexed owner,
        WatcherType watcherType
    );
    event WatcherTriggered(bytes32 indexed watcherId, bytes triggerData);
    event WatcherCancelled(bytes32 indexed watcherId);

    modifier onlyExecutor() {
        require(authorizedExecutors[msg.sender], "Not authorized executor");
        _;
    }

    constructor(address _intentDecomposer) {
        owner = msg.sender;
        intentDecomposer = _intentDecomposer;
    }

    /// @notice Register a new persistent watcher
    function registerWatcher(
        bytes32 parentIntentId,
        address watcherOwner,
        WatcherType watcherType,
        bytes calldata parameters,
        bytes calldata triggerAction,
        uint256 expiresAt
    ) external returns (bytes32 watcherId) {
        require(msg.sender == intentDecomposer || msg.sender == watcherOwner, "Unauthorized");

        watcherId = keccak256(abi.encodePacked(
            parentIntentId, watcherOwner, watcherType, block.timestamp
        ));

        watchers[watcherId] = Watcher({
            watcherId: watcherId,
            parentIntentId: parentIntentId,
            owner: watcherOwner,
            watcherType: watcherType,
            status: WatcherStatus.ACTIVE,
            parameters: parameters,
            triggerAction: triggerAction,
            createdAt: block.timestamp,
            expiresAt: expiresAt,
            lastChecked: block.timestamp
        });

        userWatchers[watcherOwner].push(watcherId);
        activeWatcherIds.push(watcherId);

        emit WatcherCreated(watcherId, parentIntentId, watcherOwner, watcherType);
        return watcherId;
    }

    /// @notice Check if a price watcher should trigger
    function checkPriceWatcher(bytes32 watcherId) public view returns (bool shouldTrigger) {
        Watcher storage w = watchers[watcherId];
        require(w.watcherType == WatcherType.PRICE, "Not price watcher");
        require(w.status == WatcherStatus.ACTIVE, "Not active");

        PriceParams memory params = abi.decode(w.parameters, (PriceParams));
        AggregatorV3Interface feed = AggregatorV3Interface(params.priceFeed);
        (, int256 price,,,) = feed.latestRoundData();

        if (params.comparison == ComparisonOp.GT) return price > params.threshold;
        if (params.comparison == ComparisonOp.LT) return price < params.threshold;
        if (params.comparison == ComparisonOp.GTE) return price >= params.threshold;
        if (params.comparison == ComparisonOp.LTE) return price <= params.threshold;
        return false;
    }

    /// @notice Executor triggers a watcher and returns the action to execute
    function triggerWatcher(bytes32 watcherId) external onlyExecutor returns (bytes memory action) {
        Watcher storage w = watchers[watcherId];
        require(w.status == WatcherStatus.ACTIVE, "Not active");
        require(block.timestamp < w.expiresAt, "Expired");

        w.status = WatcherStatus.TRIGGERED;
        w.lastChecked = block.timestamp;

        emit WatcherTriggered(watcherId, w.triggerAction);
        return w.triggerAction;
    }

    /// @notice User cancels their watcher
    function cancelWatcher(bytes32 watcherId) external {
        require(watchers[watcherId].owner == msg.sender, "Not owner");
        watchers[watcherId].status = WatcherStatus.CANCELLED;
        emit WatcherCancelled(watcherId);
    }

    /// @notice Get all active watchers for a user
    function getUserActiveWatchers(address user) external view returns (bytes32[] memory) {
        bytes32[] memory all = userWatchers[user];
        uint256 count = 0;
        for (uint i = 0; i < all.length; i++) {
            if (watchers[all[i]].status == WatcherStatus.ACTIVE) count++;
        }
        bytes32[] memory active = new bytes32[](count);
        uint256 j = 0;
        for (uint i = 0; i < all.length; i++) {
            if (watchers[all[i]].status == WatcherStatus.ACTIVE) {
                active[j++] = all[i];
            }
        }
        return active;
    }
}
```

---

### Contract 3: TriggerExecutor.sol

**Purpose:** When a watcher fires, this contract creates a new intent and routes it back through the system.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IWatcherRegistry {
    function checkPriceWatcher(bytes32 watcherId) external view returns (bool);
    function triggerWatcher(bytes32 watcherId) external returns (bytes memory);
}

interface IIntentDecomposer {
    function submitDecomposition(
        address user,
        bytes calldata segments,
        bytes calldata watchers
    ) external returns (bytes32);
}

contract TriggerExecutor {
    IWatcherRegistry public watcherRegistry;
    address public aiAgent;

    // Track triggered intents for audit trail
    struct TriggerEvent {
        bytes32 watcherId;
        bytes32 newIntentId;
        uint256 timestamp;
        bool success;
    }

    mapping(bytes32 => TriggerEvent[]) public triggerHistory;

    event TriggerFired(
        bytes32 indexed watcherId,
        bytes32 indexed newIntentId,
        uint256 timestamp
    );
    event TriggerFailed(bytes32 indexed watcherId, string reason);

    constructor(address _watcherRegistry, address _aiAgent) {
        watcherRegistry = IWatcherRegistry(_watcherRegistry);
        aiAgent = _aiAgent;
    }

    /// @notice Check and execute a batch of watchers (called by keeper/agent)
    function checkAndExecute(bytes32[] calldata watcherIds) external {
        for (uint i = 0; i < watcherIds.length; i++) {
            _processWatcher(watcherIds[i]);
        }
    }

    function _processWatcher(bytes32 watcherId) internal {
        try watcherRegistry.checkPriceWatcher(watcherId) returns (bool shouldTrigger) {
            if (shouldTrigger) {
                bytes memory action = watcherRegistry.triggerWatcher(watcherId);
                // Action contains the encoded new intent to create
                // The AI agent picks this up off-chain and creates
                // a new decomposed intent
                emit TriggerFired(watcherId, bytes32(0), block.timestamp);
            }
        } catch Error(string memory reason) {
            emit TriggerFailed(watcherId, reason);
        }
    }
}
```

---

### Contract 4: IntentRouter.sol

**Purpose:** Routes solved intent segments to the correct Arbitrum protocols.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract IntentRouter {
    // Approved protocol adapters
    mapping(address => bool) public approvedProtocols;
    mapping(string => address) public protocolAdapters;

    address public owner;

    event SegmentExecuted(
        bytes32 indexed intentId,
        address protocol,
        bool success
    );

    constructor() {
        owner = msg.sender;
    }

    /// @notice Execute a series of intent segments atomically
    function executeSegments(
        bytes32 intentId,
        address[] calldata protocols,
        bytes[] calldata callDatas,
        uint256[] calldata values
    ) external payable returns (bool[] memory results) {
        require(protocols.length == callDatas.length, "Length mismatch");
        results = new bool[](protocols.length);

        for (uint i = 0; i < protocols.length; i++) {
            require(approvedProtocols[protocols[i]], "Protocol not approved");
            (bool success,) = protocols[i].call{value: values[i]}(callDatas[i]);
            results[i] = success;
            emit SegmentExecuted(intentId, protocols[i], success);
        }
    }

    // Protocol adapter registration
    function addProtocol(string calldata name, address adapter) external {
        require(msg.sender == owner, "Not owner");
        protocolAdapters[name] = adapter;
        approvedProtocols[adapter] = true;
    }
}
```

---

## Off-Chain Components

### AI Intent Decomposer Service

```
Technology: Node.js / Python
LLM: Claude API or similar for NL parsing
Identity: ERC-8004 registered agent on Arbitrum

Flow:
1. User types: "Put $5K into the best yield on Arbitrum,
   exit if TVL drops 20% or governance proposes parameter change"

2. AI parses into structured intent:
   {
     "immediate_segments": [
       {
         "type": "swap",
         "from": "USDC",
         "to": "best_yield_token",
         "amount": "5000",
         "routing": "evaluate_at_execution"
       },
       {
         "type": "deposit",
         "protocol": "evaluated_protocol",
         "token": "yield_token"
       }
     ],
     "persistent_watchers": [
       {
         "type": "risk",
         "condition": "tvl_drop",
         "threshold": 2000,  // 20% in basis points
         "action": {
           "type": "withdraw_and_swap",
           "to": "USDC"
         }
       },
       {
         "type": "governance",
         "monitor": "protocol_governance_contract",
         "watch_for": "parameter_change_proposal",
         "action": {
           "type": "alert_user",
           "fallback": "auto_exit_if_no_response_24h"
         }
       }
     ]
   }

3. AI submits decomposition on-chain via IntentDecomposer contract
4. Immediate segments go to solver network
5. Watcher configs go to WatcherRegistry
```

### Trigger Monitoring Service (Keeper)

```
Technology: Node.js with ethers.js / Rust (Stylus candidate)
Runs: Continuously, polling active watchers

Loop:
1. Fetch all active watcher IDs from WatcherRegistry
2. For each watcher:
   - Price watchers: call checkPriceWatcher() every block
   - Governance watchers: listen for ProposalCreated events
   - Risk watchers: compare current TVL vs baseline
   - Time watchers: check if nextTrigger <= block.timestamp
3. When condition met: call TriggerExecutor.checkAndExecute()
4. TriggerExecutor fires the watcher and emits event
5. AI agent picks up event, creates new intent, loops back

Payment: Agent uses x402 to pay for oracle data feeds
```

---

## Tech Stack

| Component | Technology | Notes |
|-----------|-----------|-------|
| Smart contracts | Solidity 0.8.24+ | Foundry for testing |
| Watcher engine | Rust via Stylus (bonus) | High-perf condition matching |
| AI decomposer | Node.js + LLM API | Claude/GPT for NL parsing |
| Keeper service | Node.js + ethers.js | Polls watchers, triggers |
| Frontend | React + wagmi + viem | Wallet connection |
| Oracle feeds | Chainlink on Arbitrum | Price data |
| Agent identity | ERC-8004 | On-chain AI identity |
| Agent payments | x402 | Machine-to-machine payments |
| Testnet | Arbitrum Sepolia | Primary deployment |
| Secondary | Robinhood Chain testnet | Cross-chain demo |

---

## 3-Week Build Plan

### Week 1: Core Loop (Intent → Execute)

**Day 1-2: Project setup**
- Initialize Foundry project
- Deploy IntentDecomposer.sol to Arbitrum Sepolia
- Deploy IntentRouter.sol with 2-3 protocol adapters (Uniswap, Aave)
- Set up AI decomposer service (basic NL → structured intent)

**Day 3-4: Solver integration**
- Build lightweight solver that routes through Arbitrum DEXes
- Connect AI output → solver → on-chain execution
- Test: type "swap 0.1 ETH to USDC" → watch it execute

**Day 5-7: End-to-end basic flow**
- Wire up: NL input → AI decompose → solve → execute on Arbitrum
- Build minimal frontend (text input + transaction status)
- Get the "wow" moment working: type English → see on-chain tx

### Week 2: Persistent Watchers (THE DIFFERENTIATOR)

**Day 8-9: WatcherRegistry.sol**
- Deploy WatcherRegistry with PriceWatcher support
- Integrate Chainlink price feeds on Arbitrum Sepolia
- Test: register a price watcher, verify checkPriceWatcher()

**Day 10-11: TriggerExecutor + Keeper**
- Deploy TriggerExecutor.sol
- Build keeper service that polls active watchers
- **Critical milestone**: get the LOOP working
  - Create intent with price watcher
  - Watcher detects price cross
  - Trigger fires → new intent created → new execution
  - THE LOOP CLOSES

**Day 12-14: Additional watcher types**
- Add GovernanceWatcher (monitor proposal events)
- Add TimeWatcher (interval-based triggers)
- Add RiskWatcher (TVL monitoring) if time allows
- Register AI agent with ERC-8004

### Week 3: Polish + Demo

**Day 15-16: Frontend dashboard**
- Active intents view (positions + live watchers)
- Real-time watcher status ("Watching: ETH price > $4000... no trigger yet")
- Trigger history (audit trail of all loop iterations)
- Intent input with AI-powered suggestions

**Day 17-18: Robinhood Chain + Stylus**
- Deploy contracts on Robinhood Chain testnet
- If feasible: port watcher matching engine to Stylus (Rust)
- Cross-chain intent demo (intent on Arbitrum One, watcher on Robinhood)

**Day 19-21: Demo prep**
- Script the demo flow (see Demo Script below)
- Record backup video
- Write pitch deck
- Test everything end-to-end multiple times

---

## Demo Script (THE WINNING MOMENT)

```
1. OPEN the Sigil app, connect wallet

2. TYPE: "Put 0.5 ETH into the best yield on Arbitrum.
   If ETH drops below $3500, exit everything to USDC.
   Rebalance every 24 hours."

3. SHOW the AI decomposer breaking this into:
   - Swap segment: ETH → yield token
   - Deposit segment: deposit into protocol
   - Price watcher: ETH < $3500 → exit to USDC
   - Time watcher: every 24h → rebalance

4. WATCH the immediate segments execute on Arbitrum Sepolia
   (show the tx on Arbiscan)

5. SHOW the dashboard: position is live, TWO watchers active
   - Price watcher: "Monitoring ETH/USD... current: $3800"
   - Time watcher: "Next rebalance in 23h 45m"

6. THE KILLER MOMENT: Manually trigger a price drop on testnet
   (use a mock oracle or manipulate the feed)

7. WATCH IT HAPPEN LIVE:
   - Watcher detects: "ETH dropped below $3500!"
   - Trigger fires automatically
   - New intent created: "Exit yield position → swap to USDC"
   - AI decomposes the exit intent
   - Solver executes the exit
   - Dashboard updates: "Position closed. USDC safe."

8. SHOW the trigger history: full audit trail of the loop

9. CLOSE with: "This intent was typed once.
   It executed, watched, reacted, and protected the user's money
   — all autonomously, all on Arbitrum."
```

---

## Judging Category Alignment

| Arbitrum Category | How Sigil Fits |
|---|---|
| **DeFi: Intent-based DeFi systems** | DIRECT HIT — this is literally what they asked for |
| **AI Agents: Automated DeFi strategies** | AI decomposer + trigger executor are autonomous agents |
| **AI Agents: Autonomous payment systems** | x402 for agent-to-agent payments |
| **Bonus: Stylus-powered applications** | Watcher engine in Rust/WASM |
| **Bonus: Crosschain liquidity apps** | Cross-chain intents (Arbitrum ↔ Robinhood Chain) |

---

## Competitive Advantage

| What exists | What Sigil adds |
|---|---|
| CoW Protocol, UniswapX (fire-and-forget intents) | Intents that PERSIST after execution |
| Chainlink Automation (keeper triggers) | AI-powered decomposition of natural language |
| Gelato Network (automated tasks) | Intent LOOP — triggers create new intents |
| ERC-7521 (intent standard) | Consumer-facing NL interface on top of the standard |
| Reactive Network (reactive contracts) | Full product: NL → decompose → solve → watch → react |

**Nobody has combined all five layers into one consumer product.**

---

## Team Allocation (4 people)

| Role | Person | Focus |
|---|---|---|
| Smart contract lead | Dev 1 | All 4 contracts, Foundry tests, deployment |
| AI/Backend lead | Dev 2 | NL decomposer, keeper service, ERC-8004 |
| Frontend lead | Dev 3 | React dashboard, wallet integration, demo UI |
| Integration lead | Dev 4 | Solver routing, Stylus port, Robinhood Chain |

---

## Risk Mitigation

| Risk | Mitigation |
|---|---|
| AI decomposer accuracy | Start with template intents (pre-defined patterns), add free-form NL as stretch goal |
| Watcher reliability | Run keeper on redundant infra, add manual trigger fallback |
| Demo failure | Pre-record backup video, have testnet pre-loaded with state |
| Scope creep | MVP = price watcher loop only. Governance + time are stretch goals |
| Gas costs for watchers | Batch watcher checks in single tx, use Stylus for efficiency |

---

## Post-Hackathon Vision

Sigil becomes the **intent operating system for Arbitrum**:

1. Open the watcher registry as a public good — any protocol can register watcher types
2. Decentralize the keeper network — anyone can run a trigger executor and earn fees via ERC-8004 identity and x402 payments
3. Build an intent marketplace — users share and fork successful intent strategies ("sigils")
4. Expand to cross-chain — watchers on any EVM chain, execution on Arbitrum
5. Partner with wallets — embed Sigil as the default "smart action" layer

The persistent intent primitive is as fundamental as the swap or the lending pool.
It just doesn't exist yet.

---

## Phase Implementation Plan

The 3-Week Build Plan above is **Phase 1** in a longer execution arc. This section maps the end-to-end implementation roadmap from hackathon MVP to ecosystem-scale infrastructure — the concrete steps that turn the Post-Hackathon Vision into shipping reality.

### Phase Overview

| Phase | Name | Timeline | Goal | Stage Gate |
|---|---|---|---|---|
| **0** | Foundation | T-1 week | Repo, infra, team alignment | Skeleton tx deploys & emits event in CI |
| **1** | Hackathon MVP | Weeks 1–3 | Closed loop on Arbitrum Sepolia | Live demo: NL → execute → watch → trigger → re-execute |
| **2** | Alpha Hardening | Months 1–2 | Security + watcher breadth | All 4 watcher types stable, internal audit clean |
| **3** | Public Beta | Months 3–4 | Open testnet, external audit | 500+ active intents, <0.1% trigger failure |
| **4** | Mainnet Launch | Months 5–6 | Production on Arbitrum One | $1M+ TVL routed through intents |
| **5** | Ecosystem Scale | Months 7–12 | Public good, cross-chain, marketplace | 3+ chains, 10+ partner integrations |

---

### Phase 0 — Foundation (Pre-Build)

**Objective:** Eliminate avoidable friction before the hackathon clock starts.

**Deliverables**
- Monorepo with `/contracts`, `/agent`, `/keeper`, `/frontend`, `/scripts` layout
- Foundry setup with CI on every push (lint, build, test, gas snapshot)
- Pre-funded Arbitrum Sepolia wallets for every dev; testnet ETH topped up
- Chainlink price feed addresses, protocol adapter targets, and ABIs catalogued in `/scripts/addresses.ts`
- Architecture decision records (ADRs) for: watcher polling vs event-driven, intent ID hashing scheme, x402 payment flow, agent key custody

**Exit Criteria:** A skeleton "hello world" transaction (deploy → call → event emit) runs green in CI on Arbitrum Sepolia.

**Owner:** Smart contract lead + Integration lead

---

### Phase 1 — Hackathon MVP (Weeks 1–3)

**Objective:** Prove the persistent intent loop works end-to-end on a public testnet, with a live, undeniable demo.

**Scope (delivered by 3-Week Build Plan above)**
- 4 core contracts deployed on Arbitrum Sepolia
- AI decomposer wired to Claude API with structured-output prompting
- Keeper service polling watchers every block
- Frontend dashboard with live watcher status and trigger history
- Demo flow rehearsed and recorded as backup

**Success Metrics**

| Metric | Target |
|---|---|
| End-to-end loop latency (trigger → new execution) | < 30 seconds |
| Demo dry-runs without failure | 5 consecutive |
| Watcher types implemented | Price (required); Time + Governance (stretch) |
| On-chain transactions visible in demo | ≥ 4 on Arbiscan |
| Frontend load → first contract write | < 5 seconds |

**Exit Criteria:** Demo executes flawlessly in front of judges; codebase is in a shippable state, not a duct-taped state.

**Stretch:** Stylus watcher engine port, Robinhood Chain deployment, RiskWatcher live.

---

### Phase 2 — Alpha Hardening (Months 1–2 Post-Hackathon)

**Objective:** Convert the demo into something a friendly user would trust with $100 of real funds (still testnet).

**Workstreams**
- **Security:** Slither + Mythril static analysis, Foundry invariant + fuzz testing across all contracts, internal review by an external Solidity dev
- **Watcher completeness:** Production implementations of governance (event-driven via subgraph), risk (TVL + contract-upgrade monitoring), and time watchers
- **Gas optimization:** Batch watcher checks, packed storage, custom errors, Stylus port of the `checkAllWatchers()` hot path
- **Reliability:** Redundant keeper deployment (3+ regions), failover logic, manual trigger fallback exposed to users in the UI
- **Observability:** Trigger history indexer (Subsquid or Goldsky), watcher-failure dashboard, alert pipeline (PagerDuty / Discord)
- **AI accuracy:** Eval suite of 100+ NL intent examples with expected decompositions; track regression rate per LLM version

**Success Metrics**
- 0 critical or high findings in internal audit
- 50 closed-alpha users, average intent lifetime > 7 days
- Watcher trigger success rate ≥ 99%
- Gas per watcher check < 50K (post-Stylus)
- AI decomposition accuracy ≥ 95% on eval set

**Exit Criteria:** External audit firm engaged and scoped; no known critical or high-severity bugs; alpha users report no friction blockers.

---

### Phase 3 — Public Beta (Months 3–4)

**Objective:** Open Sigil to public testnet usage and complete an external audit.

**Workstreams**
- **External audit:** Engagement with a reputable firm (Spearbit, Trail of Bits, ChainSecurity, or Zellic); two-round remediation cycle
- **Keeper decentralization:** Open keeper participation via ERC-8004 identity; keepers earn fees via x402 micropayments per successful trigger; staking/slashing parameters defined
- **Protocol breadth:** Adapters for ≥ 10 Arbitrum protocols — Uniswap v3/v4, GMX v2, Aave v3, Camelot, Pendle, Radiant, Balancer, Curve, Lido (wstETH), Frax
- **Frontend polish:** Mobile-responsive, intent template library ("sigils"), sharable intent permalinks, embedded simulation preview
- **Cross-chain prep:** Watchers running on a second chain (Base or Robinhood Chain) firing into Arbitrum execution via canonical bridges
- **Documentation:** Full developer docs, intent authoring guide, watcher specification document

**Success Metrics**

| Metric | Target |
|---|---|
| Active intents on testnet | 500+ |
| Decentralized keepers | ≥ 5 independent operators |
| Trigger failure rate | < 0.1% |
| Median time from condition met → trigger fired | ≤ 1 block |
| External audit | Passed, all medium+ findings resolved |

**Exit Criteria:** Audit report public; bug bounty program funded; mainnet deployment scripts dry-run on a forked mainnet without errors.

---

### Phase 4 — Mainnet Launch (Months 5–6)

**Objective:** Deploy production contracts to Arbitrum One and onboard real capital safely.

**Workstreams**
- **Phased rollout:** Per-intent value caps (start at $1K, scale weekly based on incident rate); pausable governance via multi-sig timelock; emergency-exit function for all open positions
- **Bug bounty:** Immunefi listing with $250K+ pool; tiered payouts by severity
- **Partnerships:** Wallet integrations (target one launch partner — Rabby, Family, or Frame); begin custody-grade integration conversations (Fireblocks, Safe)
- **Intent marketplace MVP:** Users publish intent templates; on-chain attribution for forks; creator royalty fees routed via x402
- **Cross-chain live:** Cross-chain intents (Arbitrum ↔ at least one other rollup) in production with security model documented

**Success Metrics**
- $1M+ cumulative TVL routed through Sigil intents in first 30 days
- 0 user funds lost
- Average user has ≥ 2 active watchers
- ≥ 1 wallet partner shipped to production
- Mainnet trigger success rate ≥ 99.5%

**Exit Criteria:** 30 days post-launch with no critical incidents; week-over-week new user growth trending positive; partner pipeline has ≥ 3 wallets in active integration.

---

### Phase 5 — Ecosystem Scale (Months 7–12)

**Objective:** Transform Sigil from a product into infrastructure that others build on.

**Workstreams**
- **Public-good watcher registry:** Permissionless registration of new watcher types via a standardized `IWatcher` interface any builder can implement
- **SDK:** TypeScript and Rust SDKs for third-party builders to author intents programmatically; documentation site with live playground
- **Wallet layer:** Default "smart action" provider for ≥ 3 wallets; one-click intent installation from any dApp via a universal intent URI scheme
- **Multi-chain:** Live on Arbitrum One, Robinhood Chain, Base, Optimism — unified watcher network monitoring all four with a single user view
- **Decentralization:** DAO formation for parameter governance (fees, keeper requirements, watcher type approvals); evaluate token launch to align keepers + users + protocols
- **Composability:** Other protocols build on Sigil — lending protocols use it for liquidation prevention, DAOs use it for treasury policy enforcement, vaults use it for automated rebalancing

**Success Metrics**
- 10+ integrating partner protocols
- 3+ chains live with unified watcher state
- 100+ community-contributed watcher types or intent templates
- $50M+ TVL governed by persistent intents
- Sigil cited as a primitive in ≥ 5 external research papers or protocol whitepapers

**Exit Criteria:** N/A — this is the steady-state operating phase. Subsequent phases address category expansion (e.g. non-EVM chains, off-chain triggers, MEV-aware execution).

---

### Phase Dependency Flow

```
Phase 0  ──►  Phase 1  ──►  Phase 2  ──►  Phase 3  ──►  Phase 4  ──►  Phase 5
Foundation   Hackathon    Alpha          Public          Mainnet         Ecosystem
             MVP          Hardening      Beta            Launch          Scale

   │            │             │              │               │               │
   ▼            ▼             ▼              ▼               ▼               ▼
 CI green   Demo loop    Internal       External        Real capital    Public good
 on testnet on Sepolia   audit clean    audit + 500     + partner       + multi-chain
                         + 50 alpha     test users      wallets         + DAO
```

---

### Cross-Phase Workstreams

These run continuously across all phases, deepening at each stage:

| Workstream | Phase 1 | Phase 2 | Phase 3 | Phase 4 | Phase 5 |
|---|---|---|---|---|---|
| **Security** | Foundry tests | Slither + fuzz + internal audit | External audit | Bug bounty | Continuous audits |
| **Watchers** | Price (live), Time stretch | All 4 types live | Cross-chain watchers | Production-grade | Permissionless types |
| **Keepers** | 1 (in-house) | 3 redundant | 5+ decentralized | Open network | DAO-governed |
| **Protocols** | 2 (Uniswap, Aave) | 5 | 10 | 10+ on mainnet | 25+ |
| **ERC-8004 Identity** | Registered | Reputation tracking | Multi-agent support | Agent marketplace | Standard adoption |
| **x402 Payments** | Oracle data fees | Keeper fees | Cross-keeper settlement | Marketplace royalties | Full agent economy |
| **AI Decomposer** | Templates + free-form | Eval suite, fine-tuning | Multi-model ensemble | On-chain verifiable inference (research) | Open-source models |

---

### Phase Risk Register

| Phase | Top Risk | Mitigation |
|---|---|---|
| 0 | Team alignment / scope drift | ADRs locked before code, daily 15-min standups |
| 1 | Demo failure on stage | Pre-recorded backup, pre-loaded testnet state, dry-runs |
| 2 | Critical bug in watcher state machine | Foundry invariant testing, formal spec of state transitions |
| 3 | External audit finds protocol-design flaws | Pre-audit informal review, budget 4 weeks for remediation |
| 4 | Mainnet exploit | Caps + pausable + bug bounty + phased rollout |
| 5 | Centralization of keeper network | Economic incentives + ERC-8004 reputation + slashing |

---

## The Pitch (30 seconds)

> "Every DeFi intent today dies after execution. You swap, it's done. You deposit, it forgets you.
>
> Sigil changes that. You inscribe your intent once — and it stays alive. Watching prices.
> Monitoring governance. Sensing risk. When conditions change, Sigil reacts automatically —
> creating new intents, executing new actions, protecting your money.
>
> We call it a persistent intent engine. It's the nervous system DeFi has been missing.
> Built on Arbitrum. Powered by AI. No one else has built this."

---

**You're building it. Go win.**
