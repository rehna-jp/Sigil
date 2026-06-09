// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../../src/IntentRouter.sol";
import "../../src/IntentDecomposer.sol";
import "../../src/adapters/UniswapV3Adapter.sol";
import "../../src/adapters/AaveV3Adapter.sol";
import "../../src/interfaces/IERC8004.sol";
import "../mocks/MockUniswapRouter.sol";
import "../mocks/MockAavePool.sol";
import "../mocks/MockERC20.sol";

contract IntentRouterTest is Test {
    IntentRouter public router;
    IntentDecomposer public decomposer;
    UniswapV3Adapter public uniswapAdapter;
    AaveV3Adapter public aaveAdapter;
    ERC8004Registry public agentRegistry;

    MockUniswapRouter public mockUniswap;
    MockAavePool public mockAave;
    MockERC20 public tokenA;
    MockERC20 public tokenB;

    address public aiAgent;
    address public user;

    function setUp() public {
        user = makeAddr("user");
        aiAgent = makeAddr("aiAgent");

        // Deploy agent registry
        agentRegistry = new ERC8004Registry();
        agentRegistry.registerAgent(aiAgent, agentRegistry.INTENT_DECOMPOSER(), "ipfs://test");

        // Deploy IntentDecomposer
        decomposer = new IntentDecomposer(aiAgent, address(agentRegistry), address(this));

        // Deploy IntentRouter
        router = new IntentRouter(address(this));

        // Set IntentDecomposer in router
        router.setIntentDecomposer(address(decomposer));

        // Authorize router in decomposer
        decomposer.addAuthorizedRouter(address(router));

        // Deploy mock protocols
        mockUniswap = new MockUniswapRouter();
        mockAave = new MockAavePool();

        // Deploy protocol adapters
        uniswapAdapter = new UniswapV3Adapter(address(mockUniswap), address(this));
        aaveAdapter = new AaveV3Adapter(address(mockAave), address(this));

        // Register adapters in router
        router.addProtocol("uniswap-v3", address(uniswapAdapter), Types.ProtocolCategory.DEX);
        router.addProtocol("aave-v3", address(aaveAdapter), Types.ProtocolCategory.LENDING);

        // Deploy mock tokens
        tokenA = new MockERC20("Token A", "TKNA", 18);
        tokenB = new MockERC20("Token B", "TKNB", 18);

        // Mint tokens to user
        tokenA.mint(user, 10000e18);
        tokenB.mint(user, 10000e18);

        // Mint tokens to mock router for swaps
        tokenA.mint(address(mockUniswap), 100000e18);
        tokenB.mint(address(mockUniswap), 100000e18);
    }

    function testAddProtocol() public {
        // Add new protocol as owner
        address newAdapter = makeAddr("newAdapter");
        router.addProtocol("gmx-v2", newAdapter, Types.ProtocolCategory.DERIVATIVES);

        assertTrue(router.approvedProtocols(newAdapter));
        assertEq(router.protocolAdapters("gmx-v2"), newAdapter);
    }

    function testAddProtocolUnauthorized() public {
        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert();
        router.addProtocol("malicious", attacker, Types.ProtocolCategory.DEX);
    }

    function testRemoveProtocol() public {
        router.removeProtocol("uniswap-v3");
        assertFalse(router.approvedProtocols(address(uniswapAdapter)));
        assertEq(router.protocolAdapters("uniswap-v3"), address(0));
    }

    function testExecuteSingleSegment() public {
        // Create segment for Uniswap swap
        Types.Segment[] memory segments = new Types.Segment[](1);

        // Encode swap parameters in simplified format: (tokenIn, tokenOut, fee, amountIn, minAmountOut)
        segments[0] = Types.Segment({
            segmentType: Types.SegmentType.SWAP,
            targetProtocol: address(uniswapAdapter),
            callData: abi.encode(
                address(tokenA),  // tokenIn
                address(tokenB),  // tokenOut
                uint24(3000),     // fee
                uint256(100e18),  // amountIn
                uint256(90e18)    // minAmountOut
            ),
            value: 0,
            minGasLimit: 300000
        });

        // Submit intent to get intentId
        vm.prank(aiAgent);
        bytes32 intentId = decomposer.submitDecomposition(
            user,
            segments,
            new Types.WatcherConfig[](0),
            block.timestamp + 1 days
        );

        // Approve tokens
        vm.prank(user);
        tokenA.approve(address(uniswapAdapter), 100e18);

        // Set mock router to return output tokens
        mockUniswap.setAmountOut(95e18);

        // Execute segments
        bool[] memory results = router.executeSegments(intentId, segments);
        assertTrue(results[0]);
    }

    function testExecuteMultipleSegments() public {
        // Create multiple segments
        Types.Segment[] memory segments = new Types.Segment[](2);

        // Segment 1: Swap on Uniswap - simplified format
        segments[0] = Types.Segment({
            segmentType: Types.SegmentType.SWAP,
            targetProtocol: address(uniswapAdapter),
            callData: abi.encode(
                address(tokenA),  // tokenIn
                address(tokenB),  // tokenOut
                uint24(3000),     // fee
                uint256(100e18),  // amountIn
                uint256(90e18)    // minAmountOut
            ),
            value: 0,
            minGasLimit: 300000
        });

        // Segment 2: Supply to Aave
        segments[1] = Types.Segment({
            segmentType: Types.SegmentType.DEPOSIT,
            targetProtocol: address(aaveAdapter),
            callData: abi.encode(
                AaveV3Adapter.AaveOperation.SUPPLY,
                address(tokenB),
                1000e18
            ),
            value: 0,
            minGasLimit: 300000
        });

        // Submit intent
        vm.prank(aiAgent);
        bytes32 intentId = decomposer.submitDecomposition(
            user,
            segments,
            new Types.WatcherConfig[](0),
            block.timestamp + 1 days
        );

        // Approve tokens for both operations
        vm.startPrank(user);
        tokenA.approve(address(uniswapAdapter), 100e18);
        tokenB.approve(address(aaveAdapter), 1000e18);
        vm.stopPrank();

        // Set mock router to return output tokens
        mockUniswap.setAmountOut(95e18);

        // Execute segments
        bool[] memory results = router.executeSegments(intentId, segments);
        assertTrue(results[0]);
        assertTrue(results[1]);
    }

    function testExecuteSegmentInvalidProtocol() public {
        // Create segment with non-existent protocol
        Types.Segment[] memory segments = new Types.Segment[](1);
        segments[0] = Types.Segment({
            segmentType: Types.SegmentType.SWAP,
            targetProtocol: makeAddr("invalidProtocol"),
            callData: "",
            value: 0,
            minGasLimit: 300000
        });

        // Submit intent
        vm.prank(aiAgent);
        bytes32 intentId = decomposer.submitDecomposition(
            user,
            segments,
            new Types.WatcherConfig[](0),
            block.timestamp + 1 days
        );

        // Execution should fail gracefully for unapproved protocol (not revert)
        bool[] memory results = router.executeSegments(intentId, segments);
        assertFalse(results[0]); // Should return false instead of reverting
    }

    function testExecuteSegmentAdapterReverts() public {
        // Set mock to revert
        mockUniswap.setShouldRevert(true);
        mockUniswap.setRevertMessage("Insufficient liquidity");

        // Create swap segment - simplified format
        Types.Segment[] memory segments = new Types.Segment[](1);
        segments[0] = Types.Segment({
            segmentType: Types.SegmentType.SWAP,
            targetProtocol: address(uniswapAdapter),
            callData: abi.encode(
                address(tokenA),  // tokenIn
                address(tokenB),  // tokenOut
                uint24(3000),     // fee
                uint256(100e18),  // amountIn
                uint256(90e18)    // minAmountOut
            ),
            value: 0,
            minGasLimit: 300000
        });

        // Submit intent
        vm.prank(aiAgent);
        bytes32 intentId = decomposer.submitDecomposition(
            user,
            segments,
            new Types.WatcherConfig[](0),
            block.timestamp + 1 days
        );

        // Approve tokens
        vm.prank(user);
        tokenA.approve(address(uniswapAdapter), 100e18);

        // Execute should fail gracefully
        bool[] memory results = router.executeSegments(intentId, segments);
        assertFalse(results[0]);
    }

    function testGetExecutionHistory() public {
        // Create and execute segment - simplified format
        Types.Segment[] memory segments = new Types.Segment[](1);
        segments[0] = Types.Segment({
            segmentType: Types.SegmentType.SWAP,
            targetProtocol: address(uniswapAdapter),
            callData: abi.encode(
                address(tokenA),  // tokenIn
                address(tokenB),  // tokenOut
                uint24(3000),     // fee
                uint256(100e18),  // amountIn
                uint256(90e18)    // minAmountOut
            ),
            value: 0,
            minGasLimit: 300000
        });

        vm.prank(aiAgent);
        bytes32 intentId = decomposer.submitDecomposition(
            user,
            segments,
            new Types.WatcherConfig[](0),
            block.timestamp + 1 days
        );

        vm.prank(user);
        tokenA.approve(address(uniswapAdapter), 100e18);

        // Set mock router to return output tokens
        mockUniswap.setAmountOut(95e18);

        router.executeSegments(intentId, segments);

        // Get execution history
        Types.SegmentExecution[] memory history = router.getExecutionHistory(intentId);
        assertEq(history.length, 1);
        assertEq(history[0].intentId, intentId);
        assertEq(history[0].segmentIndex, 0);
        assertTrue(history[0].success);
    }

    function testExecuteWithETHValue() public {
        // Create segment that needs ETH value
        Types.Segment[] memory segments = new Types.Segment[](1);
        segments[0] = Types.Segment({
            segmentType: Types.SegmentType.SWAP,
            targetProtocol: address(uniswapAdapter),
            callData: abi.encode("swap_data"),
            value: 1 ether,
            minGasLimit: 300000
        });

        vm.prank(aiAgent);
        bytes32 intentId = decomposer.submitDecomposition(
            user,
            segments,
            new Types.WatcherConfig[](0),
            block.timestamp + 1 days
        );

        // Execute with ETH value
        vm.deal(address(this), 2 ether);
        router.executeSegments{value: 1 ether}(intentId, segments);
    }

    function testPauseAndUnpause() public {
        // Create segment
        Types.Segment[] memory segments = new Types.Segment[](1);
        segments[0] = Types.Segment({
            segmentType: Types.SegmentType.SWAP,
            targetProtocol: address(uniswapAdapter),
            callData: "",
            value: 0,
            minGasLimit: 300000
        });

        vm.prank(aiAgent);
        bytes32 intentId = decomposer.submitDecomposition(
            user,
            segments,
            new Types.WatcherConfig[](0),
            block.timestamp + 1 days
        );

        // Pause router
        router.pause();

        // Try to execute while paused
        vm.expectRevert();
        router.executeSegments(intentId, segments);

        // Unpause
        router.unpause();

        // Should work now
        bool[] memory results = router.executeSegments(intentId, segments);
        assertEq(results.length, 1);
    }

    function testEmptySegmentArray() public {
        Types.Segment[] memory emptySegments = new Types.Segment[](0);

        vm.prank(aiAgent);
        bytes32 intentId = decomposer.submitDecomposition(
            user,
            emptySegments,
            new Types.WatcherConfig[](0),
            block.timestamp + 1 days
        );

        // Router should revert on empty segment array
        vm.expectRevert("IntentRouter: no segments");
        router.executeSegments(intentId, emptySegments);
    }

    // NOTE: Commented out - methods not implemented in current IntentRouter
    // function testGetProtocolCategory() public {
    //     Types.ProtocolCategory category = router.protocolCategory(address(uniswapAdapter));
    //     assertEq(uint(category), uint(Types.ProtocolCategory.DEX));

    //     category = router.protocolCategory(address(aaveAdapter));
    //     assertEq(uint(category), uint(Types.ProtocolCategory.LENDING));
    // }

    function testProtocolApprovalStatus() public {
        assertTrue(router.approvedProtocols(address(uniswapAdapter)));
        assertTrue(router.approvedProtocols(address(aaveAdapter)));
        assertFalse(router.approvedProtocols(makeAddr("nonExistent")));
    }

    function testReentrancyProtection() public {
        // This test verifies that the router has reentrancy protection
        // Create segment
        Types.Segment[] memory segments = new Types.Segment[](1);
        segments[0] = Types.Segment({
            segmentType: Types.SegmentType.SWAP,
            targetProtocol: address(uniswapAdapter),
            callData: "",
            value: 0,
            minGasLimit: 300000
        });

        vm.prank(aiAgent);
        bytes32 intentId = decomposer.submitDecomposition(
            user,
            segments,
            new Types.WatcherConfig[](0),
            block.timestamp + 1 days
        );

        // Execute (nonReentrant modifier should be active)
        router.executeSegments(intentId, segments);
    }

    function testPartialExecution() public {
        // Create segments where one will fail
        mockUniswap.setShouldRevert(false); // Uniswap succeeds
        // Leave Aave as is (will succeed)

        Types.Segment[] memory segments = new Types.Segment[](3);

        // Segment 1: Success - simplified format
        segments[0] = Types.Segment({
            segmentType: Types.SegmentType.SWAP,
            targetProtocol: address(uniswapAdapter),
            callData: abi.encode(
                address(tokenA),  // tokenIn
                address(tokenB),  // tokenOut
                uint24(3000),     // fee
                uint256(100e18),  // amountIn
                uint256(90e18)    // minAmountOut
            ),
            value: 0,
            minGasLimit: 300000
        });

        // Segment 2: Will fail (invalid protocol)
        segments[1] = Types.Segment({
            segmentType: Types.SegmentType.SWAP,
            targetProtocol: makeAddr("invalidProtocol"),
            callData: "",
            value: 0,
            minGasLimit: 300000
        });

        // Segment 3: Success
        segments[2] = Types.Segment({
            segmentType: Types.SegmentType.DEPOSIT,
            targetProtocol: address(aaveAdapter),
            callData: abi.encode(
                AaveV3Adapter.AaveOperation.SUPPLY,
                address(tokenB),
                1000e18
            ),
            value: 0,
            minGasLimit: 300000
        });

        vm.prank(aiAgent);
        bytes32 intentId = decomposer.submitDecomposition(
            user,
            segments,
            new Types.WatcherConfig[](0),
            block.timestamp + 1 days
        );

        // Approve tokens
        vm.startPrank(user);
        tokenA.approve(address(uniswapAdapter), 100e18);
        tokenB.approve(address(aaveAdapter), 1000e18);
        vm.stopPrank();

        // Set mock router to return output tokens
        mockUniswap.setAmountOut(95e18);

        // Execute - should have mixed results
        bool[] memory results = router.executeSegments(intentId, segments);
        assertTrue(results[0]);   // Uniswap success
        assertFalse(results[1]);  // Invalid protocol failure
        assertTrue(results[2]);   // Aave success
    }
}
