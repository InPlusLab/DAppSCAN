// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;
pragma experimental ABIEncoderV2;

interface IMinter {
    function transfer(address, uint256) external;
}
