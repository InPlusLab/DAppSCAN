// SPDX-License-Identifier: MIT

// Originally: https://github.com/CryptoManiacsZone/mooniswap/blob/master/contracts/libraries/UniERC20.sol

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "hardhat/console.sol";

library UniERC20 {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    function isETH(IERC20 token) internal pure returns (bool) {
        return (address(token) == address(0));
    }

    function uniBalanceOf(IERC20 token, address account) internal view returns (uint256) {
        if (isETH(token)) {
            return account.balance;
        } else {
            return token.balanceOf(account);
        }
    }

    function uniTransfer(
        IERC20 token,
        address to,
        uint256 amount
    ) internal {
        if (amount > 0) {
            if (isETH(token)) {
                (bool success, ) = payable(to).call{value: amount}("");
                require(success, "Transfer failed");
            } else {
                token.safeTransfer(to, amount);
            }
        }
    }

    function uniTransferFromSenderToThis(IERC20 token, uint256 amount) internal {
        if (amount > 0) {
            if (isETH(token)) {
                require(msg.value >= amount, "UniERC20: not enough value");
                if (msg.value > amount) {
                    // Return remainder if exist
                    uint256 refundAmount = msg.value.sub(amount);
                    (bool success, ) = msg.sender.call{value: refundAmount}("");
                    require(success, "Transfer failed");
                }
            } else {
                token.safeTransferFrom(msg.sender, address(this), amount);
            }
        }
    }
}
