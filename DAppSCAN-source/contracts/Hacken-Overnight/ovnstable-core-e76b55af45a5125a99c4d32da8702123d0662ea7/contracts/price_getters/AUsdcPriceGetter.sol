// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../price_getters/AbstractPriceGetter.sol";
import "../interfaces/IConnector.sol";

contract AUsdcPriceGetter is AbstractPriceGetter {
    function getUsdcBuyPrice() external pure override returns (uint256) {
        return DENOMINATOR;
    }

    function getUsdcSellPrice() external pure override returns (uint256) {
        return DENOMINATOR;
    }
}

