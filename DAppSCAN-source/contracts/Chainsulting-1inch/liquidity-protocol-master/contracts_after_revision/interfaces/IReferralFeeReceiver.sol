// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

/// @title Referral fee collector interface
interface IReferralFeeReceiver {
    function updateReward(address referral, uint256 referralShare) external;
}
