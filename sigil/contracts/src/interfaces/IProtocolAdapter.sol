// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../libraries/Types.sol";

/**
 * @title IProtocolAdapter
 * @notice Interface for protocol adapters
 * @dev Each protocol (Uniswap, Aave, GMX, etc.) implements this interface
 */
interface IProtocolAdapter {
    // ============ Events ============

    /// @notice Emitted when adapter executes successfully
    event AdapterExecuted(
        address indexed user,
        bytes segmentData,
        bytes returnData
    );

    /// @notice Emitted when adapter execution fails
    event AdapterFailed(address indexed user, bytes segmentData, string reason);

    // ============ Functions ============

    /**
     * @notice Execute a segment on the protocol
     * @param segmentData ABI-encoded segment-specific data
     * @param user User address (for token approvals and transfers)
     * @param value ETH value to send with the call
     * @return success True if execution succeeded
     * @return returnData Return data from protocol or error message
     */
    function execute(
        bytes calldata segmentData,
        address user,
        uint256 value
    ) external payable returns (bool success, bytes memory returnData);

    /**
     * @notice Simulate execution without state changes
     * @param segmentData ABI-encoded segment-specific data
     * @param user User address
     * @return canExecute True if execution would succeed
     * @return reason Reason for failure if canExecute is false
     */
    function simulate(bytes calldata segmentData, address user)
        external
        view
        returns (bool canExecute, string memory reason);

    /**
     * @notice Get protocol name
     * @return name Protocol name (e.g., "Uniswap V3")
     */
    function getProtocolName() external pure returns (string memory name);

    /**
     * @notice Get supported segment types
     * @return types Array of supported segment type enums
     */
    function getSupportedSegmentTypes()
        external
        pure
        returns (Types.SegmentType[] memory types);

    /**
     * @notice Get protocol version
     * @return version Version string (e.g., "3.0.0")
     */
    function getProtocolVersion() external pure returns (string memory version);

    /**
     * @notice Check if segment data is valid
     * @param segmentData ABI-encoded segment data
     * @return isValid True if data is valid
     * @return reason Reason for invalidity if isValid is false
     */
    function validateSegmentData(bytes calldata segmentData)
        external
        view
        returns (bool isValid, string memory reason);
}
