pragma solidity 0.8.6;

/**
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Hegic
 * Copyright (C) 2022 Hegic Protocol
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 **/

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IHegicStakeAndCover.sol";
import "hardhat/console.sol";

contract HegicStakeAndCover is IHegicStakeAndCover, AccessControl {
    IERC20 public immutable hegicToken;
    IERC20 public immutable baseToken;
    mapping(address => uint256) public balanceOf;
    mapping(address => uint256) public startBalance;
    address internal unlockedTokenRecipient;

    bool public withdrawalsEnabled;
    uint256 public totalBalance;
    bytes32 public constant HEGIC_POOL_ROLE = keccak256("HEGIC_POOL_ROLE");

    constructor(IERC20 _hegic, IERC20 _baseToken) {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        hegicToken = _hegic;
        baseToken = _baseToken;
        unlockedTokenRecipient = msg.sender;
    }

    /**
     * @notice Used for withdrawing of deposited
     * tokens from the contract
     * @param to The recipient address
     * @param amount The amount to withdraw
     **/
    function transfer(address to, uint256 amount)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        baseToken.transfer(to, amount);
    }

    function availableBalance() external view override returns (uint256) {
        return baseToken.balanceOf(address(this));
    }

    /**
     * @notice Used for transferring tokens for replenishing
     * of the Hegic Operational Treasury contract
     * @param amount The amount to transfer
     **/
    function payOut(uint256 amount)
        external
        override
        onlyRole(HEGIC_POOL_ROLE)
    {
        baseToken.transfer(msg.sender, amount);
    }

    /**
     * @notice Used for adding tokens
     * to the unlockedTokenRecipient balance
     **/
    function saveFreeTokens() external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 amount = hegicToken.balanceOf(address(this)) - totalBalance;
        totalBalance += amount;
        balanceOf[unlockedTokenRecipient] += amount;
    }

    /**
     * @notice Used for calculating
     * the user's balance in the base token
     * @param holder The user address
     **/
    function shareOf(address holder) public view returns (uint256) {
        return
            (baseToken.balanceOf(address(this)) * balanceOf[holder]) /
            totalBalance;
    }

    /**
     * @notice Used for setting the shares
     * among the eligible users
     * @param account The user address
     * @param amount The share size
     **/
    function trasferShare(address account, uint256 amount) external {
        require(profitOf(msg.sender) == 0);
        require(profitOf(account) == 0);
        balanceOf[msg.sender] -= amount;
        balanceOf[account] += amount;
        startBalance[msg.sender] = shareOf(msg.sender);
        startBalance[account] = shareOf(account);
    }

    /**
     * @notice Used for calculating the claimable profit
     * @param account The user address
     **/
    function profitOf(address account)
        public
        view
        returns (uint256 profitAmount)
    {
        return
            (balanceOf[account] * baseToken.balanceOf(address(this))) /
            totalBalance -
            startBalance[account];
    }

    /**
     * @notice Used for withdrawing tokens from the contract
     * @param amount The amount of tokens
     **/
    function withdraw(uint256 amount) external {
        require(
            withdrawalsEnabled,
            "HegicStakeAndCover: Withdrawals are currently disabled"
        );
        _withdraw(msg.sender, msg.sender, amount);
    }

    /**
     * @notice Used for enabling the token
     * transfers from the contract
     * @param value True or false
     **/
    function setWithdrawalsEnabled(bool value)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        withdrawalsEnabled = value;
    }

    /**
     * @notice Used for claiming profits
     * accumulated on the contract
     **/
    function claimProfit() public returns (uint256 profit) {
        profit = profitOf(msg.sender);
        require(profit > 0, "HegicStakeAndCover: The claimable profit is zero");
        uint256 profitShare =
            (profit * totalBalance) / baseToken.balanceOf(address(this));
        _withdraw(msg.sender, unlockedTokenRecipient, profitShare);
    }

    function _withdraw(
        address account,
        address hegicDestination,
        uint256 amount
    ) internal {
        uint256 liquidityShare =
            (amount * baseToken.balanceOf(address(this))) / totalBalance;
        balanceOf[account] -= amount;
        startBalance[account] =
            (balanceOf[account] * baseToken.balanceOf(address(this))) /
            totalBalance;
        totalBalance -= amount;
        hegicToken.transfer(hegicDestination, amount);
        baseToken.transfer(account, liquidityShare);
        emit Withdrawn(msg.sender, hegicDestination, amount, liquidityShare);
    }

    /**
     * @notice Used for depositing tokens into the contract
     * @param amount The amount of tokens
     **/
    function provide(uint256 amount) external {
        if (profitOf(msg.sender) > 0) claimProfit();
        uint256 liquidityShare =
            (amount * baseToken.balanceOf(address(this))) / totalBalance;
        balanceOf[msg.sender] += amount;
        startBalance[msg.sender] = shareOf(msg.sender);
        totalBalance += amount;
        hegicToken.transferFrom(msg.sender, address(this), amount);
        baseToken.transferFrom(msg.sender, address(this), liquidityShare);
        emit Provided(msg.sender, amount, liquidityShare);
    }
}
