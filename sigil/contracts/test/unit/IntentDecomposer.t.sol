// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../../src/IntentDecomposer.sol";
import "../../src/interfaces/IERC8004.sol";
import "../mocks/MockChainlinkFeed.sol";

contract IntentDecomposerTest is Test {
    IntentDecomposer public decomposer;
    ERC8004Registry public registry;
    address public aiAgent;
    address public user;
    address public router;

    event IntentDecomposed(
        bytes32 indexed intentId,
        address indexed user,
        address indexed submitter,
        uint256 segmentCount,
        uint256 watcherCount,
        uint256 expiresAt
    );

    function setUp() public {
        user = makeAddr("user");
        aiAgent = makeAddr("aiAgent");
        router = makeAddr("router");

        // Deploy registry and register AI agent
        registry = new ERC8004Registry();
        registry.registerAgent(
            aiAgent,
            registry.INTENT_DECOMPOSER(),
            "ipfs://test"
        );

        // Deploy IntentDecomposer
        decomposer = new IntentDecomposer(aiAgent, address(registry), address(this));
    }

    function testSubmitDecomposition() public {
        // Create segments
        Types.Segment[] memory segments = new Types.Segment[](1);
        segments[0] = Types.Segment({
            segmentType: Types.SegmentType.SWAP,
            targetProtocol: address(0x123),
            callData: "",
            value: 0,
            minGasLimit: 100000
        });

        // Create empty watchers
        Types.WatcherConfig[] memory watchers = new Types.WatcherConfig[](0);

        uint256 expiresAt = block.timestamp + 1 days;

        // Submit as AI agent
        vm.prank(aiAgent);
        vm.expectEmit(false, true, true, true);
        emit IntentDecomposed(bytes32(0), user, aiAgent, 1, 0, expiresAt);

        bytes32 intentId = decomposer.submitDecomposition(
            user,
            segments,
            watchers,
            expiresAt
        );

        // Verify intent was created
        Types.DecomposedIntent memory intent = decomposer.getIntent(intentId);
        assertEq(intent.user, user);
        assertEq(intent.submitter, aiAgent);
        assertEq(intent.segmentCount, 1);
        assertEq(uint(intent.status), uint(Types.IntentStatus.PENDING));
    }

    function testSubmitDecompositionOnlyAgent() public {
        Types.Segment[] memory segments = new Types.Segment[](0);
        Types.WatcherConfig[] memory watchers = new Types.WatcherConfig[](0);

        // Try to submit as non-agent (should fail)
        vm.prank(user);
        vm.expectRevert("IntentDecomposer: not authorized");
        decomposer.submitDecomposition(user, segments, watchers, block.timestamp + 1 days);
    }

    function testSubmitDecompositionInvalidExpiry() public {
        Types.Segment[] memory segments = new Types.Segment[](0);
        Types.WatcherConfig[] memory watchers = new Types.WatcherConfig[](0);

        // Try with expiry in past
        vm.prank(aiAgent);
        vm.expectRevert("IntentDecomposer: expiry in past");
        decomposer.submitDecomposition(user, segments, watchers, block.timestamp - 1);

        // Try with expiry too far in future
        vm.prank(aiAgent);
        vm.expectRevert("IntentDecomposer: expiry too far");
        decomposer.submitDecomposition(
            user,
            segments,
            watchers,
            block.timestamp + 366 days
        );
    }

    function testCancelIntent() public {
        // Create and submit intent
        Types.Segment[] memory segments = new Types.Segment[](1);
        segments[0] = Types.Segment({
            segmentType: Types.SegmentType.SWAP,
            targetProtocol: address(0x123),
            callData: "",
            value: 0,
            minGasLimit: 100000
        });
        Types.WatcherConfig[] memory watchers = new Types.WatcherConfig[](0);

        vm.prank(aiAgent);
        bytes32 intentId = decomposer.submitDecomposition(
            user,
            segments,
            watchers,
            block.timestamp + 1 days
        );

        // Cancel as user
        vm.prank(user);
        decomposer.cancelIntent(intentId);

        // Verify status
        Types.DecomposedIntent memory intent = decomposer.getIntent(intentId);
        assertEq(uint(intent.status), uint(Types.IntentStatus.CANCELLED));
    }

    function testCancelIntentUnauthorized() public {
        // Create intent
        Types.Segment[] memory segments = new Types.Segment[](0);
        Types.WatcherConfig[] memory watchers = new Types.WatcherConfig[](0);

        vm.prank(aiAgent);
        bytes32 intentId = decomposer.submitDecomposition(
            user,
            segments,
            watchers,
            block.timestamp + 1 days
        );

        // Try to cancel as different user
        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert("IntentDecomposer: not intent owner");
        decomposer.cancelIntent(intentId);
    }

    function testGetUserIntents() public {
        Types.Segment[] memory segments = new Types.Segment[](0);
        Types.WatcherConfig[] memory watchers = new Types.WatcherConfig[](0);

        // Create multiple intents
        vm.startPrank(aiAgent);
        bytes32 intent1 = decomposer.submitDecomposition(
            user,
            segments,
            watchers,
            block.timestamp + 1 days
        );
        bytes32 intent2 = decomposer.submitDecomposition(
            user,
            segments,
            watchers,
            block.timestamp + 1 days
        );
        vm.stopPrank();

        // Get user intents
        bytes32[] memory userIntents = decomposer.getUserIntents(user);
        assertEq(userIntents.length, 2);
        assertEq(userIntents[0], intent1);
        assertEq(userIntents[1], intent2);
    }

    function testAuthorizeRouter() public {
        assertFalse(decomposer.isAuthorizedRouter(router));

        decomposer.addAuthorizedRouter(router);
        assertTrue(decomposer.isAuthorizedRouter(router));

        decomposer.removeAuthorizedRouter(router);
        assertFalse(decomposer.isAuthorizedRouter(router));
    }

    function testReportSegmentExecution() public {
        // Create intent with segment
        Types.Segment[] memory segments = new Types.Segment[](1);
        segments[0] = Types.Segment({
            segmentType: Types.SegmentType.SWAP,
            targetProtocol: address(0x123),
            callData: "",
            value: 0,
            minGasLimit: 100000
        });
        Types.WatcherConfig[] memory watchers = new Types.WatcherConfig[](0);

        vm.prank(aiAgent);
        bytes32 intentId = decomposer.submitDecomposition(
            user,
            segments,
            watchers,
            block.timestamp + 1 days
        );

        // Authorize router
        decomposer.addAuthorizedRouter(router);

        // Report execution
        vm.prank(router);
        decomposer.reportSegmentExecution(intentId, 0, true, "");

        // Verify status changed to COMPLETED (no watchers)
        Types.DecomposedIntent memory intent = decomposer.getIntent(intentId);
        assertEq(uint(intent.status), uint(Types.IntentStatus.COMPLETED));
    }

    function testPause() public {
        // Pause contract
        decomposer.pause();

        // Try to submit (should fail)
        Types.Segment[] memory segments = new Types.Segment[](0);
        Types.WatcherConfig[] memory watchers = new Types.WatcherConfig[](0);

        vm.prank(aiAgent);
        vm.expectRevert(); // OpenZeppelin v5 uses EnforcedPause() custom error
        decomposer.submitDecomposition(user, segments, watchers, block.timestamp + 1 days);

        // Unpause
        decomposer.unpause();

        // Should work now
        vm.prank(aiAgent);
        decomposer.submitDecomposition(user, segments, watchers, block.timestamp + 1 days);
    }
}
