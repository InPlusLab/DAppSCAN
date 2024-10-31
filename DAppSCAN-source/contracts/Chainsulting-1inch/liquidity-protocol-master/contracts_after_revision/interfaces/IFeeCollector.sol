// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

/// @title Fee collector interface
interface IFeeCollector {
    /// @notice Adds specified `amount` as reward to `receiver`
    function updateReward(address receiver, uint256 amount) external;
    /// @notice Same as `updateReward` but for multiple accounts
    function updateRewards(address[] calldata receivers, uint256[] calldata amounts) external;
}
