// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IStakingRewards {
    function stakeLockedFor(
        address who,
        uint256 amount,
        uint256 duration
    ) external;

    function stakeFor(address who, uint256 amount) external;

    function stakeLocked(uint256 amount, uint256 secs) external;

    function withdrawLocked(bytes32 kekId) external;

    function getReward() external;

    function stake(uint256 amount) external;

    function withdraw(uint256 amount) external;

    function lastTimeRewardApplicable() external view returns (uint256);

    function rewardPerToken() external view returns (uint256);

    function earned(address account) external view returns (uint256);

    function getRewardForDuration() external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);
}
