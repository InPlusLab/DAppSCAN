// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.10;

import {Auth, Authority} from "solmate/auth/Auth.sol";
import "./BaseFlywheelRewards.sol";

/** 
 @title Flywheel Static Reward Stream
 @notice Determines rewards per strategy based on a fixed reward rate per second
*/
contract FlywheelStaticRewards is Auth, BaseFlywheelRewards {
    event RewardsInfoUpdate(ERC20 indexed strategy, uint224 rewardsPerSecond, uint32 rewardsEndTimestamp);

    struct RewardsInfo {
        /// @notice Rewards per second
        uint224 rewardsPerSecond;
        /// @notice The timestamp the rewards end at
        /// @dev use 0 to specify no end
        uint32 rewardsEndTimestamp;
    }

    /// @notice rewards info per strategy
    mapping(ERC20 => RewardsInfo) public rewardsInfo;

    constructor(
        FlywheelCore _flywheel,
        address _owner,
        Authority _authority
    ) Auth(_owner, _authority) BaseFlywheelRewards(_flywheel) {}

    /**
     @notice set rewards per second and rewards end time for Fei Rewards
     @param strategy the strategy to accrue rewards for
     @param rewards the rewards info for the strategy
     */
    function setRewardsInfo(ERC20 strategy, RewardsInfo calldata rewards) external requiresAuth {
        rewardsInfo[strategy] = rewards;
        emit RewardsInfoUpdate(strategy, rewards.rewardsPerSecond, rewards.rewardsEndTimestamp);
    }

    /**
     @notice calculate and transfer accrued rewards to flywheel core
     @param strategy the strategy to accrue rewards for
     @param lastUpdatedTimestamp the last updated time for strategy
     @return amount the amount of tokens accrued and transferred
     */
    function getAccruedRewards(ERC20 strategy, uint32 lastUpdatedTimestamp)
        external
        view
        override
        onlyFlywheel
        returns (uint256 amount)
    {
        RewardsInfo memory rewards = rewardsInfo[strategy];

        uint256 elapsed;
        if (rewards.rewardsEndTimestamp == 0 || rewards.rewardsEndTimestamp > block.timestamp) {
            elapsed = block.timestamp - lastUpdatedTimestamp;
        } else if (rewards.rewardsEndTimestamp > lastUpdatedTimestamp) {
            elapsed = rewards.rewardsEndTimestamp - lastUpdatedTimestamp;
        }

        amount = rewards.rewardsPerSecond * elapsed;
    }
}
