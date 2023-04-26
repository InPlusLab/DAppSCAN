// SPDX-License-Identifier: MIT

pragma solidity 0.8.3;

interface IUniswapFactory
{
    function getPair(address tokenA, address tokenB) external view returns (address);
    function createPair(address tokenA, address tokenB) external returns (address);
}
