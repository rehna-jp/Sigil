// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {WatcherRegistry} from "./WatcherRegistry.sol";

/// @title TriggerExecutor
/// @notice Checks watchers in batch and triggers them when conditions are met.
///         The off-chain keeper calls checkAndExecuteBatch() every ~12 seconds.
///         When TriggerFired is emitted, the AI backend creates a new decomposed
///         intent from the triggerAction data — closing the Sigil loop.
contract TriggerExecutor is Ownable, ReentrancyGuard {

    struct TriggerRecord {
        bytes32 watcherId;
        uint256 timestamp;
        bool success;
        bytes triggerAction;
    }

    WatcherRegistry public watcherRegistry;
    mapping(bytes32 => TriggerRecord[]) private _triggerHistory;
    uint256 public totalTriggersExecuted;

    event TriggerFired(bytes32 indexed watcherId, bytes triggerAction, uint256 timestamp);
    event TriggerFailed(bytes32 indexed watcherId, string reason, uint256 timestamp);
    event BatchChecked(uint256 watchersChecked, uint256 watchersTriggered, uint256 timestamp);

    error ZeroAddress();
    error EmptyBatch();

    constructor(address _watcherRegistry, address _owner) Ownable(_owner) {
        if (_watcherRegistry == address(0)) revert ZeroAddress();
        watcherRegistry = WatcherRegistry(_watcherRegistry);
    }

    /// @notice Check and execute a batch of watchers — never reverts
    function checkAndExecuteBatch(bytes32[] calldata watcherIds)
        external nonReentrant returns (uint256 triggered)
    {
        if (watcherIds.length == 0) revert EmptyBatch();
        for (uint256 i; i < watcherIds.length; i++) {
            if (_processWatcher(watcherIds[i])) triggered++;
        }
        totalTriggersExecuted += triggered;
        emit BatchChecked(watcherIds.length, triggered, block.timestamp);
    }

    /// @notice Check and execute a single watcher
    function checkAndExecuteSingle(bytes32 watcherId)
        external nonReentrant returns (bool triggered)
    {
        triggered = _processWatcher(watcherId);
        if (triggered) totalTriggersExecuted++;
    }

    function getTriggerHistory(bytes32 watcherId) external view returns (TriggerRecord[] memory) {
        return _triggerHistory[watcherId];
    }

    function getTriggerCount(bytes32 watcherId) external view returns (uint256) {
        return _triggerHistory[watcherId].length;
    }

    function setWatcherRegistry(address _registry) external onlyOwner {
        if (_registry == address(0)) revert ZeroAddress();
        watcherRegistry = WatcherRegistry(_registry);
    }

    function _processWatcher(bytes32 watcherId) internal returns (bool) {
        WatcherRegistry.Watcher memory w;
        try watcherRegistry.getWatcher(watcherId) returns (WatcherRegistry.Watcher memory _w) {
            w = _w;
        } catch {
            emit TriggerFailed(watcherId, "watcher not found", block.timestamp);
            return false;
        }

        if (w.status != WatcherRegistry.WatcherStatus.ACTIVE) return false;
        if (block.timestamp >= w.expiresAt) {
            emit TriggerFailed(watcherId, "expired", block.timestamp);
            return false;
        }

        bool conditionMet = _checkCondition(watcherId, w.watcherType);
        if (!conditionMet) return false;

        bytes memory action;
        try watcherRegistry.triggerWatcher(watcherId) returns (bytes memory _action) {
            action = _action;
        } catch Error(string memory reason) {
            emit TriggerFailed(watcherId, reason, block.timestamp);
            return false;
        } catch {
            emit TriggerFailed(watcherId, "trigger call failed", block.timestamp);
            return false;
        }

        _triggerHistory[watcherId].push(TriggerRecord({
            watcherId: watcherId,
            timestamp: block.timestamp,
            success: true,
            triggerAction: action
        }));

        emit TriggerFired(watcherId, action, block.timestamp);
        return true;
    }

    function _checkCondition(
        bytes32 watcherId,
        WatcherRegistry.WatcherType watcherType
    ) internal view returns (bool) {
        if (watcherType == WatcherRegistry.WatcherType.PRICE) {
            try watcherRegistry.checkPriceWatcher(watcherId) returns (bool r) { return r; }
            catch { return false; }
        }
        if (watcherType == WatcherRegistry.WatcherType.TIME) {
            try watcherRegistry.checkTimeWatcher(watcherId) returns (bool r) { return r; }
            catch { return false; }
        }
        // GOVERNANCE + RISK: keeper calls checkAndExecuteSingle directly after off-chain detection
        return true;
    }
}
