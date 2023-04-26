// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "./utils/AccessControl.sol";

contract Treasury is AccessControl {
    using SafeMath for uint256;
    using SafeERC20 for ERC20;

    receive() external payable {}

    /**
     * @notice Transfer target token to recipient.
     * @param token Target token.
     * @param recipient Recipient.
     * @param amount Transfer amount.
     */
    function transfer(
        address token,
        address recipient,
        uint256 amount
    ) external onlyAllowed returns (bool) {
        ERC20(token).safeTransfer(recipient, amount);
        return true;
    }

    /**
     * @notice Transfer ETH to recipient.
     * @param recipient Recipient.
     * @param amount Transfer amount.
     */
    function transferETH(address payable recipient, uint256 amount) external onlyAllowed returns (bool) {
        recipient.transfer(amount);
        return true;
    }

    /**
     * @notice Approve target token to recipient.
     * @param token Target token.
     * @param recipient Recipient.
     * @param amount Approve amount.
     */
    function approve(
        address token,
        address recipient,
        uint256 amount
    ) external onlyAllowed returns (bool) {
        ERC20(token).safeApprove(recipient, amount);
        return true;
    }
}
