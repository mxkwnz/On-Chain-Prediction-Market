// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../contracts/GovernanceToken.sol";
import "../contracts/MarketGovernor.sol";
import "../contracts/Timelock.sol";
import "../contracts/OracleAdapter.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract GovernorTest is Test {
    GovernanceToken public token;
    Timelock        public timelock;
    MarketGovernor  public governor;
    OracleAdapter   public oracle;

    address public deployer = makeAddr("deployer");
    address public whale    = makeAddr("whale");
    address public alice    = makeAddr("alice");
    address public bob      = makeAddr("bob");
    address public stranger = makeAddr("stranger");

    uint256 public constant TOTAL_SUPPLY = 1_000_000e18;

    function setUp() public {
        vm.startPrank(deployer);

        token = new GovernanceToken(deployer);

        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](1);
        executors[0] = address(0);
        timelock = new Timelock(proposers, executors, deployer);

        governor = new MarketGovernor(
            IVotes(address(token)),
            TimelockController(payable(address(timelock)))
        );

        timelock.grantRole(timelock.PROPOSER_ROLE(),  address(governor));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));
        timelock.revokeRole(timelock.DEFAULT_ADMIN_ROLE(), deployer);

        OracleAdapter impl = new OracleAdapter();
        bytes memory initData = abi.encodeCall(
            OracleAdapter.initialize,
            (address(timelock), address(governor))
        );
        oracle = OracleAdapter(address(new ERC1967Proxy(address(impl), initData)));

        token.mint(whale, TOTAL_SUPPLY * 60 / 100);
        token.mint(alice, TOTAL_SUPPLY * 20 / 100);
        token.mint(bob,   TOTAL_SUPPLY * 20 / 100);

        vm.stopPrank();

        vm.prank(whale); token.delegate(whale);
        vm.prank(alice); token.delegate(alice);
        vm.prank(bob);   token.delegate(bob);
        vm.roll(block.number + 1);
    }

    function test_votingDelay_is1day() public view {
        assertEq(governor.votingDelay(), 1 days);
    }

    function test_votingPeriod_is1week() public view {
        assertEq(governor.votingPeriod(), 1 weeks);
    }

    function test_quorumNumerator_is4percent() public view {
        assertEq(governor.quorumNumerator(), 4);
    }

    function test_proposalThreshold_is1percent() public view {
        assertEq(governor.proposalThreshold(), TOTAL_SUPPLY / 100);
    }

    function test_timelock_minDelay_is2days() public view {
        assertEq(timelock.getMinDelay(), 2 days);
    }


    function test_fullLifecycle_proposeVoteQueueExecute() public {
        address[] memory targets   = new address[](1);
        uint256[] memory values    = new uint256[](1);
        bytes[]   memory calldatas = new bytes[](1);
        targets[0]    = address(oracle);
        calldatas[0]  = abi.encodeCall(OracleAdapter.setStalenessThreshold, (30 minutes));
        string memory desc = "Proposal 1: reduce staleness to 30 min";

        vm.prank(whale);
        uint256 pid = governor.propose(targets, values, calldatas, desc);
        assertEq(uint256(governor.state(pid)), uint256(IGovernor.ProposalState.Pending));

        vm.warp(block.timestamp + 1 days + 1);
        vm.roll(block.number + 1);
        assertEq(uint256(governor.state(pid)), uint256(IGovernor.ProposalState.Active));

        vm.prank(whale); governor.castVote(pid, 1);
        vm.prank(alice); governor.castVote(pid, 0);

        vm.warp(block.timestamp + 1 weeks + 1);
        vm.roll(block.number + 1);
        assertEq(uint256(governor.state(pid)), uint256(IGovernor.ProposalState.Succeeded));

        bytes32 descHash = keccak256(bytes(desc));
        governor.queue(targets, values, calldatas, descHash);
        assertEq(uint256(governor.state(pid)), uint256(IGovernor.ProposalState.Queued));

        vm.warp(block.timestamp + 2 days + 1);

        governor.execute(targets, values, calldatas, descHash);
        assertEq(uint256(governor.state(pid)), uint256(IGovernor.ProposalState.Executed));

        assertEq(oracle.stalenessThreshold(), 30 minutes);
    }

    function test_propose_revertsIfBelowThreshold() public {
        address[] memory targets   = new address[](1);
        uint256[] memory values    = new uint256[](1);
        bytes[]   memory calldatas = new bytes[](1);
        targets[0]   = address(oracle);
        calldatas[0] = abi.encodeCall(OracleAdapter.setStalenessThreshold, (30 minutes));
        vm.prank(stranger);
        vm.expectRevert();
        governor.propose(targets, values, calldatas, "Should fail");
    }

    function test_castVote_doubleVote_reverts() public {
        address[] memory targets   = new address[](1);
        uint256[] memory values    = new uint256[](1);
        bytes[]   memory calldatas = new bytes[](1);
        targets[0]   = address(oracle);
        calldatas[0] = abi.encodeCall(OracleAdapter.setStalenessThreshold, (30 minutes));
        vm.prank(whale);
        uint256 pid = governor.propose(targets, values, calldatas, "double vote");
        vm.warp(block.timestamp + 1 days + 1);
        vm.roll(block.number + 1);
        vm.prank(whale); governor.castVote(pid, 1);
        vm.prank(whale);
        vm.expectRevert();
        governor.castVote(pid, 1);
    }

    function test_castVote_revertsIfNotActive() public {
        address[] memory targets   = new address[](1);
        uint256[] memory values    = new uint256[](1);
        bytes[]   memory calldatas = new bytes[](1);
        targets[0]   = address(oracle);
        calldatas[0] = abi.encodeCall(OracleAdapter.setStalenessThreshold, (30 minutes));
        vm.prank(whale);
        uint256 pid = governor.propose(targets, values, calldatas, "too early");
        vm.prank(alice);
        vm.expectRevert();
        governor.castVote(pid, 1);
    }

    function test_hasVoted_returnsTrueAfterVote() public {
        address[] memory targets   = new address[](1);
        uint256[] memory values    = new uint256[](1);
        bytes[]   memory calldatas = new bytes[](1);
        targets[0]   = address(oracle);
        calldatas[0] = abi.encodeCall(OracleAdapter.setStalenessThreshold, (30 minutes));
        vm.prank(whale);
        uint256 pid = governor.propose(targets, values, calldatas, "hasVoted");
        vm.warp(block.timestamp + 1 days + 1);
        vm.roll(block.number + 1);
        assertFalse(governor.hasVoted(pid, whale));
        vm.prank(whale);
        governor.castVote(pid, 1);
        assertTrue(governor.hasVoted(pid, whale));
    }

    function test_proposal_defeated_withoutQuorum() public {
        vm.prank(deployer);
        GovernanceToken t = new GovernanceToken(address(this));
        address[] memory p = new address[](0);
        address[] memory e = new address[](1);
        e[0] = address(0);
        Timelock tl = new Timelock(p, e, address(this));
        MarketGovernor g = new MarketGovernor(IVotes(address(t)), TimelockController(payable(address(tl))));
        tl.grantRole(tl.PROPOSER_ROLE(), address(g));
        tl.revokeRole(tl.DEFAULT_ADMIN_ROLE(), address(this));

        uint256 supply = 1_000_000e18;
        t.mint(whale, supply * 98 / 100);
        t.mint(alice, supply * 1  / 100 + 1); 

        vm.prank(whale); t.delegate(whale);
        vm.prank(alice); t.delegate(alice);
        vm.roll(block.number + 1);

        address[] memory targets   = new address[](1);
        uint256[] memory values    = new uint256[](1);
        bytes[]   memory calldatas = new bytes[](1);
        targets[0] = address(oracle);
        calldatas[0] = abi.encodeCall(OracleAdapter.setStalenessThreshold, (30 minutes));

        vm.prank(alice);
        uint256 pid = g.propose(targets, values, calldatas, "low quorum");
        vm.warp(block.timestamp + 1 days + 1);
        vm.roll(block.number + 1);
        vm.prank(alice);
        g.castVote(pid, 1);
        vm.warp(block.timestamp + 1 weeks + 1);
        vm.roll(block.number + 1);
        assertEq(uint256(g.state(pid)), uint256(IGovernor.ProposalState.Defeated));
    }

    function test_governance_overrideDisputedResolution() public {
        vm.prank(address(timelock));
        oracle.resolveMarket(42, true);

        vm.prank(alice);
        oracle.disputeResolution(42);

        address[] memory targets   = new address[](1);
        uint256[] memory values    = new uint256[](1);
        bytes[]   memory calldatas = new bytes[](1);
        targets[0]   = address(oracle);
        calldatas[0] = abi.encodeCall(OracleAdapter.overrideResolution, (42, false));
        string memory desc = "Override market 42 to NO";

        vm.prank(whale);
        uint256 pid = governor.propose(targets, values, calldatas, desc);
        vm.warp(block.timestamp + 1 days + 1);
        vm.roll(block.number + 1);
        vm.prank(whale); governor.castVote(pid, 1);
        vm.prank(alice); governor.castVote(pid, 1);
        vm.prank(bob);   governor.castVote(pid, 1);
        vm.warp(block.timestamp + 1 weeks + 1);
        vm.roll(block.number + 1);
        bytes32 descHash = keccak256(bytes(desc));
        governor.queue(targets, values, calldatas, descHash);
        vm.warp(block.timestamp + 2 days + 1);
        governor.execute(targets, values, calldatas, descHash);

        assertFalse(oracle.getFinalOutcome(42));
    }

    function testFuzz_proposalThreshold_enforcement(uint96 balance) public {
        uint256 threshold = governor.proposalThreshold();
        address voter = makeAddr("fuzzVoter");
        vm.prank(deployer);
        token.mint(voter, balance);
        vm.prank(voter);
        token.delegate(voter);
        vm.roll(block.number + 1);

        address[] memory targets   = new address[](1);
        uint256[] memory values    = new uint256[](1);
        bytes[]   memory calldatas = new bytes[](1);
        targets[0]   = address(oracle);
        calldatas[0] = abi.encodeCall(OracleAdapter.setStalenessThreshold, (30 minutes));

        if (uint256(balance) >= threshold) {
            vm.prank(voter);
            governor.propose(targets, values, calldatas, "fuzz ok");
        } else {
            vm.prank(voter);
            vm.expectRevert();
            governor.propose(targets, values, calldatas, "fuzz fail");
        }
    }
}