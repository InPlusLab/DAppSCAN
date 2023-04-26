// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';

library ERC20Helper {
    ///@dev library to interact with ERC20 token
    using SafeERC20 for IERC20;

    ///@notice approve the token to be able to transfer it
    ///@param token address of the token
    ///@param spender address of the spender
    ///@param amount amount to approve
    function _approveToken(
        address token,
        address spender,
        uint256 amount
    ) internal {
        if (IERC20(token).allowance(address(this), spender) >= amount) {
            return;
        }
        IERC20(token).approve(spender, amount);
    }

    ///@notice return the allowance of the token that the spender is able to spend
    ///@param token address of the token
    ///@param owner address of the owner
    ///@param spender address of the spender
    ///@return uint256 allowance amount
    function _getAllowance(
        address token,
        address owner,
        address spender
    ) internal view returns (uint256) {
        return IERC20(token).allowance(owner, spender);
    }

    ///@notice pull token if it is below the threshold amount
    ///@param token address of the token
    ///@param from address of the sender
    ///@param amount amount of tokens to be pulled
    ///@return uint256 amount of the tokens that were pulled
    function _pullTokensIfNeeded(
        address token,
        address from,
        uint256 amount
    ) internal returns (uint256) {
        uint256 needed = 0;
        uint256 balance = _getBalance(token, address(this));
        if (balance < amount) {
            if (amount - balance < _getBalance(token, from)) {
                needed = amount - balance;
                IERC20(token).safeTransferFrom(from, address(this), needed);
            }
        }
        return needed;
    }

    ///@notice withdraw the tokens from the vault and send them to the user
    ///@param token address of the token
    ///@param to address of the user
    ///@param amount amount of tokens to withdraw
    function _withdrawTokens(
        address token,
        address to,
        uint256 amount
    ) internal returns (uint256 amountOut) {
        uint256 balance = _getBalance(token, address(this));
        if (balance < amount) {
            amountOut = balance;
        } else {
            amountOut = amount;
        }
        IERC20(token).safeTransferFrom(address(this), to, amountOut);
    }

    ///@notice get the balance of the token for the given address
    ///@param token address of the token
    ///@param account address of the account
    ///@return uint256 return the balance of the token for the given address
    function _getBalance(address token, address account) internal view returns (uint256) {
        return IERC20(token).balanceOf(account);
    }
}
