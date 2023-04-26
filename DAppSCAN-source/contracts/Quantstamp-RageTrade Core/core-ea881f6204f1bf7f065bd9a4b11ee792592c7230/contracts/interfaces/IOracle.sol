// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

interface IOracle {
    function getTwapPriceX128(uint32 twapDuration) external view returns (uint256 priceX128);
}
