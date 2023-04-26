// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import { IOracle } from '../interfaces/IOracle.sol';

contract SettlementTokenOracle is IOracle {
    function getTwapPriceX128(uint32) external pure returns (uint256 priceX128) {
        priceX128 = 1 << 128;
    }
}
