// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./base/SigilBase.sol";
import "./libraries/Types.sol";
import "./interfaces/IIntentRouter.sol";
import "./interfaces/IProtocolAdapter.sol";
import "./interfaces/IIntentDecomposer.sol";

/**
 * @title IntentRouter
 * @notice Routes intent segments to protocol adapters and executes them
 * @dev Manages protocol adapter registry and atomic execution
 */
contract IntentRouter is SigilBase, IIntentRouter {
    // ============ State Variables ============

    /// @notice Mapping of protocol names to adapter addresses
    mapping(string => address) public protocolAdapters;

    /// @notice Mapping of addresses to approval status
    mapping(address => bool) public approvedProtocols;

    /// @notice Mapping of segment types to default protocol names
    mapping(Types.SegmentType => string) public defaultProtocols;

    /// @notice Mapping of protocol addresses to categories
    mapping(address => Types.ProtocolCategory) public protocolCategory;

    /// @notice Execution history for intents
    mapping(bytes32 => Types.SegmentExecution[]) private executionHistory;

    /// @notice IntentDecomposer contract address
    address public intentDecomposer;

    /// @notice Execution timeout
    uint256 public executionTimeout = 5 minutes;

    /// @notice Maximum gas per segment
    uint256 public maxGasPerSegment = 1000000;

    // ============ Modifiers ============

    modifier onlyIntentDecomposer() {
        require(
            msg.sender == intentDecomposer,
            "IntentRouter: not intent decomposer"
        );
        _;
    }

    // ============ Constructor ============

    constructor(address initialOwner) SigilBase(initialOwner) {}

    // ============ External Functions ============

    /**
     * @inheritdoc IIntentRouter
     */
    function executeSegments(
        bytes32 intentId,
        Types.Segment[] calldata segments
    )
        external
        payable
        override
        whenNotPaused
        nonReentrant
        returns (bool[] memory results)
    {
        require(segments.length > 0, "IntentRouter: no segments");

        results = new bool[](segments.length);
        uint256 successCount = 0;

        for (uint256 i = 0; i < segments.length; i++) {
            uint256 gasStart = gasleft();
            Types.Segment calldata segment = segments[i];

            // Execute segment
            (bool success, bytes memory returnData) = _executeSegment(
                intentId,
                i,
                segment
            );

            results[i] = success;
            if (success) {
                successCount++;
            }

            // Record execution
            uint256 gasUsed = gasStart - gasleft();
            executionHistory[intentId].push(
                Types.SegmentExecution({
                    intentId: intentId,
                    segmentIndex: i,
                    protocol: segment.targetProtocol,
                    timestamp: block.timestamp,
                    gasUsed: gasUsed,
                    success: success,
                    returnData: returnData
                })
            );

            // Report to IntentDecomposer if set
            if (intentDecomposer != address(0)) {
                try
                    IIntentDecomposer(intentDecomposer).reportSegmentExecution(
                        intentId,
                        i,
                        success,
                        returnData
                    )
                {} catch {}
            }
        }

        emit ExecutionCompleted(intentId, segments.length, successCount);

        return results;
    }

    /**
     * @inheritdoc IIntentRouter
     */
    function executeWithPlan(
        bytes32 intentId,
        Types.ExecutionPlan calldata plan
    )
        external
        payable
        override
        whenNotPaused
        nonReentrant
        returns (bool[] memory results)
    {
        require(plan.protocols.length > 0, "IntentRouter: no protocols");
        require(
            plan.protocols.length == plan.callDatas.length &&
                plan.protocols.length == plan.values.length &&
                plan.protocols.length == plan.gasLimits.length,
            "IntentRouter: length mismatch"
        );

        results = new bool[](plan.protocols.length);

        for (uint256 i = 0; i < plan.protocols.length; i++) {
            require(
                approvedProtocols[plan.protocols[i]],
                "IntentRouter: protocol not approved"
            );

            (bool success, bytes memory returnData) = plan.protocols[i].call{
                value: plan.values[i],
                gas: plan.gasLimits[i]
            }(plan.callDatas[i]);

            results[i] = success;

            if (success) {
                emit SegmentExecuted(
                    intentId,
                    i,
                    plan.protocols[i],
                    true,
                    plan.gasLimits[i]
                );
            } else {
                emit SegmentFailed(intentId, i, plan.protocols[i], returnData);
            }
        }

        return results;
    }

    /**
     * @inheritdoc IIntentRouter
     */
    function simulateExecution(
        bytes32 intentId,
        Types.Segment[] calldata segments
    ) external override returns (bool[] memory results, uint256 totalGas) {
        results = new bool[](segments.length);
        totalGas = 0;

        for (uint256 i = 0; i < segments.length; i++) {
            uint256 gasStart = gasleft();

            // This is a simplified simulation - in production would use staticcall
            results[i] = approvedProtocols[segments[i].targetProtocol];

            totalGas += gasStart - gasleft();
        }

        return (results, totalGas);
    }

    /**
     * @inheritdoc IIntentRouter
     */
    function addProtocol(
        string calldata name,
        address adapter,
        Types.ProtocolCategory category
    ) external override onlyOwner {
        require(adapter != address(0), "IntentRouter: zero adapter");
        require(
            protocolAdapters[name] == address(0),
            "IntentRouter: already exists"
        );

        protocolAdapters[name] = adapter;
        approvedProtocols[adapter] = true;
        protocolCategory[adapter] = category;

        emit ProtocolAdded(name, adapter, category);
    }

    /**
     * @inheritdoc IIntentRouter
     */
    function removeProtocol(string calldata name) external override onlyOwner {
        address adapter = protocolAdapters[name];
        require(adapter != address(0), "IntentRouter: not found");

        approvedProtocols[adapter] = false;
        delete protocolAdapters[name];
        delete protocolCategory[adapter];

        emit ProtocolRemoved(name, adapter);
    }

    /**
     * @inheritdoc IIntentRouter
     */
    function setDefaultProtocol(
        Types.SegmentType segmentType,
        string calldata protocolName
    ) external override onlyOwner {
        require(
            protocolAdapters[protocolName] != address(0),
            "IntentRouter: protocol not found"
        );
        defaultProtocols[segmentType] = protocolName;
    }

    /**
     * @inheritdoc IIntentRouter
     */
    function getProtocolAdapter(string calldata name)
        external
        view
        override
        returns (address adapter)
    {
        return protocolAdapters[name];
    }

    /**
     * @inheritdoc IIntentRouter
     */
    function getExecutionHistory(bytes32 intentId)
        external
        view
        override
        returns (Types.SegmentExecution[] memory history)
    {
        return executionHistory[intentId];
    }

    /**
     * @inheritdoc IIntentRouter
     */
    function isApprovedProtocol(address protocol)
        external
        view
        override
        returns (bool)
    {
        return approvedProtocols[protocol];
    }

    /**
     * @notice Set IntentDecomposer address
     * @param _intentDecomposer Address of IntentDecomposer
     */
    function setIntentDecomposer(address _intentDecomposer) external onlyOwner {
        require(_intentDecomposer != address(0), "IntentRouter: zero address");
        intentDecomposer = _intentDecomposer;
    }

    /**
     * @notice Set maximum gas per segment
     * @param maxGas Maximum gas limit
     */
    function setMaxGasPerSegment(uint256 maxGas) external onlyOwner {
        require(maxGas >= 100000, "IntentRouter: gas too low");
        maxGasPerSegment = maxGas;
    }

    /**
     * @notice Set execution timeout
     * @param timeout Timeout in seconds
     */
    function setExecutionTimeout(uint256 timeout) external onlyOwner {
        require(timeout >= 1 minutes, "IntentRouter: timeout too short");
        executionTimeout = timeout;
    }

    // ============ Internal Functions ============

    /**
     * @dev Execute a single segment
     * @param intentId Intent identifier
     * @param segmentIndex Index of segment
     * @param segment Segment to execute
     * @return success True if execution succeeded
     * @return returnData Return data or error message
     */
    function _executeSegment(
        bytes32 intentId,
        uint256 segmentIndex,
        Types.Segment calldata segment
    ) internal returns (bool success, bytes memory returnData) {
        // Check if protocol is approved - return false instead of reverting for partial execution
        if (!approvedProtocols[segment.targetProtocol]) {
            return (false, "Protocol not approved");
        }

        // Get the actual intent owner from IntentDecomposer
        address intentOwner = msg.sender; // Default to msg.sender
        if (intentDecomposer != address(0)) {
            try IIntentDecomposer(intentDecomposer).getIntent(intentId) returns (
                Types.DecomposedIntent memory intent
            ) {
                intentOwner = intent.user;
            } catch {}
        }

        uint256 gasLimit = segment.minGasLimit > 0
            ? segment.minGasLimit
            : maxGasPerSegment;

        // Try to call the protocol adapter
        try
            IProtocolAdapter(segment.targetProtocol).execute{
                value: segment.value,
                gas: gasLimit
            }(segment.callData, intentOwner, segment.value)
        returns (bool _success, bytes memory _returnData) {
            success = _success;
            returnData = _returnData;

            emit SegmentExecuted(
                intentId,
                segmentIndex,
                segment.targetProtocol,
                success,
                gasLimit
            );
        } catch Error(string memory reason) {
            success = false;
            returnData = bytes(reason);

            emit SegmentFailed(
                intentId,
                segmentIndex,
                segment.targetProtocol,
                returnData
            );
        } catch (bytes memory lowLevelData) {
            success = false;
            returnData = lowLevelData;

            emit SegmentFailed(
                intentId,
                segmentIndex,
                segment.targetProtocol,
                returnData
            );
        }

        return (success, returnData);
    }

    /**
     * @notice Fallback to receive ETH
     */
    receive() external payable {}
}
