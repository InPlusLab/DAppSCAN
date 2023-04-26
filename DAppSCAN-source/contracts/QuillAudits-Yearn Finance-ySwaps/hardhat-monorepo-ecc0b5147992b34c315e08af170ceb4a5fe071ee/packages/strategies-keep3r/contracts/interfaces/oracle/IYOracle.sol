// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

interface IYOracle {
  function defaultOracle() external view returns (address _defaultOracle);

  function pairOracle(address _pair) external view returns (address _oracle);

  function setPairOracle(address _pair, address _oracle) external;

  function setDefaultOracle(address _oracle) external;

  function getAmountOut(
    address _pair,
    address _tokenIn,
    uint256 _amountIn,
    address _tokenOut
  ) external view returns (uint256 _amountOut);
}
