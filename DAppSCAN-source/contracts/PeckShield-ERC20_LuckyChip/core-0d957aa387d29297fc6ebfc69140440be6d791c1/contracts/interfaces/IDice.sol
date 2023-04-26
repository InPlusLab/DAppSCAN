// SPDX-License-Identifier: MIT
  
pragma solidity 0.6.12;

interface IDice {
    function tokenAddr() external view returns (address);
    function canWithdrawAmount(uint256 _amount) external view returns (uint256);
}
