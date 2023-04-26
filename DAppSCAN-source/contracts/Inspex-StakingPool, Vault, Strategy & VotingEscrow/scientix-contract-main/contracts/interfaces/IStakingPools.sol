// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.6.12;

interface IStakingPools  {
  function deposit(uint256 _poolId, uint256 _depositAmount) external;
  function exit(uint256 _poolId) external;
  function claim(uint256 _poolId) external;
  function getStakeTotalUnclaimed(address _account, uint256 _poolId) external view returns (uint256);
}