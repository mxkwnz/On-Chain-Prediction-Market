// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract MockAggregator is AggregatorV3Interface {
    int256  private _price;
    uint8   private _decimals;
    uint256 private _updatedAt;
    uint80  private _roundId;
    string  private _description;

    constructor(int256 initialPrice, uint8 dec, string memory desc) {
        _price     = initialPrice;
        _decimals  = dec;
        _updatedAt = block.timestamp;
        _roundId   = 1;
        _description = desc;
    }

    function setPrice(int256 newPrice) external {
        _price = newPrice;
        _roundId++;
        _updatedAt = block.timestamp;
    }

    function setUpdatedAt(uint256 ts) external { _updatedAt = ts; }

    function makeStale(uint256 ageInSeconds) external {
        _updatedAt = block.timestamp - ageInSeconds;
    }

    function decimals() external view override returns (uint8) { return _decimals; }
    function description() external view override returns (string memory) { return _description; }
    function version() external pure override returns (uint256) { return 3; }

    function getRoundData(uint80) external view override
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (_roundId, _price, _updatedAt, _updatedAt, _roundId);
    }

    function latestRoundData() external view override
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (_roundId, _price, _updatedAt, _updatedAt, _roundId);
    }
}