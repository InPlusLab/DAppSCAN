// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import '../StakingRewardsDualV2.sol';

contract StakingRewardsDualV2_ARTH3CRV_V2 is StakingRewardsDualV2 {
    constructor(
        address _owner,
        address _rewardsToken0,
        address _rewardsToken1,
        address _stakingToken,
        address _arthAddress,
        address _timelockAddress,
        uint256 _poolWeight0,
        uint256 _poolWeight1
    )
        StakingRewardsDualV2(
            _owner,
            _rewardsToken0,
            _rewardsToken1,
            _stakingToken,
            _arthAddress,
            _timelockAddress,
            _poolWeight0,
            _poolWeight1
        )
    {}
}
