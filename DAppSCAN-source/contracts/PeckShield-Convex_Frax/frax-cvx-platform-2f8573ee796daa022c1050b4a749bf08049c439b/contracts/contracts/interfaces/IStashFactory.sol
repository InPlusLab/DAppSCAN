// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface IStashFactory{
    function CreateStash(uint256,address,address,uint256) external returns(address);
}