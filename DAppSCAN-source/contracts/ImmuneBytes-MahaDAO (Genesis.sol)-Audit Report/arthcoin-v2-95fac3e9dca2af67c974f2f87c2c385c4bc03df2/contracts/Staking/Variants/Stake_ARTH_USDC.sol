// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import '../StakingRewards.sol';

contract Stake_ARTH_USDC is StakingRewards {
    constructor(
        address _owner,
        address _rewardsDistribution,
        address _rewardsToken,
        address _stakingToken,
        address _arthAddress,
        address _timelockAddress,
        uint256 _poolWeight
    )
        StakingRewards(
            _owner,
            _rewardsDistribution,
            _rewardsToken,
            _stakingToken,
            _arthAddress,
            _timelockAddress,
            _poolWeight
        )
    {}
}
