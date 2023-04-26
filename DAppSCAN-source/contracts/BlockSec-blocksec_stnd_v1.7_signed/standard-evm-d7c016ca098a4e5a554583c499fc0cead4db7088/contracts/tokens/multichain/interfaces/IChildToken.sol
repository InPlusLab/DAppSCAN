// SPDX-License-Identifier: Apache-2.0

// File: contracts/lib/IChildToken.sol

pragma solidity 0.6.12;

interface IChildToken {
    function deposit(address user, bytes calldata depositData) external;
}