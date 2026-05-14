// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../contracts/PredictionMarket.sol";
import "../contracts/MarketFactory.sol";
import "../contracts/OutcomeToken1155.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock USDC", "mUSDC") {}
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockOracle {
    bool public outcome;
    function setOutcome(bool _outcome) external {
        outcome = _outcome;
    }
    function getFinalOutcome(uint256) external view returns (bool) {
        return outcome;
    }
}

contract PredictionMarketTest is Test {
    PredictionMarket public market;
    MarketFactory public factory;
    MockERC20 public collateral;
    OutcomeToken1155 public outcomeToken;
    MockOracle public oracle;

    address public alice = address(0xA11CE);
    address public bob = address(0xB0B);
    address public feeCollector = address(0xFEED);

    function setUp() public {
        collateral = new MockERC20();
        oracle = new MockOracle();
        
        factory = new MarketFactory(address(collateral), feeCollector, address(oracle));
        
        address marketAddr = factory.createMarket("Will ETH reach $5k?", block.timestamp + 1 days);
        market = PredictionMarket(payable(marketAddr));
        outcomeToken = market.outcomeToken();

        collateral.mint(alice, 1000e18);
        collateral.mint(bob, 1000e18);
    }

    function test_Liquidity() public {
        vm.startPrank(alice);
        collateral.approve(address(market), 100e18);
        market.addLiquidity(100e18);
        vm.stopPrank();

        assertEq(market.reserveYES(), 100e18);
        assertEq(market.reserveNO(), 100e18);
    }

    function test_BuySlippage() public {
        vm.startPrank(alice);
        collateral.approve(address(market), 100e18);
        market.addLiquidity(100e18);
        vm.stopPrank();

        vm.startPrank(bob);
        collateral.approve(address(market), 50e18);
        
        // Try to buy YES with 50 collateral.
        // Initial reserves: 100 YES, 100 NO.
        // Buy logic:
        // net = 50 * 0.99 = 49.5 (1% fee)
        // r0 = 100 + 49.5 = 149.5
        // r1 = 100 + 49.5 = 149.5
        // sharesOut = r0 - (k / r1) = 149.5 - (100*100 / 149.5) = 149.5 - 66.88 = 82.61
        uint256 shares = market.buy(0, 50e18, 0);
        assertEq(outcomeToken.balanceOf(bob, 0), shares);
        vm.stopPrank();
    }

    function test_ResolveAndClaim() public {
        vm.startPrank(alice);
        collateral.approve(address(market), 100e18);
        market.addLiquidity(100e18);
        vm.stopPrank();

        vm.startPrank(bob);
        collateral.approve(address(market), 10e18);
        market.buy(0, 10e18, 0);
        vm.stopPrank();

        // Warp time
        vm.warp(block.timestamp + 2 days);
        
        // Oracle says YES (true)
        oracle.setOutcome(true);
        market.resolve();

        uint256 bobBalBefore = collateral.balanceOf(bob);
        uint256 bobShares = outcomeToken.balanceOf(bob, 0);
        
        vm.startPrank(bob);
        market.claim();
        vm.stopPrank();

        assertEq(collateral.balanceOf(bob), bobBalBefore + bobShares);
    }
}
