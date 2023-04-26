// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

interface IStrategy {

    function controller() external view returns (address);
    function getWant() external view returns (address);
    function deposit() external;
    function harvest() external;
    function withdraw(uint) external;
    function withdrawAll() external returns (uint256);
    function balanceOf() external view returns (uint256);
}