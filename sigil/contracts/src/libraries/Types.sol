// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title Types
 * @notice Shared type definitions for the Sigil Persistent Intent Engine
 * @dev All contracts import this library for consistent type usage
 */
library Types {
    // ============ Enums ============

    /// @notice Intent lifecycle status
    enum IntentStatus {
        PENDING,      // Submitted but not executed
        EXECUTING,    // Immediate segments in progress
        ACTIVE,       // Immediate segments done, watchers active
        TRIGGERED,    // Watcher condition met, new intent created
        COMPLETED,    // All segments + watchers completed
        CANCELLED,    // User or admin cancelled
        EXPIRED       // Passed expiry timestamp
    }

    /// @notice Type of watcher for on-chain monitoring
    enum WatcherType {
        PRICE,        // Chainlink oracle price thresholds
        TIME,         // Interval-based triggers
        RISK,         // TVL drops, protocol upgrades
        GOVERNANCE    // Proposal monitoring
    }

    /// @notice Watcher lifecycle status
    enum WatcherStatus {
        ACTIVE,       // Monitoring conditions
        TRIGGERED,    // Condition met, action executed
        EXPIRED,      // Passed expiry timestamp
        CANCELLED     // User or admin cancelled
    }

    /// @notice Comparison operations for watchers
    enum ComparisonOp {
        GT,           // Greater than
        LT,           // Less than
        GTE,          // Greater than or equal
        LTE,          // Less than or equal
        EQ,           // Equal
        NEQ           // Not equal
    }

    /// @notice Type of intent segment
    enum SegmentType {
        SWAP,         // Token swap on DEX
        DEPOSIT,      // Deposit to lending/yield protocol
        WITHDRAW,     // Withdraw from protocol
        HEDGE,        // Open hedge position (perpetuals)
        CUSTOM        // Custom protocol interaction
    }

    /// @notice Protocol category for routing
    enum ProtocolCategory {
        DEX,          // Decentralized exchange
        LENDING,      // Lending protocol
        DERIVATIVES,  // Perpetuals, options
        YIELD,        // Yield farming
        CUSTOM        // Custom protocol
    }

    // ============ Core Structs ============

    /// @notice A single atomic action to execute
    struct Segment {
        SegmentType segmentType;    // Type of action
        address targetProtocol;      // Protocol address or adapter
        bytes callData;              // ABI-encoded function call
        uint256 value;               // ETH value to send
        uint256 minGasLimit;         // Minimum gas required
    }

    /// @notice Configuration for creating a watcher
    struct WatcherConfig {
        WatcherType watcherType;     // Type of watcher
        bytes parameters;            // ABI-encoded type-specific params
        bytes triggerAction;         // Action to execute when triggered
        uint256 expiresAt;           // Expiry timestamp
    }

    /// @notice Decomposed intent with segments and watchers
    struct DecomposedIntent {
        bytes32 intentId;            // Unique intent identifier
        address user;                // Intent owner
        address submitter;           // AI agent that decomposed it
        bytes32[] watcherIds;        // Associated watcher IDs
        uint256 segmentCount;        // Number of immediate segments
        uint256 timestamp;           // Creation timestamp
        uint256 expiresAt;           // Intent expiry
        IntentStatus status;         // Current status
    }

    /// @notice Persistent watcher monitoring on-chain state
    struct Watcher {
        bytes32 watcherId;           // Unique watcher identifier
        bytes32 parentIntentId;      // Parent intent reference
        address owner;               // Watcher owner
        WatcherType watcherType;     // Type of watcher
        WatcherStatus status;        // Current status
        bytes parameters;            // Type-specific encoded params
        bytes triggerAction;         // Encoded action for trigger
        uint256 createdAt;           // Creation timestamp
        uint256 expiresAt;           // Expiry timestamp
        uint256 lastChecked;         // Last check timestamp
        uint256 checkCount;          // Number of checks (gas tracking)
    }

    // ============ Watcher Parameter Structs ============

    /// @notice Parameters for price-based watchers
    struct PriceParams {
        address priceFeed;           // Chainlink oracle address
        int256 threshold;            // Price threshold
        ComparisonOp comparison;     // Comparison operation
        uint8 decimals;              // Price feed decimals
    }

    /// @notice Parameters for time-based watchers
    struct TimeParams {
        uint256 interval;            // Seconds between triggers
        uint256 nextTrigger;         // Next trigger timestamp
        uint256 maxTriggers;         // Max times to trigger (0 = unlimited)
        uint256 triggerCount;        // Times triggered so far
    }

    /// @notice Parameters for risk-based watchers
    struct RiskParams {
        address protocol;            // Protocol to monitor
        address tvlOracle;           // TVL oracle address (optional)
        uint256 tvlDropThreshold;    // Drop threshold in basis points
        uint256 baselineTVL;         // Baseline TVL value
        bool watchUpgrades;          // Monitor contract upgrades
        address proxyAdmin;          // Proxy admin if watching upgrades
    }

    /// @notice Parameters for governance-based watchers
    struct GovernanceParams {
        address governanceContract;  // Governance contract address
        bytes4 proposalSelector;     // Function selector to watch
        bytes32[] watchedParamHashes; // Keccak256 of params to watch
        bool triggerOnAny;           // true = any proposal, false = specific params
    }

    // ============ Execution Tracking Structs ============

    /// @notice Record of a watcher trigger event
    struct TriggerEvent {
        bytes32 watcherId;           // Watcher that triggered
        bytes32 newIntentId;         // New intent created from trigger
        address executor;            // Who triggered it
        uint256 timestamp;           // Trigger timestamp
        uint256 gasUsed;             // Gas consumed
        bool success;                // Execution success
        bytes failureReason;         // Error data if failed
    }

    /// @notice Record of segment execution
    struct SegmentExecution {
        bytes32 intentId;            // Parent intent
        uint256 segmentIndex;        // Index in segment array
        address protocol;            // Protocol executed on
        uint256 timestamp;           // Execution timestamp
        uint256 gasUsed;             // Gas consumed
        bool success;                // Execution success
        bytes returnData;            // Return data or error
    }

    // ============ Execution Plan Struct ============

    /// @notice Plan for executing multiple segments
    struct ExecutionPlan {
        address[] protocols;         // Protocol addresses
        bytes[] callDatas;           // Encoded calls
        uint256[] values;            // ETH values
        uint256[] gasLimits;         // Gas limits per segment
    }
}
