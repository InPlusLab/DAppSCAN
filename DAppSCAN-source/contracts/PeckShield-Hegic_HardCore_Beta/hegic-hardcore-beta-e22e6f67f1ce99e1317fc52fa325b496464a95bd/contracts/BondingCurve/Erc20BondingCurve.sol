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
 */

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./Linear.sol";
import "./IBondingCurve.sol";

contract Erc20BondingCurve is LinearBondingCurve {
    using SafeERC20 for IERC20;

    IERC20 public immutable saleToken;
    IERC20 public immutable purchaseToken;
    uint256 public soldAmount;
    uint256 public comissionShare = 20;
    address payable public hegicDevelopmentFund;

    event Bought(address indexed account, uint256 amount, uint256 ethAmount);
    event Sold(
        address indexed account,
        uint256 amount,
        uint256 ethAmount,
        uint256 comission
    );

    constructor(
        IERC20 _saleToken,
        IERC20 _purchaseToken,
        uint256 k,
        uint256 startPrice
    ) LinearBondingCurve(k, startPrice) {
        saleToken = _saleToken;
        purchaseToken = _purchaseToken;
        hegicDevelopmentFund = payable(msg.sender);
        _setupRole(LBC_ADMIN_ROLE, msg.sender);
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function buy(uint256 tokenAmount) external {
        uint256 nextSold = soldAmount + tokenAmount;
        uint256 purchaseAmount = s(soldAmount, nextSold);
        soldAmount = nextSold;

        purchaseToken.safeTransferFrom(
            msg.sender,
            address(this),
            purchaseAmount
        );
        saleToken.safeTransfer(msg.sender, tokenAmount);

        emit Bought(msg.sender, tokenAmount, purchaseAmount);
    }

    function sell(uint256 tokenAmount) external {
        uint256 nextSold = soldAmount - tokenAmount;
        uint256 saleAmount = s(nextSold, soldAmount);
        uint256 comission = (saleAmount * comissionShare) / 100;
        uint256 refund = saleAmount - comission;
        require(comission > 0, "Amount is too small");
        soldAmount = nextSold;

        saleToken.safeTransferFrom(msg.sender, address(this), tokenAmount);
        purchaseToken.safeTransfer(hegicDevelopmentFund, comission);
        purchaseToken.safeTransfer(msg.sender, refund);

        emit Sold(msg.sender, tokenAmount, refund, comission);
    }

    function setHDF(address payable value)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        hegicDevelopmentFund = value;
    }

    function setCommissionShare(uint256 value)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        comissionShare = value;
    }

    function destruct() external onlyRole(DEFAULT_ADMIN_ROLE) {
        selfdestruct(hegicDevelopmentFund);
    }

    function withdawERC20(IERC20 token) external onlyRole(DEFAULT_ADMIN_ROLE) {
        token.transfer(hegicDevelopmentFund, token.balanceOf(address(this)));
    }
}
