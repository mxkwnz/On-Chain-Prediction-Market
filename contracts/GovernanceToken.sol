// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract GovernanceToken is ERC20, ERC20Permit, ERC20Votes, Ownable {

    event TokensMinted(address indexed to, uint256 amount);

    constructor(address initialOwner)
        ERC20("PredictDAO Token", "PDT")
        ERC20Permit("PredictDAO Token")
        Ownable(initialOwner)
    {}

    function balanceOfAssembly(address account) external view returns (uint256 bal) {
        assembly {
            mstore(0x00, account)
            mstore(0x20, 0x00)         
            let slot := keccak256(0x00, 0x40)
            bal := sload(slot)
        }
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
        emit TokensMinted(to, amount);
    }

    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Votes)
    {
        super._update(from, to, value);
    }

    function nonces(address owner)
        public
        view
        override(ERC20Permit, Nonces)
        returns (uint256)
    {
        return super.nonces(owner);
    }
}