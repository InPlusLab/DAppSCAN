// SPDX-License-Identifier: MIT

pragma solidity >=0.6.11;

abstract contract RewardsDistributionRecipient {
    address public rewardsDistribution;

    function notifyRewardAmount(address rewardToken, uint256 reward) external virtual;

    modifier onlyRewardsDistribution() {
        require(msg.sender == rewardsDistribution, 'Caller is not RewardsDistribution contract');
        _;
    }
}
