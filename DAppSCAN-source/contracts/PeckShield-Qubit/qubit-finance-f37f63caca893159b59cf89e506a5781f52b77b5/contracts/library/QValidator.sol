// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

/*
      ___       ___       ___       ___       ___
     /\  \     /\__\     /\  \     /\  \     /\  \
    /::\  \   /:/ _/_   /::\  \   _\:\  \    \:\  \
    \:\:\__\ /:/_/\__\ /::\:\__\ /\/::\__\   /::\__\
     \::/  / \:\/:/  / \:\::/  / \::/\/__/  /:/\/__/
     /:/  /   \::/  /   \::/  /   \:\__\    \/__/
     \/__/     \/__/     \/__/     \/__/

*
* MIT License
* ===========
*
* Copyright (c) 2021 QubitFinance
*
* Permission is hereby granted, free of charge, to any person obtaining a copy
* of this software and associated documentation files (the "Software"), to deal
* in the Software without restriction, including without limitation the rights
* to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
* copies of the Software, and to permit persons to whom the Software is
* furnished to do so, subject to the following conditions:
*
* The above copyright notice and this permission notice shall be included in all
* copies or substantial portions of the Software.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
* AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
* OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
* SOFTWARE.
*/

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "../interfaces/IPriceCalculator.sol";
import "../interfaces/IQValidator.sol";
import "../interfaces/IQToken.sol";
import "../interfaces/IQore.sol";
import "../library/QConstant.sol";

contract QValidator is IQValidator, OwnableUpgradeable {
    using SafeMath for uint;

    /* ========== CONSTANT VARIABLES ========== */

    IPriceCalculator public constant oracle = IPriceCalculator(0x20E5E35ba29dC3B540a1aee781D0814D5c77Bce6);

    /* ========== STATE VARIABLES ========== */

    IQore public qore;

    /* ========== INITIALIZER ========== */

    function initialize() external initializer {
        __Ownable_init();
    }

    /* ========== VIEWS ========== */

    function getAccountLiquidity(
        address account,
        address qToken,
        uint redeemAmount,
        uint borrowAmount
    ) external view override returns (uint liquidity, uint shortfall) {
        uint accCollateralValueInUSD;
        uint accBorrowValueInUSD;

        address[] memory assets = qore.marketListOf(account);
        uint[] memory prices = oracle.getUnderlyingPrices(assets);
        for (uint i = 0; i < assets.length; i++) {
            require(prices[i] != 0, "QValidator: price error");
            QConstant.AccountSnapshot memory snapshot = IQToken(payable(assets[i])).accountSnapshot(account);

            uint collateralValuePerShareInUSD = snapshot
                .exchangeRate
                .mul(prices[i])
                .mul(qore.marketInfoOf(payable(assets[i])).collateralFactor)
                .div(1e36);
            accCollateralValueInUSD = accCollateralValueInUSD.add(
                snapshot.qTokenBalance.mul(collateralValuePerShareInUSD).div(1e18)
            );
            accBorrowValueInUSD = accBorrowValueInUSD.add(snapshot.borrowBalance.mul(prices[i]).div(1e18));

            if (assets[i] == qToken) {
                accBorrowValueInUSD = accBorrowValueInUSD.add(redeemAmount.mul(collateralValuePerShareInUSD).div(1e18));
                accBorrowValueInUSD = accBorrowValueInUSD.add(borrowAmount.mul(prices[i]).div(1e18));
            }
        }

        liquidity = accCollateralValueInUSD > accBorrowValueInUSD
            ? accCollateralValueInUSD.sub(accBorrowValueInUSD)
            : 0;
        shortfall = accCollateralValueInUSD > accBorrowValueInUSD
            ? 0
            : accBorrowValueInUSD.sub(accCollateralValueInUSD);
    }

    function getAccountLiquidityValue(address account)
        external
        view
        override
        returns (uint collateralUSD, uint borrowUSD)
    {
        address[] memory assets = qore.marketListOf(account);
        uint[] memory prices = oracle.getUnderlyingPrices(assets);
        collateralUSD = 0;
        borrowUSD = 0;
        for (uint i = 0; i < assets.length; i++) {
            require(prices[i] != 0, "QValidator: price error");
            QConstant.AccountSnapshot memory snapshot = IQToken(payable(assets[i])).accountSnapshot(account);

            uint collateralValuePerShareInUSD = snapshot
                .exchangeRate
                .mul(prices[i])
                .mul(qore.marketInfoOf(payable(assets[i])).collateralFactor)
                .div(1e36);
            collateralUSD = collateralUSD.add(snapshot.qTokenBalance.mul(collateralValuePerShareInUSD).div(1e18));
            borrowUSD = borrowUSD.add(snapshot.borrowBalance.mul(prices[i]).div(1e18));
        }
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function setQore(address _qore) external onlyOwner {
        require(_qore != address(0), "QValidator: invalid qore address");
        require(address(qore) == address(0), "QValidator: qore already set");
        qore = IQore(_qore);
    }

    /* ========== ALLOWED FUNCTIONS ========== */

    function redeemAllowed(
        address qToken,
        address redeemer,
        uint redeemAmount
    ) external override returns (bool) {
        (, uint shortfall) = _getAccountLiquidityInternal(redeemer, qToken, redeemAmount, 0);
        return shortfall == 0;
    }

    function borrowAllowed(
        address qToken,
        address borrower,
        uint borrowAmount
    ) external override returns (bool) {
        require(qore.checkMembership(borrower, address(qToken)), "QValidator: enterMarket required");
        require(oracle.getUnderlyingPrice(address(qToken)) > 0, "QValidator: Underlying price error");

        // Borrow cap of 0 corresponds to unlimited borrowing
        uint borrowCap = qore.marketInfoOf(qToken).borrowCap;
        if (borrowCap != 0) {
            uint totalBorrows = IQToken(payable(qToken)).accruedTotalBorrow();
            uint nextTotalBorrows = totalBorrows.add(borrowAmount);
            require(nextTotalBorrows < borrowCap, "QValidator: market borrow cap reached");
        }

        (, uint shortfall) = _getAccountLiquidityInternal(borrower, qToken, 0, borrowAmount);
        return shortfall == 0;
    }

    function liquidateAllowed(
        address qToken,
        address borrower,
        uint liquidateAmount,
        uint closeFactor
    ) external override returns (bool) {
        // The borrower must have shortfall in order to be liquidate
        (, uint shortfall) = _getAccountLiquidityInternal(borrower, address(0), 0, 0);
        require(shortfall != 0, "QValidator: Insufficient shortfall");

        // The liquidator may not repay more than what is allowed by the closeFactor
        uint borrowBalance = IQToken(payable(qToken)).accruedBorrowBalanceOf(borrower);
        uint maxClose = closeFactor.mul(borrowBalance).div(1e18);
        return liquidateAmount <= maxClose;
    }

    function qTokenAmountToSeize(
        address qTokenBorrowed,
        address qTokenCollateral,
        uint amount
    ) external override returns (uint seizeQAmount) {
        uint priceBorrowed = oracle.getUnderlyingPrice(qTokenBorrowed);
        uint priceCollateral = oracle.getUnderlyingPrice(qTokenCollateral);
        require(priceBorrowed != 0 && priceCollateral != 0, "QValidator: price error");

        uint exchangeRate = IQToken(payable(qTokenCollateral)).accruedExchangeRate();
        require(exchangeRate != 0, "QValidator: exchangeRate of qTokenCollateral is zero");

        // seizeQTokenAmount = amount * (liquidationIncentive * priceBorrowed) / (priceCollateral * exchangeRate)
        return amount.mul(qore.liquidationIncentive()).mul(priceBorrowed).div(priceCollateral.mul(exchangeRate));
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    function _getAccountLiquidityInternal(
        address account,
        address qToken,
        uint redeemAmount,
        uint borrowAmount
    ) private returns (uint liquidity, uint shortfall) {
        uint accCollateralValueInUSD;
        uint accBorrowValueInUSD;

        address[] memory assets = qore.marketListOf(account);
        uint[] memory prices = oracle.getUnderlyingPrices(assets);
        for (uint i = 0; i < assets.length; i++) {
            require(prices[i] != 0, "QValidator: price error");
            QConstant.AccountSnapshot memory snapshot = IQToken(payable(assets[i])).accruedAccountSnapshot(account);

            uint collateralValuePerShareInUSD = snapshot
                .exchangeRate
                .mul(prices[i])
                .mul(qore.marketInfoOf(payable(assets[i])).collateralFactor)
                .div(1e36);
            accCollateralValueInUSD = accCollateralValueInUSD.add(
                snapshot.qTokenBalance.mul(collateralValuePerShareInUSD).div(1e18)
            );
            accBorrowValueInUSD = accBorrowValueInUSD.add(snapshot.borrowBalance.mul(prices[i]).div(1e18));

            if (assets[i] == qToken) {
                accBorrowValueInUSD = accBorrowValueInUSD.add(redeemAmount.mul(collateralValuePerShareInUSD).div(1e18));
                accBorrowValueInUSD = accBorrowValueInUSD.add(borrowAmount.mul(prices[i]).div(1e18));
            }
        }

        liquidity = accCollateralValueInUSD > accBorrowValueInUSD
            ? accCollateralValueInUSD.sub(accBorrowValueInUSD)
            : 0;
        shortfall = accCollateralValueInUSD > accBorrowValueInUSD
            ? 0
            : accBorrowValueInUSD.sub(accCollateralValueInUSD);
    }
}
