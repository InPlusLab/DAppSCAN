// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;


interface IReferralFeeReceiver {
    function updateReward(address referral, uint256 referralShare) external;
}
