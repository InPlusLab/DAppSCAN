// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.10;

import "./BaseFlywheelRewards.sol";
import {SafeCastLib} from "solmate/utils/SafeCastLib.sol";

/** 
 @title Flywheel Dynamic Reward Stream
 @notice Determines rewards based on a dynamic reward stream.
         Rewards are transferred linearly over a "rewards cycle" to prevent gaming the reward distribution. 
         The reward source can be arbitrary logic, but most common is to "pass through" rewards from some other source.
         The getNextCycleRewards() hook should also transfer the next cycle's rewards to this contract to ensure proper accounting.
*/
abstract contract FlywheelDynamicRewards is BaseFlywheelRewards {
    using SafeTransferLib for ERC20;
    using SafeCastLib for uint256;

    event NewRewardsCycle(uint32 indexed start, uint32 indexed end, uint192 reward);

    /// @notice the length of a rewards cycle
    uint32 public immutable rewardsCycleLength;

    struct RewardsCycle {
        uint32 start;
        uint32 end;
        uint192 reward;
    }

    mapping(ERC20 => RewardsCycle) public rewardsCycle;

    constructor(FlywheelCore _flywheel, uint32 _rewardsCycleLength) BaseFlywheelRewards(_flywheel) {
        rewardsCycleLength = _rewardsCycleLength;
    }

    /**
     @notice calculate and transfer accrued rewards to flywheel core
     @param strategy the strategy to accrue rewards for
     @return amount the amount of tokens accrued and transferred
     */
    function getAccruedRewards(ERC20 strategy, uint32 lastUpdatedTimestamp)
        external
        override
        onlyFlywheel
        returns (uint256 amount)
    {
        RewardsCycle memory cycle = rewardsCycle[strategy];

        uint32 timestamp = block.timestamp.safeCastTo32();

        uint32 latest = timestamp >= cycle.end ? cycle.end : timestamp;
        uint32 earliest = lastUpdatedTimestamp <= cycle.start ? cycle.start : lastUpdatedTimestamp;
        if (cycle.end != 0) {
            amount = (cycle.reward * (latest - earliest)) / (cycle.end - cycle.start);
            assert(amount <= cycle.reward); // should never happen because latest <= cycle.end and earliest >= cycle.start
        }
        // if cycle has ended, reset cycle and transfer all available
        if (timestamp >= cycle.end) {
            uint32 end = ((timestamp + rewardsCycleLength) / rewardsCycleLength) * rewardsCycleLength;
            uint192 rewards = getNextCycleRewards(strategy);

            // reset for next cycle
            rewardsCycle[strategy] = RewardsCycle({start: timestamp, end: end, reward: rewards});

            emit NewRewardsCycle(timestamp, end, rewards);
        }
    }

    function getNextCycleRewards(ERC20 strategy) internal virtual returns (uint192);
}
