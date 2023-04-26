// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;
import './../yearn/IHarvestableStrategy.sol';

interface ICrvStrategy is IHarvestableStrategy {
  function gauge() external pure returns (address);

  function proxy() external pure returns (address);

  function voter() external pure returns (address);
}
