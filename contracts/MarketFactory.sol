// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./PredictionMarket.sol";
import "./OutcomeToken1155.sol";

/**
 * @title MarketFactory
 * @dev Factory for deploying PredictionMarket contracts using CREATE and CREATE2.
 */
contract MarketFactory {
    address[] public allMarkets;
    address public immutable collateralToken;
    address public feeCollector;
    address public oracleAdapter;

    event MarketCreated(address indexed marketAddress, uint256 marketId, string question, uint256 endTime);

    constructor(address _collateralToken, address _feeCollector, address _oracleAdapter) {
        collateralToken = _collateralToken;
        feeCollector = _feeCollector;
        oracleAdapter = _oracleAdapter;
    }

    /**
     * @dev Create a new prediction market using CREATE.
     */
    function createMarket(
        string memory question,
        uint256 endTime
    ) external returns (address) {
        uint256 marketId = allMarkets.length;
        
        OutcomeToken1155 outcomeToken = new OutcomeToken1155("");
        
        PredictionMarket market = new PredictionMarket(
            marketId,
            question,
            endTime,
            oracleAdapter,
            collateralToken,
            address(outcomeToken),
            msg.sender,
            feeCollector
        );

        outcomeToken.transferOwnership(address(market));

        allMarkets.push(address(market));
        emit MarketCreated(address(market), marketId, question, endTime);
        return address(market);
    }

    /**
     * @dev Create a new prediction market using CREATE2.
     */
    function createMarketDeterministic(
        string memory question,
        uint256 endTime,
        bytes32 salt
    ) external returns (address) {
        uint256 marketId = allMarkets.length;
        
        OutcomeToken1155 outcomeToken = new OutcomeToken1155{salt: salt}("");
        
        PredictionMarket market = new PredictionMarket{salt: salt}(
            marketId,
            question,
            endTime,
            oracleAdapter,
            collateralToken,
            address(outcomeToken),
            msg.sender,
            feeCollector
        );

        outcomeToken.transferOwnership(address(market));

        allMarkets.push(address(market));
        emit MarketCreated(address(market), marketId, question, endTime);
        return address(market);
    }

    function getMarketsCount() external view returns (uint256) {
        return allMarkets.length;
    }
}
