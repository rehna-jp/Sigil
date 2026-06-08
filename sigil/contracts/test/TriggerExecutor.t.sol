// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {TriggerExecutor} from "../src/TriggerExecutor.sol";
import {WatcherRegistry} from "../src/WatcherRegistry.sol";
import {MockPriceFeed} from "../src/mocks/MockPriceFeed.sol";

contract TriggerExecutorTest is Test {
    TriggerExecutor executor;
    WatcherRegistry registry;
    MockPriceFeed   mockFeed;

    address owner    = makeAddr("owner");
    address user     = makeAddr("user");
    address stranger = makeAddr("stranger");

    bytes32 constant PARENT_ID = keccak256("parent");
    int256  constant ETH_3800  = 380000000000;
    int256  constant ETH_3500  = 350000000000;
    int256  constant ETH_3400  = 340000000000;
    int256  constant ETH_3000  = 300000000000;

    // ── Helpers ───────────────────────────────────────────────────

    function _registerPrice(int256 threshold) internal returns (bytes32) {
        bytes memory params = abi.encode(WatcherRegistry.PriceParams({
            priceFeed: address(mockFeed),
            threshold: threshold,
            comparison: WatcherRegistry.ComparisonOp.LT
        }));
        vm.prank(user);
        return registry.registerWatcher(
            PARENT_ID, user, WatcherRegistry.WatcherType.PRICE,
            params, abi.encode("exit_to_usdc"), block.timestamp + 30 days
        );
    }

    function _registerTime(uint256 interval, uint256 maxTriggers) internal returns (bytes32) {
        bytes memory params = abi.encode(WatcherRegistry.TimeParams({
            interval: interval,
            nextTrigger: block.timestamp + interval,
            maxTriggers: maxTriggers,
            triggerCount: 0
        }));
        vm.prank(user);
        return registry.registerWatcher(
            PARENT_ID, user, WatcherRegistry.WatcherType.TIME,
            params, abi.encode("rebalance"), block.timestamp + 7 days
        );
    }

    // ── Setup ─────────────────────────────────────────────────────

    function setUp() public {
        vm.startPrank(owner);
        registry  = new WatcherRegistry(owner);
        executor  = new TriggerExecutor(address(registry), owner);
        mockFeed  = new MockPriceFeed(ETH_3800, 8, "ETH/USD Mock", owner);
        registry.authorizeExecutor(address(executor));
        registry.setIntentDecomposer(user); // user acts as decomposer in tests
        vm.stopPrank();
    }

    // ── checkAndExecuteSingle ─────────────────────────────────────

    function test_single_falseWhenConditionNotMet() public {
        bytes32 id = _registerPrice(ETH_3500);
        // Price at $3,800, above $3,500 threshold
        bool triggered = executor.checkAndExecuteSingle(id);
        assertFalse(triggered);
    }

    function test_single_trueAndFiresWhenConditionMet() public {
        bytes32 id = _registerPrice(ETH_3500);
        vm.prank(owner);
        mockFeed.dropPrice(ETH_3400);

        vm.expectEmit(true, false, false, false);
        emit TriggerExecutor.TriggerFired(id, abi.encode("exit_to_usdc"), block.timestamp);

        bool triggered = executor.checkAndExecuteSingle(id);
        assertTrue(triggered);
    }

    function test_single_incrementsTotalTriggers() public {
        bytes32 id = _registerPrice(ETH_3500);
        vm.prank(owner);
        mockFeed.dropPrice(ETH_3400);
        executor.checkAndExecuteSingle(id);
        assertEq(executor.totalTriggersExecuted(), 1);
    }

    function test_single_watcherBecomesTriggered() public {
        bytes32 id = _registerPrice(ETH_3500);
        vm.prank(owner);
        mockFeed.dropPrice(ETH_3400);
        executor.checkAndExecuteSingle(id);
        assertEq(uint8(registry.getWatcher(id).status), uint8(WatcherRegistry.WatcherStatus.TRIGGERED));
    }

    // ── checkAndExecuteBatch ──────────────────────────────────────

    function test_batch_revertsOnEmpty() public {
        vm.expectRevert(TriggerExecutor.EmptyBatch.selector);
        executor.checkAndExecuteBatch(new bytes32[](0));
    }

    function test_batch_triggersOnlyConditionsMet() public {
        bytes32 id1 = _registerPrice(ETH_3500); // threshold $3,500
        vm.warp(block.timestamp + 1);
        bytes32 id2 = _registerPrice(ETH_3000); // threshold $3,000 — higher bar

        // Drop to $3,400 — only id1 should trigger
        vm.prank(owner);
        mockFeed.dropPrice(ETH_3400);

        bytes32[] memory batch = new bytes32[](2);
        batch[0] = id1;
        batch[1] = id2;

        uint256 triggered = executor.checkAndExecuteBatch(batch);
        assertEq(triggered, 1);
        assertEq(executor.totalTriggersExecuted(), 1);
    }

    function test_batch_doesNotRevertOnBadWatcherId() public {
        bytes32 id1  = _registerPrice(ETH_3500);
        bytes32 badId = keccak256("nonexistent");

        vm.prank(owner);
        mockFeed.dropPrice(ETH_3400);

        bytes32[] memory batch = new bytes32[](2);
        batch[0] = id1;
        batch[1] = badId; // nonexistent — should be skipped, not revert

        uint256 triggered = executor.checkAndExecuteBatch(batch);
        assertEq(triggered, 1);
    }

    function test_batch_emitsBatchChecked() public {
        bytes32 id = _registerPrice(ETH_3500);
        vm.prank(owner);
        mockFeed.dropPrice(ETH_3400);

        bytes32[] memory batch = new bytes32[](1);
        batch[0] = id;

        vm.expectEmit(false, false, false, true);
        emit TriggerExecutor.BatchChecked(1, 1, block.timestamp);
        executor.checkAndExecuteBatch(batch);
    }

    function test_batch_skipsAlreadyTriggeredWatcher() public {
        bytes32 id = _registerPrice(ETH_3500);
        vm.prank(owner);
        mockFeed.dropPrice(ETH_3400);

        bytes32[] memory batch = new bytes32[](1);
        batch[0] = id;

        executor.checkAndExecuteBatch(batch); // first run — triggers
        uint256 after1 = executor.totalTriggersExecuted();

        executor.checkAndExecuteBatch(batch); // second run — already triggered, skip
        assertEq(executor.totalTriggersExecuted(), after1); // no change
    }

    // ── trigger history ───────────────────────────────────────────

    function test_history_recordedCorrectly() public {
        bytes32 id = _registerPrice(ETH_3500);
        vm.prank(owner);
        mockFeed.dropPrice(ETH_3400);
        executor.checkAndExecuteSingle(id);

        TriggerExecutor.TriggerRecord[] memory h = executor.getTriggerHistory(id);
        assertEq(h.length, 1);
        assertTrue(h[0].success);
        assertEq(h[0].watcherId, id);
        assertEq(h[0].triggerAction, abi.encode("exit_to_usdc"));
    }

    function test_getTriggerCount() public {
        bytes32 id = _registerPrice(ETH_3500);
        assertEq(executor.getTriggerCount(id), 0);
        vm.prank(owner);
        mockFeed.dropPrice(ETH_3400);
        executor.checkAndExecuteSingle(id);
        assertEq(executor.getTriggerCount(id), 1);
    }

    // ── TIME watcher via executor ─────────────────────────────────

    function test_timeWatcher_triggersAfterInterval() public {
        bytes32 id = _registerTime(3600, 0);
        assertFalse(executor.checkAndExecuteSingle(id)); // before interval
        vm.warp(block.timestamp + 3601);

        vm.expectEmit(true, false, false, false);
        emit TriggerExecutor.TriggerFired(id, abi.encode("rebalance"), block.timestamp);
        assertTrue(executor.checkAndExecuteSingle(id));
    }
}
