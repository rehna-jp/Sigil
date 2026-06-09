// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./base/SigilBase.sol";
import "./libraries/Types.sol";
import "./interfaces/ITriggerExecutor.sol";
import "./interfaces/IWatcherRegistry.sol";
import "./interfaces/IIntentDecomposer.sol";

/**
 * @title TriggerExecutor
 * @notice Closes the intent loop - triggers watchers and creates new intents
 * @dev Monitors watchers, executes triggers, and coordinates with AI agent
 */
contract TriggerExecutor is SigilBase, ITriggerExecutor {
    // ============ State Variables ============

    /// @notice Watcher Registry contract
    IWatcherRegistry public watcherRegistry;

    /// @notice Intent Decomposer contract
    IIntentDecomposer public intentDecomposer;

    /// @notice AI agent address
    address public aiAgent;

    /// @notice Trigger history for each watcher
    mapping(bytes32 => Types.TriggerEvent[]) private triggerHistory;

    /// @notice Last trigger block for each watcher
    mapping(bytes32 => uint256) public lastTriggerBlock;

    /// @notice Failed trigger count for each watcher
    mapping(bytes32 => uint256) public failedTriggerCount;

    /// @notice Executor rewards pending claim
    mapping(address => uint256) public pendingRewards;

    /// @notice Maximum batch size for watcher checking
    uint256 public maxBatchSize = 50;

    /// @notice Maximum retry attempts for failed triggers
    uint256 public maxRetries = 3;

    /// @notice Executor reward in basis points (10 = 0.1%)
    uint256 public executorRewardBps = 10;

    /// @notice Minimum executor gas reserve
    uint256 public minExecutorGas = 500000;

    /// @notice Total rewards distributed
    uint256 public totalRewardsDistributed;

    // ============ Constructor ============

    constructor(
        address _watcherRegistry,
        address _aiAgent,
        address initialOwner
    ) SigilBase(initialOwner) {
        require(_watcherRegistry != address(0), "TriggerExecutor: zero registry");
        require(_aiAgent != address(0), "TriggerExecutor: zero agent");

        watcherRegistry = IWatcherRegistry(_watcherRegistry);
        aiAgent = _aiAgent;
    }

    // ============ External Functions ============

    /**
     * @inheritdoc ITriggerExecutor
     */
    function checkAndExecuteBatch(bytes32[] calldata watcherIds)
        external
        override
        whenNotPaused
        nonReentrant
        returns (uint256 triggeredCount)
    {
        require(watcherIds.length > 0, "TriggerExecutor: empty batch");
        require(
            watcherIds.length <= maxBatchSize,
            "TriggerExecutor: batch too large"
        );
        require(gasleft() >= minExecutorGas, "TriggerExecutor: insufficient gas");

        uint256 watchersChecked = 0;
        triggeredCount = 0;

        // Check conditions for all watchers
        bool[] memory shouldTrigger = watcherRegistry.checkWatchers(watcherIds);

        // Process triggers
        for (uint256 i = 0; i < watcherIds.length; i++) {
            watchersChecked++;

            if (shouldTrigger[i]) {
                // Prevent same-block re-triggering
                if (lastTriggerBlock[watcherIds[i]] == block.number) {
                    continue;
                }

                bool success = processWatcher(watcherIds[i]);
                if (success) {
                    triggeredCount++;
                }
            }
        }

        // Calculate and distribute rewards
        if (triggeredCount > 0) {
            uint256 reward = (triggeredCount * 0.001 ether * executorRewardBps) / 10000;
            if (address(this).balance >= reward) {
                pendingRewards[msg.sender] += reward;
                totalRewardsDistributed += reward;
            }
        }

        emit BatchExecuted(watchersChecked, triggeredCount, msg.sender);

        return triggeredCount;
    }

    /**
     * @inheritdoc ITriggerExecutor
     */
    function processWatcher(bytes32 watcherId)
        public
        override
        whenNotPaused
        returns (bool triggered)
    {
        // First check if the watcher's condition is met
        bytes32[] memory ids = new bytes32[](1);
        ids[0] = watcherId;
        bool[] memory shouldTrigger = watcherRegistry.checkWatchers(ids);

        if (!shouldTrigger[0]) {
            return false;
        }

        uint256 gasStart = gasleft();

        try watcherRegistry.triggerWatcher(watcherId) returns (
            bytes memory action,
            address owner
        ) {
            lastTriggerBlock[watcherId] = block.number;

            // Decode action to get segments for new intent
            bytes32 newIntentId = bytes32(0);

            // If intentDecomposer is set, create new intent on-chain
            if (address(intentDecomposer) != address(0)) {
                try this._decodeAndCreateIntent(action, owner) returns (bytes32 intentId) {
                    newIntentId = intentId;
                } catch {
                    // If decoding/creation fails, just continue without new intent
                    // This allows the trigger to still succeed
                }
            }

            // Create trigger event record
            Types.TriggerEvent memory triggerEvent = Types.TriggerEvent({
                watcherId: watcherId,
                newIntentId: newIntentId,
                executor: msg.sender,
                timestamp: block.timestamp,
                gasUsed: gasStart - gasleft(),
                success: true,
                failureReason: ""
            });

            triggerHistory[watcherId].push(triggerEvent);

            emit TriggerFired(
                watcherId,
                newIntentId,
                msg.sender,
                triggerEvent.gasUsed
            );

            // Reset failed count on success
            failedTriggerCount[watcherId] = 0;

            return true;
        } catch Error(string memory reason) {
            failedTriggerCount[watcherId]++;

            // Record failed trigger
            Types.TriggerEvent memory failedEvent = Types.TriggerEvent({
                watcherId: watcherId,
                newIntentId: bytes32(0),
                executor: msg.sender,
                timestamp: block.timestamp,
                gasUsed: gasStart - gasleft(),
                success: false,
                failureReason: bytes(reason)
            });

            triggerHistory[watcherId].push(failedEvent);

            emit TriggerFailed(watcherId, reason, failedTriggerCount[watcherId]);

            return false;
        } catch (bytes memory lowLevelData) {
            failedTriggerCount[watcherId]++;

            Types.TriggerEvent memory failedEvent = Types.TriggerEvent({
                watcherId: watcherId,
                newIntentId: bytes32(0),
                executor: msg.sender,
                timestamp: block.timestamp,
                gasUsed: gasStart - gasleft(),
                success: false,
                failureReason: lowLevelData
            });

            triggerHistory[watcherId].push(failedEvent);

            emit TriggerFailed(
                watcherId,
                "Low-level error",
                failedTriggerCount[watcherId]
            );

            return false;
        }
    }

    /**
     * @inheritdoc ITriggerExecutor
     */
    function manualTrigger(bytes32 watcherId) external override onlyOwner {
        require(watcherId != bytes32(0), "TriggerExecutor: invalid watcher");

        bool success = processWatcher(watcherId);
        require(success, "TriggerExecutor: manual trigger failed");
    }

    /**
     * @inheritdoc ITriggerExecutor
     */
    function getTriggerHistory(bytes32 watcherId)
        external
        view
        override
        returns (Types.TriggerEvent[] memory events)
    {
        return triggerHistory[watcherId];
    }

    /**
     * @inheritdoc ITriggerExecutor
     */
    function getFailedWatchers()
        external
        view
        override
        returns (bytes32[] memory watcherIds)
    {
        // Get all active watchers
        bytes32[] memory activeWatchers = watcherRegistry.getActiveWatcherIds();
        uint256 failedCount = 0;

        // Count failed watchers
        for (uint256 i = 0; i < activeWatchers.length; i++) {
            if (
                failedTriggerCount[activeWatchers[i]] > 0 &&
                failedTriggerCount[activeWatchers[i]] < maxRetries
            ) {
                failedCount++;
            }
        }

        // Create array of failed watchers
        watcherIds = new bytes32[](failedCount);
        uint256 index = 0;

        for (uint256 i = 0; i < activeWatchers.length; i++) {
            if (
                failedTriggerCount[activeWatchers[i]] > 0 &&
                failedTriggerCount[activeWatchers[i]] < maxRetries
            ) {
                watcherIds[index] = activeWatchers[i];
                index++;
            }
        }

        return watcherIds;
    }

    /**
     * @inheritdoc ITriggerExecutor
     */
    function estimateBatchGas(bytes32[] calldata watcherIds)
        external
        view
        override
        returns (uint256 gasEstimate)
    {
        // Rough estimate: 200k gas per watcher check + trigger
        gasEstimate = watcherIds.length * 200000;

        // Add base overhead
        gasEstimate += 100000;

        return gasEstimate;
    }

    /**
     * @inheritdoc ITriggerExecutor
     */
    function claimRewards() external override nonReentrant {
        uint256 reward = pendingRewards[msg.sender];
        require(reward > 0, "TriggerExecutor: no rewards");
        require(
            address(this).balance >= reward,
            "TriggerExecutor: insufficient balance"
        );

        pendingRewards[msg.sender] = 0;

        (bool success, ) = msg.sender.call{value: reward}("");
        require(success, "TriggerExecutor: transfer failed");

        emit RewardPaid(msg.sender, reward);
    }

    /**
     * @inheritdoc ITriggerExecutor
     */
    function setMaxBatchSize(uint256 size) external override onlyOwner {
        require(size > 0 && size <= 100, "TriggerExecutor: invalid size");
        maxBatchSize = size;
    }

    /**
     * @inheritdoc ITriggerExecutor
     */
    function setExecutorRewardBps(uint256 bps) external override onlyOwner {
        require(bps <= 1000, "TriggerExecutor: bps too high"); // Max 10%
        executorRewardBps = bps;
    }

    /**
     * @notice Set IntentDecomposer address
     * @param _intentDecomposer Address of IntentDecomposer
     */
    function setIntentDecomposer(address _intentDecomposer) external onlyOwner {
        require(_intentDecomposer != address(0), "TriggerExecutor: zero address");
        intentDecomposer = IIntentDecomposer(_intentDecomposer);
    }

    /**
     * @notice Update AI agent address
     * @param _aiAgent New AI agent address
     */
    function updateAIAgent(address _aiAgent) external onlyOwner {
        require(_aiAgent != address(0), "TriggerExecutor: zero address");
        aiAgent = _aiAgent;
    }

    /**
     * @notice Set max retry attempts
     * @param retries Maximum retry attempts
     */
    function setMaxRetries(uint256 retries) external onlyOwner {
        require(retries > 0 && retries <= 10, "TriggerExecutor: invalid retries");
        maxRetries = retries;
    }

    /**
     * @notice Set minimum executor gas reserve
     * @param gasReserve Minimum gas reserve
     */
    function setMinExecutorGas(uint256 gasReserve) external onlyOwner {
        require(gasReserve >= 100000, "TriggerExecutor: gas too low");
        minExecutorGas = gasReserve;
    }

    /**
     * @notice Fund executor rewards pool
     */
    function fundRewardsPool() external payable {
        require(msg.value > 0, "TriggerExecutor: zero value");
    }

    /**
     * @notice Withdraw excess rewards pool funds
     * @param to Address to send funds to
     * @param amount Amount to withdraw
     */
    function withdrawRewardsPool(address payable to, uint256 amount)
        external
        onlyOwner
    {
        require(to != address(0), "TriggerExecutor: zero address");
        require(amount > 0, "TriggerExecutor: zero amount");
        require(
            address(this).balance >= amount,
            "TriggerExecutor: insufficient balance"
        );

        (bool success, ) = to.call{value: amount}("");
        require(success, "TriggerExecutor: transfer failed");
    }

    /**
     * @notice Decode trigger action and create new intent
     * @dev This function is called externally by processWatcher via try-catch
     * @param action Encoded trigger action (segments array)
     * @param user User who owns the intent
     * @return intentId New intent ID
     */
    function _decodeAndCreateIntent(bytes memory action, address user)
        external
        returns (bytes32 intentId)
    {
        // Only callable by this contract
        require(msg.sender == address(this), "TriggerExecutor: only self");

        // Decode action as segments array
        Types.Segment[] memory segments = abi.decode(action, (Types.Segment[]));

        // Create empty watchers array for new intent
        // Note: In production, you might want to recreate the same watchers
        // or allow the trigger action to specify new watchers
        Types.WatcherConfig[] memory watchers = new Types.WatcherConfig[](0);

        // Submit new intent as AI agent
        // Use a reasonable expiry (30 days from now)
        intentId = intentDecomposer.submitDecomposition(
            user,
            segments,
            watchers,
            block.timestamp + 30 days
        );

        return intentId;
    }

    /**
     * @notice Fallback to receive ETH for rewards pool
     */
    receive() external payable {}
}
