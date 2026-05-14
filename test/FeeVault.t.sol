// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../contracts/FeeVault.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockUSDC is ERC20 {
    constructor() ERC20("Mock USDC", "mUSDC") {}
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract FeeVaultTest is Test {
    FeeVault public vault;
    MockUSDC public usdc;

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public feeSource = makeAddr("feeSource");

    function setUp() public {
        usdc = new MockUSDC();
        vault = new FeeVault(IERC20(address(usdc)));

        usdc.mint(alice, 10_000e18);
        usdc.mint(bob, 10_000e18);
        usdc.mint(feeSource, 10_000e18);
    }



    function test_deposit_basic() public {
        vm.startPrank(alice);
        usdc.approve(address(vault), 1000e18);
        uint256 shares = vault.deposit(1000e18, alice);
        vm.stopPrank();

        assertGt(shares, 0, "Should receive shares");
        assertEq(vault.balanceOf(alice), shares);
        assertEq(vault.totalAssets(), 1000e18);
    }

    function test_deposit_multipleUsers() public {
        vm.startPrank(alice);
        usdc.approve(address(vault), 1000e18);
        uint256 aliceShares = vault.deposit(1000e18, alice);
        vm.stopPrank();

        vm.startPrank(bob);
        usdc.approve(address(vault), 1000e18);
        uint256 bobShares = vault.deposit(1000e18, bob);
        vm.stopPrank();

        assertEq(aliceShares, bobShares, "Same deposit should give same shares");
        assertEq(vault.totalAssets(), 2000e18);
    }

    function test_deposit_afterFeeAccrual_giveFewerShares() public {
        vm.startPrank(alice);
        usdc.approve(address(vault), 1000e18);
        vault.deposit(1000e18, alice);
        vm.stopPrank();

        // Fees arrive (simulates PredictionMarket sending fees)
        vm.prank(feeSource);
        usdc.transfer(address(vault), 100e18);

        // Bob deposits after fees — should get fewer shares per token
        vm.startPrank(bob);
        usdc.approve(address(vault), 1000e18);
        uint256 bobShares = vault.deposit(1000e18, bob);
        vm.stopPrank();

        assertLt(bobShares, vault.balanceOf(alice), "Bob should get fewer shares after fee accrual");
    }



    function test_withdraw_basic() public {
        vm.startPrank(alice);
        usdc.approve(address(vault), 1000e18);
        vault.deposit(1000e18, alice);
        vault.withdraw(1000e18, alice, alice);
        vm.stopPrank();

        assertEq(usdc.balanceOf(alice), 10_000e18, "Should get all USDC back");
        assertEq(vault.totalAssets(), 0);
    }

    function test_withdraw_withFeeProfit() public {
        vm.startPrank(alice);
        usdc.approve(address(vault), 1000e18);
        vault.deposit(1000e18, alice);
        vm.stopPrank();

        // Fees arrive
        vm.prank(feeSource);
        usdc.transfer(address(vault), 200e18);

        // Alice redeems all shares
        uint256 aliceShares = vault.balanceOf(alice);
        vm.prank(alice);
        uint256 assets = vault.redeem(aliceShares, alice, alice);

        assertApproxEqAbs(assets, 1200e18, 10, "Should receive deposit + all fees");
    }

    function test_withdraw_proportionalFeeDistribution() public {
        vm.startPrank(alice);
        usdc.approve(address(vault), 1000e18);
        vault.deposit(1000e18, alice);
        vm.stopPrank();

        vm.startPrank(bob);
        usdc.approve(address(vault), 1000e18);
        vault.deposit(1000e18, bob);
        vm.stopPrank();

        // 200 in fees arrive
        vm.prank(feeSource);
        usdc.transfer(address(vault), 200e18);

        uint256 aliceShares = vault.balanceOf(alice);
        uint256 bobShares = vault.balanceOf(bob);

        vm.prank(alice);
        uint256 aliceAssets = vault.redeem(aliceShares, alice, alice);

        vm.prank(bob);
        uint256 bobAssets = vault.redeem(bobShares, bob, bob);

        // Each should get ~1100 (1000 deposit + 100 fee share)
        assertApproxEqAbs(aliceAssets, 1100e18, 1e15, "Alice should get ~1100");
        assertApproxEqAbs(bobAssets, 1100e18, 1e15, "Bob should get ~1100");
    }



    function test_redeem_all() public {
        vm.startPrank(alice);
        usdc.approve(address(vault), 500e18);
        uint256 shares = vault.deposit(500e18, alice);

        uint256 assets = vault.redeem(shares, alice, alice);
        vm.stopPrank();

        assertEq(assets, 500e18);
        assertEq(vault.balanceOf(alice), 0);
    }



    function test_syncFees() public {
        vm.startPrank(alice);
        usdc.approve(address(vault), 1000e18);
        vault.deposit(1000e18, alice);
        vm.stopPrank();

        vm.prank(feeSource);
        usdc.transfer(address(vault), 50e18);

        vault.syncFees();
        assertEq(vault.totalFeesAccrued(), 50e18);
        assertEq(vault.pendingFees(), 0);
    }

    function test_syncFees_revertsWhenNoFees() public {
        vm.startPrank(alice);
        usdc.approve(address(vault), 1000e18);
        vault.deposit(1000e18, alice);
        vm.stopPrank();

        vm.expectRevert(FeeVault.NoFeesToSync.selector);
        vault.syncFees();
    }

    function test_pendingFees() public {
        vm.startPrank(alice);
        usdc.approve(address(vault), 1000e18);
        vault.deposit(1000e18, alice);
        vm.stopPrank();

        assertEq(vault.pendingFees(), 0);

        vm.prank(feeSource);
        usdc.transfer(address(vault), 75e18);

        assertEq(vault.pendingFees(), 75e18);
    }



    function test_sweepToken() public {
        MockUSDC randomToken = new MockUSDC();
        randomToken.mint(address(vault), 100e18);

        vault.sweepToken(IERC20(address(randomToken)), alice);
        assertEq(randomToken.balanceOf(alice), 100e18);
    }

    function test_sweepToken_cannotSweepUnderlying() public {
        vm.expectRevert(FeeVault.CannotSweepUnderlying.selector);
        vault.sweepToken(IERC20(address(usdc)), alice);
    }

    function test_sweepToken_onlyOwner() public {
        MockUSDC randomToken = new MockUSDC();
        randomToken.mint(address(vault), 100e18);

        vm.prank(alice);
        vm.expectRevert();
        vault.sweepToken(IERC20(address(randomToken)), alice);
    }



    function test_previewDeposit_matchesActual() public {
        vm.startPrank(alice);
        usdc.approve(address(vault), 1000e18);

        uint256 expectedShares = vault.previewDeposit(1000e18);
        uint256 actualShares = vault.deposit(1000e18, alice);
        vm.stopPrank();

        assertEq(actualShares, expectedShares);
    }

    function test_previewRedeem_matchesActual() public {
        vm.startPrank(alice);
        usdc.approve(address(vault), 1000e18);
        uint256 shares = vault.deposit(1000e18, alice);

        uint256 expectedAssets = vault.previewRedeem(shares);
        uint256 actualAssets = vault.redeem(shares, alice, alice);
        vm.stopPrank();

        assertEq(actualAssets, expectedAssets);
    }



    function testFuzz_depositWithdrawRoundTrip(uint256 amount) public {
        amount = bound(amount, 1e6, 1_000_000e18);

        usdc.mint(alice, amount);

        vm.startPrank(alice);
        usdc.approve(address(vault), amount);
        uint256 shares = vault.deposit(amount, alice);
        uint256 assets = vault.redeem(shares, alice, alice);
        vm.stopPrank();

        assertEq(assets, amount, "Should get back exact deposit when no fees accrued");
    }
}
