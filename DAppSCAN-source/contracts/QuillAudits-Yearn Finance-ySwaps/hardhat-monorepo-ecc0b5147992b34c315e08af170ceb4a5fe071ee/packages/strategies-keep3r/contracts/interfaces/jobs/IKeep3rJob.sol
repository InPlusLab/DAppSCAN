// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface IKeep3rJob {
  event SetRewardMultiplier(uint256 _rewardMultiplier);

  function rewardMultiplier() external view returns (uint256 _rewardMultiplier);

  function setRewardMultiplier(uint256 _rewardMultiplier) external;
}
