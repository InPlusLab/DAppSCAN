// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

interface IAaveDeposit {
    ///@notice deposit to aave some token amount
    ///@param token token address
    ///@param amount amount to deposit
    ///@return id of the deposited position
    ///@return shares emitted
    function depositToAave(address token, uint256 amount) external returns (uint256 id, uint256 shares);
}
