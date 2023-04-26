pragma solidity ^0.8.0;

/**
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Buffer
 * Copyright (C) 2020 Buffer Protocol
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
 */

interface ILiquidityPool {
    struct LockedLiquidity {
        uint256 amount;
        uint256 premium;
        bool locked;
    }

    event Profit(uint256 indexed id, uint256 amount);
    event Loss(uint256 indexed id, uint256 amount);
    event Provide(address indexed account, uint256 amount, uint256 writeAmount);
    event Withdraw(
        address indexed account,
        uint256 amount,
        uint256 writeAmount
    );

    function unlock(uint256 id) external;

    function send(
        uint256 id,
        address payable account,
        uint256 amount
    ) external;

    function totalBalance() external view returns (uint256 amount);
    // function unlockPremium(uint256 amount) external;
}

interface IBNBLiquidityPool is ILiquidityPool {
    function lock(uint256 id, uint256 amount) external payable;
}

interface IBufferOptions {
    event Create(
        uint256 indexed id,
        address indexed account,
        uint256 settlementFee,
        uint256 totalFee
    );

    event Exercise(uint256 indexed id, uint256 profit);
    event Expire(uint256 indexed id, uint256 premium);
    enum State {Inactive, Active, Exercised, Expired}
    enum OptionType {Invalid, Put, Call}

    struct Option {
        State state;
        uint256 strike;
        uint256 amount;
        uint256 lockedAmount;
        uint256 premium;
        uint256 expiration;
        OptionType optionType;
    }
}

interface IBufferStaking {
    event Claim(address indexed acount, uint256 amount);
    event Profit(uint256 amount);

    function claimProfit() external returns (uint256 profit);

    function buy(uint256 amountOfTokens) external;

    function sell(uint256 amountOfTokens) external;

    function profitOf(address account) external view returns (uint256);
}

interface IBufferStakingBNB is IBufferStaking {
    function sendProfit() external payable;
}

interface IBufferStakingIBFR is IBufferStaking {
    function sendProfit(uint256 amount) external;
}
