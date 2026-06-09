// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../../src/adapters/AaveV3Adapter.sol";
import "../mocks/MockAavePool.sol";
import "../mocks/MockERC20.sol";

contract AaveV3AdapterTest is Test {
    AaveV3Adapter public adapter;
    MockAavePool public mockPool;
    MockERC20 public usdc;

    address public user;

    function setUp() public {
        user = makeAddr("user");

        // Deploy mock pool
        mockPool = new MockAavePool();

        // Deploy adapter
        adapter = new AaveV3Adapter(address(mockPool), address(this));

        // Deploy mock USDC
        usdc = new MockERC20("USD Coin", "USDC", 6);

        // Mint tokens to user
        usdc.mint(user, 10000e6);
    }

    function testGetProtocolName() public {
        assertEq(adapter.getProtocolName(), "Aave V3");
    }

    function testGetProtocolVersion() public {
        assertEq(adapter.getProtocolVersion(), "3.0.0");
    }

    function testGetSupportedSegmentTypes() public {
        Types.SegmentType[] memory types = adapter.getSupportedSegmentTypes();
        assertEq(types.length, 2);
        assertEq(uint(types[0]), uint(Types.SegmentType.DEPOSIT));
        assertEq(uint(types[1]), uint(Types.SegmentType.WITHDRAW));
    }

    function testExecuteSupply() public {
        // Prepare supply operation
        bytes memory segmentData = abi.encode(
            AaveV3Adapter.AaveOperation.SUPPLY,
            address(usdc),
            1000e6
        );

        // User approves adapter
        vm.prank(user);
        usdc.approve(address(adapter), 1000e6);

        // Execute supply
        (bool success, bytes memory returnData) = adapter.execute(segmentData, user, 0);
        assertTrue(success);

        uint256 suppliedAmount = abi.decode(returnData, (uint256));
        assertEq(suppliedAmount, 1000e6);

        // Verify mock pool received tokens
        assertEq(mockPool.getUserSupplied(user, address(usdc)), 1000e6);
    }

    function testExecuteWithdraw() public {
        // First supply tokens
        bytes memory supplyData = abi.encode(
            AaveV3Adapter.AaveOperation.SUPPLY,
            address(usdc),
            1000e6
        );

        vm.prank(user);
        usdc.approve(address(adapter), 1000e6);

        adapter.execute(supplyData, user, 0);

        // Now withdraw
        bytes memory withdrawData = abi.encode(
            AaveV3Adapter.AaveOperation.WITHDRAW,
            address(usdc),
            500e6
        );

        (bool success, bytes memory returnData) = adapter.execute(withdrawData, user, 0);
        assertTrue(success);

        uint256 withdrawnAmount = abi.decode(returnData, (uint256));
        assertEq(withdrawnAmount, 500e6);

        // Verify remaining supply
        assertEq(mockPool.getUserSupplied(user, address(usdc)), 500e6);
    }

    function testExecuteBorrow() public {
        // Supply collateral first
        bytes memory supplyData = abi.encode(
            AaveV3Adapter.AaveOperation.SUPPLY,
            address(usdc),
            1000e6
        );

        vm.prank(user);
        usdc.approve(address(adapter), 1000e6);
        adapter.execute(supplyData, user, 0);

        // Mint tokens to pool so it can lend
        usdc.mint(address(mockPool), 10000e6);

        // Borrow
        bytes memory borrowData = abi.encode(
            AaveV3Adapter.AaveOperation.BORROW,
            address(usdc),
            500e6
        );

        (bool success, bytes memory returnData) = adapter.execute(borrowData, user, 0);
        assertTrue(success);

        uint256 borrowedAmount = abi.decode(returnData, (uint256));
        assertEq(borrowedAmount, 500e6);
    }

    function testExecuteRepay() public {
        // Supply collateral
        vm.prank(user);
        usdc.approve(address(adapter), 1000e6);
        adapter.execute(
            abi.encode(AaveV3Adapter.AaveOperation.SUPPLY, address(usdc), 1000e6),
            user,
            0
        );

        // Borrow
        usdc.mint(address(mockPool), 10000e6);
        adapter.execute(
            abi.encode(AaveV3Adapter.AaveOperation.BORROW, address(usdc), 500e6),
            user,
            0
        );

        // Repay
        vm.prank(user);
        usdc.approve(address(adapter), 500e6);

        bytes memory repayData = abi.encode(
            AaveV3Adapter.AaveOperation.REPAY,
            address(usdc),
            500e6
        );

        (bool success, bytes memory returnData) = adapter.execute(repayData, user, 0);
        assertTrue(success);

        uint256 repaidAmount = abi.decode(returnData, (uint256));
        assertEq(repaidAmount, 500e6);
    }

    function testExecuteInvalidAsset() public {
        bytes memory segmentData = abi.encode(
            AaveV3Adapter.AaveOperation.SUPPLY,
            address(0), // Zero address
            1000e6
        );

        (bool success, bytes memory returnData) = adapter.execute(segmentData, user, 0);
        assertFalse(success);
        assertEq(string(returnData), "Invalid asset address");
    }

    function testExecuteZeroAmount() public {
        bytes memory segmentData = abi.encode(
            AaveV3Adapter.AaveOperation.SUPPLY,
            address(usdc),
            0 // Zero amount
        );

        (bool success, bytes memory returnData) = adapter.execute(segmentData, user, 0);
        assertFalse(success);
        assertEq(string(returnData), "Zero amount");
    }

    function testExecuteInsufficientBalance() public {
        address poorUser = makeAddr("poorUser");

        bytes memory segmentData = abi.encode(
            AaveV3Adapter.AaveOperation.SUPPLY,
            address(usdc),
            1000e6
        );

        (bool success,) = adapter.execute(segmentData, poorUser, 0);
        assertFalse(success);
    }

    function testSimulateSupply() public {
        bytes memory segmentData = abi.encode(
            AaveV3Adapter.AaveOperation.SUPPLY,
            address(usdc),
            1000e6
        );

        // User approves
        vm.prank(user);
        usdc.approve(address(adapter), 1000e6);

        (bool canExecute, string memory reason) = adapter.simulate(segmentData, user);
        assertTrue(canExecute);
        assertEq(bytes(reason).length, 0);
    }

    function testSimulateInsufficientBalance() public {
        address poorUser = makeAddr("poorUser");

        bytes memory segmentData = abi.encode(
            AaveV3Adapter.AaveOperation.SUPPLY,
            address(usdc),
            1000e6
        );

        (bool canExecute, string memory reason) = adapter.simulate(segmentData, poorUser);
        assertFalse(canExecute);
        assertEq(reason, "Insufficient balance");
    }

    function testSimulateInsufficientAllowance() public {
        bytes memory segmentData = abi.encode(
            AaveV3Adapter.AaveOperation.SUPPLY,
            address(usdc),
            1000e6
        );

        // No approval
        (bool canExecute, string memory reason) = adapter.simulate(segmentData, user);
        assertFalse(canExecute);
        assertEq(reason, "Insufficient allowance");
    }

    function testSimulateWithdraw() public {
        // Withdraw doesn't need balance/allowance check in simulate
        bytes memory segmentData = abi.encode(
            AaveV3Adapter.AaveOperation.WITHDRAW,
            address(usdc),
            1000e6
        );

        (bool canExecute, string memory reason) = adapter.simulate(segmentData, user);
        assertTrue(canExecute);
        assertEq(bytes(reason).length, 0);
    }

    function testValidateSegmentData() public {
        bytes memory segmentData = abi.encode(
            AaveV3Adapter.AaveOperation.SUPPLY,
            address(usdc),
            1000e6
        );

        (bool isValid, string memory reason) = adapter.validateSegmentData(segmentData);
        assertTrue(isValid);
        assertEq(bytes(reason).length, 0);
    }

    function testValidateSegmentDataInvalid() public {
        // Invalid encoding
        bytes memory invalidData = abi.encode(uint256(123));

        (bool isValid, string memory reason) = adapter.validateSegmentData(invalidData);
        assertFalse(isValid);
        assertEq(reason, "Invalid segment data encoding");
    }

    function testDecodeSegmentData() public {
        bytes memory segmentData = abi.encode(
            AaveV3Adapter.AaveOperation.SUPPLY,
            address(usdc),
            1000e6
        );

        (
            AaveV3Adapter.AaveOperation operation,
            address asset,
            uint256 amount
        ) = adapter.decodeSegmentData(segmentData);

        assertEq(uint(operation), uint(AaveV3Adapter.AaveOperation.SUPPLY));
        assertEq(asset, address(usdc));
        assertEq(amount, 1000e6);
    }

    function testRecoverToken() public {
        // Send tokens to adapter accidentally
        usdc.mint(address(adapter), 100e6);

        uint256 balanceBefore = usdc.balanceOf(address(this));

        // Recover as owner
        adapter.recoverToken(address(usdc), address(this), 100e6);

        uint256 balanceAfter = usdc.balanceOf(address(this));
        assertEq(balanceAfter - balanceBefore, 100e6);
    }

    function testRecoverTokenUnauthorized() public {
        usdc.mint(address(adapter), 100e6);

        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert();
        adapter.recoverToken(address(usdc), attacker, 100e6);
    }

    function testRecoverTokenZeroAddress() public {
        vm.expectRevert("AaveV3Adapter: zero token");
        adapter.recoverToken(address(0), address(this), 100e6);
    }

    function testRecoverTokenZeroRecipient() public {
        usdc.mint(address(adapter), 100e6);

        vm.expectRevert("AaveV3Adapter: zero recipient");
        adapter.recoverToken(address(usdc), address(0), 100e6);
    }

    function testReceiveETH() public {
        // Adapter should accept ETH
        vm.deal(address(this), 1 ether);
        (bool success,) = address(adapter).call{value: 1 ether}("");
        assertTrue(success);
        assertEq(address(adapter).balance, 1 ether);
    }

    function testSupplyMultipleTimes() public {
        bytes memory segmentData = abi.encode(
            AaveV3Adapter.AaveOperation.SUPPLY,
            address(usdc),
            500e6
        );

        // First supply
        vm.prank(user);
        usdc.approve(address(adapter), 1000e6);

        adapter.execute(segmentData, user, 0);
        assertEq(mockPool.getUserSupplied(user, address(usdc)), 500e6);

        // Second supply
        adapter.execute(segmentData, user, 0);
        assertEq(mockPool.getUserSupplied(user, address(usdc)), 1000e6);
    }

    function testWithdrawMoreThanSupplied() public {
        // Supply 1000
        vm.prank(user);
        usdc.approve(address(adapter), 1000e6);
        adapter.execute(
            abi.encode(AaveV3Adapter.AaveOperation.SUPPLY, address(usdc), 1000e6),
            user,
            0
        );

        // Try to withdraw 2000 (should fail in mock)
        mockPool.setShouldRevert(true);
        mockPool.setRevertMessage("Insufficient balance");

        bytes memory withdrawData = abi.encode(
            AaveV3Adapter.AaveOperation.WITHDRAW,
            address(usdc),
            2000e6
        );

        (bool success,) = adapter.execute(withdrawData, user, 0);
        assertFalse(success);

        // Reset mock
        mockPool.setShouldRevert(false);
    }

    function testBorrowWithoutCollateral() public {
        // Try to borrow without supplying collateral
        mockPool.setShouldRevert(true);
        mockPool.setRevertMessage("Insufficient collateral");

        bytes memory borrowData = abi.encode(
            AaveV3Adapter.AaveOperation.BORROW,
            address(usdc),
            500e6
        );

        (bool success,) = adapter.execute(borrowData, user, 0);
        assertFalse(success);

        mockPool.setShouldRevert(false);
    }

    function testAllOperationsInSequence() public {
        // Complete flow: Supply -> Borrow -> Repay -> Withdraw

        // 1. Supply
        vm.prank(user);
        usdc.approve(address(adapter), 2000e6);

        (bool success1,) = adapter.execute(
            abi.encode(AaveV3Adapter.AaveOperation.SUPPLY, address(usdc), 1000e6),
            user,
            0
        );
        assertTrue(success1);

        // 2. Borrow
        usdc.mint(address(mockPool), 10000e6);
        (bool success2,) = adapter.execute(
            abi.encode(AaveV3Adapter.AaveOperation.BORROW, address(usdc), 500e6),
            user,
            0
        );
        assertTrue(success2);

        // 3. Repay
        vm.prank(user);
        usdc.approve(address(adapter), 500e6);
        (bool success3,) = adapter.execute(
            abi.encode(AaveV3Adapter.AaveOperation.REPAY, address(usdc), 500e6),
            user,
            0
        );
        assertTrue(success3);

        // 4. Withdraw
        (bool success4,) = adapter.execute(
            abi.encode(AaveV3Adapter.AaveOperation.WITHDRAW, address(usdc), 1000e6),
            user,
            0
        );
        assertTrue(success4);

        // Verify final state
        assertEq(mockPool.getUserSupplied(user, address(usdc)), 0);
    }
}
