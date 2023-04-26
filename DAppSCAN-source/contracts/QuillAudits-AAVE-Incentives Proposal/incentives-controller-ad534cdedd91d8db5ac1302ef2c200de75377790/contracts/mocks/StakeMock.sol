pragma solidity 0.7.5;

import {IStakedTokenWithConfig} from '../interfaces/IStakedTokenWithConfig.sol';
import {IERC20} from '@aave/aave-stake/contracts/interfaces/IERC20.sol';

contract StakeMock is IStakedTokenWithConfig {
  address public immutable override STAKED_TOKEN;

  constructor(address stakedToken) {
    STAKED_TOKEN = stakedToken;
  }

  function stake(address to, uint256 amount) external override {
      IERC20(STAKED_TOKEN).transferFrom(msg.sender, address(this), amount);
  }

  function redeem(address to, uint256 amount) external override {}

  function cooldown() external override {}

  function claimRewards(address to, uint256 amount) external override {}
}
