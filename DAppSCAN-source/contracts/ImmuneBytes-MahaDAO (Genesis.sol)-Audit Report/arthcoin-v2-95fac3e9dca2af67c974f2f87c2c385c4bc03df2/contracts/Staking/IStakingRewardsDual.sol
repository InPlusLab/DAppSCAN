// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IStakingRewardsDual {
    function stake(uint256 amount) external;

    function withdraw(uint256 amount) external;

    function getReward() external;

    function stakeLocked(uint256 amount, uint256 secs) external;

    function withdrawLocked(bytes32 kekId) external;

    function lastTimeRewardApplicable() external view returns (uint256);

    function rewardPerToken() external view returns (uint256, uint256);

    function earned(address account) external view returns (uint256, uint256);

    function getRewardForDuration() external view returns (uint256, uint256);

    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    // function exit() external;
}
