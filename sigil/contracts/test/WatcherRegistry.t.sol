// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {WatcherRegistry} from "../src/WatcherRegistry.sol";
import {MockPriceFeed} from "../src/mocks/MockPriceFeed.sol";

contract WatcherRegistryTest is Test {
    WatcherRegistry registry;
    MockPriceFeed   mockFeed;

    address owner      = makeAddr("owner");
    address executor   = makeAddr("executor");
    address decomposer = makeAddr("decomposer");
    address user       = makeAddr("user");
    address stranger   = makeAddr("stranger");

    bytes32 constant PARENT_ID = keccak256("test_intent");
    int256  constant ETH_3800  = 380000000000;
    int256  constant ETH_3500  = 350000000000;
    int256  constant ETH_3400  = 340000000000;
    int256  constant ETH_4100  = 410000000000;

    // ── Helpers ───────────────────────────────────────────────────

    function _priceParams(int256 threshold, WatcherRegistry.ComparisonOp op)
        internal view returns (bytes memory)
    {
        return abi.encode(WatcherRegistry.PriceParams({
            priceFeed: address(mockFeed),
            threshold: threshold,
            comparison: op
        }));
    }

    function _timeParams(uint256 interval, uint256 maxTriggers)
        internal view returns (bytes memory)
    {
        return abi.encode(WatcherRegistry.TimeParams({
            interval: interval,
            nextTrigger: block.timestamp + interval,
            maxTriggers: maxTriggers,
            triggerCount: 0
        }));
    }

    function _registerPrice(address caller, int256 threshold, WatcherRegistry.ComparisonOp op)
        internal returns (bytes32)
    {
        vm.prank(caller);
        return registry.registerWatcher(
            PARENT_ID, user, WatcherRegistry.WatcherType.PRICE,
            _priceParams(threshold, op),
            abi.encode("exit"),
            block.timestamp + 30 days
        );
    }

    // ── Setup ─────────────────────────────────────────────────────

    function setUp() public {
        vm.startPrank(owner);
        registry  = new WatcherRegistry(owner);
        mockFeed  = new MockPriceFeed(ETH_3800, 8, "ETH/USD Mock", owner);
        registry.authorizeExecutor(executor);
        registry.setIntentDecomposer(decomposer);
        vm.stopPrank();
    }

    // ── registerWatcher ───────────────────────────────────────────

    function test_register_fromDecomposer() public {
        bytes32 id = _registerPrice(decomposer, ETH_3500, WatcherRegistry.ComparisonOp.LT);
        assertTrue(id != bytes32(0));
        assertEq(registry.getActiveWatcherCount(), 1);

        WatcherRegistry.Watcher memory w = registry.getWatcher(id);
        assertEq(w.owner, user);
        assertEq(uint8(w.status), uint8(WatcherRegistry.WatcherStatus.ACTIVE));
    }

    function test_register_fromOwnerDirectly() public {
        bytes32 id = _registerPrice(user, ETH_3500, WatcherRegistry.ComparisonOp.LT);
        assertTrue(id != bytes32(0));
    }

    function test_register_revertsIfStranger() public {
        vm.prank(stranger);
        vm.expectRevert(WatcherRegistry.Unauthorized.selector);
        registry.registerWatcher(
            PARENT_ID, user, WatcherRegistry.WatcherType.PRICE,
            _priceParams(ETH_3500, WatcherRegistry.ComparisonOp.LT),
            abi.encode("exit"), block.timestamp + 30 days
        );
    }

    function test_register_revertsOnEmptyParams() public {
        vm.prank(user);
        vm.expectRevert(WatcherRegistry.InvalidParameters.selector);
        registry.registerWatcher(
            PARENT_ID, user, WatcherRegistry.WatcherType.PRICE,
            "", abi.encode("exit"), block.timestamp + 30 days
        );
    }

    // ── checkPriceWatcher ─────────────────────────────────────────

    function test_checkPrice_falseWhenAboveThreshold() public {
        // ETH at $3,800 — threshold $3,500 LT — should NOT trigger
        bytes32 id = _registerPrice(decomposer, ETH_3500, WatcherRegistry.ComparisonOp.LT);
        assertFalse(registry.checkPriceWatcher(id));
    }

    function test_checkPrice_trueWhenBelowThreshold() public {
        bytes32 id = _registerPrice(decomposer, ETH_3500, WatcherRegistry.ComparisonOp.LT);
        vm.prank(owner);
        mockFeed.dropPrice(ETH_3400);
        assertTrue(registry.checkPriceWatcher(id));
    }

    function test_checkPrice_GT_comparison() public {
        bytes32 id = _registerPrice(user, ETH_4100, WatcherRegistry.ComparisonOp.GT);
        assertFalse(registry.checkPriceWatcher(id)); // $3,800 < $4,100
        vm.prank(owner);
        mockFeed.setPrice(ETH_4100 + 1);
        assertTrue(registry.checkPriceWatcher(id));
    }

    function test_checkPrice_GTE_comparison() public {
        bytes32 id = _registerPrice(user, ETH_3800, WatcherRegistry.ComparisonOp.GTE);
        assertTrue(registry.checkPriceWatcher(id)); // $3,800 >= $3,800
    }

    function test_checkPrice_LTE_comparison() public {
        bytes32 id = _registerPrice(user, ETH_3800, WatcherRegistry.ComparisonOp.LTE);
        assertTrue(registry.checkPriceWatcher(id)); // $3,800 <= $3,800
    }

    function test_checkPrice_falseOnStaleData() public {
        bytes32 id = _registerPrice(decomposer, ETH_3500, WatcherRegistry.ComparisonOp.LT);
        vm.prank(owner);
        mockFeed.dropPrice(ETH_3400);
        // Warp 2 hours — price data becomes stale
        vm.warp(block.timestamp + 7201);
        assertFalse(registry.checkPriceWatcher(id));
    }

    function test_checkPrice_revertsOnWrongType() public {
        bytes memory params = _timeParams(3600, 0);
        vm.prank(user);
        bytes32 id = registry.registerWatcher(
            PARENT_ID, user, WatcherRegistry.WatcherType.TIME,
            params, abi.encode("rebalance"), block.timestamp + 7 days
        );
        vm.expectRevert(WatcherRegistry.InvalidWatcherType.selector);
        registry.checkPriceWatcher(id);
    }

    // ── checkTimeWatcher ──────────────────────────────────────────

    function test_checkTime_falseBeforeInterval() public {
        bytes memory params = _timeParams(3600, 0);
        vm.prank(user);
        bytes32 id = registry.registerWatcher(
            PARENT_ID, user, WatcherRegistry.WatcherType.TIME,
            params, abi.encode("rebalance"), block.timestamp + 7 days
        );
        assertFalse(registry.checkTimeWatcher(id));
    }

    function test_checkTime_trueAfterInterval() public {
        bytes memory params = _timeParams(3600, 0);
        vm.prank(user);
        bytes32 id = registry.registerWatcher(
            PARENT_ID, user, WatcherRegistry.WatcherType.TIME,
            params, abi.encode("rebalance"), block.timestamp + 7 days
        );
        vm.warp(block.timestamp + 3601);
        assertTrue(registry.checkTimeWatcher(id));
    }

    // ── triggerWatcher ────────────────────────────────────────────

    function test_trigger_returnsAction() public {
        bytes32 id = _registerPrice(decomposer, ETH_3500, WatcherRegistry.ComparisonOp.LT);
        vm.prank(owner);
        mockFeed.dropPrice(ETH_3400);

        vm.prank(executor);
        bytes memory action = registry.triggerWatcher(id);
        assertEq(action, abi.encode("exit"));

        WatcherRegistry.Watcher memory w = registry.getWatcher(id);
        assertEq(uint8(w.status), uint8(WatcherRegistry.WatcherStatus.TRIGGERED));
        assertEq(registry.getActiveWatcherCount(), 0);
    }

    function test_trigger_revertsIfNotExecutor() public {
        bytes32 id = _registerPrice(decomposer, ETH_3500, WatcherRegistry.ComparisonOp.LT);
        vm.prank(stranger);
        vm.expectRevert(WatcherRegistry.Unauthorized.selector);
        registry.triggerWatcher(id);
    }

    function test_trigger_revertsIfAlreadyTriggered() public {
        bytes32 id = _registerPrice(decomposer, ETH_3500, WatcherRegistry.ComparisonOp.LT);
        vm.prank(owner);
        mockFeed.dropPrice(ETH_3400);
        vm.startPrank(executor);
        registry.triggerWatcher(id);
        vm.expectRevert(WatcherRegistry.WatcherNotActive.selector);
        registry.triggerWatcher(id);
        vm.stopPrank();
    }

    // ── TIME re-arm logic ─────────────────────────────────────────

    function test_timeWatcher_rearmsUntilMaxTriggers() public {
        bytes memory params = _timeParams(3600, 2); // max 2 triggers
        vm.prank(user);
        bytes32 id = registry.registerWatcher(
            PARENT_ID, user, WatcherRegistry.WatcherType.TIME,
            params, abi.encode("rebalance"), block.timestamp + 7 days
        );

        // First trigger — should re-arm
        vm.warp(block.timestamp + 3601);
        vm.prank(executor);
        registry.triggerWatcher(id);
        assertEq(uint8(registry.getWatcher(id).status), uint8(WatcherRegistry.WatcherStatus.ACTIVE));
        assertEq(registry.getActiveWatcherCount(), 1);

        // Second trigger — hits maxTriggers, deactivates
        vm.warp(block.timestamp + 3601);
        vm.prank(executor);
        registry.triggerWatcher(id);
        assertEq(uint8(registry.getWatcher(id).status), uint8(WatcherRegistry.WatcherStatus.TRIGGERED));
        assertEq(registry.getActiveWatcherCount(), 0);
    }

    // ── cancelWatcher ─────────────────────────────────────────────

    function test_cancel_byOwner() public {
        bytes32 id = _registerPrice(user, ETH_3500, WatcherRegistry.ComparisonOp.LT);
        vm.prank(user);
        registry.cancelWatcher(id);
        assertEq(uint8(registry.getWatcher(id).status), uint8(WatcherRegistry.WatcherStatus.CANCELLED));
        assertEq(registry.getActiveWatcherCount(), 0);
    }

    function test_cancel_revertsIfNotOwner() public {
        bytes32 id = _registerPrice(user, ETH_3500, WatcherRegistry.ComparisonOp.LT);
        vm.prank(stranger);
        vm.expectRevert(WatcherRegistry.NotWatcherOwner.selector);
        registry.cancelWatcher(id);
    }

    function test_cancel_revertsIfAlreadyCancelled() public {
        bytes32 id = _registerPrice(user, ETH_3500, WatcherRegistry.ComparisonOp.LT);
        vm.startPrank(user);
        registry.cancelWatcher(id);
        vm.expectRevert(WatcherRegistry.WatcherNotActive.selector);
        registry.cancelWatcher(id);
        vm.stopPrank();
    }

    // ── active list integrity ─────────────────────────────────────

    function test_activeList_staysConsistentAfterRemovals() public {
        bytes32 id1 = _registerPrice(user, ETH_3500, WatcherRegistry.ComparisonOp.LT);
        vm.warp(block.timestamp + 1);
        bytes32 id2 = _registerPrice(user, ETH_3500, WatcherRegistry.ComparisonOp.LT);
        vm.warp(block.timestamp + 1);
        bytes32 id3 = _registerPrice(user, ETH_3500, WatcherRegistry.ComparisonOp.LT);

        assertEq(registry.getActiveWatcherCount(), 3);

        // Cancel middle one
        vm.prank(user);
        registry.cancelWatcher(id2);
        assertEq(registry.getActiveWatcherCount(), 2);

        // Remaining IDs should all be ACTIVE
        bytes32[] memory remaining = registry.getActiveWatcherIds();
        for (uint256 i; i < remaining.length; i++) {
            assertEq(uint8(registry.getWatcher(remaining[i]).status), uint8(WatcherRegistry.WatcherStatus.ACTIVE));
        }

        // Cancel last
        vm.prank(user);
        registry.cancelWatcher(id3);
        assertEq(registry.getActiveWatcherCount(), 1);

        // Cancel first
        vm.prank(user);
        registry.cancelWatcher(id1);
        assertEq(registry.getActiveWatcherCount(), 0);
    }

    function test_getUserActiveWatchers_filtersCorrectly() public {
        bytes32 id1 = _registerPrice(user, ETH_3500, WatcherRegistry.ComparisonOp.LT);
        vm.warp(block.timestamp + 1);
        _registerPrice(user, ETH_3500, WatcherRegistry.ComparisonOp.LT);

        vm.prank(user);
        registry.cancelWatcher(id1);

        bytes32[] memory active = registry.getUserActiveWatchers(user);
        assertEq(active.length, 1);
    }
}
