// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../libraries/Types.sol";

/**
 * @title IIntentRouter
 * @notice Interface for Intent Router - Routes segments to protocol adapters
 * @dev Handles atomic execution of intent segments
 */
interface IIntentRouter {
    // ============ Events ============

    /// @notice Emitted when a segment is executed
    event SegmentExecuted(
        bytes32 indexed intentId,
        uint256 segmentIndex,
        address indexed protocol,
        bool success,
        uint256 gasUsed
    );

    /// @notice Emitted when a segment fails
    event SegmentFailed(
        bytes32 indexed intentId,
        uint256 segmentIndex,
        address indexed protocol,
        bytes reason
    );

    /// @notice Emitted when execution is completed
    event ExecutionCompleted(
        bytes32 indexed intentId,
        uint256 totalSegments,
        uint256 successCount
    );

    /// @notice Emitted when a protocol adapter is added
    event ProtocolAdded(
        string name,
        address indexed adapter,
        Types.ProtocolCategory category
    );

    /// @notice Emitted when a protocol adapter is removed
    event ProtocolRemoved(string name, address indexed adapter);

    // ============ Functions ============

    /**
     * @notice Execute multiple segments atomically
     * @param intentId Intent identifier
     * @param segments Array of segments to execute
     * @return results Array of success status for each segment
     */
    function executeSegments(
        bytes32 intentId,
        Types.Segment[] calldata segments
    ) external payable returns (bool[] memory results);

    /**
     * @notice Execute with a custom execution plan
     * @param intentId Intent identifier
     * @param plan Execution plan with protocols, calldata, values, gas limits
     * @return results Array of success status for each execution
     */
    function executeWithPlan(
        bytes32 intentId,
        Types.ExecutionPlan calldata plan
    ) external payable returns (bool[] memory results);

    /**
     * @notice Simulate execution without state changes
     * @param intentId Intent identifier
     * @param segments Array of segments to simulate
     * @return results Array of success status
     * @return totalGas Total gas that would be consumed
     */
    function simulateExecution(
        bytes32 intentId,
        Types.Segment[] calldata segments
    ) external returns (bool[] memory results, uint256 totalGas);

    /**
     * @notice Add a protocol adapter
     * @param name Protocol name (e.g., "uniswap-v3")
     * @param adapter Adapter contract address
     * @param category Protocol category
     */
    function addProtocol(
        string calldata name,
        address adapter,
        Types.ProtocolCategory category
    ) external;

    /**
     * @notice Remove a protocol adapter
     * @param name Protocol name
     */
    function removeProtocol(string calldata name) external;

    /**
     * @notice Set default protocol for a segment type
     * @param segmentType Segment type
     * @param protocolName Protocol name to use as default
     */
    function setDefaultProtocol(
        Types.SegmentType segmentType,
        string calldata protocolName
    ) external;

    /**
     * @notice Get protocol adapter address
     * @param name Protocol name
     * @return adapter Adapter contract address
     */
    function getProtocolAdapter(string calldata name)
        external
        view
        returns (address adapter);

    /**
     * @notice Get execution history for an intent
     * @param intentId Intent identifier
     * @return history Array of segment execution records
     */
    function getExecutionHistory(bytes32 intentId)
        external
        view
        returns (Types.SegmentExecution[] memory history);

    /**
     * @notice Check if a protocol is approved
     * @param protocol Protocol address
     * @return bool True if approved
     */
    function isApprovedProtocol(address protocol) external view returns (bool);
}
