// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IFuseComptroller {
  function markets(address) external returns (bool, uint256);

  function enterMarkets(address[] calldata) external returns (uint256[] memory);

  function exitMarket(address cTokenAddress) external returns (uint256);

  function cTokensByUnderlying(address underlyingAsset) external view returns (address);
}
