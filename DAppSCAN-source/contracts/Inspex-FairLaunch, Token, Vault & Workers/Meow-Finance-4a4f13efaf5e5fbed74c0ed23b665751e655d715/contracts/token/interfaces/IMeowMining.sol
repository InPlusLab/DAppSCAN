// SPDX-License-Identifier: MIT
pragma solidity 0.6.6;

interface IMeowMining {
  // Info of each user.
  struct UserInfo {
    uint256 amount;
    uint256 rewardDebt;
    address fundedBy;
    uint256 lockedAmount;
    uint256 lastUnlockTime;
    uint256 lockTo;
  }

  // Info of each pool.
  struct PoolInfo {
    address stakeToken;
    uint256 allocPoint;
    uint256 lastRewardTime;
    uint256 accMeowPerShare;
  }

  // Return MeowToken address.
  function meow() external view returns (address);

  // Return MEOW tokens created per second.
  function meowPerSecond() external view returns (uint256);

  // Return MeowMining pool length.
  function poolLength() external view returns (uint256);

  // Return total allocation points.
  function totalAllocPoint() external view returns (uint256);

  // Return info of the given pool.
  function poolInfo(uint256 _pid)
    external
    view
    returns (
      address,
      uint256,
      uint256,
      uint256
    );

  // Return info of given user on the given pool.
  function userInfo(uint256 _pid, address _user)
    external
    view
    returns (
      uint256,
      uint256,
      address,
      uint256,
      uint256,
      uint256
    );

  function addPool(uint256 _allocPoint, address _stakeToken) external;

  function setPool(uint256 _pid, uint256 _allocPoint) external;

  function manualMint(address _to, uint256 _amount) external;

  // Return pending MeowToken for given user on given pool.
  function pendingMeow(uint256 _pid, address _user) external view returns (uint256);

  // Return pending unlock MeowToken.
  function availableUnlock(uint256 _pid, address _user) external view returns (uint256);

  function updatePool(uint256 _pid) external;

  function deposit(
    address _for,
    uint256 _pid,
    uint256 _amount
  ) external;

  function withdraw(
    address _for,
    uint256 _pid,
    uint256 _amount
  ) external;

  function withdrawAll(address _for, uint256 _pid) external;

  function harvest(uint256 _pid) external;

  function emergencyWithdraw(uint256 pid) external;
}
