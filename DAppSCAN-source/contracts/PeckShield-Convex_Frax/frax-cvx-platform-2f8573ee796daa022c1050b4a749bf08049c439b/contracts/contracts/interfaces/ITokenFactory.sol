// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface ITokenFactory{
    function CreateDepositToken(address) external returns(address);
}