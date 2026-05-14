// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../contracts/OracleAdapter.sol";
import "../contracts/mocks/MockAggregator.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract OracleAdapterTest is Test {
    OracleAdapter  public oracle;
    MockAggregator public mockFeed;

    address public owner  = makeAddr("owner");
    address public gov    = makeAddr("governor");
    address public alice  = makeAddr("alice");
    address public bob    = makeAddr("bob");

    bytes32 public constant ETH_USD = keccak256("ETH/USD");

    function setUp() public {
        OracleAdapter impl = new OracleAdapter();
        bytes memory initData = abi.encodeCall(OracleAdapter.initialize, (owner, gov));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        oracle = OracleAdapter(address(proxy));

        mockFeed = new MockAggregator(2000e8, 8, "ETH/USD");

        vm.prank(owner);
        oracle.registerFeed(ETH_USD, address(mockFeed));
    }

    function test_registerFeed_storesCorrectly() public view {
        assertEq(address(oracle.feeds(ETH_USD)), address(mockFeed));
    }

    function test_registerFeed_revertsIfNotOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        oracle.registerFeed(keccak256("BTC/USD"), address(mockFeed));
    }

    function test_registerFeed_revertsOnZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(OracleAdapter.ZeroAddress.selector);
        oracle.registerFeed(keccak256("BTC/USD"), address(0));
    }

    function test_getPrice_revertsOnUnknownFeed() public {
        vm.expectRevert(
            abi.encodeWithSelector(OracleAdapter.FeedNotRegistered.selector, keccak256("FAKE"))
        );
        oracle.getPrice(keccak256("FAKE"));
    }

    function test_getPrice_returnsCorrectPrice() public view {
        (int256 price, uint8 dec) = oracle.getPrice(ETH_USD);
        assertEq(price, 2000e8);
        assertEq(dec, 8);
    }

    function test_getPrice_revertsIfStale() public {
        mockFeed.makeStale(2 hours);
        vm.expectRevert();
        oracle.getPrice(ETH_USD);
    }

    function test_getPrice_revertsIfPriceZero() public {
        mockFeed.setPrice(0);
        vm.expectRevert(abi.encodeWithSelector(OracleAdapter.InvalidPrice.selector, 0));
        oracle.getPrice(ETH_USD);
    }

    function test_getPrice_revertsIfPriceNegative() public {
        mockFeed.setPrice(-1);
        vm.expectRevert(abi.encodeWithSelector(OracleAdapter.InvalidPrice.selector, -1));
        oracle.getPrice(ETH_USD);
    }

    function test_getPriceNormalized_8decimals() public view {
        uint256 n = oracle.getPriceNormalized(ETH_USD);
        assertEq(n, 2000e18);
    }

    function test_staleness_exactlyAtThreshold_passes() public {
        mockFeed.makeStale(1 hours);
        (int256 price, ) = oracle.getPrice(ETH_USD);
        assertEq(price, 2000e8);
    }

    function test_setStalenessThreshold_works() public {
        vm.prank(owner);
        oracle.setStalenessThreshold(30 minutes);
        assertEq(oracle.stalenessThreshold(), 30 minutes);

        mockFeed.makeStale(45 minutes);
        vm.expectRevert();
        oracle.getPrice(ETH_USD);
    }

    function test_setStalenessThreshold_revertsIfNotOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        oracle.setStalenessThreshold(30 minutes);
    }

    function test_resolveMarket_setsProposed() public {
        vm.prank(owner);
        oracle.resolveMarket(1, true);
        (bool proposed, bool outcome, , , , ) = oracle.resolutions(1);
        assertTrue(proposed);
        assertTrue(outcome);
    }

    function test_resolveMarket_revertsIfAlreadyResolved() public {
        vm.prank(owner);
        oracle.resolveMarket(1, true);
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(OracleAdapter.AlreadyResolved.selector, 1));
        oracle.resolveMarket(1, true);
    }

    function test_resolveMarket_revertsIfNotOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        oracle.resolveMarket(1, true);
    }

    function test_disputeResolution_works() public {
        vm.prank(owner);
        oracle.resolveMarket(1, true);
        vm.prank(alice);
        oracle.disputeResolution(1);
        (, , , bool disputed, , ) = oracle.resolutions(1);
        assertTrue(disputed);
    }

    function test_disputeResolution_revertsAfterWindow() public {
        vm.prank(owner);
        oracle.resolveMarket(1, true);
        vm.warp(block.timestamp + 25 hours);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(OracleAdapter.DisputeWindowClosed.selector, 1));
        oracle.disputeResolution(1);
    }

    function test_disputeResolution_revertsIfAlreadyDisputed() public {
        vm.prank(owner);
        oracle.resolveMarket(1, true);
        vm.prank(alice);
        oracle.disputeResolution(1);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(OracleAdapter.AlreadyDisputed.selector, 1));
        oracle.disputeResolution(1);
    }

    function test_disputeResolution_revertsIfNotResolved() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(OracleAdapter.NotYetResolved.selector, 99));
        oracle.disputeResolution(99);
    }

    function test_disputeResolution_revertsIfFinalized() public {
        vm.prank(owner);
        oracle.resolveMarket(1, true);
        vm.warp(block.timestamp + 25 hours);
        oracle.finalizeResolution(1);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(OracleAdapter.AlreadyFinalized.selector, 1));
        oracle.disputeResolution(1);
    }

    function test_overrideResolution_byGovernor() public {
        vm.prank(owner);
        oracle.resolveMarket(1, true);
        vm.prank(alice);
        oracle.disputeResolution(1);
        vm.prank(gov);
        oracle.overrideResolution(1, false);
        (, , , , bool finalized, bool finalOutcome) = oracle.resolutions(1);
        assertTrue(finalized);
        assertFalse(finalOutcome);
    }

    function test_overrideResolution_revertsIfNotGovernor() public {
        vm.prank(owner);
        oracle.resolveMarket(1, true);
        vm.prank(alice);
        oracle.disputeResolution(1);
        vm.prank(alice);
        vm.expectRevert(OracleAdapter.NotGovernor.selector);
        oracle.overrideResolution(1, false);
    }

    function test_overrideResolution_revertsIfNotDisputed() public {
        vm.prank(owner);
        oracle.resolveMarket(1, true);
        vm.prank(gov);
        vm.expectRevert(abi.encodeWithSelector(OracleAdapter.NotDisputed.selector, 1));
        oracle.overrideResolution(1, false);
    }

    function test_overrideResolution_revertsIfAlreadyFinalized() public {
        vm.prank(owner);
        oracle.resolveMarket(1, true);
        vm.prank(alice);
        oracle.disputeResolution(1);
        vm.prank(gov);
        oracle.overrideResolution(1, false);
        vm.prank(gov);
        vm.expectRevert(abi.encodeWithSelector(OracleAdapter.AlreadyFinalized.selector, 1));
        oracle.overrideResolution(1, false);
    }

    function test_finalizeResolution_afterWindow() public {
        vm.prank(owner);
        oracle.resolveMarket(1, true);
        vm.warp(block.timestamp + 25 hours);
        vm.prank(alice);
        oracle.finalizeResolution(1);
        (, , , , bool finalized, bool finalOutcome) = oracle.resolutions(1);
        assertTrue(finalized);
        assertTrue(finalOutcome);
    }

    function test_finalizeResolution_revertsInsideWindow() public {
        vm.prank(owner);
        oracle.resolveMarket(1, true);
        vm.warp(block.timestamp + 10 hours);
        vm.expectRevert(abi.encodeWithSelector(OracleAdapter.DisputeWindowStillOpen.selector, 1));
        oracle.finalizeResolution(1);
    }

    function test_finalizeResolution_revertsIfDisputed() public {
        vm.prank(owner);
        oracle.resolveMarket(1, true);
        vm.prank(alice);
        oracle.disputeResolution(1);
        vm.warp(block.timestamp + 48 hours);
        vm.expectRevert(abi.encodeWithSelector(OracleAdapter.DisputeWindowStillOpen.selector, 1));
        oracle.finalizeResolution(1);
    }

    function test_getFinalOutcome_revertsIfNotFinalized() public {
        vm.prank(owner);
        oracle.resolveMarket(1, true);
        vm.expectRevert("OracleAdapter: not finalized yet");
        oracle.getFinalOutcome(1);
    }

    function test_getFinalOutcome_afterFinalize() public {
        vm.prank(owner);
        oracle.resolveMarket(1, false);
        vm.warp(block.timestamp + 25 hours);
        oracle.finalizeResolution(1);
        assertFalse(oracle.getFinalOutcome(1));
    }

    function test_setGovernor_revertsOnZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(OracleAdapter.ZeroAddress.selector);
        oracle.setGovernor(address(0));
    }

    function test_setGovernor_updatesCorrectly() public {
        vm.prank(owner);
        oracle.setGovernor(alice);
        assertEq(oracle.governor(), alice);
    }

    function testFuzz_getPriceNormalized_alwaysPositive(int256 rawPrice) public {
        rawPrice = bound(rawPrice, 1, int256(1e30));
        mockFeed.setPrice(rawPrice);
        uint256 n = oracle.getPriceNormalized(ETH_USD);
        assertGt(n, 0);
    }

    function testFuzz_resolveAndFinalize_outcomePreserved(uint256 marketId, bool outcome) public {
        vm.assume(marketId < type(uint128).max);
        vm.prank(owner);
        oracle.resolveMarket(marketId, outcome);
        vm.warp(block.timestamp + 25 hours);
        oracle.finalizeResolution(marketId);
        assertEq(oracle.getFinalOutcome(marketId), outcome);
    }

    function testFuzz_staleness_revertsWhenOlderThanThreshold(uint256 priceAge) public {
        priceAge = bound(priceAge, 1 hours + 1, 100 days);
        mockFeed.makeStale(priceAge);
        vm.expectRevert();
        oracle.getPrice(ETH_USD);
    }

    function testFuzz_multipleMarketsIndependent(uint256 idA, uint256 idB, bool outcomeA, bool outcomeB) public {
        vm.assume(idA != idB);
        vm.assume(idA < type(uint64).max);
        vm.assume(idB < type(uint64).max);

        vm.prank(owner);
        oracle.resolveMarket(idA, outcomeA);
        vm.prank(owner);
        oracle.resolveMarket(idB, outcomeB);

        vm.warp(block.timestamp + 25 hours);
        oracle.finalizeResolution(idA);
        oracle.finalizeResolution(idB);

        assertEq(oracle.getFinalOutcome(idA), outcomeA);
        assertEq(oracle.getFinalOutcome(idB), outcomeB);
    }
}