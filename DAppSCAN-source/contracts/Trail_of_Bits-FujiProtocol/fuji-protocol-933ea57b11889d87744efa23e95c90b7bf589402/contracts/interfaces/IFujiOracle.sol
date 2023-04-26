// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IFujiOracle {
  function getPriceOf(
    address _collateralAsset,
    address _borrowAsset,
    uint8 _decimals
  ) external view returns (uint256);
}
