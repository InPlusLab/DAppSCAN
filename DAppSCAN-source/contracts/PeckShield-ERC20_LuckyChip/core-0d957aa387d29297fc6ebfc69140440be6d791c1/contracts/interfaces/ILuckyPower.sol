// SPDX-License-Identifier: MIT
  
pragma solidity 0.6.12;

interface ILuckyPower {
    function updateBonus(address bonusToken, uint256 amount) external;
    function updatePower(address account) external;
    function getPower(address account) external view returns (uint256);
}
