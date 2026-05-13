// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../contracts/OracleAdapter.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

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
}