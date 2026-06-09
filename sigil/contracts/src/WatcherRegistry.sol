// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./base/SigilBase.sol";
import "./libraries/Types.sol";
import "./interfaces/IWatcherRegistry.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title WatcherRegistry
 * @notice THE CORE IP - Persistent watchers monitoring on-chain state
 * @dev Supports PRICE, TIME, RISK, and GOVERNANCE watchers
 */
contract WatcherRegistry is SigilBase, IWatcherRegistry {
    // ============ State Variables ============

    /// @notice Mapping of watcher IDs to watchers
    mapping(bytes32 => Types.Watcher) public watchers;

    /// @notice Mapping of users to their watcher IDs
    mapping(address => bytes32[]) private userWatcherIds;

    /// @notice Mapping of intent IDs to watcher IDs
    mapping(bytes32 => bytes32[]) private intentWatcherIds;

    /// @notice Active watcher IDs array
    bytes32[] public activeWatcherIds;

    /// @notice Mapping of watcher ID to index in activeWatcherIds
    mapping(bytes32 => uint256) private activeWatcherIndex;

    /// @notice Mapping of watcher ID to active status
    mapping(bytes32 => bool) private isWatcherActive;

    /// @notice Authorized executors (keeper network)
    mapping(address => bool) public authorizedExecutors;

    /// @notice IntentDecomposer contract address
    address public intentDecomposer;

    /// @notice Chainlink price feeds
    mapping(string => address) public priceFeeds;

    /// @notice Baseline TVL for protocols (for risk watchers)
    mapping(address => uint256) public baselineTVL;

    /// @notice Watcher nonce for ID generation
    uint256 public watcherNonce;

    /// @notice Maximum watcher lifetime
    uint256 public maxWatcherLifetime = 365 days;

    /// @notice Minimum expiry duration
    uint256 public minExpiryDuration = 1 hours;

    // ============ Modifiers ============

    modifier onlyExecutor() {
        require(
            authorizedExecutors[msg.sender],
            "WatcherRegistry: not authorized executor"
        );
        _;
    }

    modifier onlyIntentDecomposer() {
        require(
            msg.sender == intentDecomposer,
            "WatcherRegistry: not intent decomposer"
        );
        _;
    }

    // ============ Constructor ============

    constructor(address _intentDecomposer, address initialOwner)
        SigilBase(initialOwner)
    {
        require(
            _intentDecomposer != address(0),
            "WatcherRegistry: zero decomposer"
        );
        intentDecomposer = _intentDecomposer;
    }

    // ============ External Functions ============

    /**
     * @inheritdoc IWatcherRegistry
     */
    function registerWatcher(
        bytes32 parentIntentId,
        address watcherOwner,
        Types.WatcherType watcherType,
        bytes calldata parameters,
        bytes calldata triggerAction,
        uint256 expiresAt
    )
        external
        override
        onlyIntentDecomposer
        whenNotPaused
        nonReentrant
        returns (bytes32 watcherId)
    {
        require(watcherOwner != address(0), "WatcherRegistry: zero owner");
        require(
            expiresAt > block.timestamp + minExpiryDuration,
            "WatcherRegistry: expiry too soon"
        );
        require(
            expiresAt <= block.timestamp + maxWatcherLifetime,
            "WatcherRegistry: expiry too far"
        );

        // Generate unique watcher ID
        watcherId = keccak256(
            abi.encodePacked(
                parentIntentId,
                watcherOwner,
                watcherType,
                parameters,
                watcherNonce,
                block.timestamp
            )
        );
        watcherNonce++;

        // Create watcher
        watchers[watcherId] = Types.Watcher({
            watcherId: watcherId,
            parentIntentId: parentIntentId,
            owner: watcherOwner,
            watcherType: watcherType,
            status: Types.WatcherStatus.ACTIVE,
            parameters: parameters,
            triggerAction: triggerAction,
            createdAt: block.timestamp,
            expiresAt: expiresAt,
            lastChecked: 0,
            checkCount: 0
        });

        // Add to active watchers
        activeWatcherIndex[watcherId] = activeWatcherIds.length;
        activeWatcherIds.push(watcherId);
        isWatcherActive[watcherId] = true;

        // Track by user and intent
        userWatcherIds[watcherOwner].push(watcherId);
        intentWatcherIds[parentIntentId].push(watcherId);

        emit WatcherCreated(
            watcherId,
            parentIntentId,
            watcherOwner,
            watcherType,
            expiresAt
        );

        return watcherId;
    }

    /**
     * @inheritdoc IWatcherRegistry
     */
    function checkWatchers(bytes32[] calldata watcherIds)
        external
        view
        override
        returns (bool[] memory shouldTrigger)
    {
        shouldTrigger = new bool[](watcherIds.length);

        for (uint256 i = 0; i < watcherIds.length; i++) {
            Types.Watcher storage watcher = watchers[watcherIds[i]];

            if (watcher.status != Types.WatcherStatus.ACTIVE) {
                shouldTrigger[i] = false;
                continue;
            }

            if (block.timestamp > watcher.expiresAt) {
                shouldTrigger[i] = false;
                continue;
            }

            if (watcher.watcherType == Types.WatcherType.PRICE) {
                shouldTrigger[i] = checkPriceWatcher(watcherIds[i]);
            } else if (watcher.watcherType == Types.WatcherType.TIME) {
                shouldTrigger[i] = checkTimeWatcher(watcherIds[i]);
            } else if (watcher.watcherType == Types.WatcherType.RISK) {
                shouldTrigger[i] = checkRiskWatcher(watcherIds[i]);
            } else if (watcher.watcherType == Types.WatcherType.GOVERNANCE) {
                shouldTrigger[i] = checkGovernanceWatcher(watcherIds[i]);
            }
        }

        return shouldTrigger;
    }

    /**
     * @inheritdoc IWatcherRegistry
     */
    function checkPriceWatcher(bytes32 watcherId)
        public
        view
        override
        returns (bool)
    {
        Types.Watcher storage watcher = watchers[watcherId];
        if (watcher.status != Types.WatcherStatus.ACTIVE) return false;

        Types.PriceParams memory params = abi.decode(
            watcher.parameters,
            (Types.PriceParams)
        );

        require(params.priceFeed != address(0), "WatcherRegistry: invalid feed");

        try
            AggregatorV3Interface(params.priceFeed).latestRoundData()
        returns (
            uint80,
            int256 answer,
            uint256,
            uint256 updatedAt,
            uint80
        ) {
            // Check for stale data (more than 1 hour old)
            if (block.timestamp - updatedAt > 1 hours) {
                return false;
            }

            // Check price condition based on comparison operator
            if (params.comparison == Types.ComparisonOp.GT) {
                return answer > params.threshold;
            } else if (params.comparison == Types.ComparisonOp.LT) {
                return answer < params.threshold;
            } else if (params.comparison == Types.ComparisonOp.GTE) {
                return answer >= params.threshold;
            } else if (params.comparison == Types.ComparisonOp.LTE) {
                return answer <= params.threshold;
            } else if (params.comparison == Types.ComparisonOp.EQ) {
                return answer == params.threshold;
            } else if (params.comparison == Types.ComparisonOp.NEQ) {
                return answer != params.threshold;
            }

            return false;
        } catch {
            return false;
        }
    }

    /**
     * @inheritdoc IWatcherRegistry
     */
    function checkTimeWatcher(bytes32 watcherId)
        public
        view
        override
        returns (bool)
    {
        Types.Watcher storage watcher = watchers[watcherId];
        if (watcher.status != Types.WatcherStatus.ACTIVE) return false;

        Types.TimeParams memory params = abi.decode(
            watcher.parameters,
            (Types.TimeParams)
        );

        // Check if next trigger time has passed
        if (block.timestamp < params.nextTrigger) {
            return false;
        }

        // Check if max triggers reached
        if (params.maxTriggers > 0 && params.triggerCount >= params.maxTriggers) {
            return false;
        }

        return true;
    }

    /**
     * @inheritdoc IWatcherRegistry
     */
    function checkRiskWatcher(bytes32 watcherId)
        public
        view
        override
        returns (bool)
    {
        Types.Watcher storage watcher = watchers[watcherId];
        if (watcher.status != Types.WatcherStatus.ACTIVE) return false;

        Types.RiskParams memory params = abi.decode(
            watcher.parameters,
            (Types.RiskParams)
        );

        // Check TVL drop if oracle is set
        if (params.tvlOracle != address(0)) {
            try
                AggregatorV3Interface(params.tvlOracle).latestRoundData()
            returns (uint80, int256 currentTVL, uint256, uint256, uint80) {
                if (currentTVL < 0) return false;

                uint256 tvlDrop = params.baselineTVL > uint256(currentTVL)
                    ? params.baselineTVL - uint256(currentTVL)
                    : 0;

                uint256 dropBps = (tvlDrop * 10000) / params.baselineTVL;

                if (dropBps >= params.tvlDropThreshold) {
                    return true;
                }
            } catch {
                return false;
            }
        }

        // Check for upgrades if watching proxy
        if (params.watchUpgrades && params.proxyAdmin != address(0)) {
            // This would require checking if implementation has changed
            // Simplified for hackathon - in production would check ProxyAdmin events
            return false;
        }

        return false;
    }

    /**
     * @inheritdoc IWatcherRegistry
     */
    function checkGovernanceWatcher(bytes32 watcherId)
        public
        view
        override
        returns (bool)
    {
        Types.Watcher storage watcher = watchers[watcherId];
        if (watcher.status != Types.WatcherStatus.ACTIVE) return false;

        // Governance watching requires event monitoring
        // This would typically be done off-chain by keepers
        // Returning false for now - production implementation would
        // check governance proposal events and match against watchedParamHashes
        return false;
    }

    /**
     * @inheritdoc IWatcherRegistry
     */
    function triggerWatcher(bytes32 watcherId)
        external
        override
        onlyExecutor
        nonReentrant
        returns (bytes memory action, address owner)
    {
        Types.Watcher storage watcher = watchers[watcherId];
        require(
            watcher.status == Types.WatcherStatus.ACTIVE,
            "WatcherRegistry: not active"
        );
        require(
            block.timestamp <= watcher.expiresAt,
            "WatcherRegistry: expired"
        );

        // Update watcher status
        watcher.status = Types.WatcherStatus.TRIGGERED;
        watcher.lastChecked = block.timestamp;
        watcher.checkCount++;

        // Remove from active watchers
        _removeFromActiveWatchers(watcherId);

        // Update time watcher if applicable
        if (watcher.watcherType == Types.WatcherType.TIME) {
            Types.TimeParams memory params = abi.decode(
                watcher.parameters,
                (Types.TimeParams)
            );
            params.triggerCount++;
            params.nextTrigger = block.timestamp + params.interval;
            watcher.parameters = abi.encode(params);
        }

        emit WatcherTriggered(
            watcherId,
            watcher.parentIntentId,
            watcher.triggerAction,
            block.number
        );

        return (watcher.triggerAction, watcher.owner);
    }

    /**
     * @inheritdoc IWatcherRegistry
     */
    function cancelWatcher(bytes32 watcherId) external override nonReentrant {
        Types.Watcher storage watcher = watchers[watcherId];
        require(watcher.watcherId != bytes32(0), "WatcherRegistry: invalid watcher");
        require(
            msg.sender == watcher.owner ||
                msg.sender == owner() ||
                msg.sender == intentDecomposer,
            "WatcherRegistry: not authorized"
        );
        require(
            watcher.status == Types.WatcherStatus.ACTIVE,
            "WatcherRegistry: not active"
        );

        watcher.status = Types.WatcherStatus.CANCELLED;
        _removeFromActiveWatchers(watcherId);

        emit WatcherCancelled(watcherId, msg.sender);
    }

    /**
     * @inheritdoc IWatcherRegistry
     */
    function extendWatcher(bytes32 watcherId, uint256 newExpiresAt)
        external
        override
        nonReentrant
    {
        Types.Watcher storage watcher = watchers[watcherId];
        require(watcher.watcherId != bytes32(0), "WatcherRegistry: invalid watcher");
        require(
            msg.sender == watcher.owner || msg.sender == owner(),
            "WatcherRegistry: not authorized"
        );
        require(
            watcher.status == Types.WatcherStatus.ACTIVE,
            "WatcherRegistry: not active"
        );
        require(
            newExpiresAt > watcher.expiresAt,
            "WatcherRegistry: not extending"
        );
        require(
            newExpiresAt <= block.timestamp + maxWatcherLifetime,
            "WatcherRegistry: expiry too far"
        );

        watcher.expiresAt = newExpiresAt;
    }

    /**
     * @inheritdoc IWatcherRegistry
     */
    function getWatcher(bytes32 watcherId)
        external
        view
        override
        returns (Types.Watcher memory watcher)
    {
        return watchers[watcherId];
    }

    /**
     * @inheritdoc IWatcherRegistry
     */
    function getUserActiveWatchers(address user)
        external
        view
        override
        returns (bytes32[] memory watcherIds)
    {
        bytes32[] memory allUserWatchers = userWatcherIds[user];
        uint256 activeCount = 0;

        // Count active watchers
        for (uint256 i = 0; i < allUserWatchers.length; i++) {
            if (watchers[allUserWatchers[i]].status == Types.WatcherStatus.ACTIVE) {
                activeCount++;
            }
        }

        // Create array of active watchers
        watcherIds = new bytes32[](activeCount);
        uint256 index = 0;
        for (uint256 i = 0; i < allUserWatchers.length; i++) {
            if (watchers[allUserWatchers[i]].status == Types.WatcherStatus.ACTIVE) {
                watcherIds[index] = allUserWatchers[i];
                index++;
            }
        }

        return watcherIds;
    }

    /**
     * @inheritdoc IWatcherRegistry
     */
    function getIntentWatchers(bytes32 intentId)
        external
        view
        override
        returns (bytes32[] memory watcherIds)
    {
        return intentWatcherIds[intentId];
    }

    /**
     * @inheritdoc IWatcherRegistry
     */
    function addPriceFeed(string calldata pair, address feed)
        external
        override
        onlyOwner
    {
        require(feed != address(0), "WatcherRegistry: zero feed");
        priceFeeds[pair] = feed;
        emit PriceFeedAdded(pair, feed);
    }

    /**
     * @inheritdoc IWatcherRegistry
     */
    function updateBaselineTVL(address protocol, uint256 tvl)
        external
        override
        onlyOwner
    {
        require(protocol != address(0), "WatcherRegistry: zero protocol");
        baselineTVL[protocol] = tvl;
    }

    /**
     * @inheritdoc IWatcherRegistry
     */
    function addAuthorizedExecutor(address executor)
        external
        override
        onlyOwner
    {
        require(executor != address(0), "WatcherRegistry: zero executor");
        authorizedExecutors[executor] = true;
        emit ExecutorAuthorized(executor);
    }

    /**
     * @inheritdoc IWatcherRegistry
     */
    function removeAuthorizedExecutor(address executor)
        external
        override
        onlyOwner
    {
        authorizedExecutors[executor] = false;
        emit ExecutorDeauthorized(executor);
    }

    /**
     * @inheritdoc IWatcherRegistry
     */
    function cleanupExpiredWatchers(bytes32[] calldata watcherIds)
        external
        override
    {
        for (uint256 i = 0; i < watcherIds.length; i++) {
            Types.Watcher storage watcher = watchers[watcherIds[i]];

            if (
                watcher.status == Types.WatcherStatus.ACTIVE &&
                block.timestamp > watcher.expiresAt
            ) {
                watcher.status = Types.WatcherStatus.EXPIRED;
                _removeFromActiveWatchers(watcherIds[i]);
                emit WatcherExpired(watcherIds[i]);
            }
        }
    }

    /**
     * @inheritdoc IWatcherRegistry
     */
    function getActiveWatcherIds()
        external
        view
        override
        returns (bytes32[] memory watcherIds)
    {
        return activeWatcherIds;
    }

    /**
     * @notice Set max watcher lifetime
     * @param lifetime New maximum lifetime in seconds
     */
    function setMaxWatcherLifetime(uint256 lifetime) external onlyOwner {
        require(lifetime >= 1 days, "WatcherRegistry: too short");
        maxWatcherLifetime = lifetime;
    }

    // ============ Internal Functions ============

    /**
     * @dev Remove watcher from active watchers array with O(1) complexity
     * @param watcherId Watcher ID to remove
     */
    function _removeFromActiveWatchers(bytes32 watcherId) internal {
        if (!isWatcherActive[watcherId]) return;

        uint256 index = activeWatcherIndex[watcherId];
        uint256 lastIndex = activeWatcherIds.length - 1;

        if (index != lastIndex) {
            bytes32 lastWatcherId = activeWatcherIds[lastIndex];
            activeWatcherIds[index] = lastWatcherId;
            activeWatcherIndex[lastWatcherId] = index;
        }

        activeWatcherIds.pop();
        delete activeWatcherIndex[watcherId];
        isWatcherActive[watcherId] = false;
    }
}
