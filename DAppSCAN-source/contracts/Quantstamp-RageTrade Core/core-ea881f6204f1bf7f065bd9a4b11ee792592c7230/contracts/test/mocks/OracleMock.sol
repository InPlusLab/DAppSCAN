// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { IOracle } from '../../interfaces/IOracle.sol';

import { PriceMath } from '../../libraries/PriceMath.sol';

contract OracleMock is IOracle {
    using PriceMath for uint256;
    using PriceMath for uint160;

    uint256 priceX128;

    constructor() {
        setPriceX128(1 << 128);
    }

    function getTwapPriceX128(uint32) external view returns (uint256) {
        return priceX128;
    }

    function getTwapSqrtPriceX96(uint32) external view returns (uint160 sqrtPriceX96) {
        sqrtPriceX96 = priceX128.toSqrtPriceX96();
    }

    function setSqrtPriceX96(uint160 _sqrtPriceX96) public {
        priceX128 = _sqrtPriceX96.toPriceX128();
    }

    function setPriceX128(uint256 _priceX128) public {
        priceX128 = _priceX128;
    }
}
