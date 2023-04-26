// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IAaveAddressProviderRegistry {
  function getAddressesProvidersList() external view returns (address[] memory);
}
