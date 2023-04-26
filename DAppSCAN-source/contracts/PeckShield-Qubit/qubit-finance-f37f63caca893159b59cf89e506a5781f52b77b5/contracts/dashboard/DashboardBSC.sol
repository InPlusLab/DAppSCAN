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
import "../interfaces/IQToken.sol";
import "../interfaces/IQore.sol";
import "../interfaces/IDashboard.sol";
import "../interfaces/IQDistributor.sol";
import "../interfaces/IQubitLocker.sol";
import "../interfaces/IQValidator.sol";

contract DashboardBSC is IDashboard, OwnableUpgradeable {
    using SafeMath for uint;

    /* ========== CONSTANT VARIABLES ========== */

    address private constant QBT = 0x17B7163cf1Dbd286E262ddc68b553D899B93f526;
    IPriceCalculator public constant priceCalculator = IPriceCalculator(0x20E5E35ba29dC3B540a1aee781D0814D5c77Bce6);

    /* ========== STATE VARIABLES ========== */

    IQore public qore;
    IQDistributor public qDistributor;
    IQubitLocker public qubitLocker;
    IQValidator public qValidator;

    /* ========== INITIALIZER ========== */

    function initialize() external initializer {
        __Ownable_init();
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function setQore(address _qore) external onlyOwner {
        require(_qore != address(0), "DashboardBSC: invalid qore address");
        require(address(qore) == address(0), "DashboardBSC: qore already set");
        qore = IQore(_qore);
    }

    function setQDistributor(address _qDistributor) external onlyOwner {
        require(_qDistributor != address(0), "DashboardBSC: invalid qDistributor address");
        qDistributor = IQDistributor(_qDistributor);
    }

    function setLocker(address _qubitLocker) external onlyOwner {
        require(_qubitLocker != address(0), "DashboardBSC: invalid locker address");
        qubitLocker = IQubitLocker(_qubitLocker);
    }

    function setQValidator(address _qValidator) external onlyOwner {
        require(_qValidator != address(0), "DashboardBSC: invalid qValidator address");
        qValidator = IQValidator(_qValidator);
    }

    /* ========== VIEW FUNCTIONS ========== */

    function statusOf(address account, address[] memory markets)
        external
        view
        override
        returns (LockerData memory, MarketData[] memory)
    {
        MarketData[] memory results = new MarketData[](markets.length);
        for (uint i = 0; i < markets.length; i++) {
            results[i] = marketDataOf(account, markets[i]);
        }
        return (lockerDataOf(account), results);
    }

    function apyDistributionOf(address market) public view returns (uint apySupplyQBT, uint apyBorrowQBT) {
        (uint supplyRate, uint borrowRate) = qDistributor.qubitRatesOf(market);
        (uint boostedSupply, uint boostedBorrow) = qDistributor.totalBoosted(market);

        // base supply QBT APY == (qubitRate * 365 days * price Of Qubit) / (Total effective balance * exchangeRate * price of asset) / 2.5
        uint numerSupply = supplyRate.mul(365 days).mul(priceCalculator.priceOf(QBT));
        uint denomSupply = boostedSupply
            .mul(IQToken(market).exchangeRate())
            .mul(priceCalculator.getUnderlyingPrice(market))
            .div(1e36);
        apySupplyQBT = (denomSupply > 0) ? numerSupply.div(denomSupply).mul(100).div(250) : 0;

        // base borrow QBT APY == (qubitRate * 365 days * price Of Qubit) / (Total effective balance * interestIndex * price of asset) / 2.5
        uint numerBorrow = borrowRate.mul(365 days).mul(priceCalculator.priceOf(QBT));
        uint denomBorrow = boostedBorrow
            .mul(IQToken(market).getAccInterestIndex())
            .mul(priceCalculator.getUnderlyingPrice(market))
            .div(1e36);
        apyBorrowQBT = (denomBorrow > 0) ? numerBorrow.div(denomBorrow).mul(100).div(250) : 0;
    }

    function userApyDistributionOf(address account, address market)
        public
        view
        returns (uint userApySupplyQBT, uint userApyBorrowQBT)
    {
        (uint apySupplyQBT, uint apyBorrowQBT) = apyDistributionOf(market);

        (uint userBoostedSupply, uint userBoostedBorrow) = qDistributor.boostedBalanceOf(market, account);
        uint userSupply = IQToken(market).balanceOf(account);
        uint userBorrow = IQToken(market).borrowBalanceOf(account).mul(1e18).div(IQToken(market).getAccInterestIndex());

        // user supply QBT APY == ((qubitRate * 365 days * price Of Qubit) / (Total effective balance * exchangeRate * price of asset) ) * my boosted balance  / my balance
        userApySupplyQBT = (userSupply > 0) ? apySupplyQBT.mul(250).div(100).mul(userBoostedSupply).div(userSupply) : 0;
        // user borrow QBT APY == (qubitRate * 365 days * price Of Qubit) / (Total effective balance * interestIndex * price of asset) * my boosted balance  / my balance
        userApyBorrowQBT = (userBorrow > 0) ? apyBorrowQBT.mul(250).div(100).mul(userBoostedBorrow).div(userBorrow) : 0;
    }

    function marketDataOf(address account, address market) public view returns (MarketData memory) {
        MarketData memory marketData;

        (uint apySupplyQBT, uint apyBorrowQBT) = apyDistributionOf(market);
        marketData.apySupply = IQToken(market).supplyRatePerSec().mul(365 days);
        marketData.apySupplyQBT = apySupplyQBT;
        marketData.apyBorrow = IQToken(market).borrowRatePerSec().mul(365 days);
        marketData.apyBorrowQBT = apyBorrowQBT;

        // calculate my APY for QBT reward
        (uint userBoostedSupply, uint userBoostedBorrow) = qDistributor.boostedBalanceOf(market, account);
        uint userSupply = IQToken(market).balanceOf(account);
        uint userBorrow = IQToken(market).borrowBalanceOf(account).mul(1e18).div(IQToken(market).getAccInterestIndex());
        // user supply QBT APY == ((qubitRate * 365 days * price Of Qubit) / (Total effective balance * exchangeRate * price of asset) ) * my boosted balance  / my balance
        marketData.apyMySupplyQBT = (userSupply > 0)
            ? apySupplyQBT.mul(250).div(100).mul(userBoostedSupply).div(userSupply)
            : 0;
        // user borrow QBT APY == (qubitRate * 365 days * price Of Qubit) / (Total effective balance * interestIndex * price of asset) * my boosted balance  / my balance
        marketData.apyMyBorrowQBT = (userBorrow > 0)
            ? apyBorrowQBT.mul(250).div(100).mul(userBoostedBorrow).div(userBorrow)
            : 0;

        marketData.liquidity = IQToken(market).getCash();
        marketData.collateralFactor = qore.marketInfoOf(market).collateralFactor;

        marketData.membership = qore.checkMembership(account, market);
        marketData.supply = IQToken(market).underlyingBalanceOf(account);
        marketData.borrow = IQToken(market).borrowBalanceOf(account);
        marketData.totalSupply = IQToken(market).totalSupply().mul(IQToken(market).exchangeRate()).div(1e18);
        marketData.totalBorrow = IQToken(market).totalBorrow();
        (marketData.supplyBoosted, marketData.borrowBoosted) = qDistributor.boostedBalanceOf(market, account);
        (marketData.totalSupplyBoosted, marketData.totalBorrowBoosted) = qDistributor.totalBoosted(market);
        return marketData;
    }

    function marketsOf(address account, address[] memory markets) public view returns (MarketData[] memory) {
        MarketData[] memory results = new MarketData[](markets.length);
        for (uint i = 0; i < markets.length; i++) {
            results[i] = marketDataOf(account, markets[i]);
        }
        return results;
    }

    function lockerDataOf(address account) public view returns (LockerData memory) {
        LockerData memory lockerInfo;

        lockerInfo.totalLocked = qubitLocker.totalBalance();
        lockerInfo.locked = qubitLocker.balanceOf(account);

        (uint totalScore, ) = qubitLocker.totalScore();
        lockerInfo.totalScore = totalScore;
        lockerInfo.score = qubitLocker.scoreOf(account);

        lockerInfo.available = qubitLocker.availableOf(account);
        lockerInfo.expiry = qubitLocker.expiryOf(account);
        return lockerInfo;
    }

    function portfolioDataOf(address account) public view returns (PortfolioData memory) {
        PortfolioData memory portfolioData;
        address[] memory markets = qore.allMarkets();
        uint supplyEarnInUSD;
        uint supplyQBTEarnInUSD;
        uint borrowInterestInUSD;
        uint borrowQBTEarnInUSD;
        uint totalInUSD;

        for (uint i = 0; i < markets.length; i++) {
            MarketData memory marketData;
            marketData = marketDataOf(account, markets[i]);

            uint marketSupplyInUSD = marketData.supply.mul(priceCalculator.getUnderlyingPrice(markets[i])).div(1e18);
            uint marketBorrowInUSD = marketData.borrow.mul(priceCalculator.getUnderlyingPrice(markets[i])).div(1e18);

            supplyEarnInUSD = supplyEarnInUSD.add(marketSupplyInUSD.mul(marketData.apySupply).div(1e18));
            borrowInterestInUSD = borrowInterestInUSD.add(marketBorrowInUSD.mul(marketData.apyBorrow).div(1e18));
            supplyQBTEarnInUSD = supplyQBTEarnInUSD.add(marketSupplyInUSD.mul(marketData.apyMySupplyQBT).div(1e18));
            borrowQBTEarnInUSD = borrowQBTEarnInUSD.add(marketBorrowInUSD.mul(marketData.apyMyBorrowQBT).div(1e18));
            totalInUSD = totalInUSD.add(marketSupplyInUSD).add(marketBorrowInUSD);

            portfolioData.supplyInUSD = portfolioData.supplyInUSD.add(marketSupplyInUSD);
            portfolioData.borrowInUSD = portfolioData.borrowInUSD.add(marketBorrowInUSD);
            if (marketData.membership) {
                portfolioData.limitInUSD = portfolioData.limitInUSD.add(
                    marketSupplyInUSD.mul(marketData.collateralFactor).div(1e18)
                );
            }
        }
        if (totalInUSD > 0) {
            if (supplyEarnInUSD.add(supplyQBTEarnInUSD).add(borrowQBTEarnInUSD) > borrowInterestInUSD) {
                portfolioData.userApy = int(
                    supplyEarnInUSD
                        .add(supplyQBTEarnInUSD)
                        .add(borrowQBTEarnInUSD)
                        .sub(borrowInterestInUSD)
                        .mul(1e18)
                        .div(totalInUSD)
                );
            } else {
                portfolioData.userApy =
                    int(-1) *
                    int(
                        borrowInterestInUSD
                            .sub(supplyEarnInUSD.add(supplyQBTEarnInUSD).add(borrowQBTEarnInUSD))
                            .mul(1e18)
                            .div(totalInUSD)
                    );
            }
            portfolioData.userApySupply = supplyEarnInUSD.mul(1e18).div(totalInUSD);
            portfolioData.userApySupplyQBT = supplyQBTEarnInUSD.mul(1e18).div(totalInUSD);
            portfolioData.userApyBorrow = borrowInterestInUSD.mul(1e18).div(totalInUSD);
            portfolioData.userApyBorrowQBT = borrowQBTEarnInUSD.mul(1e18).div(totalInUSD);
        }

        return portfolioData;
    }

    function getUserLiquidityData(uint page, uint resultPerPage)
        external
        view
        returns (AccountLiquidityData[] memory, uint next)
    {
        uint index = page.mul(resultPerPage);
        uint limit = page.add(1).mul(resultPerPage);
        next = page.add(1);

        if (limit > qore.getTotalUserList().length) {
            limit = qore.getTotalUserList().length;
            next = 0;
        }

        if (qore.getTotalUserList().length == 0 || index > qore.getTotalUserList().length - 1) {
            return (new AccountLiquidityData[](0), 0);
        }

        AccountLiquidityData[] memory segment = new AccountLiquidityData[](limit.sub(index));

        uint cursor = 0;
        for (index; index < limit; index++) {
            if (index < qore.getTotalUserList().length) {
                address account = qore.getTotalUserList()[index];
                uint marketCount = qore.marketListOf(account).length;
                (uint collateralUSD, uint borrowUSD) = qValidator.getAccountLiquidityValue(account);
                segment[cursor] = AccountLiquidityData({
                    account: account,
                    marketCount: marketCount,
                    collateralUSD: collateralUSD,
                    borrowUSD: borrowUSD
                });
            }
            cursor++;
        }
        return (segment, next);
        //
        //        uint start;
        //        uint size;
        //        if (pageSize == 0) {
        //            start = 0;
        //            size = totalUserList.length;
        //        } else if (totalUserList.length < pageSize) {
        //            start = 0;
        //            size = page == 0 ? totalUserList.length : 0;
        //        } else {
        //            start = page.mul(pageSize);
        //            if (start <= totalUserList.length) {
        //                if (page == totalUserList.length.div(pageSize)) {
        //                    size = totalUserList.length.mod(pageSize);
        //                } else {
        //                    size = pageSize;
        //                }
        //            } else {
        //                size = 0;
        //            }
        //        }
        //
        //        AccountPortfolio[] memory portfolioList = new AccountPortfolio[](size);
        //        for (uint i = start; i < start.add(size); i ++) {
        //            portfolioList[i.sub(start)].userAddress = totalUserList[i];
        //            (portfolioList[i.sub(start)].collateralUSD, portfolioList[i.sub(start)].borrowUSD) = qValidator.getAccountLiquidityValue(totalUserList[i]);
        //            portfolioList[i.sub(start)].marketListLength = marketListOfUsers[totalUserList[i]].length;
        //        }
        //        return portfolioList;
    }

    function getUnclaimedQBT(address account) public view returns (uint unclaimedQBT) {
        address[] memory markets = qore.allMarkets();

        for (uint i = 0; i < markets.length; i++) {
            unclaimedQBT = unclaimedQBT.add(qDistributor.accruedQubit(markets[i], account));
        }
    }

    function getAvgBoost(address account) public view returns (uint) {
        address[] memory markets = qore.allMarkets();
        uint boostSum;
        uint boostNum;

        for (uint i = 0; i < markets.length; i++) {
            (uint userBoostedSupply, uint userBoostedBorrow) = qDistributor.boostedBalanceOf(markets[i], account);
            uint userSupply = IQToken(markets[i]).balanceOf(account);
            uint userBorrow = IQToken(markets[i]).borrowBalanceOf(account).mul(1e18).div(
                IQToken(markets[i]).getAccInterestIndex()
            );

            uint supplyBoost = (userSupply > 0) ? userBoostedSupply.mul(1e18).div(userSupply).mul(250).div(100) : 0;
            uint borrowBoost = (userBorrow > 0) ? userBoostedBorrow.mul(1e18).div(userBorrow).mul(250).div(100) : 0;

            if (supplyBoost > 0) {
                boostSum = boostSum.add(supplyBoost);
                boostNum = boostNum.add(1);
            }
            if (borrowBoost > 0) {
                boostSum = boostSum.add(borrowBoost);
                boostNum = boostNum.add(1);
            }
        }
        return (boostNum > 0) ? boostSum.div(boostNum) : 0;
    }
}
