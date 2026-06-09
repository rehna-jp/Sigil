// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./base/SigilBase.sol";
import "./libraries/Types.sol";
import "./interfaces/IERC8004.sol";
import "./interfaces/IIntentDecomposer.sol";
import "./interfaces/IWatcherRegistry.sol";

/**
 * @title IntentDecomposer
 * @notice Entry point for all intents - manages AI agent identity and intent lifecycle
 * @dev Inherits from SigilBase for security patterns
 */
contract IntentDecomposer is SigilBase, IIntentDecomposer {
    // ============ State Variables ============

    /// @notice AI agent authorized to submit decompositions
    address public aiAgent;

    /// @notice ERC-8004 agent registry for identity verification
    IERC8004Registry public agentRegistry;

    /// @notice Watcher registry for registering persistent watchers
    IWatcherRegistry public watcherRegistry;

    /// @notice Mapping of intent IDs to decomposed intents
    mapping(bytes32 => Types.DecomposedIntent) public intents;

    /// @notice Mapping of users to their intent IDs
    mapping(address => bytes32[]) public userIntents;

    /// @notice Mapping of intent IDs to their segments
    mapping(bytes32 => Types.Segment[]) private intentSegments;

    /// @notice Mapping of intent IDs to segment execution status
    mapping(bytes32 => mapping(uint256 => bool)) public segmentExecuted;

    /// @notice Mapping of authorized routers
    mapping(address => bool) public authorizedRouters;

    /// @notice Mapping of authorized submitters (can submit intents)
    mapping(address => bool) public authorizedSubmitters;

    /// @notice Nonce for generating unique intent IDs
    uint256 public intentNonce;

    /// @notice Maximum intent lifetime (1 year)
    uint256 public constant MAX_INTENT_LIFETIME = 365 days;

    // ============ Modifiers ============

    /// @notice Restrict to AI agent or authorized submitter
    modifier onlyAgent() {
        require(
            msg.sender == aiAgent || authorizedSubmitters[msg.sender],
            "IntentDecomposer: not authorized"
        );
        if (msg.sender == aiAgent) {
            require(
                agentRegistry.isActiveAgent(aiAgent),
                "IntentDecomposer: agent not active"
            );
        }
        _;
    }

    /// @notice Restrict to authorized routers
    modifier onlyRouter() {
        require(
            authorizedRouters[msg.sender],
            "IntentDecomposer: not authorized router"
        );
        _;
    }

    /// @notice Restrict to intent owner or AI agent
    modifier onlyIntentOwner(bytes32 intentId) {
        require(
            msg.sender == intents[intentId].user || msg.sender == aiAgent,
            "IntentDecomposer: not intent owner"
        );
        _;
    }

    // ============ Constructor ============

    /**
     * @notice Initialize IntentDecomposer with AI agent and registry
     * @param _aiAgent Address of the AI agent
     * @param _agentRegistry Address of the ERC-8004 registry
     * @param initialOwner Address of contract owner
     */
    constructor(
        address _aiAgent,
        address _agentRegistry,
        address initialOwner
    ) SigilBase(initialOwner) {
        require(_aiAgent != address(0), "IntentDecomposer: zero AI agent");
        require(
            _agentRegistry != address(0),
            "IntentDecomposer: zero registry"
        );

        aiAgent = _aiAgent;
        agentRegistry = IERC8004Registry(_agentRegistry);
    }

    // ============ External Functions ============

    /**
     * @inheritdoc IIntentDecomposer
     */
    function submitDecomposition(
        address user,
        Types.Segment[] calldata segments,
        Types.WatcherConfig[] calldata watchers,
        uint256 expiresAt
    )
        external
        override
        onlyAgent
        whenNotPaused
        nonReentrant
        returns (bytes32 intentId)
    {
        require(user != address(0), "IntentDecomposer: zero user");
        require(
            expiresAt > block.timestamp,
            "IntentDecomposer: expiry in past"
        );
        require(
            expiresAt <= block.timestamp + MAX_INTENT_LIFETIME,
            "IntentDecomposer: expiry too far"
        );

        // Generate unique intent ID
        intentId = keccak256(
            abi.encodePacked(user, intentNonce, block.timestamp, msg.sender)
        );
        intentNonce++;

        // Store segments
        for (uint256 i = 0; i < segments.length; i++) {
            intentSegments[intentId].push(segments[i]);
        }

        // Register watchers if watcher registry is set
        bytes32[] memory watcherIds = new bytes32[](watchers.length);
        if (address(watcherRegistry) != address(0) && watchers.length > 0) {
            for (uint256 i = 0; i < watchers.length; i++) {
                watcherIds[i] = watcherRegistry.registerWatcher(
                    intentId,
                    user,
                    watchers[i].watcherType,
                    watchers[i].parameters,
                    watchers[i].triggerAction,
                    watchers[i].expiresAt
                );
            }
        }

        // Create intent record
        intents[intentId] = Types.DecomposedIntent({
            intentId: intentId,
            user: user,
            submitter: msg.sender,
            watcherIds: watcherIds,
            segmentCount: segments.length,
            timestamp: block.timestamp,
            expiresAt: expiresAt,
            status: segments.length > 0
                ? Types.IntentStatus.PENDING
                : Types.IntentStatus.ACTIVE
        });

        // Track user's intents
        userIntents[user].push(intentId);

        emit IntentDecomposed(
            intentId,
            user,
            msg.sender,
            segments.length,
            watchers.length,
            expiresAt
        );

        return intentId;
    }

    /**
     * @inheritdoc IIntentDecomposer
     */
    function reportSegmentExecution(
        bytes32 intentId,
        uint256 segmentIndex,
        bool success,
        bytes calldata returnData
    ) external override onlyRouter whenNotPaused nonReentrant {
        Types.DecomposedIntent storage intent = intents[intentId];
        require(intent.intentId != bytes32(0), "IntentDecomposer: invalid intent");
        require(
            segmentIndex < intent.segmentCount,
            "IntentDecomposer: invalid segment index"
        );
        require(
            !segmentExecuted[intentId][segmentIndex],
            "IntentDecomposer: already executed"
        );

        // Mark segment as executed
        segmentExecuted[intentId][segmentIndex] = true;

        emit SegmentExecuted(intentId, segmentIndex, success);

        // Check if all segments are executed
        bool allExecuted = true;
        for (uint256 i = 0; i < intent.segmentCount; i++) {
            if (!segmentExecuted[intentId][i]) {
                allExecuted = false;
                break;
            }
        }

        // Update intent status
        if (allExecuted) {
            Types.IntentStatus oldStatus = intent.status;
            Types.IntentStatus newStatus = intent.watcherIds.length > 0
                ? Types.IntentStatus.ACTIVE
                : Types.IntentStatus.COMPLETED;

            intent.status = newStatus;
            emit IntentStatusChanged(intentId, oldStatus, newStatus);
        } else if (intent.status == Types.IntentStatus.PENDING) {
            Types.IntentStatus oldStatus = intent.status;
            intent.status = Types.IntentStatus.EXECUTING;
            emit IntentStatusChanged(intentId, oldStatus, Types.IntentStatus.EXECUTING);
        }
    }

    /**
     * @inheritdoc IIntentDecomposer
     */
    function cancelIntent(bytes32 intentId)
        external
        override
        onlyIntentOwner(intentId)
        nonReentrant
    {
        Types.DecomposedIntent storage intent = intents[intentId];
        require(intent.intentId != bytes32(0), "IntentDecomposer: invalid intent");
        require(
            intent.status != Types.IntentStatus.CANCELLED &&
                intent.status != Types.IntentStatus.COMPLETED,
            "IntentDecomposer: already finished"
        );

        Types.IntentStatus oldStatus = intent.status;
        intent.status = Types.IntentStatus.CANCELLED;

        emit IntentStatusChanged(intentId, oldStatus, Types.IntentStatus.CANCELLED);
        emit IntentCancelled(intentId, msg.sender);

        // Cancel associated watchers
        if (address(watcherRegistry) != address(0)) {
            for (uint256 i = 0; i < intent.watcherIds.length; i++) {
                try watcherRegistry.cancelWatcher(intent.watcherIds[i]) {} catch {}
            }
        }
    }

    /**
     * @inheritdoc IIntentDecomposer
     */
    function getIntent(bytes32 intentId)
        external
        view
        override
        returns (Types.DecomposedIntent memory intent)
    {
        return intents[intentId];
    }

    /**
     * @inheritdoc IIntentDecomposer
     */
    function getIntentStatus(bytes32 intentId)
        external
        view
        override
        returns (Types.IntentStatus status)
    {
        return intents[intentId].status;
    }

    /**
     * @inheritdoc IIntentDecomposer
     */
    function getUserIntents(address user)
        external
        view
        override
        returns (bytes32[] memory intentIds)
    {
        return userIntents[user];
    }

    /**
     * @inheritdoc IIntentDecomposer
     */
    function getIntentWatchers(bytes32 intentId)
        external
        view
        override
        returns (bytes32[] memory watcherIds)
    {
        return intents[intentId].watcherIds;
    }

    /**
     * @notice Get segments for an intent
     * @param intentId Intent identifier
     * @return segments Array of intent segments
     */
    function getIntentSegments(bytes32 intentId)
        external
        view
        returns (Types.Segment[] memory segments)
    {
        return intentSegments[intentId];
    }

    /**
     * @inheritdoc IIntentDecomposer
     */
    function addAuthorizedRouter(address router) external override onlyOwner {
        require(router != address(0), "IntentDecomposer: zero address");
        require(!authorizedRouters[router], "IntentDecomposer: already authorized");

        authorizedRouters[router] = true;
        emit RouterAuthorized(router);
    }

    /**
     * @inheritdoc IIntentDecomposer
     */
    function removeAuthorizedRouter(address router) external override onlyOwner {
        require(authorizedRouters[router], "IntentDecomposer: not authorized");

        authorizedRouters[router] = false;
        emit RouterDeauthorized(router);
    }

    /**
     * @inheritdoc IIntentDecomposer
     */
    function isAuthorizedRouter(address router)
        external
        view
        override
        returns (bool)
    {
        return authorizedRouters[router];
    }

    /**
     * @notice Add authorized submitter (e.g., TriggerExecutor)
     * @param submitter Address to authorize
     */
    function addAuthorizedSubmitter(address submitter) external onlyOwner {
        require(submitter != address(0), "IntentDecomposer: zero address");
        require(!authorizedSubmitters[submitter], "IntentDecomposer: already authorized");

        authorizedSubmitters[submitter] = true;
    }

    /**
     * @notice Remove authorized submitter
     * @param submitter Address to deauthorize
     */
    function removeAuthorizedSubmitter(address submitter) external onlyOwner {
        require(authorizedSubmitters[submitter], "IntentDecomposer: not authorized");

        authorizedSubmitters[submitter] = false;
    }

    /**
     * @notice Check if address is authorized submitter
     * @param submitter Address to check
     * @return True if authorized
     */
    function isAuthorizedSubmitter(address submitter)
        external
        view
        returns (bool)
    {
        return authorizedSubmitters[submitter];
    }

    /**
     * @notice Set watcher registry address
     * @param _watcherRegistry Address of watcher registry
     */
    function setWatcherRegistry(address _watcherRegistry) external onlyOwner {
        require(_watcherRegistry != address(0), "IntentDecomposer: zero address");
        watcherRegistry = IWatcherRegistry(_watcherRegistry);
    }

    /**
     * @notice Update AI agent address
     * @param _aiAgent New AI agent address
     */
    function updateAIAgent(address _aiAgent) external onlyOwner {
        require(_aiAgent != address(0), "IntentDecomposer: zero address");
        aiAgent = _aiAgent;
    }

    /**
     * @notice Check and update expired intents
     * @param intentIds Array of intent IDs to check
     */
    function checkExpiredIntents(bytes32[] calldata intentIds) external {
        for (uint256 i = 0; i < intentIds.length; i++) {
            Types.DecomposedIntent storage intent = intents[intentIds[i]];

            if (
                intent.intentId != bytes32(0) &&
                block.timestamp > intent.expiresAt &&
                intent.status != Types.IntentStatus.EXPIRED &&
                intent.status != Types.IntentStatus.CANCELLED &&
                intent.status != Types.IntentStatus.COMPLETED
            ) {
                Types.IntentStatus oldStatus = intent.status;
                intent.status = Types.IntentStatus.EXPIRED;
                emit IntentStatusChanged(
                    intentIds[i],
                    oldStatus,
                    Types.IntentStatus.EXPIRED
                );
            }
        }
    }
}
