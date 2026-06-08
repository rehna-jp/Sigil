// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AggregatorV3Interface} from "@chainlink/shared/interfaces/AggregatorV3Interface.sol";

/// @title WatcherRegistry
/// @notice THE CORE IP — On-chain persistent watchers that monitor conditions
///         and trigger new intents when those conditions are met.
///
///         Every other intent protocol (CoW, UniswapX, Anoma):
///           intent executes → intent dies.
///
///         Sigil:
///           intent executes → watchers live on-chain → condition met →
///           trigger fires → new intent created → loop continues.
contract WatcherRegistry is Ownable, ReentrancyGuard {

    // ─── Enums ────────────────────────────────────────────────────

    enum WatcherType   { PRICE, GOVERNANCE, RISK, TIME }
    enum WatcherStatus { ACTIVE, TRIGGERED, EXPIRED, CANCELLED }
    enum ComparisonOp  { GT, LT, GTE, LTE }

    // ─── Structs ──────────────────────────────────────────────────

    struct Watcher {
        bytes32 watcherId;
        bytes32 parentIntentId;
        address owner;
        WatcherType watcherType;
        WatcherStatus status;
        bytes parameters;
        bytes triggerAction;
        uint256 createdAt;
        uint256 expiresAt;
        uint256 lastChecked;
    }

    struct PriceParams {
        address priceFeed;
        int256 threshold;       // e.g. $3,500 = 350000000000 (8 decimals)
        ComparisonOp comparison;
    }

    struct GovernanceParams {
        address governanceContract;
        bytes4 proposalSelector;
    }

    struct TimeParams {
        uint256 interval;
        uint256 nextTrigger;
        uint256 maxTriggers;    // 0 = unlimited
        uint256 triggerCount;
    }

    // ─── Storage ──────────────────────────────────────────────────

    mapping(bytes32 => Watcher) public watchers;
    mapping(address => bytes32[]) private _userWatchers;

    bytes32[] private _activeIds;
    mapping(bytes32 => uint256) private _activeIndex;

    mapping(address => bool) public authorizedExecutors;
    address public intentDecomposer;
    mapping(address => uint256) private _ownerNonce;

    // ─── Events ───────────────────────────────────────────────────

    event WatcherCreated(bytes32 indexed watcherId, bytes32 indexed parentIntentId, address indexed owner, WatcherType watcherType, uint256 expiresAt);
    event WatcherTriggered(bytes32 indexed watcherId, bytes triggerAction, uint256 timestamp);
    event WatcherCancelled(bytes32 indexed watcherId, address indexed by);
    event WatcherExpired(bytes32 indexed watcherId);
    event ExecutorAuthorized(address indexed executor);
    event ExecutorRevoked(address indexed executor);

    // ─── Errors ───────────────────────────────────────────────────

    error Unauthorized();
    error WatcherNotFound();
    error WatcherNotActive();
    error WatcherAlreadyExpired();
    error InvalidWatcherType();
    error InvalidParameters();
    error NotWatcherOwner();
    error ZeroAddress();

    // ─── Constructor ──────────────────────────────────────────────

    constructor(address _owner) Ownable(_owner) {}

    // ─── Core Functions ───────────────────────────────────────────

    /// @notice Register a new persistent watcher
    function registerWatcher(
        bytes32 parentIntentId,
        address watcherOwner,
        WatcherType watcherType,
        bytes calldata parameters,
        bytes calldata triggerAction,
        uint256 expiresAt
    ) external returns (bytes32 watcherId) {
        if (msg.sender != intentDecomposer && msg.sender != watcherOwner) revert Unauthorized();
        if (watcherOwner == address(0)) revert ZeroAddress();
        if (parameters.length == 0) revert InvalidParameters();
        if (expiresAt != 0 && expiresAt <= block.timestamp) revert InvalidParameters();

        watcherId = keccak256(abi.encodePacked(
            parentIntentId, watcherOwner, uint8(watcherType), block.timestamp, _ownerNonce[watcherOwner]++
        ));

        uint256 expiry = expiresAt == 0 ? type(uint256).max : expiresAt;

        watchers[watcherId] = Watcher({
            watcherId: watcherId,
            parentIntentId: parentIntentId,
            owner: watcherOwner,
            watcherType: watcherType,
            status: WatcherStatus.ACTIVE,
            parameters: parameters,
            triggerAction: triggerAction,
            createdAt: block.timestamp,
            expiresAt: expiry,
            lastChecked: block.timestamp
        });

        _userWatchers[watcherOwner].push(watcherId);
        _activeIndex[watcherId] = _activeIds.length;
        _activeIds.push(watcherId);

        emit WatcherCreated(watcherId, parentIntentId, watcherOwner, watcherType, expiry);
    }

    /// @notice Check if a PRICE watcher condition is met — pure view, no state change
    function checkPriceWatcher(bytes32 watcherId) public view returns (bool) {
        Watcher storage w = watchers[watcherId];
        if (w.watcherId == bytes32(0)) revert WatcherNotFound();
        if (w.watcherType != WatcherType.PRICE) revert InvalidWatcherType();
        if (w.status != WatcherStatus.ACTIVE) return false;
        if (block.timestamp >= w.expiresAt) return false;

        PriceParams memory p = abi.decode(w.parameters, (PriceParams));
        (, int256 price,, uint256 updatedAt,) = AggregatorV3Interface(p.priceFeed).latestRoundData();

        // Reject stale data older than 1 hour
        if (block.timestamp - updatedAt > 3600) return false;

        if (p.comparison == ComparisonOp.GT)  return price > p.threshold;
        if (p.comparison == ComparisonOp.LT)  return price < p.threshold;
        if (p.comparison == ComparisonOp.GTE) return price >= p.threshold;
        if (p.comparison == ComparisonOp.LTE) return price <= p.threshold;
        return false;
    }

    /// @notice Check if a TIME watcher is ready to fire
    function checkTimeWatcher(bytes32 watcherId) public view returns (bool) {
        Watcher storage w = watchers[watcherId];
        if (w.watcherId == bytes32(0)) revert WatcherNotFound();
        if (w.watcherType != WatcherType.TIME) revert InvalidWatcherType();
        if (w.status != WatcherStatus.ACTIVE) return false;
        if (block.timestamp >= w.expiresAt) return false;

        TimeParams memory p = abi.decode(w.parameters, (TimeParams));
        if (p.maxTriggers > 0 && p.triggerCount >= p.maxTriggers) return false;
        return block.timestamp >= p.nextTrigger;
    }

    /// @notice Trigger a watcher — only callable by authorized TriggerExecutor
    function triggerWatcher(bytes32 watcherId) external nonReentrant returns (bytes memory triggerAction) {
        if (!authorizedExecutors[msg.sender]) revert Unauthorized();

        Watcher storage w = watchers[watcherId];
        if (w.watcherId == bytes32(0)) revert WatcherNotFound();
        if (w.status != WatcherStatus.ACTIVE) revert WatcherNotActive();
        if (block.timestamp >= w.expiresAt) {
            w.status = WatcherStatus.EXPIRED;
            _removeFromActive(watcherId);
            emit WatcherExpired(watcherId);
            revert WatcherAlreadyExpired();
        }

        if (w.watcherType == WatcherType.TIME) {
            // TIME watchers re-arm after each trigger
            TimeParams memory p = abi.decode(w.parameters, (TimeParams));
            p.triggerCount++;
            p.nextTrigger = block.timestamp + p.interval;
            if (p.maxTriggers > 0 && p.triggerCount >= p.maxTriggers) {
                w.status = WatcherStatus.TRIGGERED;
                _removeFromActive(watcherId);
            } else {
                w.parameters = abi.encode(p);
            }
        } else {
            // PRICE, GOVERNANCE, RISK — one-shot
            w.status = WatcherStatus.TRIGGERED;
            _removeFromActive(watcherId);
        }

        w.lastChecked = block.timestamp;
        emit WatcherTriggered(watcherId, w.triggerAction, block.timestamp);
        return w.triggerAction;
    }

    /// @notice Cancel a watcher — only callable by its owner
    function cancelWatcher(bytes32 watcherId) external {
        Watcher storage w = watchers[watcherId];
        if (w.watcherId == bytes32(0)) revert WatcherNotFound();
        if (w.owner != msg.sender) revert NotWatcherOwner();
        if (w.status != WatcherStatus.ACTIVE) revert WatcherNotActive();
        w.status = WatcherStatus.CANCELLED;
        _removeFromActive(watcherId);
        emit WatcherCancelled(watcherId, msg.sender);
    }

    // ─── View Functions ───────────────────────────────────────────

    function getWatcher(bytes32 watcherId) external view returns (Watcher memory) {
        return watchers[watcherId];
    }

    function getActiveWatcherIds() external view returns (bytes32[] memory) {
        return _activeIds;
    }

    function getActiveWatcherCount() external view returns (uint256) {
        return _activeIds.length;
    }

    function getUserActiveWatchers(address user) external view returns (bytes32[] memory) {
        bytes32[] memory all = _userWatchers[user];
        uint256 count;
        for (uint256 i; i < all.length; i++) if (watchers[all[i]].status == WatcherStatus.ACTIVE) count++;
        bytes32[] memory active = new bytes32[](count);
        uint256 j;
        for (uint256 i; i < all.length; i++) if (watchers[all[i]].status == WatcherStatus.ACTIVE) active[j++] = all[i];
        return active;
    }

    function getUserWatcherCount(address user) external view returns (uint256) {
        return _userWatchers[user].length;
    }

    // ─── Admin ────────────────────────────────────────────────────

    function authorizeExecutor(address executor) external onlyOwner {
        if (executor == address(0)) revert ZeroAddress();
        authorizedExecutors[executor] = true;
        emit ExecutorAuthorized(executor);
    }

    function revokeExecutor(address executor) external onlyOwner {
        authorizedExecutors[executor] = false;
        emit ExecutorRevoked(executor);
    }

    function setIntentDecomposer(address _decomposer) external onlyOwner {
        if (_decomposer == address(0)) revert ZeroAddress();
        intentDecomposer = _decomposer;
    }

    // ─── Internal ─────────────────────────────────────────────────

    function _removeFromActive(bytes32 watcherId) internal {
        uint256 idx = _activeIndex[watcherId];
        uint256 last = _activeIds.length - 1;
        if (idx != last) {
            bytes32 lastId = _activeIds[last];
            _activeIds[idx] = lastId;
            _activeIndex[lastId] = idx;
        }
        _activeIds.pop();
        delete _activeIndex[watcherId];
    }
}
