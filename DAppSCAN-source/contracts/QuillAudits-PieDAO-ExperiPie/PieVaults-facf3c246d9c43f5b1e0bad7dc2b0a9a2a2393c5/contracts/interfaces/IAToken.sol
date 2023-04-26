// SPDX-License-Identifier: MIT
pragma experimental ABIEncoderV2;
pragma solidity ^0.7.1;

interface IAToken {
    function redeem(uint256 _amount) external;
}

