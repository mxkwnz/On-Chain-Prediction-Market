// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title OutcomeToken1155
 * @dev ERC1155 token representing YES/NO outcome shares for prediction markets.
 *      Token ID 0 = YES outcome, Token ID 1 = NO outcome.
 *      Only the owner (PredictionMarket contract) can mint and burn tokens.
 */
contract OutcomeToken1155 is ERC1155, Ownable {
    uint256 public constant YES = 0;
    uint256 public constant NO = 1;

    /// @dev Track total supply per token ID for transparency
    mapping(uint256 => uint256) private _totalSupply;

    event OutcomeMinted(address indexed to, uint256 indexed id, uint256 amount);
    event OutcomeBurned(address indexed from, uint256 indexed id, uint256 amount);
    event OutcomeBatchMinted(address indexed to, uint256[] ids, uint256[] amounts);
    event OutcomeBatchBurned(address indexed from, uint256[] ids, uint256[] amounts);

    constructor(string memory uri) ERC1155(uri) Ownable(msg.sender) {}

    /**
     * @dev Mint outcome shares. Only callable by market contract (owner).
     */
    function mint(address to, uint256 id, uint256 amount, bytes memory data) external onlyOwner {
        _totalSupply[id] += amount;
        _mint(to, id, amount, data);
        emit OutcomeMinted(to, id, amount);
    }

    /**
     * @dev Burn outcome shares. Only callable by market contract (owner).
     */
    function burn(address from, uint256 id, uint256 amount) external onlyOwner {
        _totalSupply[id] -= amount;
        _burn(from, id, amount);
        emit OutcomeBurned(from, id, amount);
    }

    /**
     * @dev Batch mint multiple outcome types in a single tx (gas efficient).
     */
    function mintBatch(
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) external onlyOwner {
        for (uint256 i = 0; i < ids.length; i++) {
            _totalSupply[ids[i]] += amounts[i];
        }
        _mintBatch(to, ids, amounts, data);
        emit OutcomeBatchMinted(to, ids, amounts);
    }

    /**
     * @dev Batch burn multiple outcome types in a single tx (gas efficient).
     */
    function burnBatch(
        address from,
        uint256[] memory ids,
        uint256[] memory amounts
    ) external onlyOwner {
        for (uint256 i = 0; i < ids.length; i++) {
            _totalSupply[ids[i]] -= amounts[i];
        }
        _burnBatch(from, ids, amounts);
        emit OutcomeBatchBurned(from, ids, amounts);
    }

    /**
     * @dev Returns the total supply of a given token ID.
     */
    function totalSupply(uint256 id) external view returns (uint256) {
        return _totalSupply[id];
    }

    /**
     * @dev Returns true if any tokens of the given ID have been minted.
     */
    function exists(uint256 id) external view returns (bool) {
        return _totalSupply[id] > 0;
    }

    /**
     * @dev Update the metadata URI. Only callable by owner.
     */
    function setURI(string memory newuri) external onlyOwner {
        _setURI(newuri);
    }
}
