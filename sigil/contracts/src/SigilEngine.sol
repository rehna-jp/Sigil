// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

contract SigilEngine is Ownable, ReentrancyGuard, Pausable {
    event IntentCreated(uint256 indexed id, address indexed owner, string intent);
    event IntentCanceled(uint256 indexed id);

    struct Intent {
        address owner;
        string text;
        bool active;
        uint256 createdAt;
    }

    Intent[] public intents;

    function createIntent(string calldata text) external whenNotPaused nonReentrant returns (uint256) {
        intents.push(Intent(msg.sender, text, true, block.timestamp));
        uint256 id = intents.length - 1;
        emit IntentCreated(id, msg.sender, text);
        return id;
    }

    function cancelIntent(uint256 id) external {
        Intent storage it = intents[id];
        require(it.owner == msg.sender || owner() == msg.sender, "Sigil: not owner");
        require(it.active, "Sigil: inactive");
        it.active = false;
        emit IntentCanceled(id);
    }

    function getIntent(uint256 id) external view returns (address, string memory, bool, uint256) {
        Intent storage it = intents[id];
        return (it.owner, it.text, it.active, it.createdAt);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
