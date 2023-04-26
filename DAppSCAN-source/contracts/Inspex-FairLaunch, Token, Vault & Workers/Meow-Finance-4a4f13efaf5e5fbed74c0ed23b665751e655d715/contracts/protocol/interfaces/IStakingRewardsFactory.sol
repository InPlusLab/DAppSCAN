pragma solidity 0.6.6;

interface IStakingRewardsFactory {
  // Views
  function rewardsToken() external view returns (address);

  function stakingRewardsGenesis() external view returns (uint256);

  function stakingTokens(uint256 _pid) external view returns (address);

  function stakingRewardsInfoByStakingToken(address _stakingToken)
    external
    view
    returns (
      address,
      uint256,
      uint256
    );
}
