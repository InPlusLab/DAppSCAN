// SPDX-License-Identifier: Apache-2.0

pragma solidity >=0.5.0;

interface IUniswapV2FactoryMinimal {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}
