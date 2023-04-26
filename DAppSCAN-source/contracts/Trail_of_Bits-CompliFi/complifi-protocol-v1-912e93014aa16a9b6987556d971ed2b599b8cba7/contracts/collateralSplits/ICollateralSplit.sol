// "SPDX-License-Identifier: GPL-3.0-or-later"

pragma solidity 0.7.6;

/// @title Collateral Split interface
/// @notice Contains mathematical functions used to calculate relative claim
/// on collateral of primary and complement assets after settlement.
/// @dev Created independently from specification and published to the CollateralSplitRegistry
interface ICollateralSplit {
    /// @notice Proof of collateral split contract
    /// @dev Verifies that contract is a collateral split contract
    /// @return true if contract is a collateral split contract
    function isCollateralSplit() external pure returns (bool);

    /// @notice Symbol of the collateral split
    /// @dev Should be resolved through CollateralSplitRegistry contract
    /// @return collateral split specification symbol
    function symbol() external pure returns (string memory);

    /// @notice Calcs primary asset class' share of collateral at settlement.
    /// @dev Returns ranged value between 0 and 1 multiplied by 10 ^ 12
    /// @param _underlyingStarts underlying values in the start of Live period
    /// @param _underlyingEndRoundHints specify for each oracle round of the end of Live period
    /// @return _split primary asset class' share of collateral at settlement
    /// @return _underlyingEnds underlying values in the end of Live period
    function split(
        address[] calldata _oracles,
        address[] calldata _oracleIterators,
        int256[] calldata _underlyingStarts,
        uint256 _settleTime,
        uint256[] calldata _underlyingEndRoundHints
    ) external view returns (uint256 _split, int256[] memory _underlyingEnds);
}
