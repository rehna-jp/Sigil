// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title IntentDecomposer
/// @notice On-chain registry for intents decomposed by the Sigil AI agent.
///         The AI agent parses user natural language input off-chain, then calls
///         submitDecomposition() to register the structured intent on-chain.
///         Each intent has immediate segments (execute now) and watcher configs (persist).
contract IntentDecomposer is Ownable, ReentrancyGuard {

    // ─── Structs ──────────────────────────────────────────────────

    struct Segment {
        uint8 segmentType;  // 0=SWAP, 1=DEPOSIT, 2=WITHDRAW, 3=HEDGE
        address protocol;
        bytes callData;
        uint256 value;
    }

    struct WatcherConfig {
        uint8 watcherType;    // 0=PRICE, 1=GOVERNANCE, 2=RISK, 3=TIME
        bytes parameters;
        bytes triggerAction;
        uint256 expiry;
    }

    struct DecomposedIntent {
        bytes32 intentId;
        address user;
        uint256 timestamp;
        bool active;
        bool executed;
        uint256 segmentCount;
        uint256 watcherCount;
    }

    // ─── Storage ──────────────────────────────────────────────────

    address public aiAgent;
    address public intentRouter;
    address public watcherRegistry;

    mapping(bytes32 => DecomposedIntent) public intents;
    mapping(bytes32 => Segment[]) private _segments;
    mapping(bytes32 => WatcherConfig[]) private _watchers;
    mapping(address => bytes32[]) private _userIntents;
    mapping(address => uint256) private _nonce;

    // ─── Events ───────────────────────────────────────────────────

    event IntentDecomposed(bytes32 indexed intentId, address indexed user, uint256 segmentCount, uint256 watcherCount, uint256 timestamp);
    event IntentExecuted(bytes32 indexed intentId, address indexed user);
    event IntentDeactivated(bytes32 indexed intentId, address indexed by);
    event AIAgentSet(address indexed agent);
    event IntentRouterSet(address indexed router);
    event WatcherRegistrySet(address indexed registry);

    // ─── Errors ───────────────────────────────────────────────────

    error OnlyAIAgent();
    error OnlyIntentRouter();
    error OnlyIntentOwnerOrAgent();
    error IntentNotFound();
    error IntentAlreadyExecuted();
    error IntentNotActive();
    error EmptySegments();
    error ZeroAddress();

    // ─── Modifiers ────────────────────────────────────────────────

    modifier onlyAIAgent() {
        if (msg.sender != aiAgent) revert OnlyAIAgent();
        _;
    }

    modifier onlyIntentRouter() {
        if (msg.sender != intentRouter) revert OnlyIntentRouter();
        _;
    }

    // ─── Constructor ──────────────────────────────────────────────

    constructor(address _owner) Ownable(_owner) {}

    // ─── Core Functions ───────────────────────────────────────────

    /// @notice AI agent submits a decomposed intent on behalf of a user
    function submitDecomposition(
        address user,
        Segment[] calldata segments,
        WatcherConfig[] calldata watchers
    ) external nonReentrant onlyAIAgent returns (bytes32 intentId) {
        if (user == address(0)) revert ZeroAddress();
        if (segments.length == 0) revert EmptySegments();

        intentId = keccak256(abi.encodePacked(user, block.timestamp, _nonce[user]++, msg.sender));

        intents[intentId] = DecomposedIntent({
            intentId: intentId,
            user: user,
            timestamp: block.timestamp,
            active: true,
            executed: false,
            segmentCount: segments.length,
            watcherCount: watchers.length
        });

        for (uint256 i; i < segments.length; i++) _segments[intentId].push(segments[i]);
        for (uint256 i; i < watchers.length; i++) _watchers[intentId].push(watchers[i]);
        _userIntents[user].push(intentId);

        emit IntentDecomposed(intentId, user, segments.length, watchers.length, block.timestamp);
    }

    /// @notice Mark intent segments as executed — only callable by IntentRouter
    function markExecuted(bytes32 intentId) external onlyIntentRouter {
        DecomposedIntent storage intent = intents[intentId];
        if (intent.intentId == bytes32(0)) revert IntentNotFound();
        if (intent.executed) revert IntentAlreadyExecuted();
        intent.executed = true;
        emit IntentExecuted(intentId, intent.user);
    }

    /// @notice Deactivate an intent — callable by owner or AI agent
    function deactivateIntent(bytes32 intentId) external {
        DecomposedIntent storage intent = intents[intentId];
        if (intent.intentId == bytes32(0)) revert IntentNotFound();
        if (msg.sender != intent.user && msg.sender != aiAgent) revert OnlyIntentOwnerOrAgent();
        if (!intent.active) revert IntentNotActive();
        intent.active = false;
        emit IntentDeactivated(intentId, msg.sender);
    }

    // ─── View Functions ───────────────────────────────────────────

    function getIntent(bytes32 intentId) external view returns (DecomposedIntent memory) {
        return intents[intentId];
    }

    function getSegments(bytes32 intentId) external view returns (Segment[] memory) {
        return _segments[intentId];
    }

    function getWatchers(bytes32 intentId) external view returns (WatcherConfig[] memory) {
        return _watchers[intentId];
    }

    function getUserIntents(address user) external view returns (bytes32[] memory) {
        return _userIntents[user];
    }

    function getUserActiveIntents(address user) external view returns (bytes32[] memory) {
        bytes32[] memory all = _userIntents[user];
        uint256 count;
        for (uint256 i; i < all.length; i++) if (intents[all[i]].active) count++;
        bytes32[] memory active = new bytes32[](count);
        uint256 j;
        for (uint256 i; i < all.length; i++) if (intents[all[i]].active) active[j++] = all[i];
        return active;
    }

    function getIntentCount(address user) external view returns (uint256) {
        return _userIntents[user].length;
    }

    // ─── Admin ────────────────────────────────────────────────────

    function setAIAgent(address _agent) external onlyOwner {
        if (_agent == address(0)) revert ZeroAddress();
        aiAgent = _agent;
        emit AIAgentSet(_agent);
    }

    function setIntentRouter(address _router) external onlyOwner {
        if (_router == address(0)) revert ZeroAddress();
        intentRouter = _router;
        emit IntentRouterSet(_router);
    }

    function setWatcherRegistry(address _registry) external onlyOwner {
        if (_registry == address(0)) revert ZeroAddress();
        watcherRegistry = _registry;
        emit WatcherRegistrySet(_registry);
    }
}
