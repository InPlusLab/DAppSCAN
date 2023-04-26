// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

interface yvERC20 {
    function deposit(uint) external;
    function withdraw(uint) external;
    function getPricePerFullShare() external view returns (uint);
}