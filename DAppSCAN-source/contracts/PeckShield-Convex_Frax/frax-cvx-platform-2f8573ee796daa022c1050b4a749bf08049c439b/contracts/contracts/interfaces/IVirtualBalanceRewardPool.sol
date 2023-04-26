// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface IVirtualBalanceRewardPool{
    function initialize(
        address deposit_,
        address reward_,
        address op_
    ) external;
    function addExtraReward(address) external;
}