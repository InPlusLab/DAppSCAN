// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "./IDepositaryBalanceView.sol";

contract StableTokenDepositaryBalanceView is Ownable, IDepositaryBalanceView {
    using SafeMath for uint256;
    using SafeERC20 for ERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice Balance decimals.
    uint256 public override decimals = 18;

    /// @dev Allowed tokens.
    EnumerableSet.AddressSet private tokens;

    /// @notice An event emitted when token allowed.
    event TokenAllowed(address token);

    /// @notice An event emitted when token denied.
    event TokenDenied(address token);

    /**
     * @notice Allow token.
     * @param token Allowed token.
     */
    function allowToken(address token) external onlyOwner {
        require(!tokens.contains(token), "TokenDepositary::allowToken: token already allowed");

        uint256 tokenDecimals = ERC20(token).decimals();
        require(tokenDecimals <= decimals, "TokenDepositary::allowToken: invalid token decimals");

        tokens.add(token);
        emit TokenAllowed(token);
    }

    /**
     * @notice Deny token.
     * @param token Denied token.
     */
    function denyToken(address token) external onlyOwner {
        require(tokens.contains(token), "TokenDepositary::denyToken: token already denied");

        tokens.remove(token);
        emit TokenDenied(token);
    }

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
    ) external onlyOwner {
        ERC20(token).safeTransfer(recipient, amount);
    }

    /**
     * @return Allowed tokens list.
     */
    function allowedTokens() external view returns (address[] memory) {
        address[] memory result = new address[](tokens.length());

        for(uint256 i = 0; i < tokens.length(); i++) {
            result[i] = tokens.at(i);
        }

        return result;
    }

    function balance() external override view returns (uint256) {
        uint256 result;

        for(uint256 i = 0; i < tokens.length(); i++) {
            ERC20 token = ERC20(tokens.at(i));
            uint256 tokenBalance = token.balanceOf(address(this));
            uint256 tokenDecimals = token.decimals();

            result = result.add(tokenBalance.mul(10**(decimals.sub(tokenDecimals))));
        }

        return result;
    }
}
