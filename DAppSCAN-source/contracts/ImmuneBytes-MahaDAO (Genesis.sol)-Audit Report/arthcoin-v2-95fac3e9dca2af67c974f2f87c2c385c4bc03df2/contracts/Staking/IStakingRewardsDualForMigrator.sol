// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import {IERC20} from '../ERC20/IERC20.sol';

interface IStakingRewardsDualForMigrator {
    struct ILockedStake {
        bytes32 kekId;
        uint256 startTimestamp;
        uint256 amount;
        uint256 endingTimestamp;
        uint256 multiplier; // 6 decimals of precision, 1x = 1000000.
    }

    function stake(uint256 amount) external;

    function stakeLocked(uint256 amount, uint256 secs) external;

    function withdraw(uint256 amount) external;

    function withdrawLocked(bytes32 kekId) external;

    function getReward() external;

    function unlockStakes() external;

    function stakingToken() external view returns (IERC20);

    function lockedStakesOf(address account)
        external
        view
        returns (ILockedStake[] memory);

    function lastTimeRewardApplicable() external view returns (uint256);

    function rewardPerToken() external view returns (uint256, uint256);

    function earned(address account) external view returns (uint256, uint256);

    function getRewardForDuration() external view returns (uint256, uint256);

    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    // function exit() external;
}
