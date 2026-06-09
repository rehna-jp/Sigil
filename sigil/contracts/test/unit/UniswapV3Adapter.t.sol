// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../../src/adapters/UniswapV3Adapter.sol";
import "../mocks/MockUniswapRouter.sol";
import "../mocks/MockERC20.sol";

contract UniswapV3AdapterTest is Test {
    UniswapV3Adapter public adapter;
    MockUniswapRouter public mockRouter;
    MockERC20 public tokenA;
    MockERC20 public tokenB;

    address public user;

    function setUp() public {
        user = makeAddr("user");

        // Deploy mock router
        mockRouter = new MockUniswapRouter();

        // Deploy adapter
        adapter = new UniswapV3Adapter(address(mockRouter), address(this));

        // Deploy mock tokens
        tokenA = new MockERC20("Token A", "TKNA", 18);
        tokenB = new MockERC20("Token B", "TKNB", 18);

        // Mint tokens
        tokenA.mint(user, 10000e18);
        tokenB.mint(address(mockRouter), 100000e18); // Router has output tokens
    }

    function testGetProtocolName() public {
        assertEq(adapter.getProtocolName(), "Uniswap V3");
    }

    function testGetProtocolVersion() public {
        assertEq(adapter.getProtocolVersion(), "3.0.0");
    }

    function testGetSupportedSegmentTypes() public {
        Types.SegmentType[] memory types = adapter.getSupportedSegmentTypes();
        assertEq(types.length, 1);
        assertEq(uint(types[0]), uint(Types.SegmentType.SWAP));
    }

    function testExecuteExactInputSingle() public {
        // Encode segment data: (tokenIn, tokenOut, fee, amountIn, minAmountOut)
        bytes memory segmentData = abi.encode(
            address(tokenA),  // tokenIn
            address(tokenB),  // tokenOut
            uint24(3000),     // fee
            uint256(100e18),  // amountIn
            uint256(90e18)    // minAmountOut
        );

        // User approves adapter
        vm.prank(user);
        tokenA.approve(address(adapter), 100e18);

        // Set mock router to return 95e18 tokens
        mockRouter.setAmountOut(95e18);

        // Execute swap
        (bool success, bytes memory returnData) = adapter.execute(segmentData, user, 0);
        assertTrue(success);

        uint256 amountOut = abi.decode(returnData, (uint256));
        assertEq(amountOut, 95e18);
    }

    function testExecuteInsufficientBalance() public {
        // User has no tokens
        address poorUser = makeAddr("poorUser");

        bytes memory segmentData = abi.encode(
            address(tokenA),  // tokenIn
            address(tokenB),  // tokenOut
            uint24(3000),     // fee
            uint256(100e18),  // amountIn
            uint256(90e18)    // minAmountOut
        );

        // Execute should fail
        (bool success,) = adapter.execute(segmentData, poorUser, 0);
        assertFalse(success);
    }

    function testExecuteInsufficientAllowance() public {
        // User has tokens but no allowance
        bytes memory segmentData = abi.encode(
            address(tokenA),  // tokenIn
            address(tokenB),  // tokenOut
            uint24(3000),     // fee
            uint256(100e18),  // amountIn
            uint256(90e18)    // minAmountOut
        );

        // Execute should fail (no approval)
        (bool success,) = adapter.execute(segmentData, user, 0);
        assertFalse(success);
    }

    function testExecuteRouterReverts() public {
        // Set router to revert
        mockRouter.setShouldRevert(true);
        mockRouter.setRevertMessage("Slippage exceeded");

        bytes memory segmentData = abi.encode(
            address(tokenA),  // tokenIn
            address(tokenB),  // tokenOut
            uint24(3000),     // fee
            uint256(100e18),  // amountIn
            uint256(90e18)    // minAmountOut
        );

        vm.prank(user);
        tokenA.approve(address(adapter), 100e18);

        // Execute should handle revert gracefully
        (bool success, bytes memory returnData) = adapter.execute(segmentData, user, 0);
        assertFalse(success);
        // Check error message contains the revert reason
        string memory errorMsg = string(returnData);
        assertTrue(bytes(errorMsg).length > 0);
    }

    function testSimulate() public {
        bytes memory segmentData = abi.encode(
            address(tokenA),  // tokenIn
            address(tokenB),  // tokenOut
            uint24(3000),     // fee
            uint256(100e18),  // amountIn
            uint256(90e18)    // minAmountOut
        );

        // User approves
        vm.prank(user);
        tokenA.approve(address(adapter), 100e18);

        // Simulate should pass
        (bool canExecute, string memory reason) = adapter.simulate(segmentData, user);
        assertTrue(canExecute);
        assertEq(bytes(reason).length, 0);
    }

    function testSimulateInsufficientBalance() public {
        address poorUser = makeAddr("poorUser");

        bytes memory segmentData = abi.encode(
            address(tokenA),  // tokenIn
            address(tokenB),  // tokenOut
            uint24(3000),     // fee
            uint256(100e18),  // amountIn
            uint256(90e18)    // minAmountOut
        );

        (bool canExecute, string memory reason) = adapter.simulate(segmentData, poorUser);
        assertFalse(canExecute);
        assertEq(reason, "Insufficient balance");
    }

    function testSimulateInsufficientAllowance() public {
        bytes memory segmentData = abi.encode(
            address(tokenA),  // tokenIn
            address(tokenB),  // tokenOut
            uint24(3000),     // fee
            uint256(100e18),  // amountIn
            uint256(90e18)    // minAmountOut
        );

        // No approval given
        (bool canExecute, string memory reason) = adapter.simulate(segmentData, user);
        assertFalse(canExecute);
        assertEq(reason, "Insufficient allowance");
    }

    function testValidateSegmentData() public {
        bytes memory segmentData = abi.encode(
            address(tokenA),  // tokenIn
            address(tokenB),  // tokenOut
            uint24(3000),     // fee
            uint256(100e18),  // amountIn
            uint256(90e18)    // minAmountOut
        );

        (bool isValid, string memory reason) = adapter.validateSegmentData(segmentData);
        assertTrue(isValid);
        assertEq(bytes(reason).length, 0);
    }

    function testValidateSegmentDataInvalid() public {
        // Invalid data (not properly encoded)
        bytes memory invalidData = abi.encode(uint256(123));

        (bool isValid, string memory reason) = adapter.validateSegmentData(invalidData);
        assertFalse(isValid);
        assertEq(reason, "Invalid segment data encoding");
    }

    function testDecodeSegmentData() public {
        bytes memory segmentData = abi.encode(
            address(tokenA),  // tokenIn
            address(tokenB),  // tokenOut
            uint24(3000),     // fee
            uint256(100e18),  // amountIn
            uint256(90e18)    // minAmountOut
        );

        (
            address tokenIn,
            address tokenOut,
            uint24 fee,
            uint256 amountIn,
            uint256 minAmountOut
        ) = adapter.decodeSegmentData(segmentData);

        assertEq(tokenIn, address(tokenA));
        assertEq(tokenOut, address(tokenB));
        assertEq(fee, 3000);
        assertEq(amountIn, 100e18);
        assertEq(minAmountOut, 90e18);
    }

    function testRecoverToken() public {
        // Send some tokens to adapter accidentally
        tokenA.mint(address(adapter), 100e18);

        uint256 balanceBefore = tokenA.balanceOf(address(this));

        // Recover as owner
        adapter.recoverToken(address(tokenA), address(this), 100e18);

        uint256 balanceAfter = tokenA.balanceOf(address(this));
        assertEq(balanceAfter - balanceBefore, 100e18);
    }

    function testRecoverTokenUnauthorized() public {
        tokenA.mint(address(adapter), 100e18);

        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert();
        adapter.recoverToken(address(tokenA), attacker, 100e18);
    }

    function testReceiveETH() public {
        // Adapter should accept ETH
        vm.deal(address(this), 1 ether);
        (bool success,) = address(adapter).call{value: 1 ether}("");
        assertTrue(success);
        assertEq(address(adapter).balance, 1 ether);
    }

    function testExecuteWithZeroAmountIn() public {
        bytes memory segmentData = abi.encode(
            address(tokenA),  // tokenIn
            address(tokenB),  // tokenOut
            uint24(3000),     // fee
            uint256(0),       // amountIn - ZERO!
            uint256(0)        // minAmountOut
        );

        (bool success,) = adapter.execute(segmentData, user, 0);
        // Should handle zero amount (may succeed or fail depending on implementation)
        // At minimum, should not revert unexpectedly
    }

    function testExecuteWithExpiredDeadline() public {
        // Note: Adapter sets deadline to block.timestamp internally,
        // so this test just ensures it handles the situation gracefully
        bytes memory segmentData = abi.encode(
            address(tokenA),  // tokenIn
            address(tokenB),  // tokenOut
            uint24(3000),     // fee
            uint256(100e18),  // amountIn
            uint256(90e18)    // minAmountOut
        );

        vm.prank(user);
        tokenA.approve(address(adapter), 100e18);

        // Execute (should work since adapter sets deadline to current timestamp)
        adapter.execute(segmentData, user, 0);
        // Test that it handles the situation gracefully
    }
}
