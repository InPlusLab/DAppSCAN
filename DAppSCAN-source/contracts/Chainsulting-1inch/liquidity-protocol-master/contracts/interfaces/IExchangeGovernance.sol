// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;


interface IExchangeGovernance {
    function parameters() external view returns(uint256 leftoverReferralShare);

    function leftoverReferralShare() external view returns(uint256);
}
