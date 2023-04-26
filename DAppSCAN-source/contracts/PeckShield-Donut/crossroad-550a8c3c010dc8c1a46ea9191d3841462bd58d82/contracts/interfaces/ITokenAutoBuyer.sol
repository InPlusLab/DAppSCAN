// SPDX-License-Identifier: MIT

pragma solidity 0.8.3;

interface ITokenAutoBuyer
{
    function costInBnb(uint256 _amountOut) external view returns (uint256);
    function buyTokenFixed(uint256 _amountOut, address _outTarget, address _refundTarget) external payable returns (uint256);
    function buyTokenFromBnb(address _outTarget) external payable;
}
