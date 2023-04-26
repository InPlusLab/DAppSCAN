// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IIdleCDOTrancheRewards.sol";

contract MockIdleCDO {
  using SafeERC20 for IERC20;

  address[] public rewards;
  address public trancheRewardsContract;

  constructor(address[] memory _rewards) {
    rewards = _rewards;
  }

  function setTrancheRewardsContract(address a) external {
    trancheRewardsContract = a;
  }

  function depositReward(address _reward, uint256 _amount) external {
    IERC20(_reward).safeApprove(trancheRewardsContract, _amount);
    IIdleCDOTrancheRewards(trancheRewardsContract).depositReward(_reward, _amount);
  }

  function depositRewardWithoutApprove(address _reward, uint256 _amount) external {
    IIdleCDOTrancheRewards(trancheRewardsContract).depositReward(_reward, _amount);
  }
}
