// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

contract VulnerableClaim {
    mapping(address => uint256) public balances;

    function deposit() external payable {
        balances[msg.sender] += msg.value;
    }

    function withdraw() external {
        uint256 amount = balances[msg.sender];
        require(amount > 0, "nothing to withdraw");
        (bool ok, ) = msg.sender.call{value: amount}("");
        require(ok, "transfer failed");
        balances[msg.sender] = 0; 
    }

    receive() external payable {}
}

contract SafeClaim {
    mapping(address => uint256) public balances;

    function deposit() external payable {
        balances[msg.sender] += msg.value;
    }

    function withdraw() external {
        uint256 amount = balances[msg.sender];
        require(amount > 0, "nothing to withdraw");
        balances[msg.sender] = 0;
        (bool ok, ) = msg.sender.call{value: amount}("");
        require(ok, "transfer failed");
    }

    receive() external payable {}
}

contract ReentrancyAttacker {
    VulnerableClaim public target;
    uint256 public stolenAmount;

    constructor(VulnerableClaim _target) payable {
        target = _target;
    }

    function attack() external payable {
        target.deposit{value: 1 ether}();
        target.withdraw();
    }

    receive() external payable {
        stolenAmount += msg.value;
        if (address(target).balance >= 1 ether) {
            target.withdraw(); 
        }
    }
}

contract VulnerableAdmin {
    address public owner;
    uint256 public fee;

    constructor() {
        owner = msg.sender;
        fee   = 100;
    }

    function setFee(uint256 newFee) external {
        fee = newFee;
    }
}

contract SafeAdmin {
    address public owner;
    uint256 public fee;

    error NotOwner();

    constructor() {
        owner = msg.sender;
        fee   = 100;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    function setFee(uint256 newFee) external onlyOwner {
        fee = newFee;
    }
}

contract SecurityCasesTest is Test {
    VulnerableClaim  public vulnerable;
    SafeClaim        public safe;
    ReentrancyAttacker public attacker;
    VulnerableAdmin  public vulnAdmin;
    SafeAdmin        public safeAdmin;

    address public alice = makeAddr("alice");

    function setUp() public {
        vulnerable = new VulnerableClaim();
        safe       = new SafeClaim();
        vulnAdmin  = new VulnerableAdmin();
        safeAdmin  = new SafeAdmin();

        vm.deal(alice, 10 ether);
        vm.prank(alice);
        vulnerable.deposit{value: 5 ether}();

        vm.prank(alice);
        safe.deposit{value: 5 ether}();
    }

    function test_BEFORE_reentrancy_attack_succeeds() public {
        attacker = new ReentrancyAttacker{value: 1 ether}(vulnerable);

        uint256 balanceBefore = address(alice).balance;

        attacker.attack{value: 1 ether}();

        assertGt(attacker.stolenAmount(), 1 ether, "reentrancy should have stolen extra ETH");
    }

    function test_AFTER_reentrancy_attack_fails() public {
        SafeReentrancyAttacker safeAttacker = new SafeReentrancyAttacker{value: 1 ether}(safe);
        safeAttacker.attack();
        assertEq(safeAttacker.stolenAmount(), 1 ether);
    }

    function test_BEFORE_accessControl_anyoneCanSetFee() public {
        vm.prank(alice); 
        vulnAdmin.setFee(0); 
        assertEq(vulnAdmin.fee(), 0);
    }

    function test_AFTER_accessControl_onlyOwnerCanSetFee() public {
        vm.prank(alice);
        vm.expectRevert(SafeAdmin.NotOwner.selector);
        safeAdmin.setFee(0);
        assertEq(safeAdmin.fee(), 100);
    }

    function test_AFTER_accessControl_ownerCanSetFee() public {
        safeAdmin.setFee(200);
        assertEq(safeAdmin.fee(), 200);
    }
}

contract SafeReentrancyAttacker {
    SafeClaim public target;
    uint256 public stolenAmount;

    constructor(SafeClaim _target) payable {
        target = _target;
    }

    function attack() external {
        target.deposit{value: 1 ether}();
        target.withdraw();
    }

    receive() external payable {
        stolenAmount += msg.value;
        if (address(target).balance >= 1 ether) {
            try target.withdraw() {} catch {} 
        }
    }
}