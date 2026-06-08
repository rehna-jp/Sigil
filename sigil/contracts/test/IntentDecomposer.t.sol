// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {IntentDecomposer} from "../src/IntentDecomposer.sol";

contract IntentDecomposerTest is Test {
    IntentDecomposer decomposer;

    address owner     = makeAddr("owner");
    address aiAgent   = makeAddr("aiAgent");
    address router    = makeAddr("router");
    address user      = makeAddr("user");
    address stranger  = makeAddr("stranger");

    // ── Helpers ───────────────────────────────────────────────────

    function _seg() internal pure returns (IntentDecomposer.Segment[] memory s) {
        s = new IntentDecomposer.Segment[](1);
        s[0] = IntentDecomposer.Segment({
            segmentType: 0,
            protocol: address(0x1234),
            callData: abi.encode("swap"),
            value: 0
        });
    }

    function _wat() internal view returns (IntentDecomposer.WatcherConfig[] memory w) {
        w = new IntentDecomposer.WatcherConfig[](1);
        w[0] = IntentDecomposer.WatcherConfig({
            watcherType: 0,
            parameters: abi.encode(address(0x5678), int256(350000000000), uint8(1)),
            triggerAction: abi.encode("exit"),
            expiry: block.timestamp + 30 days
        });
    }

    function _submit(IntentDecomposer.Segment[] memory s, IntentDecomposer.WatcherConfig[] memory w)
        internal returns (bytes32)
    {
        vm.prank(aiAgent);
        return decomposer.submitDecomposition(user, s, w);
    }

    // ── Setup ─────────────────────────────────────────────────────

    function setUp() public {
        vm.startPrank(owner);
        decomposer = new IntentDecomposer(owner);
        decomposer.setAIAgent(aiAgent);
        decomposer.setIntentRouter(router);
        vm.stopPrank();
    }

    // ── submitDecomposition ───────────────────────────────────────

    function test_submit_storesIntent() public {
        bytes32 id = _submit(_seg(), _wat());
        IntentDecomposer.DecomposedIntent memory intent = decomposer.getIntent(id);

        assertEq(intent.user, user);
        assertTrue(intent.active);
        assertFalse(intent.executed);
        assertEq(intent.segmentCount, 1);
        assertEq(intent.watcherCount, 1);
    }

    function test_submit_emitsEvent() public {
        vm.prank(aiAgent);
        vm.expectEmit(false, true, false, false);
        emit IntentDecomposer.IntentDecomposed(bytes32(0), user, 1, 1, block.timestamp);
        decomposer.submitDecomposition(user, _seg(), _wat());
    }

    function test_submit_revertsIfNotAgent() public {
        vm.prank(stranger);
        vm.expectRevert(IntentDecomposer.OnlyAIAgent.selector);
        decomposer.submitDecomposition(user, _seg(), _wat());
    }

    function test_submit_revertsOnEmptySegments() public {
        vm.prank(aiAgent);
        vm.expectRevert(IntentDecomposer.EmptySegments.selector);
        decomposer.submitDecomposition(user, new IntentDecomposer.Segment[](0), _wat());
    }

    function test_submit_revertsOnZeroUser() public {
        vm.prank(aiAgent);
        vm.expectRevert(IntentDecomposer.ZeroAddress.selector);
        decomposer.submitDecomposition(address(0), _seg(), _wat());
    }

    function test_submit_uniqueIds() public {
        bytes32 id1 = _submit(_seg(), _wat());
        vm.warp(block.timestamp + 1);
        bytes32 id2 = _submit(_seg(), _wat());
        assertTrue(id1 != id2);
    }

    // ── getSegments / getWatchers ─────────────────────────────────

    function test_getSegments() public {
        bytes32 id = _submit(_seg(), _wat());
        IntentDecomposer.Segment[] memory segs = decomposer.getSegments(id);
        assertEq(segs.length, 1);
        assertEq(segs[0].segmentType, 0);
        assertEq(segs[0].protocol, address(0x1234));
    }

    function test_getWatchers() public {
        bytes32 id = _submit(_seg(), _wat());
        IntentDecomposer.WatcherConfig[] memory wats = decomposer.getWatchers(id);
        assertEq(wats.length, 1);
        assertEq(wats[0].watcherType, 0);
    }

    // ── markExecuted ──────────────────────────────────────────────

    function test_markExecuted_byRouter() public {
        bytes32 id = _submit(_seg(), _wat());
        vm.prank(router);
        decomposer.markExecuted(id);
        assertTrue(decomposer.getIntent(id).executed);
    }

    function test_markExecuted_revertsIfNotRouter() public {
        bytes32 id = _submit(_seg(), _wat());
        vm.prank(stranger);
        vm.expectRevert(IntentDecomposer.OnlyIntentRouter.selector);
        decomposer.markExecuted(id);
    }

    function test_markExecuted_revertsOnDouble() public {
        bytes32 id = _submit(_seg(), _wat());
        vm.startPrank(router);
        decomposer.markExecuted(id);
        vm.expectRevert(IntentDecomposer.IntentAlreadyExecuted.selector);
        decomposer.markExecuted(id);
        vm.stopPrank();
    }

    // ── deactivateIntent ──────────────────────────────────────────

    function test_deactivate_byUser() public {
        bytes32 id = _submit(_seg(), _wat());
        vm.prank(user);
        decomposer.deactivateIntent(id);
        assertFalse(decomposer.getIntent(id).active);
    }

    function test_deactivate_byAgent() public {
        bytes32 id = _submit(_seg(), _wat());
        vm.prank(aiAgent);
        decomposer.deactivateIntent(id);
        assertFalse(decomposer.getIntent(id).active);
    }

    function test_deactivate_revertsIfStranger() public {
        bytes32 id = _submit(_seg(), _wat());
        vm.prank(stranger);
        vm.expectRevert(IntentDecomposer.OnlyIntentOwnerOrAgent.selector);
        decomposer.deactivateIntent(id);
    }

    function test_deactivate_revertsIfAlreadyInactive() public {
        bytes32 id = _submit(_seg(), _wat());
        vm.startPrank(user);
        decomposer.deactivateIntent(id);
        vm.expectRevert(IntentDecomposer.IntentNotActive.selector);
        decomposer.deactivateIntent(id);
        vm.stopPrank();
    }

    // ── getUserIntents ─────────────────────────────────────────────

    function test_getUserIntents_returnsAll() public {
        _submit(_seg(), _wat());
        vm.warp(block.timestamp + 1);
        _submit(_seg(), _wat());
        assertEq(decomposer.getUserIntents(user).length, 2);
    }

    function test_getUserActiveIntents_filtersDeactivated() public {
        bytes32 id1 = _submit(_seg(), _wat());
        vm.warp(block.timestamp + 1);
        _submit(_seg(), _wat());

        vm.prank(user);
        decomposer.deactivateIntent(id1);

        bytes32[] memory active = decomposer.getUserActiveIntents(user);
        assertEq(active.length, 1);
    }
}
