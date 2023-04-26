// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

interface ISimpleOracle {
  function getAmountOut(
    address _pair,
    address _tokenIn,
    uint256 _amountIn,
    address _tokenOut
  ) external view returns (uint256 _amountOut);
}
