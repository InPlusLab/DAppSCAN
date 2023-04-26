// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface IHarvestableStrategy {
  function harvest() external;

  function controller() external view returns (address);

  function want() external view returns (address);
}
