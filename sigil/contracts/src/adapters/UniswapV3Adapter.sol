// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../interfaces/IProtocolAdapter.sol";
import "../interfaces/protocols/IUniswapV3Router.sol";
import "../libraries/Types.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title UniswapV3Adapter
 * @notice Protocol adapter for Uniswap V3 swaps on Arbitrum
 * @dev Implements IProtocolAdapter for integration with IntentRouter
 */
contract UniswapV3Adapter is IProtocolAdapter, Ownable {
    // ============ State Variables ============

    /// @notice Uniswap V3 Swap Router
    ISwapRouter public immutable swapRouter;

    /// @notice Arbitrum One Uniswap V3 Router: 0xE592427A0AEce92De3Edee1F18E0157C05861564
    /// @notice Arbitrum Sepolia: Deploy testnet router or use mock

    // ============ Constructor ============

    constructor(address _swapRouter, address initialOwner) Ownable(initialOwner) {
        require(_swapRouter != address(0), "UniswapV3Adapter: zero router");
        swapRouter = ISwapRouter(_swapRouter);
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
        // Format: (tokenIn, tokenOut, fee, amountIn, minAmountOut)
        (
            address tokenIn,
            address tokenOut,
            uint24 fee,
            uint256 amountIn,
            uint256 minAmountOut
        ) = abi.decode(segmentData, (address, address, uint24, uint256, uint256));

        // Validate inputs
        if (tokenIn == address(0) || tokenOut == address(0)) {
            return (false, "Invalid token addresses");
        }
        if (amountIn == 0) {
            return (false, "Zero amount");
        }

        // Transfer tokens from user to this contract
        try IERC20(tokenIn).transferFrom(user, address(this), amountIn) returns (
            bool transferSuccess
        ) {
            if (!transferSuccess) {
                return (false, "Token transfer failed");
            }
        } catch {
            return (false, "Token transfer reverted");
        }

        // Approve Uniswap router
        try IERC20(tokenIn).approve(address(swapRouter), amountIn) returns (
            bool approveSuccess
        ) {
            if (!approveSuccess) {
                return (false, "Token approval failed");
            }
        } catch {
            return (false, "Token approval reverted");
        }

        // Execute swap
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: fee,
            recipient: user,
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: minAmountOut,
            sqrtPriceLimitX96: 0
        });

        try swapRouter.exactInputSingle{value: value}(params) returns (
            uint256 amountOut
        ) {
            emit AdapterExecuted(user, segmentData, abi.encode(amountOut));
            return (true, abi.encode(amountOut));
        } catch Error(string memory reason) {
            emit AdapterFailed(user, segmentData, reason);
            return (false, bytes(reason));
        } catch (bytes memory lowLevelData) {
            emit AdapterFailed(user, segmentData, "Low-level error");
            return (false, lowLevelData);
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
        (
            address tokenIn,
            address tokenOut,
            ,
            uint256 amountIn,

        ) = abi.decode(segmentData, (address, address, uint24, uint256, uint256));

        // Basic validation
        if (tokenIn == address(0) || tokenOut == address(0)) {
            return (false, "Invalid token addresses");
        }
        if (amountIn == 0) {
            return (false, "Zero amount");
        }

        // Check user balance
        try IERC20(tokenIn).balanceOf(user) returns (uint256 balance) {
            if (balance < amountIn) {
                return (false, "Insufficient balance");
            }
        } catch {
            return (false, "Balance check failed");
        }

        // Check allowance
        try IERC20(tokenIn).allowance(user, address(this)) returns (
            uint256 allowance
        ) {
            if (allowance < amountIn) {
                return (false, "Insufficient allowance");
            }
        } catch {
            return (false, "Allowance check failed");
        }

        return (true, "");
    }

    /**
     * @inheritdoc IProtocolAdapter
     */
    function getProtocolName() external pure override returns (string memory) {
        return "Uniswap V3";
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
        types = new Types.SegmentType[](1);
        types[0] = Types.SegmentType.SWAP;
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

    /**
     * @notice Helper function to decode segment data
     * @param segmentData Encoded segment data
     */
    function decodeSegmentData(bytes calldata segmentData)
        external
        pure
        returns (
            address tokenIn,
            address tokenOut,
            uint24 fee,
            uint256 amountIn,
            uint256 minAmountOut
        )
    {
        return
            abi.decode(
                segmentData,
                (address, address, uint24, uint256, uint256)
            );
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
        require(token != address(0), "UniswapV3Adapter: zero token");
        require(to != address(0), "UniswapV3Adapter: zero recipient");

        IERC20(token).transfer(to, amount);
    }

    /**
     * @notice Receive ETH
     */
    receive() external payable {}
}
