pragma solidity 0.6.6;

interface IStakingRewards {
  // Views
  function rewardsToken() external view returns (address);

  function stakingToken() external view returns (address);

  function rewardsDistribution() external view returns (address);

  function lastTimeRewardApplicable() external view returns (uint256);

  function rewardPerToken() external view returns (uint256);

  function earned(address account) external view returns (uint256);

  function totalSupply() external view returns (uint256);

  function balanceOf(address account) external view returns (uint256);

  function rewardRate() external view returns (uint256);

  // Mutative

  function stake(uint256 amount) external;

  function withdraw(uint256 amount) external;

  function getReward() external;

  function exit() external;
}
