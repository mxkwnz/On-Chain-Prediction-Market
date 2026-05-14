// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract OracleAdapter is Initializable, OwnableUpgradeable, UUPSUpgradeable {

    uint256 public constant DEFAULT_STALENESS = 1 hours;
    uint256 public constant DEFAULT_DISPUTE_WINDOW = 24 hours;

    uint256 public stalenessThreshold;
    uint256 public disputeWindow;
    address public governor;

    mapping(bytes32 => AggregatorV3Interface) public feeds;

    struct Resolution {
        bool proposed;
        bool outcome;
        uint256 proposedAt;
        bool disputed;
        bool finalized;
        bool finalOutcome;
    }

    mapping(uint256 => Resolution) public resolutions;

    event FeedRegistered(bytes32 indexed key, address feed);
    event MarketResolved(uint256 indexed marketId, bool outcome, uint256 proposedAt);
    event ResolutionDisputed(uint256 indexed marketId, address indexed disputer);
    event ResolutionOverridden(uint256 indexed marketId, bool newOutcome);
    event ResolutionFinalized(uint256 indexed marketId, bool finalOutcome);
    event StalenessThresholdUpdated(uint256 newThreshold);
    event DisputeWindowUpdated(uint256 newWindow);
    event GovernorUpdated(address newGovernor);

    error FeedNotRegistered(bytes32 key);
    error StalePrice(uint256 updatedAt, uint256 threshold);
    error InvalidPrice(int256 price);
    error AlreadyResolved(uint256 marketId);
    error NotYetResolved(uint256 marketId);
    error DisputeWindowClosed(uint256 marketId);
    error AlreadyDisputed(uint256 marketId);
    error AlreadyFinalized(uint256 marketId);
    error DisputeWindowStillOpen(uint256 marketId);
    error NotGovernor();
    error NotDisputed(uint256 marketId);
    error ZeroAddress();

    function initialize(address _owner, address _governor) external initializer {
        if (_owner == address(0)) revert ZeroAddress();
        __Ownable_init(_owner);
        stalenessThreshold = DEFAULT_STALENESS;
        disputeWindow = DEFAULT_DISPUTE_WINDOW;
        governor = _governor;
    }

    function getTimestampAssembly() public view returns (uint256 ts) {
        assembly {
            ts := timestamp()
        }
    }

    function registerFeed(bytes32 key, address feed) external onlyOwner {
        if (feed == address(0)) revert ZeroAddress();
        feeds[key] = AggregatorV3Interface(feed);
        emit FeedRegistered(key, feed);
    }

    function getPrice(bytes32 key) external view returns (int256 price, uint8 decimals) {
        AggregatorV3Interface feed = feeds[key];
        if (address(feed) == address(0)) revert FeedNotRegistered(key);

        (, int256 answer, , uint256 updatedAt, ) = feed.latestRoundData();

        if (block.timestamp - updatedAt > stalenessThreshold) {
            revert StalePrice(updatedAt, stalenessThreshold);
        }
        if (answer <= 0) revert InvalidPrice(answer);

        return (answer, feed.decimals());
    }

    function getPriceNormalized(bytes32 key) external view returns (uint256) {
        AggregatorV3Interface feed = feeds[key];
        if (address(feed) == address(0)) revert FeedNotRegistered(key);

        (, int256 answer, , uint256 updatedAt, ) = feed.latestRoundData();
        if (block.timestamp - updatedAt > stalenessThreshold) {
            revert StalePrice(updatedAt, stalenessThreshold);
        }
        if (answer <= 0) revert InvalidPrice(answer);

        uint8 dec = feed.decimals();
        if (dec < 18) return uint256(answer) * (10 ** (18 - dec));
        if (dec > 18) return uint256(answer) / (10 ** (dec - 18));
        return uint256(answer);
    }

    function resolveMarket(uint256 marketId, bool outcome) external onlyOwner {
        Resolution storage r = resolutions[marketId];
        if (r.proposed) revert AlreadyResolved(marketId);
        r.proposed = true;
        r.outcome = outcome;
        r.proposedAt = block.timestamp;
        emit MarketResolved(marketId, outcome, block.timestamp);
    }

    function disputeResolution(uint256 marketId) external {
        Resolution storage r = resolutions[marketId];
        if (!r.proposed) revert NotYetResolved(marketId);
        if (r.finalized) revert AlreadyFinalized(marketId);
        if (r.disputed) revert AlreadyDisputed(marketId);
        if (block.timestamp > r.proposedAt + disputeWindow) {
            revert DisputeWindowClosed(marketId);
        }
        r.disputed = true;
        emit ResolutionDisputed(marketId, msg.sender);
    }

    function overrideResolution(uint256 marketId, bool newOutcome) external {
        if (msg.sender != governor) revert NotGovernor();
        Resolution storage r = resolutions[marketId];
        if (!r.proposed) revert NotYetResolved(marketId);
        if (r.finalized) revert AlreadyFinalized(marketId);
        if (!r.disputed) revert NotDisputed(marketId);
        r.outcome = newOutcome;
        r.finalized = true;
        r.finalOutcome = newOutcome;
        emit ResolutionOverridden(marketId, newOutcome);
        emit ResolutionFinalized(marketId, newOutcome);
    }

    function finalizeResolution(uint256 marketId) external {
        Resolution storage r = resolutions[marketId];
        if (!r.proposed) revert NotYetResolved(marketId);
        if (r.finalized) revert AlreadyFinalized(marketId);
        if (r.disputed) revert DisputeWindowStillOpen(marketId);
        if (block.timestamp <= r.proposedAt + disputeWindow) {
            revert DisputeWindowStillOpen(marketId);
        }
        r.finalized = true;
        r.finalOutcome = r.outcome;
        emit ResolutionFinalized(marketId, r.finalOutcome);
    }

    function getFinalOutcome(uint256 marketId) external view returns (bool) {
        Resolution storage r = resolutions[marketId];
        require(r.finalized, "OracleAdapter: not finalized yet");
        return r.finalOutcome;
    }

    function setStalenessThreshold(uint256 newThreshold) external onlyOwner {
        stalenessThreshold = newThreshold;
        emit StalenessThresholdUpdated(newThreshold);
    }

    function setDisputeWindow(uint256 newWindow) external onlyOwner {
        disputeWindow = newWindow;
        emit DisputeWindowUpdated(newWindow);
    }

    function setGovernor(address newGovernor) external onlyOwner {
        if (newGovernor == address(0)) revert ZeroAddress();
        governor = newGovernor;
        emit GovernorUpdated(newGovernor);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}