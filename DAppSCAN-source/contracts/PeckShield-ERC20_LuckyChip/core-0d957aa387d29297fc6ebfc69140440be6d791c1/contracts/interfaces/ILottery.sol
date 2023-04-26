// SPDX-License-Identifier: MIT
  
pragma solidity 0.6.12;

interface ILottery {
    function getLuckyPower(address user) external view returns (uint256);
}
