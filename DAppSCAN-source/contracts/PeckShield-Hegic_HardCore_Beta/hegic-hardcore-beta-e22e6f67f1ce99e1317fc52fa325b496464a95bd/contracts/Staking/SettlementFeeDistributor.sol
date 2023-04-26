pragma solidity 0.8.6;

/**
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Hegic
 * Copyright (C) 2021 Hegic Protocol
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
import "../Interfaces/Interfaces.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract SettlementFeeDistributor is ISettlementFeeRecipient, Ownable {
    using SafeERC20 for IERC20;
    ISettlementFeeRecipient public immutable staking;
    IERC20 public immutable token;
    address public immutable HLTPs;
    uint128 public totalShare = 24;
    uint128 public stakingShare = 19;

    constructor(
        ISettlementFeeRecipient staking_,
        IERC20 token_,
        address HLTPs_
    ) {
        staking = staking_;
        token = token_;
        HLTPs = HLTPs_;
    }

    function setShares(uint128 stakingShare_, uint128 totalShare_)
        external
        onlyOwner
    {
        require(
            totalShare_ != 0,
            "SettlementFeeDistributor: totalShare is zero"
        );
        require(
            stakingShare_ <= totalShare,
            "SettlementFeeDistributor: stakingShare is too large"
        );
        totalShare = totalShare_;
        stakingShare = stakingShare_;
    }

    function distributeUnrealizedRewards() external override {
        uint256 amount = token.balanceOf(address(this));

        require(amount > 0, "SettlementFeeDistributor: Amount is zero");

        uint256 stakingAmount = (amount * stakingShare) / totalShare;
        token.safeTransfer(HLTPs, amount - stakingAmount);
        token.safeTransfer(address(staking), stakingAmount);
        staking.distributeUnrealizedRewards();
    }
}
