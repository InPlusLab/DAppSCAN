// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface IActionTrigger {
    function getATPoolInfo(uint256 _pid) external view 
        returns (address lpToken, uint256 allocRate, uint256 totalAmount);
    function getATUserAmount(uint256 _pid, address _account) external view 
        returns (uint256 acctAmount);
}