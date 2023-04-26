// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IFujiMappings {
  function addressMapping(address) external view returns (address);
}
