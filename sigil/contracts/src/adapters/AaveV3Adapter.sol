// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../interfaces/IProtocolAdapter.sol";
import "../interfaces/protocols/IAaveV3Pool.sol";
import "../interfaces/protocols/IUniswapV3Router.sol"; // For IERC20
import "../libraries/Types.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title AaveV3Adapter
 * @notice Protocol adapter for Aave V3 lending on Arbitrum
 * @dev Implements IProtocolAdapter for integration with IntentRouter
 */
contract AaveV3Adapter is IProtocolAdapter, Ownable {
    // ============ State Variables ============

    /// @notice Aave V3 Pool
    IPool public immutable aavePool;

    /// @notice Arbitrum One Aave V3 Pool: 0x794a61358D6845594F94dc1DB02A252b5b4814aD
    /// @notice Arbitrum Sepolia: Use testnet pool or mock

    // ============ Enums ============

    enum AaveOperation {
        SUPPLY,
        WITHDRAW,
        BORROW,
        REPAY
    }

    // ============ Constructor ============

    constructor(address _aavePool, address initialOwner) Ownable(initialOwner) {
        require(_aavePool != address(0), "AaveV3Adapter: zero pool");
        aavePool = IPool(_aavePool);
    }

    // ============ External Functions ============

    /**
     * @inheritdoc IProtocolAdapter
     */
    function execute(
        bytes calldata segmentData,
        address user,
        uint256 value
    ) external payable override returns (bool success, bytes memory returnData) {
        // Decode segment data
        // Format: (operation, asset, amount, [optional: interestRateMode for borrow/repay])
        (AaveOperation operation, address asset, uint256 amount) = abi.decode(
            segmentData,
            (AaveOperation, address, uint256)
        );

        // Validate inputs
        if (asset == address(0)) {
            return (false, "Invalid asset address");
        }
        if (amount == 0) {
            return (false, "Zero amount");
        }

        if (operation == AaveOperation.SUPPLY) {
            return _executeSupply(asset, amount, user, segmentData);
        } else if (operation == AaveOperation.WITHDRAW) {
            return _executeWithdraw(asset, amount, user, segmentData);
        } else if (operation == AaveOperation.BORROW) {
            return _executeBorrow(asset, amount, user, segmentData);
        } else if (operation == AaveOperation.REPAY) {
            return _executeRepay(asset, amount, user, segmentData);
        } else {
            return (false, "Invalid operation");
        }
    }

    /**
     * @inheritdoc IProtocolAdapter
     */
    function simulate(bytes calldata segmentData, address user)
        external
        view
        override
        returns (bool canExecute, string memory reason)
    {
        // Decode segment data
        (AaveOperation operation, address asset, uint256 amount) = abi.decode(
            segmentData,
            (AaveOperation, address, uint256)
        );

        // Basic validation
        if (asset == address(0)) {
            return (false, "Invalid asset address");
        }
        if (amount == 0) {
            return (false, "Zero amount");
        }

        // Check user balance for supply/repay operations
        if (
            operation == AaveOperation.SUPPLY ||
            operation == AaveOperation.REPAY
        ) {
            try IERC20(asset).balanceOf(user) returns (uint256 balance) {
                if (balance < amount) {
                    return (false, "Insufficient balance");
                }
            } catch {
                return (false, "Balance check failed");
            }

            // Check allowance
            try IERC20(asset).allowance(user, address(this)) returns (
                uint256 allowance
            ) {
                if (allowance < amount) {
                    return (false, "Insufficient allowance");
                }
            } catch {
                return (false, "Allowance check failed");
            }
        }

        return (true, "");
    }

    /**
     * @inheritdoc IProtocolAdapter
     */
    function getProtocolName() external pure override returns (string memory) {
        return "Aave V3";
    }

    /**
     * @inheritdoc IProtocolAdapter
     */
    function getSupportedSegmentTypes()
        external
        pure
        override
        returns (Types.SegmentType[] memory types)
    {
        types = new Types.SegmentType[](2);
        types[0] = Types.SegmentType.DEPOSIT;
        types[1] = Types.SegmentType.WITHDRAW;
        return types;
    }

    /**
     * @inheritdoc IProtocolAdapter
     */
    function getProtocolVersion() external pure override returns (string memory) {
        return "3.0.0";
    }

    /**
     * @inheritdoc IProtocolAdapter
     */
    function validateSegmentData(bytes calldata segmentData)
        external
        view
        override
        returns (bool isValid, string memory reason)
    {
        try this.decodeSegmentData(segmentData) {
            return (true, "");
        } catch {
            return (false, "Invalid segment data encoding");
        }
    }

    // ============ Internal Functions ============

    /**
     * @dev Execute supply operation
     */
    function _executeSupply(
        address asset,
        uint256 amount,
        address user,
        bytes memory segmentData
    ) internal returns (bool success, bytes memory returnData) {
        // Transfer tokens from user to this contract
        try IERC20(asset).transferFrom(user, address(this), amount) returns (
            bool transferSuccess
        ) {
            if (!transferSuccess) {
                return (false, "Token transfer failed");
            }
        } catch {
            return (false, "Token transfer reverted");
        }

        // Approve Aave pool
        try IERC20(asset).approve(address(aavePool), amount) returns (
            bool approveSuccess
        ) {
            if (!approveSuccess) {
                return (false, "Token approval failed");
            }
        } catch {
            return (false, "Token approval reverted");
        }

        // Supply to Aave
        try aavePool.supply(asset, amount, user, 0) {
            emit AdapterExecuted(user, segmentData, abi.encode(amount));
            return (true, abi.encode(amount));
        } catch Error(string memory reason) {
            emit AdapterFailed(user, segmentData, reason);
            return (false, bytes(reason));
        } catch (bytes memory lowLevelData) {
            emit AdapterFailed(user, segmentData, "Low-level error");
            return (false, lowLevelData);
        }
    }

    /**
     * @dev Execute withdraw operation
     */
    function _executeWithdraw(
        address asset,
        uint256 amount,
        address user,
        bytes memory segmentData
    ) internal returns (bool success, bytes memory returnData) {
        // Note: Withdrawing requires the user to have aTokens
        // In a production system, we'd need to handle aToken approvals

        try aavePool.withdraw(asset, amount, user) returns (uint256 withdrawn) {
            emit AdapterExecuted(user, segmentData, abi.encode(withdrawn));
            return (true, abi.encode(withdrawn));
        } catch Error(string memory reason) {
            emit AdapterFailed(user, segmentData, reason);
            return (false, bytes(reason));
        } catch (bytes memory lowLevelData) {
            emit AdapterFailed(user, segmentData, "Low-level error");
            return (false, lowLevelData);
        }
    }

    /**
     * @dev Execute borrow operation
     */
    function _executeBorrow(
        address asset,
        uint256 amount,
        address user,
        bytes memory segmentData
    ) internal returns (bool success, bytes memory returnData) {
        // Borrow with variable rate (2)
        uint256 interestRateMode = 2;

        try aavePool.borrow(asset, amount, interestRateMode, 0, user) {
            emit AdapterExecuted(user, segmentData, abi.encode(amount));
            return (true, abi.encode(amount));
        } catch Error(string memory reason) {
            emit AdapterFailed(user, segmentData, reason);
            return (false, bytes(reason));
        } catch (bytes memory lowLevelData) {
            emit AdapterFailed(user, segmentData, "Low-level error");
            return (false, lowLevelData);
        }
    }

    /**
     * @dev Execute repay operation
     */
    function _executeRepay(
        address asset,
        uint256 amount,
        address user,
        bytes memory segmentData
    ) internal returns (bool success, bytes memory returnData) {
        // Transfer tokens from user to this contract
        try IERC20(asset).transferFrom(user, address(this), amount) returns (
            bool transferSuccess
        ) {
            if (!transferSuccess) {
                return (false, "Token transfer failed");
            }
        } catch {
            return (false, "Token transfer reverted");
        }

        // Approve Aave pool
        try IERC20(asset).approve(address(aavePool), amount) returns (
            bool approveSuccess
        ) {
            if (!approveSuccess) {
                return (false, "Token approval failed");
            }
        } catch {
            return (false, "Token approval reverted");
        }

        // Repay with variable rate (2)
        uint256 interestRateMode = 2;

        try aavePool.repay(asset, amount, interestRateMode, user) returns (
            uint256 repaid
        ) {
            emit AdapterExecuted(user, segmentData, abi.encode(repaid));
            return (true, abi.encode(repaid));
        } catch Error(string memory reason) {
            emit AdapterFailed(user, segmentData, reason);
            return (false, bytes(reason));
        } catch (bytes memory lowLevelData) {
            emit AdapterFailed(user, segmentData, "Low-level error");
            return (false, lowLevelData);
        }
    }

    // ============ Helper Functions ============

    /**
     * @notice Helper function to decode segment data
     * @param segmentData Encoded segment data
     */
    function decodeSegmentData(bytes calldata segmentData)
        external
        pure
        returns (
            AaveOperation operation,
            address asset,
            uint256 amount
        )
    {
        return abi.decode(segmentData, (AaveOperation, address, uint256));
    }

    /**
     * @notice Emergency token recovery
     * @param token Token address
     * @param to Recipient address
     * @param amount Amount to recover
     */
    function recoverToken(
        address token,
        address to,
        uint256 amount
    ) external onlyOwner {
        require(token != address(0), "AaveV3Adapter: zero token");
        require(to != address(0), "AaveV3Adapter: zero recipient");

        IERC20(token).transfer(to, amount);
    }

    /**
     * @notice Receive ETH
     */
    receive() external payable {}
}
