// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../libraries/Types.sol";

/**
 * @title IWatcherRegistry
 * @notice Interface for Watcher Registry - THE CORE IP
 * @dev Manages persistent watchers monitoring on-chain state
 */
interface IWatcherRegistry {
    // ============ Events ============

    /// @notice Emitted when a new watcher is created
    event WatcherCreated(
        bytes32 indexed watcherId,
        bytes32 indexed parentIntentId,
        address indexed owner,
        Types.WatcherType watcherType,
        uint256 expiresAt
    );

    /// @notice Emitted when a watcher is triggered
    event WatcherTriggered(
        bytes32 indexed watcherId,
        bytes32 indexed parentIntentId,
        bytes triggerData,
        uint256 blockNumber
    );

    /// @notice Emitted when a watcher is cancelled
    event WatcherCancelled(bytes32 indexed watcherId, address cancelledBy);

    /// @notice Emitted when a watcher expires
    event WatcherExpired(bytes32 indexed watcherId);

    /// @notice Emitted when a watcher is checked
    event WatcherChecked(
        bytes32 indexed watcherId,
        bool shouldTrigger,
        uint256 checkCount
    );

    /// @notice Emitted when a price feed is added
    event PriceFeedAdded(string indexed pair, address feed);

    /// @notice Emitted when an executor is authorized
    event ExecutorAuthorized(address indexed executor);

    /// @notice Emitted when an executor is deauthorized
    event ExecutorDeauthorized(address indexed executor);

    // ============ Functions ============

    /**
     * @notice Register a new watcher
     * @param parentIntentId Parent intent identifier
     * @param watcherOwner Owner of the watcher
     * @param watcherType Type of watcher (PRICE, TIME, RISK, GOVERNANCE)
     * @param parameters ABI-encoded type-specific parameters
     * @param triggerAction Action to execute when triggered
     * @param expiresAt Expiry timestamp
     * @return watcherId Unique identifier for the watcher
     */
    function registerWatcher(
        bytes32 parentIntentId,
        address watcherOwner,
        Types.WatcherType watcherType,
        bytes calldata parameters,
        bytes calldata triggerAction,
        uint256 expiresAt
    ) external returns (bytes32 watcherId);

    /**
     * @notice Batch check multiple watchers
     * @param watcherIds Array of watcher identifiers
     * @return shouldTrigger Array of booleans indicating if each watcher should trigger
     */
    function checkWatchers(bytes32[] calldata watcherIds)
        external
        view
        returns (bool[] memory shouldTrigger);

    /**
     * @notice Check if a price watcher should trigger
     * @param watcherId Watcher identifier
     * @return bool True if price condition is met
     */
    function checkPriceWatcher(bytes32 watcherId)
        external
        view
        returns (bool);

    /**
     * @notice Check if a time watcher should trigger
     * @param watcherId Watcher identifier
     * @return bool True if time condition is met
     */
    function checkTimeWatcher(bytes32 watcherId) external view returns (bool);

    /**
     * @notice Check if a risk watcher should trigger
     * @param watcherId Watcher identifier
     * @return bool True if risk condition is met
     */
    function checkRiskWatcher(bytes32 watcherId) external view returns (bool);

    /**
     * @notice Check if a governance watcher should trigger
     * @param watcherId Watcher identifier
     * @return bool True if governance condition is met
     */
    function checkGovernanceWatcher(bytes32 watcherId)
        external
        view
        returns (bool);

    /**
     * @notice Trigger a watcher (executor only)
     * @param watcherId Watcher identifier
     * @return action Trigger action bytes
     * @return owner Watcher owner address
     */
    function triggerWatcher(bytes32 watcherId)
        external
        returns (bytes memory action, address owner);

    /**
     * @notice Cancel a watcher
     * @param watcherId Watcher identifier
     */
    function cancelWatcher(bytes32 watcherId) external;

    /**
     * @notice Extend watcher expiry
     * @param watcherId Watcher identifier
     * @param newExpiresAt New expiry timestamp
     */
    function extendWatcher(bytes32 watcherId, uint256 newExpiresAt) external;

    /**
     * @notice Get watcher details
     * @param watcherId Watcher identifier
     * @return watcher Watcher struct
     */
    function getWatcher(bytes32 watcherId)
        external
        view
        returns (Types.Watcher memory watcher);

    /**
     * @notice Get all active watchers for a user
     * @param user User address
     * @return watcherIds Array of active watcher identifiers
     */
    function getUserActiveWatchers(address user)
        external
        view
        returns (bytes32[] memory watcherIds);

    /**
     * @notice Get watchers for a specific intent
     * @param intentId Intent identifier
     * @return watcherIds Array of watcher identifiers
     */
    function getIntentWatchers(bytes32 intentId)
        external
        view
        returns (bytes32[] memory watcherIds);

    /**
     * @notice Add a Chainlink price feed
     * @param pair Price pair name (e.g., "ETH/USD")
     * @param feed Chainlink aggregator address
     */
    function addPriceFeed(string calldata pair, address feed) external;

    /**
     * @notice Update baseline TVL for a protocol
     * @param protocol Protocol address
     * @param tvl Baseline TVL value
     */
    function updateBaselineTVL(address protocol, uint256 tvl) external;

    /**
     * @notice Add an authorized executor
     * @param executor Executor address
     */
    function addAuthorizedExecutor(address executor) external;

    /**
     * @notice Remove an authorized executor
     * @param executor Executor address
     */
    function removeAuthorizedExecutor(address executor) external;

    /**
     * @notice Cleanup expired watchers
     * @param watcherIds Array of watcher identifiers to cleanup
     */
    function cleanupExpiredWatchers(bytes32[] calldata watcherIds) external;

    /**
     * @notice Get all active watcher IDs
     * @return watcherIds Array of all active watcher identifiers
     */
    function getActiveWatcherIds()
        external
        view
        returns (bytes32[] memory watcherIds);
}
