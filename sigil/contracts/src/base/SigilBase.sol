// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title SigilBase
 * @notice Base contract providing common security patterns for all Sigil contracts
 * @dev Inherits from OpenZeppelin's Ownable, ReentrancyGuard, and Pausable
 */
abstract contract SigilBase is Ownable, ReentrancyGuard, Pausable {
    // ============ Events ============

    /// @notice Emitted when contract is paused
    event ContractPaused(address indexed by);

    /// @notice Emitted when contract is unpaused
    event ContractUnpaused(address indexed by);

    // ============ Constructor ============

    /**
     * @notice Initialize base contract with owner
     * @param initialOwner Address of contract owner
     */
    constructor(address initialOwner) Ownable(initialOwner) {
        // Ownable constructor sets the owner
    }

    // ============ Admin Functions ============

    /**
     * @notice Pause contract operations
     * @dev Only owner can pause. Triggers stopped state.
     */
    function pause() external onlyOwner {
        _pause();
        emit ContractPaused(msg.sender);
    }

    /**
     * @notice Unpause contract operations
     * @dev Only owner can unpause. Returns to normal state.
     */
    function unpause() external onlyOwner {
        _unpause();
        emit ContractUnpaused(msg.sender);
    }

    /**
     * @notice Emergency withdraw of ETH stuck in contract
     * @dev Only owner can withdraw. Useful for recovering mistakenly sent ETH.
     * @param to Address to send ETH to
     */
    function emergencyWithdraw(address payable to) external onlyOwner {
        require(to != address(0), "SigilBase: zero address");
        uint256 balance = address(this).balance;
        require(balance > 0, "SigilBase: no balance");

        (bool success, ) = to.call{value: balance}("");
        require(success, "SigilBase: transfer failed");
    }

    /**
     * @notice Emergency withdraw of ERC20 tokens stuck in contract
     * @dev Only owner can withdraw. Useful for recovering mistakenly sent tokens.
     * @param token Token contract address
     * @param to Address to send tokens to
     * @param amount Amount of tokens to withdraw
     */
    function emergencyWithdrawToken(
        address token,
        address to,
        uint256 amount
    ) external onlyOwner {
        require(token != address(0), "SigilBase: zero token address");
        require(to != address(0), "SigilBase: zero to address");
        require(amount > 0, "SigilBase: zero amount");

        // Using low-level call to handle different token implementations
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(
                bytes4(keccak256("transfer(address,uint256)")),
                to,
                amount
            )
        );
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            "SigilBase: token transfer failed"
        );
    }
}
