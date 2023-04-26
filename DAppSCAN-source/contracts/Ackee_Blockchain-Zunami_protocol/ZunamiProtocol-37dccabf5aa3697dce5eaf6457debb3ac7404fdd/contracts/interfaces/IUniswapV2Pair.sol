//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface IUniswapV2Pair {
    function getReserves()
        external
        view
        returns (
            uint112,
            uint112,
            uint32
        );

    function token0() external view returns (address);

    function token1() external view returns (address);
}
