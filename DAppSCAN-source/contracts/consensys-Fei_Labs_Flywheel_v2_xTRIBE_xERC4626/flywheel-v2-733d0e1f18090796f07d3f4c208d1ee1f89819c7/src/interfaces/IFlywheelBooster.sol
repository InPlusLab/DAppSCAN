// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.10;

import {ERC20} from "solmate/tokens/ERC20.sol";

/**
 @title Balance Booster Module for Flywheel
 @notice Flywheel is a general framework for managing token incentives.
         It takes reward streams to various *strategies* such as staking LP tokens and divides them among *users* of those strategies.

         The Booster module is an optional module for virtually boosting or otherwise transforming user balances. 
         If a booster is not configured, the strategies ERC-20 balanceOf/totalSupply will be used instead.
        
         Boosting logic can be associated with referrals, vote-escrow, or other strategies.

         SECURITY NOTE: similar to how Core needs to be notified any time the strategy user composition changes, the booster would need to be notified of any conditions which change the boosted balances atomically.
         This prevents gaming of the reward calculation function by using manipulated balances when accruing.
*/
interface IFlywheelBooster {
    /**
      @notice calculate the boosted supply of a strategy.
      @param strategy the strategy to calculate boosted supply of
      @return the boosted supply
     */
    function boostedTotalSupply(ERC20 strategy) external view returns (uint256);

    /**
      @notice calculate the boosted balance of a user in a given strategy.
      @param strategy the strategy to calculate boosted balance of
      @param user the user to calculate boosted balance of
      @return the boosted balance
     */
    function boostedBalanceOf(ERC20 strategy, address user) external view returns (uint256);
}
