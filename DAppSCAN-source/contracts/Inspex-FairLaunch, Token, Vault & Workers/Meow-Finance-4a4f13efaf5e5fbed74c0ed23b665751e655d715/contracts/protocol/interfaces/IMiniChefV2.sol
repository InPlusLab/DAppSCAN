// SPDX-License-Identifier: MIT
pragma solidity 0.6.6;

import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";

interface IMiniChefV2 {
  struct UserInfo {
    uint256 amount;
    uint256 rewardDebt;
  }

  struct PoolInfo {
    uint128 accSushiPerShare;
    uint64 lastRewardTime;
    uint64 allocPoint;
  }

  function SUSHI() external view returns (address);

  function sushiPerSecond() external view returns (uint256);

  function totalAllocPoint() external view returns (uint256);

  function lpToken(uint256 _pid) external view returns (address);

  function rewarder(uint256 _pid) external view returns (address);

  function pendingSushi(uint256 _pid, address _user) external view returns (uint256);

  function poolLength() external view returns (uint256);

  function poolInfo(uint256 _pid)
    external
    view
    returns (
      uint128,
      uint64,
      uint64
    );

  function userInfo(uint256 _pid, address _user) external view returns (uint256, uint256);

  function deposit(
    uint256 pid,
    uint256 amount,
    address to
  ) external;

  function withdraw(
    uint256 pid,
    uint256 amount,
    address to
  ) external;

  function harvest(uint256 pid, address to) external;

  function withdrawAndHarvest(
    uint256 pid,
    uint256 amount,
    address to
  ) external;

  function emergencyWithdraw(uint256 pid, address to) external;
}
