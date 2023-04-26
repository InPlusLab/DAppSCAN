// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

interface IAaveWithdraw {
    ///@notice withdraw from aave some token amount
    ///@param token token address
    ///@param id position to withdraw from
    ///@return amountWithdrawn amount of token withdrawn from aave
    function withdrawFromAave(address token, uint256 id) external returns (uint256 amountWithdrawn);
}
