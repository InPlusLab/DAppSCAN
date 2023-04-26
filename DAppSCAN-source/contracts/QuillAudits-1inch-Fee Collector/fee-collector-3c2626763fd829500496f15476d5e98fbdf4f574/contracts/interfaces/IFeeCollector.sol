// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;


interface IFeeCollector {
    function updateReward(address referral, uint256 amount) external;
}
