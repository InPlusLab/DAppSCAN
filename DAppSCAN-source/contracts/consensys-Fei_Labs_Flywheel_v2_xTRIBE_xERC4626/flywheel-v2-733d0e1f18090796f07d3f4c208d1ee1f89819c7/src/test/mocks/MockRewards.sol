// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.10;

import "../../rewards/BaseFlywheelRewards.sol";

contract MockRewards is BaseFlywheelRewards {
    /// @notice rewards amount per strategy
    mapping(ERC20 => uint256) public rewardsAmount;

    constructor(FlywheelCore _flywheel) BaseFlywheelRewards(_flywheel) {}

    function setRewardsAmount(ERC20 strategy, uint256 amount) external {
        rewardsAmount[strategy] = amount;
    }

    function getAccruedRewards(ERC20 strategy, uint32) external view override onlyFlywheel returns (uint256 amount) {
        return rewardsAmount[strategy];
    }
}
