// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../contracts/PredictionMarket.sol";
import "../contracts/MarketFactory.sol";
import "../contracts/OutcomeToken1155.sol";
import "../contracts/FeeVault.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20Int is ERC20 {
    constructor() ERC20("Mock USDC", "mUSDC") {}
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockOracleInt {
    mapping(uint256 => bool) private _outcomes;
    mapping(uint256 => bool) private _finalized;

    function setOutcome(uint256 marketId, bool outcome) external {
        _outcomes[marketId] = outcome;
        _finalized[marketId] = true;
    }

    function getFinalOutcome(uint256 marketId) external view returns (bool) {
        require(_finalized[marketId], "not finalized");
        return _outcomes[marketId];
    }
}

/**
 * @title IntegrationTest
 * @dev End-to-end integration tests for the full prediction market system:
 *      MarketFactory → PredictionMarket → OutcomeToken1155 → FeeVault
 */
contract IntegrationTest is Test {
    MockERC20Int public collateral;
    MockOracleInt public oracle;
    FeeVault public feeVault;
    MarketFactory public factory;

    address public deployer = makeAddr("deployer");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public carol = makeAddr("carol");

    function setUp() public {
        vm.startPrank(deployer);

        collateral = new MockERC20Int();
        oracle = new MockOracleInt();
        feeVault = new FeeVault(IERC20(address(collateral)));
        factory = new MarketFactory(
            address(collateral),
            address(feeVault),   // fees go to vault
            address(oracle)
        );

        vm.stopPrank();

        // Fund users
        collateral.mint(alice, 10_000e18);
        collateral.mint(bob, 10_000e18);
        collateral.mint(carol, 5_000e18);
    }



    function test_e2e_fullMarketLifecycle() public {
        // 1. Carol deposits into FeeVault to earn fee yield
        vm.startPrank(carol);
        collateral.approve(address(feeVault), 2000e18);
        uint256 carolShares = feeVault.deposit(2000e18, carol);
        vm.stopPrank();
        assertGt(carolShares, 0, "Carol should receive vault shares");

        // 2. Create market
        vm.prank(alice);
        address marketAddr = factory.createMarket("Will ETH reach $5k?", block.timestamp + 1 days);
        PredictionMarket market = PredictionMarket(payable(marketAddr));
        OutcomeToken1155 outcomeToken = market.outcomeToken();

        // 3. Alice provides liquidity
        vm.startPrank(alice);
        collateral.approve(address(market), 1000e18);
        market.addLiquidity(1000e18);
        vm.stopPrank();

        assertEq(market.reserveYES(), 1000e18);
        assertEq(market.reserveNO(), 1000e18);

        // 4. Bob buys YES shares
        uint256 bobCollateralBefore = collateral.balanceOf(bob);
        vm.startPrank(bob);
        collateral.approve(address(market), 100e18);
        uint256 sharesReceived = market.buy(0, 100e18, 0); // buy YES
        vm.stopPrank();

        assertGt(sharesReceived, 0, "Bob should receive YES shares");
        assertEq(outcomeToken.balanceOf(bob, 0), sharesReceived);
        uint256 bobSpent = bobCollateralBefore - collateral.balanceOf(bob);
        assertEq(bobSpent, 100e18);

        // 5. Verify fees reached the vault
        uint256 expectedFee = (100e18 * 100) / 10000; // 1% of 100
        uint256 vaultAssets = feeVault.totalAssets();
        assertEq(vaultAssets, 2000e18 + expectedFee, "Vault should hold deposit + fee");

        // 6. Warp past market end and resolve
        vm.warp(block.timestamp + 2 days);
        oracle.setOutcome(0, true); // YES wins
        market.resolve();

        // 7. Bob claims winnings
        uint256 bobBalBefore = collateral.balanceOf(bob);
        uint256 bobWinShares = outcomeToken.balanceOf(bob, 0);

        vm.prank(bob);
        market.claim();

        assertEq(collateral.balanceOf(bob), bobBalBefore + bobWinShares, "Bob should receive payout");
        assertEq(outcomeToken.balanceOf(bob, 0), 0, "Winning shares should be burned");

        // 8. Carol withdraws from vault with fee profit
        uint256 carolVaultShares = feeVault.balanceOf(carol);
        vm.prank(carol);
        uint256 carolAssets = feeVault.redeem(carolVaultShares, carol, carol);

        assertGt(carolAssets, 2000e18, "Carol should profit from fees");
        assertApproxEqAbs(carolAssets, 2000e18 + expectedFee, 10, "Carol gets deposit + all fees");
    }



    function test_e2e_multipleTraders_feeAccrual() public {
        // Carol deposits into vault
        vm.startPrank(carol);
        collateral.approve(address(feeVault), 1000e18);
        feeVault.deposit(1000e18, carol);
        vm.stopPrank();

        // Create market
        vm.prank(alice);
        address marketAddr = factory.createMarket("Will BTC reach $100k?", block.timestamp + 1 days);
        PredictionMarket market = PredictionMarket(payable(marketAddr));

        // Alice provides liquidity
        vm.startPrank(alice);
        collateral.approve(address(market), 2000e18);
        market.addLiquidity(2000e18);
        vm.stopPrank();

        // Bob buys YES
        vm.startPrank(bob);
        collateral.approve(address(market), 500e18);
        market.buy(0, 500e18, 0);
        vm.stopPrank();

        // Alice buys NO
        vm.startPrank(alice);
        collateral.approve(address(market), 300e18);
        market.buy(1, 300e18, 0);
        vm.stopPrank();

        // Total fees = 1% of 500 + 1% of 300 = 5 + 3 = 8
        uint256 totalExpectedFees = 5e18 + 3e18;
        assertEq(feeVault.totalAssets(), 1000e18 + totalExpectedFees, "Vault should accumulate all trade fees");

        // Sync and verify tracking
        feeVault.syncFees();
        assertEq(feeVault.totalFeesAccrued(), totalExpectedFees);
    }



    function test_e2e_buySell_feesOnBothSides() public {
        vm.prank(alice);
        address marketAddr = factory.createMarket("Test market", block.timestamp + 1 days);
        PredictionMarket market = PredictionMarket(payable(marketAddr));
        OutcomeToken1155 outcomeToken = market.outcomeToken();

        vm.startPrank(alice);
        collateral.approve(address(market), 1000e18);
        market.addLiquidity(1000e18);
        vm.stopPrank();

        // Bob buys YES
        vm.startPrank(bob);
        collateral.approve(address(market), 200e18);
        uint256 shares = market.buy(0, 200e18, 0);
        vm.stopPrank();

        uint256 buyFee = (200e18 * 100) / 10000; // 2e18
        uint256 vaultAfterBuy = feeVault.totalAssets();
        assertEq(vaultAfterBuy, buyFee, "Vault should hold buy fee");

        // Bob sells some YES shares back
        vm.startPrank(bob);
        outcomeToken.setApprovalForAll(address(market), true);
        uint256 sellReturn = market.sell(0, shares / 2, 0);
        vm.stopPrank();

        // Sell also generates a fee
        uint256 vaultAfterSell = feeVault.totalAssets();
        assertGt(vaultAfterSell, vaultAfterBuy, "Vault should grow from sell fee too");
    }



    function test_e2e_losingSide_cannotClaim() public {
        vm.prank(alice);
        address marketAddr = factory.createMarket("Coin flip", block.timestamp + 1 days);
        PredictionMarket market = PredictionMarket(payable(marketAddr));

        vm.startPrank(alice);
        collateral.approve(address(market), 1000e18);
        market.addLiquidity(1000e18);
        vm.stopPrank();

        // Bob buys NO
        vm.startPrank(bob);
        collateral.approve(address(market), 50e18);
        market.buy(1, 50e18, 0); // buy NO shares
        vm.stopPrank();

        // Resolve as YES
        vm.warp(block.timestamp + 2 days);
        oracle.setOutcome(0, true); // YES wins
        market.resolve();

        // Bob has NO shares → should fail to claim (balance of winning token is 0)
        vm.prank(bob);
        vm.expectRevert("No winning shares");
        market.claim();
    }



    function test_e2e_factoryCreatesIndependentMarkets() public {
        vm.startPrank(alice);
        address m1 = factory.createMarket("Market A", block.timestamp + 1 days);
        address m2 = factory.createMarket("Market B", block.timestamp + 2 days);
        vm.stopPrank();

        assertTrue(m1 != m2, "Markets should have different addresses");
        assertEq(factory.getMarketsCount(), 2);

        PredictionMarket market1 = PredictionMarket(payable(m1));
        PredictionMarket market2 = PredictionMarket(payable(m2));

        assertTrue(
            address(market1.outcomeToken()) != address(market2.outcomeToken()),
            "Each market should have its own outcome token"
        );
    }



    function test_e2e_vaultProportionalYield() public {
        // Alice and Bob both deposit into vault
        vm.startPrank(alice);
        collateral.approve(address(feeVault), 3000e18);
        feeVault.deposit(3000e18, alice); // 75%
        vm.stopPrank();

        vm.startPrank(bob);
        collateral.approve(address(feeVault), 1000e18);
        feeVault.deposit(1000e18, bob); // 25%
        vm.stopPrank();

        // Create market and generate fees
        vm.prank(carol);
        address marketAddr = factory.createMarket("Fee test", block.timestamp + 1 days);
        PredictionMarket market = PredictionMarket(payable(marketAddr));

        collateral.mint(carol, 10_000e18);
        vm.startPrank(carol);
        collateral.approve(address(market), 5000e18);
        market.addLiquidity(2000e18);
        market.buy(0, 1000e18, 0); // generates 10e18 fee
        vm.stopPrank();

        uint256 fee = 10e18;

        // Alice redeems
        uint256 aliceShares = feeVault.balanceOf(alice);
        vm.prank(alice);
        uint256 aliceOut = feeVault.redeem(aliceShares, alice, alice);

        // Bob redeems
        uint256 bobShares = feeVault.balanceOf(bob);
        vm.prank(bob);
        uint256 bobOut = feeVault.redeem(bobShares, bob, bob);

        // Alice should get 75% of fees, Bob 25%
        assertApproxEqAbs(aliceOut, 3000e18 + (fee * 75 / 100), 1e15, "Alice 75% of fees");
        assertApproxEqAbs(bobOut, 1000e18 + (fee * 25 / 100), 1e15, "Bob 25% of fees");
    }
}
