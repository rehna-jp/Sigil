// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../../src/interfaces/protocols/IAaveV3Pool.sol";
import "../../src/interfaces/protocols/IUniswapV3Router.sol";

/**
 * @title MockAavePool
 * @notice Mock Aave V3 Pool for testing
 */
contract MockAavePool is IPool {
    bool public shouldRevert = false;
    string public revertMessage = "Mock revert";

    mapping(address => mapping(address => uint256)) public supplied;

    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }

    function setRevertMessage(string memory message) external {
        revertMessage = message;
    }

    function supply(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16
    ) external override {
        if (shouldRevert) {
            revert(revertMessage);
        }

        // Transfer tokens from sender
        IERC20(asset).transferFrom(msg.sender, address(this), amount);

        // Track supply
        supplied[onBehalfOf][asset] += amount;

        // In real Aave, would mint aTokens - we skip for simplicity
    }

    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external override returns (uint256) {
        if (shouldRevert) {
            revert(revertMessage);
        }

        // Transfer tokens back to recipient
        IERC20(asset).transfer(to, amount);

        // Track withdrawal - deduct from the recipient's supplied amount
        // (In real Aave, this would burn aTokens, but we track supplied amounts directly)
        supplied[to][asset] -= amount;

        return amount;
    }

    function borrow(
        address asset,
        uint256 amount,
        uint256,
        uint16,
        address onBehalfOf
    ) external override {
        if (shouldRevert) {
            revert(revertMessage);
        }

        // Transfer borrowed tokens
        IERC20(asset).transfer(onBehalfOf, amount);
    }

    function repay(
        address asset,
        uint256 amount,
        uint256,
        address onBehalfOf
    ) external override returns (uint256) {
        if (shouldRevert) {
            revert(revertMessage);
        }

        // Transfer repayment from sender
        IERC20(asset).transferFrom(msg.sender, address(this), amount);

        return amount;
    }

    // Helper function for testing
    function getUserSupplied(address user, address asset) external view returns (uint256) {
        return supplied[user][asset];
    }
}
