// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../contracts/GovernanceToken.sol";

contract GovernanceTokenTest is Test {
    GovernanceToken public token;

    address public owner = makeAddr("owner");
    address public alice = makeAddr("alice");
    address public bob   = makeAddr("bob");
    address public carol = makeAddr("carol");

    uint256 public aliceKey  = 0xA11CE;
    address public aliceAddr;

    function setUp() public {
        token     = new GovernanceToken(owner);
        aliceAddr = vm.addr(aliceKey);

        vm.prank(owner); token.mint(alice, 1000e18);
        vm.prank(owner); token.mint(bob,   500e18);
    }

    function test_name_and_symbol() public view {
        assertEq(token.name(), "PredictDAO Token");
        assertEq(token.symbol(), "PDT");
        assertEq(token.decimals(), 18);
    }

    function test_mint_updatesBalance() public view {
        assertEq(token.balanceOf(alice), 1000e18);
        assertEq(token.balanceOf(bob),   500e18);
    }

    function test_totalSupply_correct() public view {
        assertEq(token.totalSupply(), 1500e18);
    }

    function test_mint_revertsIfNotOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        token.mint(alice, 100e18);
    }

    function test_transfer_works() public {
        vm.prank(alice);
        token.transfer(carol, 200e18);
        assertEq(token.balanceOf(carol), 200e18);
        assertEq(token.balanceOf(alice), 800e18);
    }

    function test_transfer_revertsIfInsufficientBalance() public {
        vm.prank(alice);
        vm.expectRevert();
        token.transfer(carol, 9999e18);
    }

    function test_votingPower_zeroBeforeDelegation() public view {
        assertEq(token.getVotes(alice), 0);
    }

    function test_votingPower_afterSelfDelegate() public {
        vm.prank(alice);
        token.delegate(alice);
        assertEq(token.getVotes(alice), 1000e18);
    }

    function test_votingPower_afterDelegateToOther() public {
        vm.prank(alice);
        token.delegate(bob);
        assertEq(token.getVotes(bob), 1000e18);
        assertEq(token.getVotes(alice), 0);
    }

    function test_votingPower_updatesOnTransfer() public {
        vm.prank(alice);
        token.delegate(alice);
        vm.prank(alice);
        token.transfer(bob, 400e18);
        assertEq(token.getVotes(alice), 600e18);
    }

    function test_getPastVotes_checkpoint() public {
        vm.prank(alice);
        token.delegate(alice);
        uint256 block1 = block.number;
        vm.roll(block1 + 1);
        vm.prank(owner);
        token.mint(alice, 200e18);
        vm.roll(block1 + 2);
        assertEq(token.getPastVotes(alice, block1),     1000e18);
        assertEq(token.getPastVotes(alice, block1 + 1), 1200e18);
    }

    function test_getPastTotalSupply() public {
        uint256 block1 = block.number;
        vm.roll(block1 + 1);
        vm.prank(owner);
        token.mint(carol, 500e18);
        vm.roll(block1 + 2);
        assertEq(token.getPastTotalSupply(block1),     1500e18);
        assertEq(token.getPastTotalSupply(block1 + 1), 2000e18);
    }

    function test_redelegate_updatesVotes() public {
        vm.prank(alice);
        token.delegate(alice);
        assertEq(token.getVotes(alice), 1000e18);
        vm.prank(alice);
        token.delegate(bob);
        assertEq(token.getVotes(alice), 0);
        assertEq(token.getVotes(bob), 1000e18);
    }

    function test_permit_allowsGaslessApprove() public {
        GovernanceToken t = new GovernanceToken(owner);
        vm.prank(owner); t.mint(aliceAddr, 1000e18);

        uint256 amount   = 500e18;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce    = t.nonces(aliceAddr);

        bytes32 structHash = keccak256(abi.encode(
            keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
            aliceAddr, bob, amount, nonce, deadline
        ));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", t.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(aliceKey, digest);

        vm.prank(bob);
        t.permit(aliceAddr, bob, amount, deadline, v, r, s);
        assertEq(t.allowance(aliceAddr, bob), amount);
    }

    function test_permit_revertsIfExpired() public {
        GovernanceToken t = new GovernanceToken(owner);
        vm.prank(owner); t.mint(aliceAddr, 1000e18);
        uint256 deadline = block.timestamp - 1;
        vm.expectRevert();
        t.permit(aliceAddr, bob, 100e18, deadline, 0, bytes32(0), bytes32(0));
    }

    function test_permit_revertsOnWrongSignature() public {
        GovernanceToken t = new GovernanceToken(owner);
        vm.prank(owner); t.mint(aliceAddr, 1000e18);
        uint256 deadline = block.timestamp + 1 hours;
        uint256 bobKey = 0xB0B;
        bytes32 structHash = keccak256(abi.encode(
            keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
            aliceAddr, bob, 100e18, 0, deadline
        ));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", t.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(bobKey, digest);
        vm.expectRevert();
        t.permit(aliceAddr, bob, 100e18, deadline, v, r, s);
    }

    function test_balanceOfAssembly_matchesNormalBalanceOf() public view {
        uint256 via_solidity = token.balanceOf(alice);
        uint256 via_assembly = token.balanceOfAssembly(alice);
        assertEq(via_solidity, via_assembly);
    }

    function testFuzz_mint_totalSupplyConservation(uint96 amount) public {
        uint256 before = token.totalSupply();
        vm.prank(owner);
        token.mint(carol, amount);
        assertEq(token.totalSupply(), before + uint256(amount));
    }

    function testFuzz_votingPower_equalsBalance_afterDelegate(uint96 mintAmount) public {
        vm.prank(owner);
        token.mint(carol, mintAmount);
        vm.prank(carol);
        token.delegate(carol);
        assertEq(token.getVotes(carol), uint256(mintAmount));
    }

    function testFuzz_transfer_votingPowerConserved(uint96 transferAmount) public {
        transferAmount = uint96(bound(transferAmount, 0, 1000e18));
        vm.prank(alice); token.delegate(alice);
        vm.prank(bob);   token.delegate(bob);
        uint256 totalBefore = token.getVotes(alice) + token.getVotes(bob);
        vm.prank(alice);
        token.transfer(bob, transferAmount);
        uint256 totalAfter = token.getVotes(alice) + token.getVotes(bob);
        assertEq(totalBefore, totalAfter);
    }
}