// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../contracts/OracleAdapter.sol";
import "../contracts/PredictionMarket.sol";
import "../contracts/MarketFactory.sol";
import "../contracts/OutcomeToken1155.sol";
import "../contracts/FeeVault.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title OracleForkTest
 * @dev Fork tests against real Chainlink feeds and tokens on mainnet/testnet.
 *      Validates price feed integration, token interactions, and full market
 *      resolution flows against live infrastructure.
 */
contract OracleForkTest is Test {
    address constant CHAINLINK_ETH_USD = 0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165;

    OracleAdapter public oracle;
    address public owner = makeAddr("owner");
    address public gov   = makeAddr("governor");

    bytes32 public constant ETH_USD = keccak256("ETH/USD");

    function setUp() public {
        OracleAdapter impl = new OracleAdapter();
        bytes memory initData = abi.encodeCall(OracleAdapter.initialize, (owner, gov));
        oracle = OracleAdapter(address(new ERC1967Proxy(address(impl), initData)));

        vm.prank(owner);
        oracle.registerFeed(ETH_USD, CHAINLINK_ETH_USD);
    }



    function test_fork_getPrice_fromRealChainlink() public view {
        (int256 price, uint8 dec) = oracle.getPrice(ETH_USD);
        assertGt(price, 100e8,   "price too low");
        assertLt(price, 100_000e8, "price too high");
        assertEq(dec, 8);
        console.log("Real ETH/USD price:", uint256(price));
    }

    function test_fork_getPriceNormalized_correctScale() public view {
        uint256 normalized = oracle.getPriceNormalized(ETH_USD);
        assertGt(normalized, 100e18);
        assertLt(normalized, 100_000e18);
        console.log("Normalized ETH price (18 dec):", normalized);
    }

    function test_fork_staleness_realFeedIsRecent() public view {
        (int256 price, ) = oracle.getPrice(ETH_USD);
        assertGt(price, 0, "Real Chainlink feed should return non-stale price");
    }



    function test_fork_feedDecimals() public view {
        AggregatorV3Interface feed = AggregatorV3Interface(CHAINLINK_ETH_USD);
        uint8 dec = feed.decimals();
        assertEq(dec, 8, "ETH/USD feed should have 8 decimals");
    }

    function test_fork_feedDescription() public view {
        AggregatorV3Interface feed = AggregatorV3Interface(CHAINLINK_ETH_USD);
        string memory desc = feed.description();
        console.log("Feed description:", desc);
        // Just verify it doesn't revert and returns something
        assertGt(bytes(desc).length, 0, "Description should not be empty");
    }

    function test_fork_feedRoundData() public view {
        AggregatorV3Interface feed = AggregatorV3Interface(CHAINLINK_ETH_USD);
        (uint80 roundId, int256 answer, , uint256 updatedAt, ) = feed.latestRoundData();
        assertGt(roundId, 0, "Round ID should be positive");
        assertGt(answer, 0, "Answer should be positive");
        assertGt(updatedAt, 0, "UpdatedAt should be non-zero");
        console.log("Round ID:", roundId);
        console.log("Updated at:", updatedAt);
    }



    function test_fork_resolveMarket_withChainlinkPrice() public {
        // Get real price
        (int256 price, ) = oracle.getPrice(ETH_USD);
        uint256 ethPrice = uint256(price);

        // Resolve market based on real price threshold
        // e.g., "Will ETH be above $1000?" — almost certainly yes
        bool outcome = ethPrice > 1000e8;

        vm.prank(owner);
        oracle.resolveMarket(0, outcome);

        // Fast forward past dispute window
        vm.warp(block.timestamp + 25 hours);
        oracle.finalizeResolution(0);

        bool finalOutcome = oracle.getFinalOutcome(0);
        assertEq(finalOutcome, outcome, "Final outcome should match price-based resolution");
        console.log("Market resolved with outcome:", finalOutcome);
    }



    function test_fork_stalenessThreshold_tightening() public {
        // Set a very tight staleness threshold (1 second)
        vm.prank(owner);
        oracle.setStalenessThreshold(1);

        // Warp forward so the feed data becomes stale
        vm.warp(block.timestamp + 2 hours);

        // Should revert with stale price
        vm.expectRevert();
        oracle.getPrice(ETH_USD);
    }



    function test_fork_disputeAndOverride() public {
        // Resolve with a wrong outcome
        vm.prank(owner);
        oracle.resolveMarket(0, false);

        // Someone disputes
        address disputer = makeAddr("disputer");
        vm.prank(disputer);
        oracle.disputeResolution(0);

        // Governor overrides
        vm.prank(gov);
        oracle.overrideResolution(0, true);

        bool finalOutcome = oracle.getFinalOutcome(0);
        assertTrue(finalOutcome, "Governor override should set correct outcome");
    }



    function test_fork_multipleFeedRegistration() public {
        bytes32 BTC_USD = keccak256("BTC/USD");

        // Register another feed (using ETH feed address as placeholder since
        // we may not have a real BTC feed on the fork network)
        vm.prank(owner);
        oracle.registerFeed(BTC_USD, CHAINLINK_ETH_USD);

        // Both feeds should work
        (int256 ethPrice, ) = oracle.getPrice(ETH_USD);
        (int256 btcPrice, ) = oracle.getPrice(BTC_USD);

        assertGt(ethPrice, 0);
        assertGt(btcPrice, 0);
    }



    function test_fork_unregisteredFeedReverts() public {
        bytes32 UNKNOWN = keccak256("UNKNOWN/USD");
        vm.expectRevert(abi.encodeWithSelector(OracleAdapter.FeedNotRegistered.selector, UNKNOWN));
        oracle.getPrice(UNKNOWN);
    }
}