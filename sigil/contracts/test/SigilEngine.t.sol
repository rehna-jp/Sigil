// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/SigilEngine.sol";

contract SigilEngineTest is Test {
    SigilEngine engine;

    function setUp() public {
        engine = new SigilEngine();
    }

    function testCreateIntent() public {
        uint256 id = engine.createIntent("Buy 1 ETH if price < $2000");
        (address owner, string memory text, bool active, uint256 createdAt) = engine.getIntent(id);
        assertTrue(active);
        assertEq(owner, address(this));
        assertEq(text, "Buy 1 ETH if price < $2000");
        assertGt(createdAt, 0);
    }
}
