// SPDX-License-Identifier: MIT
pragma experimental ABIEncoderV2;
pragma solidity ^0.7.1;

interface IAaveLendingPool {
    function deposit(address _reserve, uint256 _amount, uint16 _referralCode) external;
    function core() external view returns(address);
}