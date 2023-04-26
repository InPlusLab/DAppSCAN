// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface IBaseRewards{
    function initialize(
        uint256 pid_,
        address stakingToken_,
        address rewardToken_,
        address operator_,
        address rewardManager_
    ) external;
    function addExtraReward(address) external;
    function getReward(address,bool) external;
}