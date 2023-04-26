// SPDX-License-Identifier: MIT

pragma solidity 0.8.3;

interface IUniswapPool
{
    function totalSupply() external view returns (uint);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;

    function mint(address to) external returns (uint liquidity);
    function burn(address to) external returns (uint amount0, uint amount1);
}