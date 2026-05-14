// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title CPMM
 * @dev Pricing engine for Constant Product Market Maker.
 */
library CPMM {
    /**
     * @dev Calculates the amount of shares out for a given collateral input.
     * Formula: (r0 - sharesOut) * (r1 + netCollateral) = r0 * r1
     * sharesOut = r0 - (r0 * r1) / (r1 + netCollateral)
     * @param r0 Reserve of the outcome being bought.
     * @param r1 Reserve of the other outcome.
     * @param netCollateral Amount of collateral added (after fees).
     */
    function getSharesOut(
        uint256 r0,
        uint256 r1,
        uint256 netCollateral
    ) internal pure returns (uint256) {
        require(r0 > 0 && r1 > 0, "CPMM: Zero reserves");
        uint256 k = r0 * r1;
        uint256 r0_new = k / (r1 + netCollateral);
        return r0 - r0_new;
    }

    /**
     * @dev Calculates the amount of collateral out for a given shares input (sell).
     * Formula: (r0 + sharesIn) * (r1 - collateralOut) = r0 * r1
     * collateralOut = r1 - (r0 * r1) / (r0 + sharesIn)
     * @param r0 Reserve of the outcome being sold.
     * @param r1 Reserve of the other outcome (collateral reserve).
     * @param sharesIn Amount of shares being sold.
     */
    function getCollateralOut(
        uint256 r0,
        uint256 r1,
        uint256 sharesIn
    ) internal pure returns (uint256) {
        require(r0 > 0 && r1 > 0, "CPMM: Zero reserves");
        uint256 k = r0 * r1;
        uint256 r1_new = k / (r0 + sharesIn);
        return r1 - r1_new;
    }
}
