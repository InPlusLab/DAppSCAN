// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.6;

interface ITokenPairPriceFeed {
    /// @dev Fetches the rate between a given token pair
    /// @param rateConversionData data that specifies the target tokens (each ITokenPairPriceFeed might have different input requirements)
    /// @return rate - The rate between the provided tokens
    /// @return rateDenominator
    function getRate(bytes32 rateConversionData) external view returns (uint256 rate, uint256 rateDenominator);
}
