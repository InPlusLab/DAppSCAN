// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface IUniswapV2SlidingOracle {
  function current(
    address tokenIn,
    uint256 amountIn,
    address tokenOut
  ) external view returns (uint256);

  function updatePair(address pair) external returns (bool);

  function workable(address pair) external view returns (bool);

  function workForFree() external;
}
