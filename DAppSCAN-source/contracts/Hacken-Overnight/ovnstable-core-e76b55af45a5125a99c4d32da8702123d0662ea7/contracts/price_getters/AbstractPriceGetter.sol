// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "../interfaces/IPriceGetter.sol";

contract AbstractPriceGetter is IPriceGetter {
    uint256 public constant DENOMINATOR = 10**18;

    function getUsdcBuyPrice() external view virtual override returns (uint256) {
        return DENOMINATOR;
    }

    function getUsdcSellPrice() external view virtual override returns (uint256) {
        return DENOMINATOR;
    }

    function denominator() external view virtual override returns (uint256) {
        return DENOMINATOR;
    }
}
