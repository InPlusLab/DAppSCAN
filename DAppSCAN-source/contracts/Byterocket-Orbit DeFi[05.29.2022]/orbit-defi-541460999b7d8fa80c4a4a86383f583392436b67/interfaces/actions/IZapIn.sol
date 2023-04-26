// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

interface IZapIn {
    function zapIn(
        address tokenIn,
        uint256 amountIn,
        address token0,
        address token1,
        int24 tickLower,
        int24 tickUpper,
        uint24 fee
    ) external returns (uint256);
}
