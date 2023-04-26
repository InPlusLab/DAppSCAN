// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { PriceMath } from '../libraries/PriceMath.sol';

contract PriceMathTest {
    function toPriceX128(uint160 sqrtPriceX96) public pure returns (uint256 priceX128) {
        return PriceMath.toPriceX128(sqrtPriceX96);
    }

    function toSqrtPriceX96(uint256 priceX128) public pure returns (uint160 sqrtPriceX96) {
        return PriceMath.toSqrtPriceX96(priceX128);
    }
}
