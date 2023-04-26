// SPDX-License-Identifier: MIT

pragma solidity 0.8.3;

interface IDjinnAutoBuyer
{
    function costInBnb(uint256 _amountOut) external view returns (uint256);
    function buyDjinn(uint256 _amountOut, address _outTarget, address _refundTarget) external payable returns (uint256);
}
