// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../libraries/Types.sol";

/**
 * @title IIntentDecomposer
 * @notice Interface for Intent Decomposer contract
 * @dev Manages decomposed intents with segments and watchers
 */
interface IIntentDecomposer {
    // ============ Events ============

    /// @notice Emitted when a new intent is decomposed and submitted
    event IntentDecomposed(
        bytes32 indexed intentId,
        address indexed user,
        address indexed submitter,
        uint256 segmentCount,
        uint256 watcherCount,
        uint256 expiresAt
    );

    /// @notice Emitted when a segment is executed
    event SegmentExecuted(
        bytes32 indexed intentId,
        uint256 segmentIndex,
        bool success
    );

    /// @notice Emitted when intent status changes
    event IntentStatusChanged(
        bytes32 indexed intentId,
        Types.IntentStatus oldStatus,
        Types.IntentStatus newStatus
    );

    /// @notice Emitted when an intent is cancelled
    event IntentCancelled(bytes32 indexed intentId, address cancelledBy);

    /// @notice Emitted when an authorized router is added
    event RouterAuthorized(address indexed router);

    /// @notice Emitted when a router is removed
    event RouterDeauthorized(address indexed router);

    // ============ Functions ============

    /**
     * @notice Submit a decomposed intent with segments and watchers
     * @param user Address of the intent owner
     * @param segments Array of immediate execution segments
     * @param watchers Array of watcher configurations
     * @param expiresAt Intent expiry timestamp
     * @return intentId Unique identifier for the intent
     */
    function submitDecomposition(
        address user,
        Types.Segment[] calldata segments,
        Types.WatcherConfig[] calldata watchers,
        uint256 expiresAt
    ) external returns (bytes32 intentId);

    /**
     * @notice Report execution status of a segment
     * @param intentId Intent identifier
     * @param segmentIndex Index of the segment
     * @param success Whether execution succeeded
     * @param returnData Return data or error message
     */
    function reportSegmentExecution(
        bytes32 intentId,
        uint256 segmentIndex,
        bool success,
        bytes calldata returnData
    ) external;

    /**
     * @notice Cancel an intent
     * @param intentId Intent identifier
     */
    function cancelIntent(bytes32 intentId) external;

    /**
     * @notice Get intent details
     * @param intentId Intent identifier
     * @return intent Decomposed intent struct
     */
    function getIntent(bytes32 intentId)
        external
        view
        returns (Types.DecomposedIntent memory intent);

    /**
     * @notice Get intent status
     * @param intentId Intent identifier
     * @return status Current intent status
     */
    function getIntentStatus(bytes32 intentId)
        external
        view
        returns (Types.IntentStatus status);

    /**
     * @notice Get all intent IDs for a user
     * @param user User address
     * @return intentIds Array of intent identifiers
     */
    function getUserIntents(address user)
        external
        view
        returns (bytes32[] memory intentIds);

    /**
     * @notice Get watcher IDs associated with an intent
     * @param intentId Intent identifier
     * @return watcherIds Array of watcher identifiers
     */
    function getIntentWatchers(bytes32 intentId)
        external
        view
        returns (bytes32[] memory watcherIds);

    /**
     * @notice Add an authorized router
     * @param router Router address to authorize
     */
    function addAuthorizedRouter(address router) external;

    /**
     * @notice Remove an authorized router
     * @param router Router address to deauthorize
     */
    function removeAuthorizedRouter(address router) external;

    /**
     * @notice Check if a router is authorized
     * @param router Router address to check
     * @return bool True if authorized
     */
    function isAuthorizedRouter(address router) external view returns (bool);
}
