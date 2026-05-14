// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title OutcomeToken1155
 * @dev ERC1155 token representing YES/NO outcome shares for prediction markets.
 * Nursultan is responsible for this, but implemented here for Mukhammedali's core logic.
 */
contract OutcomeToken1155 is ERC1155, Ownable {
    uint256 public constant YES = 0;
    uint256 public constant NO = 1;

    constructor(string memory uri) ERC1155(uri) Ownable(msg.sender) {}

    function mint(address to, uint256 id, uint256 amount, bytes memory data) external onlyOwner {
        _mint(to, id, amount, data);
    }

    function burn(address from, uint256 id, uint256 amount) external onlyOwner {
        _burn(from, id, amount);
    }

    function setURI(string memory newuri) external onlyOwner {
        _setURI(newuri);
    }
}
