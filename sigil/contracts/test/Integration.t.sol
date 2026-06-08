// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {IntentDecomposer} from "../src/IntentDecomposer.sol";
import {WatcherRegistry} from "../src/WatcherRegistry.sol";
import {TriggerExecutor} from "../src/TriggerExecutor.sol";
import {IntentRouter} from "../src/IntentRouter.sol";
import {MockPriceFeed} from "../src/mocks/MockPriceFeed.sol";

/// @title Integration - THE LOOP
/// @notice Proves Sigil's core innovation end-to-end:
///
///   1.  AI agent submits decomposed intent (immediate segment + price watcher)
///   2.  Watcher registered on-chain from stored WatcherConfig
///   3.  Keeper checks - price above threshold -> no trigger
///   4.  Price drops below threshold -> keeper checks -> TriggerFired emitted
///   5.  Watcher becomes TRIGGERED, removed from active list
///   6.  triggerAction data ready for AI backend to create the next intent
///
///   The loop: Intent -> Execute -> Watch -> Trigger -> New Intent -> ...
///
///   This is what makes Sigil different from CoW, UniswapX, Anoma, Gelato.
///   Every other system: intent executes -> done.
///   Sigil: intent executes -> watcher lives -> condition met -> new intent fires.
contract IntegrationTest is Test {
    IntentDecomposer decomposer;
    WatcherRegistry  registry;
    TriggerExecutor  executor;
    IntentRouter     router;
    MockPriceFeed    mockFeed;

    address owner   = makeAddr("owner");
    address aiAgent = makeAddr("aiAgent");
    address user    = makeAddr("user");

    int256 constant ETH_3800 = 380000000000; // $3,800 - start
    int256 constant ETH_3500 = 350000000000; // $3,500 - exit threshold
    int256 constant ETH_3400 = 340000000000; // $3,400 - demo drop price

    function setUp() public {
        vm.startPrank(owner);
        decomposer = new IntentDecomposer(owner);
        registry   = new WatcherRegistry(owner);
        executor   = new TriggerExecutor(address(registry), owner);
        router     = new IntentRouter(address(decomposer), owner);
        mockFeed   = new MockPriceFeed(ETH_3800, 8, "ETH/USD Mock", owner);

        decomposer.setAIAgent(aiAgent);
        decomposer.setIntentRouter(address(router));
        decomposer.setWatcherRegistry(address(registry));
        registry.authorizeExecutor(address(executor));
        registry.setIntentDecomposer(address(decomposer));
        vm.stopPrank();
    }

    // ===============================================================
    //  THE MAIN LOOP TEST
    // ===============================================================

    function test_fullLoop_intentWithPriceWatcher() public {
        console.log("\n  ================================");
        console.log("  SIGIL - THE LOOP TEST");
        console.log("  ================================");

        // ?? Step 1: AI agent submits decomposed intent ??????????
        console.log("\n  [1] AI agent submits decomposed intent...");

        IntentDecomposer.Segment[] memory segments = new IntentDecomposer.Segment[](1);
        segments[0] = IntentDecomposer.Segment({
            segmentType: 1, // DEPOSIT
            protocol: address(0xAa1),
            callData: abi.encodeWithSignature("deposit(uint256)", 1 ether),
            value: 0
        });

        // Exit action the watcher will return when triggered
        bytes memory exitAction = abi.encodeWithSignature("withdraw(uint256)", 1 ether);

        IntentDecomposer.WatcherConfig[] memory watchers = new IntentDecomposer.WatcherConfig[](1);
        watchers[0] = IntentDecomposer.WatcherConfig({
            watcherType: 0, // PRICE
            parameters: abi.encode(WatcherRegistry.PriceParams({
                priceFeed: address(mockFeed),
                threshold: ETH_3500,
                comparison: WatcherRegistry.ComparisonOp.LT
            })),
            triggerAction: exitAction,
            expiry: block.timestamp + 30 days
        });

        vm.prank(aiAgent);
        bytes32 intentId = decomposer.submitDecomposition(user, segments, watchers);
        console.log("  [OK] Intent submitted");

        IntentDecomposer.DecomposedIntent memory intent = decomposer.getIntent(intentId);
        assertTrue(intent.active);
        assertEq(intent.user, user);
        assertEq(intent.segmentCount, 1);
        assertEq(intent.watcherCount, 1);

        // ?? Step 2: Backend registers watcher from stored config ?
        console.log("\n  [2] Backend registers watcher from stored config...");

        IntentDecomposer.WatcherConfig memory wc = decomposer.getWatchers(intentId)[0];

        vm.prank(user);
        bytes32 watcherId = registry.registerWatcher(
            intentId, user,
            WatcherRegistry.WatcherType(wc.watcherType),
            wc.parameters, wc.triggerAction, wc.expiry
        );
        console.log("  [OK] Watcher registered, active count: 1");

        assertEq(registry.getActiveWatcherCount(), 1);
        assertEq(uint8(registry.getWatcher(watcherId).status), uint8(WatcherRegistry.WatcherStatus.ACTIVE));

        // ?? Step 3: Keeper checks - price above threshold ????????
        console.log("\n  [3] Keeper checks at $3,800 - should NOT trigger...");

        assertFalse(registry.checkPriceWatcher(watcherId));
        bool noTrigger = executor.checkAndExecuteSingle(watcherId);
        assertFalse(noTrigger);
        console.log("  [OK] No trigger (correct - price above threshold)");

        // ?? Step 4: Price drops - THE MOMENT ????????????????????
        console.log("\n  [4] ETH drops to $3,400 (below $3,500 threshold)...");

        vm.prank(owner);
        mockFeed.dropPrice(ETH_3400);

        assertEq(mockFeed.getPrice(), ETH_3400);
        assertTrue(registry.checkPriceWatcher(watcherId));
        console.log("  [OK] checkPriceWatcher returns true");

        // ?? Step 5: THE LOOP CLOSES ??????????????????????????????
        console.log("\n  [5] Keeper fires TriggerExecutor - THE LOOP CLOSES...");

        vm.expectEmit(true, false, false, true);
        emit TriggerExecutor.TriggerFired(watcherId, exitAction, block.timestamp);

        bool triggered = executor.checkAndExecuteSingle(watcherId);
        assertTrue(triggered);
        console.log("  [OK] TriggerFired emitted");

        // ?? Step 6: Verify final state ???????????????????????????
        console.log("\n  [6] Verifying final state...");

        WatcherRegistry.Watcher memory w = registry.getWatcher(watcherId);
        assertEq(uint8(w.status), uint8(WatcherRegistry.WatcherStatus.TRIGGERED));
        console.log("  [OK] Watcher status: TRIGGERED");

        assertEq(registry.getActiveWatcherCount(), 0);
        console.log("  [OK] Active watcher count: 0");

        TriggerExecutor.TriggerRecord[] memory history = executor.getTriggerHistory(watcherId);
        assertEq(history.length, 1);
        assertTrue(history[0].success);
        assertEq(history[0].triggerAction, exitAction);
        console.log("  [OK] Trigger history recorded with correct action data");

        assertEq(executor.totalTriggersExecuted(), 1);
        console.log("  [OK] Total triggers executed: 1");

        console.log("\n  ================================");
        console.log("  LOOP CLOSED SUCCESSFULLY");
        console.log("  Intent -> Watch -> Price Drop -> Trigger -> Action");
        console.log("  This is Sigil.");
        console.log("  ================================\n");
    }

    // ?? Supporting tests ?????????????????????????????????????????

    function test_intentWithMultipleWatchers_priceAndTime() public {
        IntentDecomposer.Segment[] memory segments = new IntentDecomposer.Segment[](1);
        segments[0] = IntentDecomposer.Segment({
            segmentType: 1, protocol: address(0x1), callData: bytes(""), value: 0
        });

        IntentDecomposer.WatcherConfig[] memory watchers = new IntentDecomposer.WatcherConfig[](2);
        watchers[0] = IntentDecomposer.WatcherConfig({
            watcherType: 0, // PRICE
            parameters: abi.encode(WatcherRegistry.PriceParams({
                priceFeed: address(mockFeed),
                threshold: ETH_3500,
                comparison: WatcherRegistry.ComparisonOp.LT
            })),
            triggerAction: abi.encode("exit"),
            expiry: block.timestamp + 30 days
        });
        watchers[1] = IntentDecomposer.WatcherConfig({
            watcherType: 3, // TIME
            parameters: abi.encode(WatcherRegistry.TimeParams({
                interval: 86400,
                nextTrigger: block.timestamp + 86400,
                maxTriggers: 0,
                triggerCount: 0
            })),
            triggerAction: abi.encode("rebalance"),
            expiry: block.timestamp + 365 days
        });

        vm.prank(aiAgent);
        bytes32 intentId = decomposer.submitDecomposition(user, segments, watchers);

        IntentDecomposer.WatcherConfig[] memory stored = decomposer.getWatchers(intentId);
        assertEq(stored.length, 2);
        assertEq(stored[0].watcherType, 0); // PRICE
        assertEq(stored[1].watcherType, 3); // TIME
    }

    function test_deactivatedIntent_doesNotBlockWatcherTrigger() public {
        // Watchers are independent from intents in the registry.
        // Deactivating an intent prevents NEW decompositions from being submitted for it,
        // but watchers already registered fire independently.
        // The AI backend is responsible for checking intent.active before creating new intents.

        IntentDecomposer.Segment[] memory segments = new IntentDecomposer.Segment[](1);
        segments[0] = IntentDecomposer.Segment({ segmentType: 0, protocol: address(0x1), callData: bytes(""), value: 0 });

        vm.prank(aiAgent);
        bytes32 intentId = decomposer.submitDecomposition(user, segments, new IntentDecomposer.WatcherConfig[](0));

        bytes memory priceParams = abi.encode(WatcherRegistry.PriceParams({
            priceFeed: address(mockFeed),
            threshold: ETH_3500,
            comparison: WatcherRegistry.ComparisonOp.LT
        }));

        vm.prank(user);
        bytes32 watcherId = registry.registerWatcher(
            intentId, user, WatcherRegistry.WatcherType.PRICE,
            priceParams, abi.encode("exit"), block.timestamp + 30 days
        );

        // User deactivates their intent
        vm.prank(user);
        decomposer.deactivateIntent(intentId);
        assertFalse(decomposer.getIntent(intentId).active);

        // Watcher still active - the registry is independent
        assertEq(uint8(registry.getWatcher(watcherId).status), uint8(WatcherRegistry.WatcherStatus.ACTIVE));
        assertEq(registry.getActiveWatcherCount(), 1);

        // Watcher still fires (AI backend checks intent.active before creating new intent)
        vm.prank(owner);
        mockFeed.dropPrice(ETH_3400);
        bool triggered = executor.checkAndExecuteSingle(watcherId);
        assertTrue(triggered);
    }

    function test_multipleUsers_independentWatchers() public {
        address user2 = makeAddr("user2");

        IntentDecomposer.Segment[] memory seg = new IntentDecomposer.Segment[](1);
        seg[0] = IntentDecomposer.Segment({ segmentType: 0, protocol: address(0x1), callData: bytes(""), value: 0 });

        vm.prank(aiAgent);
        bytes32 intent1 = decomposer.submitDecomposition(user, seg, new IntentDecomposer.WatcherConfig[](0));
        vm.prank(aiAgent);
        bytes32 intent2 = decomposer.submitDecomposition(user2, seg, new IntentDecomposer.WatcherConfig[](0));

        bytes memory params = abi.encode(WatcherRegistry.PriceParams({
            priceFeed: address(mockFeed), threshold: ETH_3500, comparison: WatcherRegistry.ComparisonOp.LT
        }));

        vm.prank(user);
        bytes32 w1 = registry.registerWatcher(intent1, user, WatcherRegistry.WatcherType.PRICE, params, abi.encode("exit1"), block.timestamp + 30 days);
        vm.prank(user2);
        bytes32 w2 = registry.registerWatcher(intent2, user2, WatcherRegistry.WatcherType.PRICE, params, abi.encode("exit2"), block.timestamp + 30 days);

        assertEq(registry.getActiveWatcherCount(), 2);
        assertEq(registry.getUserActiveWatchers(user).length, 1);
        assertEq(registry.getUserActiveWatchers(user2).length, 1);

        // Drop price - both fire
        vm.prank(owner);
        mockFeed.dropPrice(ETH_3400);

        bytes32[] memory batch = new bytes32[](2);
        batch[0] = w1;
        batch[1] = w2;
        uint256 triggered = executor.checkAndExecuteBatch(batch);
        assertEq(triggered, 2);
        assertEq(registry.getActiveWatcherCount(), 0);
    }
}
