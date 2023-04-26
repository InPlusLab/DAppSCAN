// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

struct PassRequirement {
  uint8 veteranCount;
  uint8 retiredCount;
  uint48 stakeTime;
  uint256 stakeAmount;
}

interface IStaking {
  function getPass(address user) external view returns(uint8);
  function getPassRequirements(uint8 pass) external view returns(PassRequirement memory requirements);
  function getCoefficient(address user) external view returns(int128);
}