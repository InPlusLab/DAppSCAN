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

import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import "./library/WhitelistUpgradeable.sol";
import "./library/SafeToken.sol";
import "./interfaces/IBEP20.sol";
import "./interfaces/IQDistributor.sol";
import "./interfaces/IQubitLocker.sol";
import "./interfaces/IQToken.sol";
import "./interfaces/IQore.sol";

contract QDistributor is IQDistributor, WhitelistUpgradeable, ReentrancyGuardUpgradeable {
    using SafeMath for uint;
    using SafeToken for address;

    /* ========== CONSTANT VARIABLES ========== */

    address private constant QBT = 0x17B7163cf1Dbd286E262ddc68b553D899B93f526;

    uint public constant BOOST_PORTION_Q = 60;
    uint public constant BOOST_PORTION_MAX = 100;

    IQore public constant qore = IQore(0xF70314eb9c7Fe7D88E6af5aa7F898b3A162dcd48);
    IQubitLocker public constant qubitLocker = IQubitLocker(0xB8243be1D145a528687479723B394485cE3cE773);

    /* ========== STATE VARIABLES ========== */

    mapping(address => DistributionInfo) distributions;
    mapping(address => mapping(address => UserInfo)) marketUsers;

    /* ========== MODIFIERS ========== */

    modifier updateDistributionOf(address market) {
        DistributionInfo storage dist = distributions[market];
        if (dist.accruedAt == 0) {
            dist.accruedAt = block.timestamp;
        }

        uint timeElapsed = block.timestamp > dist.accruedAt ? block.timestamp.sub(dist.accruedAt) : 0;
        if (timeElapsed > 0) {
            if (dist.totalBoostedSupply > 0) {
                dist.accPerShareSupply = dist.accPerShareSupply.add(
                    dist.supplyRate.mul(timeElapsed).mul(1e18).div(dist.totalBoostedSupply)
                );
            }

            if (dist.totalBoostedBorrow > 0) {
                dist.accPerShareBorrow = dist.accPerShareBorrow.add(
                    dist.borrowRate.mul(timeElapsed).mul(1e18).div(dist.totalBoostedBorrow)
                );
            }
        }
        dist.accruedAt = block.timestamp;
        _;
    }

    modifier onlyQore() {
        require(msg.sender == address(qore), "QDistributor: caller is not Qore");
        _;
    }

    modifier onlyMarket() {
        bool fromMarket = false;
        address[] memory markets = qore.allMarkets();
        for (uint i = 0; i < markets.length; i++) {
            if (msg.sender == markets[i]) {
                fromMarket = true;
                break;
            }
        }
        require(fromMarket == true, "QDistributor: caller should be market");
        _;
    }

    /* ========== EVENTS ========== */

    event QubitDistributionRateUpdated(address indexed qToken, uint supplyRate, uint borrowRate);
    event QubitClaimed(address indexed user, uint amount);

    /* ========== INITIALIZER ========== */

    function initialize() external initializer {
        __WhitelistUpgradeable_init();
        __ReentrancyGuard_init();
    }

    /* ========== VIEWS ========== */

    function userInfoOf(address market, address user) external view returns (UserInfo memory) {
        return marketUsers[market][user];
    }

    function accruedQubit(address market, address user) external view override returns (uint) {
        DistributionInfo memory dist = distributions[market];
        UserInfo memory userInfo = marketUsers[market][user];

        uint _accruedQubit = userInfo.accruedQubit;
        uint accPerShareSupply = dist.accPerShareSupply;
        uint accPerShareBorrow = dist.accPerShareBorrow;

        uint timeElapsed = block.timestamp > dist.accruedAt ? block.timestamp.sub(dist.accruedAt) : 0;
        if (
            timeElapsed > 0 ||
            (accPerShareSupply != userInfo.accPerShareSupply) ||
            (accPerShareBorrow != userInfo.accPerShareBorrow)
        ) {
            if (dist.totalBoostedSupply > 0) {
                accPerShareSupply = accPerShareSupply.add(
                    dist.supplyRate.mul(timeElapsed).mul(1e18).div(dist.totalBoostedSupply)
                );

                uint pendingQubit = userInfo.boostedSupply.mul(accPerShareSupply.sub(userInfo.accPerShareSupply)).div(
                    1e18
                );
                _accruedQubit = _accruedQubit.add(pendingQubit);
            }

            if (dist.totalBoostedBorrow > 0) {
                accPerShareBorrow = accPerShareBorrow.add(
                    dist.borrowRate.mul(timeElapsed).mul(1e18).div(dist.totalBoostedBorrow)
                );

                uint pendingQubit = userInfo.boostedBorrow.mul(accPerShareBorrow.sub(userInfo.accPerShareBorrow)).div(
                    1e18
                );
                _accruedQubit = _accruedQubit.add(pendingQubit);
            }
        }
        return _accruedQubit;
    }

    function qubitRatesOf(address market) external view override returns (uint supplyRate, uint borrowRate) {
        return (distributions[market].supplyRate, distributions[market].borrowRate);
    }

    function totalBoosted(address market) external view override returns (uint boostedSupply, uint boostedBorrow) {
        return (distributions[market].totalBoostedSupply, distributions[market].totalBoostedBorrow);
    }

    function boostedBalanceOf(address market, address account)
        external
        view
        override
        returns (uint boostedSupply, uint boostedBorrow)
    {
        return (marketUsers[market][account].boostedSupply, marketUsers[market][account].boostedBorrow);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function setQubitDistributionRates(
        address qToken,
        uint supplyRate,
        uint borrowRate
    ) external onlyOwner updateDistributionOf(qToken) {
        DistributionInfo storage dist = distributions[qToken];
        dist.supplyRate = supplyRate;
        dist.borrowRate = borrowRate;
        emit QubitDistributionRateUpdated(qToken, supplyRate, borrowRate);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function notifySupplyUpdated(address market, address user)
        external
        override
        nonReentrant
        onlyQore
        updateDistributionOf(market)
    {
        DistributionInfo storage dist = distributions[market];
        UserInfo storage userInfo = marketUsers[market][user];

        if (userInfo.boostedSupply > 0) {
            uint accQubitPerShare = dist.accPerShareSupply.sub(userInfo.accPerShareSupply);
            userInfo.accruedQubit = userInfo.accruedQubit.add(accQubitPerShare.mul(userInfo.boostedSupply).div(1e18));
        }
        userInfo.accPerShareSupply = dist.accPerShareSupply;

        uint boostedSupply = _calculateBoostedSupply(market, user);
        dist.totalBoostedSupply = dist.totalBoostedSupply.add(boostedSupply).sub(userInfo.boostedSupply);
        userInfo.boostedSupply = boostedSupply;
    }

    function notifyBorrowUpdated(address market, address user)
        external
        override
        nonReentrant
        onlyQore
        updateDistributionOf(market)
    {
        DistributionInfo storage dist = distributions[market];
        UserInfo storage userInfo = marketUsers[market][user];

        if (userInfo.boostedBorrow > 0) {
            uint accQubitPerShare = dist.accPerShareBorrow.sub(userInfo.accPerShareBorrow);
            userInfo.accruedQubit = userInfo.accruedQubit.add(accQubitPerShare.mul(userInfo.boostedBorrow).div(1e18));
        }
        userInfo.accPerShareBorrow = dist.accPerShareBorrow;

        uint boostedBorrow = _calculateBoostedBorrow(market, user);
        dist.totalBoostedBorrow = dist.totalBoostedBorrow.add(boostedBorrow).sub(userInfo.boostedBorrow);
        userInfo.boostedBorrow = boostedBorrow;
    }

    function notifyTransferred(
        address qToken,
        address sender,
        address receiver
    ) external override nonReentrant onlyMarket updateDistributionOf(qToken) {
        require(sender != receiver, "QDistributor: invalid transfer");
        DistributionInfo storage dist = distributions[qToken];
        UserInfo storage senderInfo = marketUsers[qToken][sender];
        UserInfo storage receiverInfo = marketUsers[qToken][receiver];

        if (senderInfo.boostedSupply > 0) {
            uint accQubitPerShare = dist.accPerShareSupply.sub(senderInfo.accPerShareSupply);
            senderInfo.accruedQubit = senderInfo.accruedQubit.add(
                accQubitPerShare.mul(senderInfo.boostedSupply).div(1e18)
            );
        }
        senderInfo.accPerShareSupply = dist.accPerShareSupply;

        if (receiverInfo.boostedSupply > 0) {
            uint accQubitPerShare = dist.accPerShareSupply.sub(receiverInfo.accPerShareSupply);
            receiverInfo.accruedQubit = receiverInfo.accruedQubit.add(
                accQubitPerShare.mul(receiverInfo.boostedSupply).div(1e18)
            );
        }
        receiverInfo.accPerShareSupply = dist.accPerShareSupply;

        uint boostedSenderSupply = _calculateBoostedSupply(qToken, sender);
        uint boostedReceiverSupply = _calculateBoostedSupply(qToken, receiver);
        dist.totalBoostedSupply = dist
            .totalBoostedSupply
            .add(boostedSenderSupply)
            .add(boostedReceiverSupply)
            .sub(senderInfo.boostedSupply)
            .sub(receiverInfo.boostedSupply);
        senderInfo.boostedSupply = boostedSenderSupply;
        receiverInfo.boostedSupply = boostedReceiverSupply;
    }

    function claimQubit(address user) external override nonReentrant {
        require(msg.sender == user, "QDistributor: invalid user");
        uint _accruedQubit = 0;

        address[] memory markets = qore.allMarkets();
        for (uint i = 0; i < markets.length; i++) {
            address market = markets[i];
            _accruedQubit = _accruedQubit.add(_claimQubit(market, user));
        }

        _transferQubit(user, _accruedQubit);
    }

    function claimQubit(address market, address user) external nonReentrant {
        require(msg.sender == user, "QDistributor: invalid user");

        uint _accruedQubit = _claimQubit(market, user);
        _transferQubit(user, _accruedQubit);
    }

    function kick(address user) external override nonReentrant {
        require(qubitLocker.scoreOf(user) == 0, "QDistributor: kick not allowed");

        address[] memory markets = qore.allMarkets();
        for (uint i = 0; i < markets.length; i++) {
            address market = markets[i];
            _updateSupplyOf(market, user);
            _updateBorrowOf(market, user);
        }
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    function _claimQubit(address market, address user) private returns (uint _accruedQubit) {
        bool hasBoostedSupply = marketUsers[market][user].boostedSupply > 0;
        bool hasBoostedBorrow = marketUsers[market][user].boostedBorrow > 0;
        if (hasBoostedSupply) _updateSupplyOf(market, user);
        if (hasBoostedBorrow) _updateBorrowOf(market, user);

        UserInfo storage userInfo = marketUsers[market][user];
        _accruedQubit = _accruedQubit.add(userInfo.accruedQubit);
        userInfo.accruedQubit = 0;

        return _accruedQubit;
    }

    function _transferQubit(address user, uint amount) private {
        amount = Math.min(amount, IBEP20(QBT).balanceOf(address(this)));
        QBT.safeTransfer(user, amount);
        emit QubitClaimed(user, amount);
    }

    function _calculateBoostedSupply(address market, address user) private view returns (uint) {
        uint defaultSupply = IQToken(market).balanceOf(user);
        uint boostedSupply = defaultSupply.mul(BOOST_PORTION_MAX - BOOST_PORTION_Q).div(BOOST_PORTION_MAX);

        uint userScore = qubitLocker.scoreOf(user);
        (uint totalScore, ) = qubitLocker.totalScore();
        if (userScore > 0 && totalScore > 0) {
            uint scoreBoosted = IQToken(market).totalSupply().mul(userScore).div(totalScore).mul(BOOST_PORTION_Q).div(
                100
            );
            boostedSupply = boostedSupply.add(scoreBoosted);
        }
        return Math.min(boostedSupply, defaultSupply);
    }

    function _calculateBoostedBorrow(address market, address user) private view returns (uint) {
        uint accInterestIndex = IQToken(market).getAccInterestIndex();
        uint defaultBorrow = IQToken(market).borrowBalanceOf(user).mul(1e18).div(accInterestIndex);
        uint boostedBorrow = defaultBorrow.mul(BOOST_PORTION_MAX - BOOST_PORTION_Q).div(BOOST_PORTION_MAX);

        uint userScore = qubitLocker.scoreOf(user);
        (uint totalScore, ) = qubitLocker.totalScore();
        if (userScore > 0 && totalScore > 0) {
            uint totalBorrow = IQToken(market).totalBorrow().mul(1e18).div(accInterestIndex);
            uint scoreBoosted = totalBorrow.mul(userScore).div(totalScore).mul(BOOST_PORTION_Q).div(100);
            boostedBorrow = boostedBorrow.add(scoreBoosted);
        }
        return Math.min(boostedBorrow, defaultBorrow);
    }

    function _updateSupplyOf(address market, address user) private updateDistributionOf(market) {
        DistributionInfo storage dist = distributions[market];
        UserInfo storage userInfo = marketUsers[market][user];

        if (userInfo.boostedSupply > 0) {
            uint accQubitPerShare = dist.accPerShareSupply.sub(userInfo.accPerShareSupply);
            userInfo.accruedQubit = userInfo.accruedQubit.add(accQubitPerShare.mul(userInfo.boostedSupply).div(1e18));
        }
        userInfo.accPerShareSupply = dist.accPerShareSupply;

        uint boostedSupply = _calculateBoostedSupply(market, user);
        dist.totalBoostedSupply = dist.totalBoostedSupply.add(boostedSupply).sub(userInfo.boostedSupply);
        userInfo.boostedSupply = boostedSupply;
    }

    function _updateBorrowOf(address market, address user) private updateDistributionOf(market) {
        DistributionInfo storage dist = distributions[market];
        UserInfo storage userInfo = marketUsers[market][user];

        if (userInfo.boostedBorrow > 0) {
            uint accQubitPerShare = dist.accPerShareBorrow.sub(userInfo.accPerShareBorrow);
            userInfo.accruedQubit = userInfo.accruedQubit.add(accQubitPerShare.mul(userInfo.boostedBorrow).div(1e18));
        }
        userInfo.accPerShareBorrow = dist.accPerShareBorrow;

        uint boostedBorrow = _calculateBoostedBorrow(market, user);
        dist.totalBoostedBorrow = dist.totalBoostedBorrow.add(boostedBorrow).sub(userInfo.boostedBorrow);
        userInfo.boostedBorrow = boostedBorrow;
    }
}
