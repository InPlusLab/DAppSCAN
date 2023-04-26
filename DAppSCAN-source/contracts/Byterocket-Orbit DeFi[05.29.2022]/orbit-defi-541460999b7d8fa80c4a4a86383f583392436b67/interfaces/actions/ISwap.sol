// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

interface ISwap {
    function swap(
        address token0Address,
        address token1Address,
        uint24 fee,
        uint256 amount0In
    ) external returns (uint256 amount1Out);
}
