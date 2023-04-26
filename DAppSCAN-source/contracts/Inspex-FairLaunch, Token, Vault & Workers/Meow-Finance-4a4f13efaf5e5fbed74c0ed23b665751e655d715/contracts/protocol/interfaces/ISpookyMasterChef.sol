// SPDX-License-Identifier: MIT
pragma solidity 0.6.6;

interface ISpookyMasterChef {
  function boo() external view returns (address);

  function booPerSecond() external view returns (uint256);

  function deposit(uint256 _pid, uint256 _amount) external;

  function emergencyWithdraw(uint256 _pid) external;

  function pendingBOO(uint256 _pid, address _user) external view returns (uint256);

  function poolInfo(uint256)
    external
    view
    returns (
      address lpToken,
      uint256 allocPoint,
      uint256 lastRewardTime,
      uint256 accBOOPerShare
    );

  function poolLength() external view returns (uint256);

  function totalAllocPoint() external view returns (uint256);

  function userInfo(uint256, address) external view returns (uint256 amount, uint256 rewardDebt);

  function withdraw(uint256 _pid, uint256 _amount) external;
}
