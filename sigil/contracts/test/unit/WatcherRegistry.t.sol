// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../../src/WatcherRegistry.sol";
import "../../src/IntentDecomposer.sol";
import "../../src/interfaces/IERC8004.sol";
import "../mocks/MockChainlinkFeed.sol";

contract WatcherRegistryTest is Test {
    WatcherRegistry public registry;
    IntentDecomposer public decomposer;
    ERC8004Registry public agentRegistry;
    MockChainlinkFeed public ethFeed;

    address public aiAgent;
    address public user;
    address public executor;

    function setUp() public {
        user = makeAddr("user");
        aiAgent = makeAddr("aiAgent");
        executor = makeAddr("executor");

        // Deploy agent registry
        agentRegistry = new ERC8004Registry();
        agentRegistry.registerAgent(aiAgent, agentRegistry.INTENT_DECOMPOSER(), "ipfs://test");

        // Deploy IntentDecomposer
        decomposer = new IntentDecomposer(aiAgent, address(agentRegistry), address(this));

        // Deploy WatcherRegistry
        registry = new WatcherRegistry(address(decomposer), address(this));

        // Set registry in decomposer
        decomposer.setWatcherRegistry(address(registry));

        // Deploy mock price feed
        ethFeed = new MockChainlinkFeed(8); // 8 decimals
        ethFeed.setPrice(3500e8); // $3500

        // Add price feed
        registry.addPriceFeed("ETH/USD", address(ethFeed));

        // Authorize executor
        registry.addAuthorizedExecutor(executor);
    }

    function testRegisterPriceWatcher() public {
        // Create price watcher params: trigger if ETH > $4000
        Types.PriceParams memory priceParams = Types.PriceParams({
            priceFeed: address(ethFeed),
            threshold: 4000e8,
            comparison: Types.ComparisonOp.GT,
            decimals: 8
        });

        bytes memory params = abi.encode(priceParams);
        bytes memory action = abi.encode("exit_position");

        // Register watcher (as IntentDecomposer)
        vm.prank(address(decomposer));
        bytes32 watcherId = registry.registerWatcher(
            bytes32(uint256(1)), // parentIntentId
            user,
            Types.WatcherType.PRICE,
            params,
            action,
            block.timestamp + 1 days
        );

        // Verify watcher was created
        Types.Watcher memory watcher = registry.getWatcher(watcherId);
        assertEq(watcher.owner, user);
        assertEq(uint(watcher.watcherType), uint(Types.WatcherType.PRICE));
        assertEq(uint(watcher.status), uint(Types.WatcherStatus.ACTIVE));
    }

    function testCheckPriceWatcherAbove() public {
        // Register watcher: trigger if ETH > $3000
        Types.PriceParams memory priceParams = Types.PriceParams({
            priceFeed: address(ethFeed),
            threshold: 3000e8,
            comparison: Types.ComparisonOp.GT,
            decimals: 8
        });

        vm.prank(address(decomposer));
        bytes32 watcherId = registry.registerWatcher(
            bytes32(uint256(1)),
            user,
            Types.WatcherType.PRICE,
            abi.encode(priceParams),
            "",
            block.timestamp + 1 days
        );

        // Current price is $3500, should trigger (> $3000)
        bool shouldTrigger = registry.checkPriceWatcher(watcherId);
        assertTrue(shouldTrigger);

        // Change price to $2500
        ethFeed.setPrice(2500e8);
        shouldTrigger = registry.checkPriceWatcher(watcherId);
        assertFalse(shouldTrigger);
    }

    function testCheckPriceWatcherBelow() public {
        // Register watcher: trigger if ETH < $3000
        Types.PriceParams memory priceParams = Types.PriceParams({
            priceFeed: address(ethFeed),
            threshold: 3000e8,
            comparison: Types.ComparisonOp.LT,
            decimals: 8
        });

        vm.prank(address(decomposer));
        bytes32 watcherId = registry.registerWatcher(
            bytes32(uint256(1)),
            user,
            Types.WatcherType.PRICE,
            abi.encode(priceParams),
            "",
            block.timestamp + 1 days
        );

        // Current price is $3500, should not trigger (not < $3000)
        bool shouldTrigger = registry.checkPriceWatcher(watcherId);
        assertFalse(shouldTrigger);

        // Change price to $2500
        ethFeed.setPrice(2500e8);
        shouldTrigger = registry.checkPriceWatcher(watcherId);
        assertTrue(shouldTrigger);
    }

    function testCheckTimeWatcher() public {
        // Register time watcher: trigger every 1 hour
        Types.TimeParams memory timeParams = Types.TimeParams({
            interval: 1 hours,
            nextTrigger: block.timestamp + 1 hours,
            maxTriggers: 0, // unlimited
            triggerCount: 0
        });

        vm.prank(address(decomposer));
        bytes32 watcherId = registry.registerWatcher(
            bytes32(uint256(1)),
            user,
            Types.WatcherType.TIME,
            abi.encode(timeParams),
            "",
            block.timestamp + 1 days
        );

        // Should not trigger yet
        bool shouldTrigger = registry.checkTimeWatcher(watcherId);
        assertFalse(shouldTrigger);

        // Warp time forward
        vm.warp(block.timestamp + 1 hours + 1);

        // Should trigger now
        shouldTrigger = registry.checkTimeWatcher(watcherId);
        assertTrue(shouldTrigger);
    }

    function testTriggerWatcher() public {
        // Register watcher
        Types.PriceParams memory priceParams = Types.PriceParams({
            priceFeed: address(ethFeed),
            threshold: 3000e8,
            comparison: Types.ComparisonOp.GT,
            decimals: 8
        });

        bytes memory action = abi.encode("exit_position");

        vm.prank(address(decomposer));
        bytes32 watcherId = registry.registerWatcher(
            bytes32(uint256(1)),
            user,
            Types.WatcherType.PRICE,
            abi.encode(priceParams),
            action,
            block.timestamp + 1 days
        );

        // Trigger watcher (as executor)
        vm.prank(executor);
        (bytes memory returnedAction, address owner) = registry.triggerWatcher(watcherId);

        assertEq(owner, user);
        assertEq(returnedAction, action);

        // Verify status changed
        Types.Watcher memory watcher = registry.getWatcher(watcherId);
        assertEq(uint(watcher.status), uint(Types.WatcherStatus.TRIGGERED));
    }

    function testTriggerWatcherUnauthorized() public {
        // Register watcher
        vm.prank(address(decomposer));
        bytes32 watcherId = registry.registerWatcher(
            bytes32(uint256(1)),
            user,
            Types.WatcherType.PRICE,
            abi.encode(Types.PriceParams(address(ethFeed), 3000e8, Types.ComparisonOp.GT, 8)),
            "",
            block.timestamp + 1 days
        );

        // Try to trigger as non-executor
        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert("WatcherRegistry: not authorized executor");
        registry.triggerWatcher(watcherId);
    }

    function testCancelWatcher() public {
        // Register watcher
        vm.prank(address(decomposer));
        bytes32 watcherId = registry.registerWatcher(
            bytes32(uint256(1)),
            user,
            Types.WatcherType.PRICE,
            abi.encode(Types.PriceParams(address(ethFeed), 3000e8, Types.ComparisonOp.GT, 8)),
            "",
            block.timestamp + 1 days
        );

        // Cancel as owner
        vm.prank(user);
        registry.cancelWatcher(watcherId);

        // Verify status
        Types.Watcher memory watcher = registry.getWatcher(watcherId);
        assertEq(uint(watcher.status), uint(Types.WatcherStatus.CANCELLED));
    }

    function testBatchCheckWatchers() public {
        // Register multiple watchers
        bytes32[] memory watcherIds = new bytes32[](3);

        Types.PriceParams memory priceParams1 = Types.PriceParams({
            priceFeed: address(ethFeed),
            threshold: 3000e8, // Current: $3500, should trigger (GT)
            comparison: Types.ComparisonOp.GT,
            decimals: 8
        });

        Types.PriceParams memory priceParams2 = Types.PriceParams({
            priceFeed: address(ethFeed),
            threshold: 4000e8, // Current: $3500, should NOT trigger (GT)
            comparison: Types.ComparisonOp.GT,
            decimals: 8
        });

        Types.PriceParams memory priceParams3 = Types.PriceParams({
            priceFeed: address(ethFeed),
            threshold: 3000e8, // Current: $3500, should NOT trigger (LT)
            comparison: Types.ComparisonOp.LT,
            decimals: 8
        });

        vm.startPrank(address(decomposer));
        watcherIds[0] = registry.registerWatcher(
            bytes32(uint256(1)),
            user,
            Types.WatcherType.PRICE,
            abi.encode(priceParams1),
            "",
            block.timestamp + 1 days
        );
        watcherIds[1] = registry.registerWatcher(
            bytes32(uint256(2)),
            user,
            Types.WatcherType.PRICE,
            abi.encode(priceParams2),
            "",
            block.timestamp + 1 days
        );
        watcherIds[2] = registry.registerWatcher(
            bytes32(uint256(3)),
            user,
            Types.WatcherType.PRICE,
            abi.encode(priceParams3),
            "",
            block.timestamp + 1 days
        );
        vm.stopPrank();

        // Batch check
        bool[] memory results = registry.checkWatchers(watcherIds);

        assertTrue(results[0]);  // Should trigger
        assertFalse(results[1]); // Should not trigger
        assertFalse(results[2]); // Should not trigger
    }

    function testGetUserActiveWatchers() public {
        // Register multiple watchers
        vm.startPrank(address(decomposer));
        bytes32 watcher1 = registry.registerWatcher(
            bytes32(uint256(1)),
            user,
            Types.WatcherType.PRICE,
            abi.encode(Types.PriceParams(address(ethFeed), 3000e8, Types.ComparisonOp.GT, 8)),
            "",
            block.timestamp + 1 days
        );
        bytes32 watcher2 = registry.registerWatcher(
            bytes32(uint256(2)),
            user,
            Types.WatcherType.PRICE,
            abi.encode(Types.PriceParams(address(ethFeed), 4000e8, Types.ComparisonOp.GT, 8)),
            "",
            block.timestamp + 1 days
        );
        vm.stopPrank();

        // Get active watchers
        bytes32[] memory activeWatchers = registry.getUserActiveWatchers(user);
        assertEq(activeWatchers.length, 2);

        // Cancel one
        vm.prank(user);
        registry.cancelWatcher(watcher1);

        // Should have only 1 now
        activeWatchers = registry.getUserActiveWatchers(user);
        assertEq(activeWatchers.length, 1);
        assertEq(activeWatchers[0], watcher2);
    }

    function testStaleDataProtection() public {
        // Warp forward to avoid underflow
        vm.warp(block.timestamp + 3 hours);

        // Set price feed data to be stale (> 1 hour old)
        ethFeed.setUpdatedAt(block.timestamp - 2 hours);

        // Register watcher
        vm.prank(address(decomposer));
        bytes32 watcherId = registry.registerWatcher(
            bytes32(uint256(1)),
            user,
            Types.WatcherType.PRICE,
            abi.encode(Types.PriceParams(address(ethFeed), 3000e8, Types.ComparisonOp.GT, 8)),
            "",
            block.timestamp + 1 days
        );

        // Should not trigger due to stale data
        bool shouldTrigger = registry.checkPriceWatcher(watcherId);
        assertFalse(shouldTrigger);
    }

    function testCleanupExpiredWatchers() public {
        // Register watcher with short expiry (must be > block.timestamp + 1 hour)
        vm.prank(address(decomposer));
        bytes32 watcherId = registry.registerWatcher(
            bytes32(uint256(1)),
            user,
            Types.WatcherType.PRICE,
            abi.encode(Types.PriceParams(address(ethFeed), 3000e8, Types.ComparisonOp.GT, 8)),
            "",
            block.timestamp + 2 hours // Must be > minExpiryDuration (1 hour)
        );

        // Warp past expiry
        vm.warp(block.timestamp + 3 hours);

        // Cleanup
        bytes32[] memory watchersToClean = new bytes32[](1);
        watchersToClean[0] = watcherId;
        registry.cleanupExpiredWatchers(watchersToClean);

        // Verify status
        Types.Watcher memory watcher = registry.getWatcher(watcherId);
        assertEq(uint(watcher.status), uint(Types.WatcherStatus.EXPIRED));
    }
}
