// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../libraries/Types.sol";

/**
 * @title ITriggerExecutor
 * @notice Interface for Trigger Executor - Closes the intent loop
 * @dev Monitors watchers, triggers them, and creates new intents
 */
interface ITriggerExecutor {
    // ============ Events ============

    /// @notice Emitted when a watcher trigger fires
    event TriggerFired(
        bytes32 indexed watcherId,
        bytes32 indexed newIntentId,
        address indexed executor,
        uint256 gasUsed
    );

    /// @notice Emitted when a trigger fails
    event TriggerFailed(
        bytes32 indexed watcherId,
        string reason,
        uint256 retryCount
    );

    /// @notice Emitted when a batch of watchers is checked
    event BatchExecuted(
        uint256 watchersChecked,
        uint256 triggersExecuted,
        address indexed executor
    );

    /// @notice Emitted when executor rewards are paid
    event RewardPaid(address indexed executor, uint256 amount);

    // ============ Functions ============

    /**
     * @notice Check and execute a batch of watchers
     * @param watcherIds Array of watcher identifiers to check
     * @return triggeredCount Number of watchers that triggered
     */
    function checkAndExecuteBatch(bytes32[] calldata watcherIds)
        external
        returns (uint256 triggeredCount);

    /**
     * @notice Process a single watcher
     * @param watcherId Watcher identifier
     * @return triggered True if watcher was triggered
     */
    function processWatcher(bytes32 watcherId) external returns (bool triggered);

    /**
     * @notice Manual trigger for a watcher (owner only)
     * @param watcherId Watcher identifier
     */
    function manualTrigger(bytes32 watcherId) external;

    /**
     * @notice Get trigger history for a watcher
     * @param watcherId Watcher identifier
     * @return events Array of trigger events
     */
    function getTriggerHistory(bytes32 watcherId)
        external
        view
        returns (Types.TriggerEvent[] memory events);

    /**
     * @notice Get failed watchers
     * @return watcherIds Array of watcher identifiers that failed
     */
    function getFailedWatchers()
        external
        view
        returns (bytes32[] memory watcherIds);

    /**
     * @notice Estimate gas for batch execution
     * @param watcherIds Array of watcher identifiers
     * @return gasEstimate Estimated gas cost
     */
    function estimateBatchGas(bytes32[] calldata watcherIds)
        external
        view
        returns (uint256 gasEstimate);

    /**
     * @notice Claim executor rewards
     */
    function claimRewards() external;

    /**
     * @notice Set maximum batch size
     * @param size Maximum number of watchers per batch
     */
    function setMaxBatchSize(uint256 size) external;

    /**
     * @notice Set executor reward basis points
     * @param bps Reward in basis points (100 = 1%)
     */
    function setExecutorRewardBps(uint256 bps) external;
}
