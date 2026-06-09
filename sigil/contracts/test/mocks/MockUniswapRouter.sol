// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../../src/interfaces/protocols/IUniswapV3Router.sol";

/**
 * @title MockUniswapRouter
 * @notice Mock Uniswap V3 Router for testing
 */
contract MockUniswapRouter is ISwapRouter {
    uint256 public amountOutToReturn = 1000e18;
    bool public shouldRevert = false;
    string public revertMessage = "Mock revert";

    function setAmountOut(uint256 amount) external {
        amountOutToReturn = amount;
    }

    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }

    function setRevertMessage(string memory message) external {
        revertMessage = message;
    }

    function exactInputSingle(ExactInputSingleParams calldata params)
        external
        payable
        override
        returns (uint256 amountOut)
    {
        if (shouldRevert) {
            revert(revertMessage);
        }

        // Transfer tokenIn from sender
        IERC20(params.tokenIn).transferFrom(msg.sender, address(this), params.amountIn);

        // Mint tokenOut to recipient (in real world would be from pool)
        // For mock, we assume this contract has unlimited tokens
        IERC20(params.tokenOut).transfer(params.recipient, amountOutToReturn);

        return amountOutToReturn;
    }

    function exactInput(ExactInputParams calldata)
        external
        payable
        override
        returns (uint256 amountOut)
    {
        if (shouldRevert) {
            revert(revertMessage);
        }
        return amountOutToReturn;
    }

    function exactOutputSingle(ExactOutputSingleParams calldata)
        external
        payable
        override
        returns (uint256 amountIn)
    {
        if (shouldRevert) {
            revert(revertMessage);
        }
        return amountOutToReturn;
    }
}
