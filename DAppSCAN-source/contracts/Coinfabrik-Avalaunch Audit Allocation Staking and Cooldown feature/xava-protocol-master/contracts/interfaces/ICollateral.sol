// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.12;

interface ICollateral {
    function saleAutoBuyers(address user, address sale) external view returns (bool);
    function depositCollateral() external payable;
    function withdrawCollateral() external payable;
    function totalBalance() external view returns (uint256);
}