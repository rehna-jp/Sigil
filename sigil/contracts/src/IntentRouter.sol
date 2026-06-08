// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IntentDecomposer} from "./IntentDecomposer.sol";

/// @title IntentRouter
/// @notice Routes solved intent segments to Arbitrum protocols atomically.
///         All segments must succeed — reverts entirely if any fails.
///         Calls IntentDecomposer.markExecuted() after successful execution.
contract IntentRouter is Ownable, ReentrancyGuard {

    IntentDecomposer public intentDecomposer;

    mapping(address => bool) public approvedProtocols;
    mapping(string => address) public protocolAdapters;

    event SegmentExecuted(bytes32 indexed intentId, uint256 indexed segmentIndex, address protocol);
    event IntentRouted(bytes32 indexed intentId, uint256 segmentCount);
    event ProtocolAdded(string name, address adapter);
    event ProtocolRemoved(string name, address adapter);

    error ProtocolNotApproved(address protocol);
    error SegmentFailed(uint256 index, bytes returnData);
    error ArrayLengthMismatch();
    error EmptySegments();
    error ZeroAddress();

    constructor(address _decomposer, address _owner) Ownable(_owner) {
        if (_decomposer == address(0)) revert ZeroAddress();
        intentDecomposer = IntentDecomposer(_decomposer);
    }

    /// @notice Execute all segments of an intent atomically
    function executeSegments(
        bytes32 intentId,
        address[] calldata protocols,
        bytes[] calldata callDatas,
        uint256[] calldata values
    ) external payable nonReentrant {
        if (protocols.length == 0) revert EmptySegments();
        if (protocols.length != callDatas.length || protocols.length != values.length) revert ArrayLengthMismatch();

        for (uint256 i; i < protocols.length; i++) {
            if (!approvedProtocols[protocols[i]]) revert ProtocolNotApproved(protocols[i]);
            (bool success, bytes memory returnData) = protocols[i].call{value: values[i]}(callDatas[i]);
            if (!success) revert SegmentFailed(i, returnData);
            emit SegmentExecuted(intentId, i, protocols[i]);
        }

        intentDecomposer.markExecuted(intentId);
        emit IntentRouted(intentId, protocols.length);
    }

    function addProtocol(string calldata name, address adapter) external onlyOwner {
        if (adapter == address(0)) revert ZeroAddress();
        protocolAdapters[name] = adapter;
        approvedProtocols[adapter] = true;
        emit ProtocolAdded(name, adapter);
    }

    function removeProtocol(string calldata name) external onlyOwner {
        address adapter = protocolAdapters[name];
        approvedProtocols[adapter] = false;
        delete protocolAdapters[name];
        emit ProtocolRemoved(name, adapter);
    }

    function setIntentDecomposer(address _decomposer) external onlyOwner {
        if (_decomposer == address(0)) revert ZeroAddress();
        intentDecomposer = IntentDecomposer(_decomposer);
    }

    receive() external payable {}
}
