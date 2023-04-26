// SPDX-License-Identifier: MIT
  
pragma solidity 0.6.12;

interface IBetMining {
    function bet(address account, address referrer, address token, uint256 amount) external returns (bool);
    function getLuckyPower(address user) external view returns (uint256);
}
