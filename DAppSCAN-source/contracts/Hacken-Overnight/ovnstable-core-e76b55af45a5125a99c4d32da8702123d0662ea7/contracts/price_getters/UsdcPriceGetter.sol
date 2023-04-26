// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "../price_getters/AbstractPriceGetter.sol";

contract UsdcPriceGetter is AbstractPriceGetter {
    function getUsdcBuyPrice() external pure override returns (uint256) {
        return DENOMINATOR;
    }

    function getUsdcSellPrice() external pure override returns (uint256) {
        return DENOMINATOR;
    }
}
