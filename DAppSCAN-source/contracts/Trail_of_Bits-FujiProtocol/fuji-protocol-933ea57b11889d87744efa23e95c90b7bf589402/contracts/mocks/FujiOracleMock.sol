// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../interfaces/IFujiOracle.sol";

contract FujiOracleMock is IFujiOracle {
  mapping(address => mapping(address => uint256)) public prices;

  function setPriceOf(
    address _collateralAsset,
    address _borrowAsset,
    uint256 _price
  ) external {
    prices[_collateralAsset][_borrowAsset] = _price;
  }

  function getPriceOf(
    address _collateralAsset,
    address _borrowAsset,
    uint8
  ) external view override returns (uint256) {
    return prices[_collateralAsset][_borrowAsset];
  }
}
