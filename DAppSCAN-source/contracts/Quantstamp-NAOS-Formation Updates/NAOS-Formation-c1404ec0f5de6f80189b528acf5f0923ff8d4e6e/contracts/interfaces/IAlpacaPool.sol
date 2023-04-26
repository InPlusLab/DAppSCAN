// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.6.12;

interface IAlpacaPool {
    function deposit(address, uint256, uint256) external;

    function withdraw(address, uint256, uint256) external;

    function harvest(uint256) external;

    function userInfo(uint256, address) external view returns (uint256, uint256, uint256, address);
}