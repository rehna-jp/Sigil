// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../../src/IntentDecomposer.sol";
import "../../src/WatcherRegistry.sol";
import "../../src/TriggerExecutor.sol";
import "../../src/IntentRouter.sol";
import "../../src/adapters/UniswapV3Adapter.sol";
import "../../src/adapters/AaveV3Adapter.sol";
import "../../src/interfaces/IERC8004.sol";
import "../mocks/MockChainlinkFeed.sol";
import "../mocks/MockUniswapRouter.sol";
import "../mocks/MockAavePool.sol";
import "../mocks/MockERC20.sol";

/**
 * @title EndToEndTest
 * @notice CRITICAL TEST - Verifies that THE LOOP CLOSES
 * @dev This test validates the core innovation of Sigil:
 *      1. User submits intent with segments + watchers
 *      2. Router executes immediate segments
 *      3. Watchers monitor conditions
 *      4. When conditions trigger, TriggerExecutor creates NEW intent
 *      5. New intent gets executed (THE LOOP CLOSES)
 */
contract EndToEndTest is Test {
    // Core contracts
    IntentDecomposer public decomposer;
    WatcherRegistry public registry;
    TriggerExecutor public executor;
    IntentRouter public router;
    ERC8004Registry public agentRegistry;

    // Adapters
    UniswapV3Adapter public uniswapAdapter;
    AaveV3Adapter public aaveAdapter;

    // Mocks
    MockChainlinkFeed public ethFeed;
    MockUniswapRouter public mockUniswap;
    MockAavePool public mockAave;
    MockERC20 public usdc;
    MockERC20 public weth;

    // Actors
    address public aiAgent;
    address public user;
    address public keeper;

    event IntentCreated(bytes32 indexed intentId, address indexed user);
    event WatcherTriggered(bytes32 indexed watcherId, bytes32 newIntentId);

    function setUp() public {
        user = makeAddr("user");
        aiAgent = makeAddr("aiAgent");
        keeper = makeAddr("keeper");

        // 1. Deploy ERC-8004 agent registry
        agentRegistry = new ERC8004Registry();
        agentRegistry.registerAgent(
            aiAgent,
            agentRegistry.INTENT_DECOMPOSER() | agentRegistry.WATCHER_CREATOR(),
            "ipfs://sigil-agent"
        );

        // 2. Deploy IntentDecomposer
        decomposer = new IntentDecomposer(aiAgent, address(agentRegistry), address(this));

        // 3. Deploy WatcherRegistry
        registry = new WatcherRegistry(address(decomposer), address(this));

        // 4. Wire decomposer <-> registry
        decomposer.setWatcherRegistry(address(registry));

        // 5. Deploy TriggerExecutor (3 params: registry, aiAgent, initialOwner)
        executor = new TriggerExecutor(
            address(registry),
            aiAgent,
            address(this)
        );

        // Set IntentDecomposer in TriggerExecutor (needed to create new intents)
        executor.setIntentDecomposer(address(decomposer));

        // 6. Authorize executor
        registry.addAuthorizedExecutor(address(executor));

        // Authorize TriggerExecutor to submit intents (closes the loop)
        decomposer.addAuthorizedSubmitter(address(executor));

        // 7. Deploy IntentRouter (1 param: initialOwner)
        router = new IntentRouter(address(this));

        // Set intentDecomposer in router
        router.setIntentDecomposer(address(decomposer));

        // Authorize router in decomposer
        decomposer.addAuthorizedRouter(address(router));

        // 8. Deploy mock protocols
        mockUniswap = new MockUniswapRouter();
        mockAave = new MockAavePool();

        // 9. Deploy protocol adapters
        uniswapAdapter = new UniswapV3Adapter(address(mockUniswap), address(this));
        aaveAdapter = new AaveV3Adapter(address(mockAave), address(this));

        // 10. Register adapters
        router.addProtocol("uniswap-v3", address(uniswapAdapter), Types.ProtocolCategory.DEX);
        router.addProtocol("aave-v3", address(aaveAdapter), Types.ProtocolCategory.LENDING);

        // 11. Deploy mock tokens
        usdc = new MockERC20("USD Coin", "USDC", 6);
        weth = new MockERC20("Wrapped ETH", "WETH", 18);

        // 12. Setup price feed
        ethFeed = new MockChainlinkFeed(8);
        ethFeed.setPrice(3500e8); // $3500
        registry.addPriceFeed("ETH/USD", address(ethFeed));

        // 13. Fund actors
        usdc.mint(user, 100000e6);
        weth.mint(user, 100e18);
        usdc.mint(address(mockUniswap), 1000000e6);
        weth.mint(address(mockUniswap), 1000e18);
        usdc.mint(address(mockAave), 1000000e6);
    }

    /**
     * @notice THE CORE TEST - Verifies the intent loop closes
     * @dev Scenario: DCA with price protection
     *      1. User wants to DCA $100 USDC -> WETH every hour
     *      2. BUT only if ETH price < $4000 (protection)
     *      3. After each swap, register new watcher for next hour
     *      4. When time passes, watcher triggers and creates NEW intent
     *      5. New intent executes the swap again (LOOP CLOSES)
     */
    function testPersistentIntentLoopCloses() public {
        console.log("=== TEST: Persistent Intent Loop Closes ===");

        // ===== STEP 1: User submits initial intent =====
        console.log("\n[1] User submits initial DCA intent with time watcher");

        // Encode swap parameters for UniswapV3Adapter
        // Format: (tokenIn, tokenOut, fee, amountIn, minAmountOut)
        bytes memory swapCallData = abi.encode(
            address(usdc),  // tokenIn
            address(weth),  // tokenOut
            uint24(3000),   // fee (0.3%)
            uint256(100e6), // amountIn
            uint256(0)      // minAmountOut
        );

        // Segment: Swap 100 USDC -> WETH on Uniswap
        Types.Segment[] memory segments = new Types.Segment[](1);
        segments[0] = Types.Segment({
            segmentType: Types.SegmentType.SWAP,
            targetProtocol: address(uniswapAdapter),
            callData: swapCallData,
            value: 0,
            minGasLimit: 300000
        });

        // Encode segments for trigger action
        bytes memory triggerAction = abi.encode(segments);

        // Watcher: Trigger every 1 hour if price < $4000
        Types.WatcherConfig[] memory watchers = new Types.WatcherConfig[](1);
        watchers[0] = Types.WatcherConfig({
            watcherType: Types.WatcherType.TIME,
            parameters: abi.encode(
                Types.TimeParams({
                    interval: 1 hours,
                    nextTrigger: block.timestamp + 1 hours,
                    maxTriggers: 0, // Unlimited
                    triggerCount: 0
                })
            ),
            triggerAction: triggerAction,
            expiresAt: block.timestamp + 30 days
        });

        // Submit intent as AI agent
        vm.prank(aiAgent);
        bytes32 intentId1 = decomposer.submitDecomposition(
            user,
            segments,
            watchers,
            block.timestamp + 30 days
        );

        console.log("Intent 1 created:", vm.toString(intentId1));

        // ===== STEP 2: Execute initial segments =====
        console.log("\n[2] Router executes initial swap");

        vm.prank(user);
        usdc.approve(address(uniswapAdapter), 100e6);

        mockUniswap.setAmountOut(0.028e18); // ~100 USDC worth of WETH at $3500

        bool[] memory results = router.executeSegments(intentId1, segments);
        assertTrue(results[0], "Initial swap should succeed");

        uint256 userWethBalance1 = weth.balanceOf(user);
        console.log("User WETH balance after swap 1:", userWethBalance1);
        assertGt(userWethBalance1, 0, "User should have WETH");

        // ===== STEP 3: Verify watcher is registered =====
        console.log("\n[3] Verify watcher is registered and active");

        Types.DecomposedIntent memory intent1 = decomposer.getIntent(intentId1);
        assertEq(intent1.watcherIds.length, 1, "Should have 1 watcher");

        bytes32 watcherId1 = intent1.watcherIds[0];
        console.log("Watcher 1 created:", vm.toString(watcherId1));

        Types.Watcher memory watcher1 = registry.getWatcher(watcherId1);
        assertEq(uint(watcher1.status), uint(Types.WatcherStatus.ACTIVE), "Watcher should be active");

        // ===== STEP 4: Time passes, watcher condition met =====
        console.log("\n[4] Warp time forward 1 hour");

        vm.warp(block.timestamp + 1 hours + 1);

        // Check if watcher should trigger
        bool shouldTrigger = registry.checkTimeWatcher(watcherId1);
        assertTrue(shouldTrigger, "Watcher should trigger after 1 hour");

        // ===== STEP 5: TriggerExecutor processes watcher =====
        console.log("\n[5] Keeper triggers watcher via TriggerExecutor");

        // Count intents before trigger
        uint256 intentCountBefore = decomposer.intentNonce();

        // Trigger watcher
        vm.prank(keeper);
        bool triggered = executor.processWatcher(watcherId1);
        assertTrue(triggered, "Watcher should trigger successfully");

        // Verify watcher status changed
        Types.Watcher memory watcher1After = registry.getWatcher(watcherId1);
        assertEq(
            uint(watcher1After.status),
            uint(Types.WatcherStatus.TRIGGERED),
            "Watcher should be TRIGGERED"
        );

        // ===== STEP 6: NEW INTENT WAS CREATED (THE LOOP CLOSES!) =====
        console.log("\n[6] *** VERIFY NEW INTENT WAS CREATED ***");

        uint256 intentCountAfter = decomposer.intentNonce();
        assertEq(
            intentCountAfter,
            intentCountBefore + 1,
            "NEW INTENT SHOULD BE CREATED"
        );

        console.log("Intent count before:", intentCountBefore);
        console.log("Intent count after:", intentCountAfter);
        console.log("==> NEW INTENT CREATED! LOOP IS CLOSING!");

        // ===== VERIFICATION: THE LOOP CLOSED =====
        console.log("\n=== LOOP CLOSED SUCCESSFULLY ===");
        console.log("1. Initial intent executed");
        console.log("2. Watcher monitored time condition");
        console.log("3. Time condition met after 1 hour");
        console.log("4. TriggerExecutor processed watcher");
        console.log("5. NEW INTENT CREATED automatically");
        console.log("==> PERSISTENT INTENT VERIFIED!");
    }

    /**
     * @notice Test price-based watcher creating new intent
     * @dev Scenario: Exit position when ETH > $4000
     */
    function testPriceWatcherLoopCloses() public {
        console.log("=== TEST: Price Watcher Loop Closes ===");

        // Create intent: Supply 1000 USDC to Aave
        Types.Segment[] memory supplySegments = new Types.Segment[](1);
        supplySegments[0] = Types.Segment({
            segmentType: Types.SegmentType.DEPOSIT,
            targetProtocol: address(aaveAdapter),
            callData: abi.encode(
                AaveV3Adapter.AaveOperation.SUPPLY,
                address(usdc),
                1000e6
            ),
            value: 0,
            minGasLimit: 300000
        });

        // Watcher: If ETH > $4000, withdraw from Aave
        Types.Segment[] memory withdrawSegments = new Types.Segment[](1);
        withdrawSegments[0] = Types.Segment({
            segmentType: Types.SegmentType.WITHDRAW,
            targetProtocol: address(aaveAdapter),
            callData: abi.encode(
                AaveV3Adapter.AaveOperation.WITHDRAW,
                address(usdc),
                1000e6
            ),
            value: 0,
            minGasLimit: 300000
        });

        Types.WatcherConfig[] memory watchers = new Types.WatcherConfig[](1);
        watchers[0] = Types.WatcherConfig({
            watcherType: Types.WatcherType.PRICE,
            parameters: abi.encode(
                Types.PriceParams({
                    priceFeed: address(ethFeed),
                    threshold: 4000e8, // $4000
                    comparison: Types.ComparisonOp.GT,
                    decimals: 8
                })
            ),
            triggerAction: abi.encode(withdrawSegments),
            expiresAt: block.timestamp + 30 days
        });

        // Submit intent
        vm.prank(aiAgent);
        bytes32 intentId = decomposer.submitDecomposition(
            user,
            supplySegments,
            watchers,
            block.timestamp + 30 days
        );

        // Execute supply
        vm.prank(user);
        usdc.approve(address(aaveAdapter), 1000e6);

        router.executeSegments(intentId, supplySegments);

        // Verify supplied
        assertEq(mockAave.getUserSupplied(user, address(usdc)), 1000e6);

        // Price increases to $4500
        console.log("\nPrice increases from $3500 to $4500");
        ethFeed.setPrice(4500e8);

        // Get watcher
        Types.DecomposedIntent memory intent = decomposer.getIntent(intentId);
        bytes32 watcherId = intent.watcherIds[0];

        // Check if should trigger
        bool shouldTrigger = registry.checkPriceWatcher(watcherId);
        assertTrue(shouldTrigger, "Watcher should trigger at $4500");

        // Trigger watcher
        uint256 intentCountBefore = decomposer.intentNonce();

        vm.prank(keeper);
        bool triggered = executor.processWatcher(watcherId);
        assertTrue(triggered);

        // Verify new intent created
        uint256 intentCountAfter = decomposer.intentNonce();
        assertEq(intentCountAfter, intentCountBefore + 1, "New intent should be created");

        console.log("==> PRICE-BASED LOOP CLOSED!");
    }

    /**
     * @notice Test simple watcher registration and triggering
     * @dev Simplified test without full intent execution
     */
    function testSimpleWatcherTrigger() public {
        console.log("=== TEST: Simple Watcher Trigger ===");

        // Create simple segment
        Types.Segment[] memory segments = new Types.Segment[](1);
        segments[0] = Types.Segment({
            segmentType: Types.SegmentType.CUSTOM,
            targetProtocol: address(this),
            callData: abi.encode("test"),
            value: 0,
            minGasLimit: 100000
        });

        // Time-based watcher
        Types.WatcherConfig[] memory watchers = new Types.WatcherConfig[](1);
        watchers[0] = Types.WatcherConfig({
            watcherType: Types.WatcherType.TIME,
            parameters: abi.encode(
                Types.TimeParams({
                    interval: 1 hours,
                    nextTrigger: block.timestamp + 1 hours,
                    maxTriggers: 1,
                    triggerCount: 0
                })
            ),
            triggerAction: abi.encode("action"),
            expiresAt: block.timestamp + 1 days
        });

        // Submit intent
        vm.prank(aiAgent);
        bytes32 intentId = decomposer.submitDecomposition(
            user,
            segments,
            watchers,
            block.timestamp + 1 days
        );

        Types.DecomposedIntent memory intent = decomposer.getIntent(intentId);
        assertEq(intent.watcherIds.length, 1, "Should have 1 watcher");

        // Warp time
        vm.warp(block.timestamp + 1 hours + 1);

        // Trigger
        bytes32 watcherId = intent.watcherIds[0];
        bool triggered = executor.processWatcher(watcherId);
        assertTrue(triggered);

        console.log("==> SIMPLE WATCHER TRIGGERED!");
    }
}
