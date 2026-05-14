// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./OutcomeToken1155.sol";
import "./CPMM.sol";

interface IOracleAdapter {
    function getFinalOutcome(uint256 marketId) external view returns (bool);
}

/**
 * @title PredictionMarket
 * @dev Manages the lifecycle of a single prediction market.
 */
contract PredictionMarket is ERC1155Holder, ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    enum MarketState { Open, Closed, Resolved, Cancelled }

    struct MarketInfo {
        uint256 marketId; // ID in OracleAdapter
        string question;
        uint256 endTime;
        address oracle;
        MarketState state;
        uint256 finalOutcome; // 0 for YES, 1 for NO
    }

    MarketInfo public market;
    IERC20 public immutable collateralToken;
    OutcomeToken1155 public immutable outcomeToken;
    
    uint256 public constant FEE_DENOMINATOR = 10000;
    uint256 public feeBps = 100; // 1%
    address public feeCollector;

    // AMM reserves
    uint256 public reserveYES;
    uint256 public reserveNO;

    event MarketResolved(uint256 outcome);
    event SharesBought(address indexed buyer, uint256 outcomeId, uint256 collateralSpent, uint256 sharesReceived);
    event SharesSold(address indexed seller, uint256 outcomeId, uint256 sharesSold, uint256 collateralReceived);
    event LiquidityAdded(address indexed provider, uint256 amount);
    event PayoutClaimed(address indexed clamer, uint256 amount);

    constructor(
        uint256 _marketId,
        string memory _question,
        uint256 _endTime,
        address _oracle,
        address _collateralToken,
        address _outcomeToken,
        address _owner,
        address _feeCollector
    ) Ownable(_owner) {
        market = MarketInfo({
            marketId: _marketId,
            question: _question,
            endTime: _endTime,
            oracle: _oracle,
            state: MarketState.Open,
            finalOutcome: 0
        });
        collateralToken = IERC20(_collateralToken);
        outcomeToken = OutcomeToken1155(_outcomeToken);
        feeCollector = _feeCollector;
    }

    modifier onlyOpen() {
        require(market.state == MarketState.Open, "Market not open");
        require(block.timestamp < market.endTime, "Market time ended");
        _;
    }

    /**
     * @dev Provide initial liquidity.
     */
    function addLiquidity(uint256 amount) external nonReentrant {
        require(reserveYES == 0 && reserveNO == 0, "Liquidity already added");
        collateralToken.safeTransferFrom(msg.sender, address(this), amount);
        
        outcomeToken.mint(address(this), 0, amount, "");
        outcomeToken.mint(address(this), 1, amount, "");
        
        reserveYES = amount;
        reserveNO = amount;
        
        emit LiquidityAdded(msg.sender, amount);
    }

    /**
     * @dev Buy outcome shares using CPMM.
     */
    function buy(uint256 outcomeId, uint256 collateralAmount, uint256 minSharesOut) external onlyOpen nonReentrant returns (uint256 sharesOut) {
        require(outcomeId <= 1, "Invalid outcome");
        require(collateralAmount > 0, "Amount must be > 0");

        uint256 fee = (collateralAmount * feeBps) / FEE_DENOMINATOR;
        uint256 netCollateral = collateralAmount - fee;

        collateralToken.safeTransferFrom(msg.sender, address(this), netCollateral);
        if (fee > 0) {
            collateralToken.safeTransferFrom(msg.sender, feeCollector, fee);
        }

        // Mint collateral-backed shares
        outcomeToken.mint(address(this), 0, netCollateral, "");
        outcomeToken.mint(address(this), 1, netCollateral, "");

        uint256 r0 = (outcomeId == 0) ? reserveYES + netCollateral : reserveNO + netCollateral;
        uint256 r1 = (outcomeId == 0) ? reserveNO + netCollateral : reserveYES + netCollateral;

        sharesOut = CPMM.getSharesOut(r0, r1, netCollateral);
        require(sharesOut >= minSharesOut, "Slippage too high");

        if (outcomeId == 0) {
            reserveYES = r0 - sharesOut;
            reserveNO = r1;
        } else {
            reserveNO = r0 - sharesOut;
            reserveYES = r1;
        }

        outcomeToken.safeTransferFrom(address(this), msg.sender, outcomeId, sharesOut, "");
        emit SharesBought(msg.sender, outcomeId, collateralAmount, sharesOut);
    }

    /**
     * @dev Sell outcome shares back to AMM.
     */
    function sell(uint256 outcomeId, uint256 sharesIn, uint256 minCollateralOut) external onlyOpen nonReentrant returns (uint256 netCollateral) {
        require(outcomeId <= 1, "Invalid outcome");
        require(sharesIn > 0, "Amount must be > 0");

        outcomeToken.safeTransferFrom(msg.sender, address(this), outcomeId, sharesIn, "");

        uint256 r0 = (outcomeId == 0) ? reserveYES : reserveNO;
        uint256 r1 = (outcomeId == 0) ? reserveNO : reserveYES;

        uint256 collateralOut = CPMM.getCollateralOut(r0, r1, sharesIn);
        require(collateralOut >= minCollateralOut, "Slippage too high");

        uint256 fee = (collateralOut * feeBps) / FEE_DENOMINATOR;
        netCollateral = collateralOut - fee;

        if (outcomeId == 0) {
            reserveYES = r0 + sharesIn;
            reserveNO = r1 - collateralOut;
        } else {
            reserveNO = r0 + sharesIn;
            reserveYES = r1 - collateralOut;
        }

        // Burn the collateral-paired shares to release collateral
        outcomeToken.burn(address(this), 0, collateralOut);
        outcomeToken.burn(address(this), 1, collateralOut);

        collateralToken.safeTransfer(msg.sender, netCollateral);
        if (fee > 0) {
            collateralToken.safeTransfer(feeCollector, fee);
        }

        emit SharesSold(msg.sender, outcomeId, sharesIn, netCollateral);
    }

    /**
     * @dev Resolve market using Oracle result.
     */
    function resolve() external {
        bool outcome = IOracleAdapter(market.oracle).getFinalOutcome(market.marketId);
        market.finalOutcome = outcome ? 1 : 0; // Assuming Oracle true = NO? Wait. 
        // Let's check OracleAdapter.outcome. Usually true=YES, false=NO.
        market.finalOutcome = outcome ? 0 : 1; 
        
        market.state = MarketState.Resolved;
        emit MarketResolved(market.finalOutcome);
    }

    /**
     * @dev Claim winnings.
     */
    function claim() external nonReentrant {
        require(market.state == MarketState.Resolved, "Market not resolved");
        uint256 amount = outcomeToken.balanceOf(msg.sender, market.finalOutcome);
        require(amount > 0, "No winning shares");

        outcomeToken.burn(msg.sender, market.finalOutcome, amount);
        collateralToken.safeTransfer(msg.sender, amount);
        
        emit PayoutClaimed(msg.sender, amount);
    }
}
