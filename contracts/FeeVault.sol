// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title FeeVault
 * @dev ERC-4626 tokenized vault that collects trading fees from prediction markets.
 *      Users deposit the collateral token and receive vault shares.
 *      When fees are sent to this vault by PredictionMarket contracts,
 *      totalAssets() increases, making each share worth more.
 *
 *      Integration:
 *      - Deploy FeeVault with the collateral token (e.g. USDC)
 *      - Set FeeVault address as `feeCollector` in MarketFactory
 *      - PredictionMarket.buy/sell transfer fees to this vault via safeTransfer
 *      - Vault depositors earn pro-rata share of all trading fees
 */
contract FeeVault is ERC4626, Ownable {
    using SafeERC20 for IERC20;

    /// @dev Running total of fees that have been accrued (for analytics)
    uint256 public totalFeesAccrued;

    /// @dev Snapshot of totalAssets at last fee tracking update
    uint256 private _lastTrackedAssets;

    event FeesAccrued(uint256 feeAmount, uint256 totalAssets);
    event EmergencyWithdraw(address indexed token, address indexed to, uint256 amount);

    error NoFeesToSync();
    error CannotSweepUnderlying();

    constructor(IERC20 _asset)
        ERC4626(_asset)
        ERC20("Prediction Market Fee Share", "pmFEE")
        Ownable(msg.sender)
    {}

    /**
     * @dev Override decimals offset to add virtual shares/assets for
     *      inflation attack protection (OpenZeppelin recommendation).
     */
    function _decimalsOffset() internal pure override returns (uint8) {
        return 3;
    }

    /**
     * @dev Sync fee accounting. Call after fees are transferred to the vault
     *      to emit an event and update the cumulative fee counter.
     *      This is optional — share prices update automatically via ERC4626.
     */
    function syncFees() external {
        uint256 currentAssets = totalAssets();
        uint256 tracked = _lastTrackedAssets;

        if (currentAssets <= tracked) revert NoFeesToSync();

        uint256 newFees = currentAssets - tracked;
        totalFeesAccrued += newFees;
        _lastTrackedAssets = currentAssets;

        emit FeesAccrued(newFees, currentAssets);
    }

    /**
     * @dev Update tracked assets on deposit.
     */
    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal override {
        super._deposit(caller, receiver, assets, shares);
        _lastTrackedAssets += assets;
    }

    /**
     * @dev Update tracked assets on withdraw.
     */
    function _withdraw(
        address caller,
        address receiver,
        address owner_,
        uint256 assets,
        uint256 shares
    ) internal override {
        super._withdraw(caller, receiver, owner_, assets, shares);
        if (assets <= _lastTrackedAssets) {
            _lastTrackedAssets -= assets;
        } else {
            _lastTrackedAssets = 0;
        }
    }

    /**
     * @dev Emergency sweep for tokens accidentally sent to the vault.
     *      Cannot sweep the underlying asset — use withdraw for that.
     */
    function sweepToken(IERC20 token, address to) external onlyOwner {
        if (address(token) == asset()) revert CannotSweepUnderlying();
        uint256 balance = token.balanceOf(address(this));
        token.safeTransfer(to, balance);
        emit EmergencyWithdraw(address(token), to, balance);
    }

    /**
     * @dev View: pending fees not yet synced.
     */
    function pendingFees() external view returns (uint256) {
        uint256 currentAssets = totalAssets();
        if (currentAssets > _lastTrackedAssets) {
            return currentAssets - _lastTrackedAssets;
        }
        return 0;
    }
}
