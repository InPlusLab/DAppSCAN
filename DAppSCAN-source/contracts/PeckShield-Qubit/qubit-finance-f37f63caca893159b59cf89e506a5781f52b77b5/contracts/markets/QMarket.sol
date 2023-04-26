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
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/IBEP20.sol";

import "../interfaces/IQValidator.sol";
import "../interfaces/IRateModel.sol";
import "../interfaces/IQToken.sol";
import "../interfaces/IQore.sol";
import "../library/QConstant.sol";

abstract contract QMarket is IQToken, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeMath for uint;

    /* ========== CONSTANT VARIABLES ========== */

    uint internal constant RESERVE_FACTOR_MAX = 1e18;
    uint internal constant DUST = 1000;

    address internal constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address internal constant BUSD = 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56;

    /* ========== STATE VARIABLES ========== */

    IQore public qore;
    IRateModel public rateModel;
    address public override underlying;

    uint public override totalSupply;
    uint public totalReserve;
    uint private _totalBorrow;

    mapping(address => uint) internal accountBalances;
    mapping(address => QConstant.BorrowInfo) internal accountBorrows;

    uint public reserveFactor;
    uint private lastAccruedTime;
    uint private accInterestIndex;

    /* ========== Event ========== */

    event RateModelUpdated(address newRateModel);
    event ReserveFactorUpdated(uint newReserveFactor);

    /* ========== INITIALIZER ========== */

    receive() external payable {}

    function __QMarket_init() internal initializer {
        __Ownable_init();
        __ReentrancyGuard_init();

        lastAccruedTime = block.timestamp;
        accInterestIndex = 1e18;
    }

    /* ========== MODIFIERS ========== */

    modifier accrue() {
        if (block.timestamp > lastAccruedTime && address(rateModel) != address(0)) {
            uint borrowRate = rateModel.getBorrowRate(getCashPrior(), _totalBorrow, totalReserve);
            uint interestFactor = borrowRate.mul(block.timestamp.sub(lastAccruedTime));
            uint pendingInterest = _totalBorrow.mul(interestFactor).div(1e18);

            _totalBorrow = _totalBorrow.add(pendingInterest);
            totalReserve = totalReserve.add(pendingInterest.mul(reserveFactor).div(1e18));
            accInterestIndex = accInterestIndex.add(interestFactor.mul(accInterestIndex).div(1e18));
            lastAccruedTime = block.timestamp;
        }
        _;
    }

    modifier onlyQore() {
        require(msg.sender == address(qore), "QToken: only Qore Contract");
        _;
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function setQore(address _qore) public onlyOwner {
        require(_qore != address(0), "QMarket: invalid qore address");
        require(address(qore) == address(0), "QMarket: qore already set");
        qore = IQore(_qore);
    }

    function setUnderlying(address _underlying) public onlyOwner {
        require(_underlying != address(0), "QMarket: invalid underlying address");
        require(underlying == address(0), "QMarket: set underlying already");
        underlying = _underlying;
    }

    function setRateModel(address _rateModel) public accrue onlyOwner {
        require(_rateModel != address(0), "QMarket: invalid rate model address");
        rateModel = IRateModel(_rateModel);
        emit RateModelUpdated(_rateModel);
    }

    function setReserveFactor(uint _reserveFactor) public accrue onlyOwner {
        require(_reserveFactor <= RESERVE_FACTOR_MAX, "QMarket: invalid reserve factor");
        reserveFactor = _reserveFactor;
        emit ReserveFactorUpdated(_reserveFactor);
    }

    /* ========== VIEWS ========== */

    function balanceOf(address account) external view override returns (uint) {
        return accountBalances[account];
    }

    function accountSnapshot(address account) external view override returns (QConstant.AccountSnapshot memory) {
        QConstant.AccountSnapshot memory snapshot;
        snapshot.qTokenBalance = accountBalances[account];
        snapshot.borrowBalance = borrowBalanceOf(account);
        snapshot.exchangeRate = exchangeRate();
        return snapshot;
    }

    function underlyingBalanceOf(address account) external view override returns (uint) {
        return accountBalances[account].mul(exchangeRate()).div(1e18);
    }

    function borrowBalanceOf(address account) public view override returns (uint) {
        QConstant.AccrueSnapshot memory snapshot = pendingAccrueSnapshot();
        QConstant.BorrowInfo storage info = accountBorrows[account];

        if (info.borrow == 0) return 0;
        return info.borrow.mul(snapshot.accInterestIndex).div(info.interestIndex);
    }

    function borrowRatePerSec() external view override returns (uint) {
        QConstant.AccrueSnapshot memory snapshot = pendingAccrueSnapshot();
        return rateModel.getBorrowRate(getCashPrior(), snapshot.totalBorrow, snapshot.totalReserve);
    }

    function supplyRatePerSec() external view override returns (uint) {
        QConstant.AccrueSnapshot memory snapshot = pendingAccrueSnapshot();
        return rateModel.getSupplyRate(getCashPrior(), snapshot.totalBorrow, snapshot.totalReserve, reserveFactor);
    }

    function totalBorrow() public view override returns (uint) {
        QConstant.AccrueSnapshot memory snapshot = pendingAccrueSnapshot();
        return snapshot.totalBorrow;
    }

    function exchangeRate() public view override returns (uint) {
        if (totalSupply == 0) return 1e18;
        QConstant.AccrueSnapshot memory snapshot = pendingAccrueSnapshot();
        return getCashPrior().add(snapshot.totalBorrow).sub(snapshot.totalReserve).mul(1e18).div(totalSupply);
    }

    function getCash() public view override returns (uint) {
        return getCashPrior();
    }

    function getAccInterestIndex() public view override returns (uint) {
        QConstant.AccrueSnapshot memory snapshot = pendingAccrueSnapshot();
        return snapshot.accInterestIndex;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function accruedAccountSnapshot(address account)
        external
        override
        accrue
        returns (QConstant.AccountSnapshot memory)
    {
        QConstant.AccountSnapshot memory snapshot;
        QConstant.BorrowInfo storage info = accountBorrows[account];
        if (info.interestIndex != 0) {
            info.borrow = info.borrow.mul(accInterestIndex).div(info.interestIndex);
            info.interestIndex = accInterestIndex;
        }

        snapshot.qTokenBalance = accountBalances[account];
        snapshot.borrowBalance = info.borrow;
        snapshot.exchangeRate = exchangeRate();
        return snapshot;
    }

    function accruedUnderlyingBalanceOf(address account) external override accrue returns (uint) {
        return accountBalances[account].mul(exchangeRate()).div(1e18);
    }

    function accruedBorrowBalanceOf(address account) external override accrue returns (uint) {
        QConstant.BorrowInfo storage info = accountBorrows[account];
        if (info.interestIndex != 0) {
            info.borrow = info.borrow.mul(accInterestIndex).div(info.interestIndex);
            info.interestIndex = accInterestIndex;
        }
        return info.borrow;
    }

    function accruedTotalBorrow() external override accrue returns (uint) {
        return _totalBorrow;
    }

    function accruedExchangeRate() external override accrue returns (uint) {
        return exchangeRate();
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    function updateBorrowInfo(
        address account,
        uint addAmount,
        uint subAmount
    ) internal {
        QConstant.BorrowInfo storage info = accountBorrows[account];
        if (info.interestIndex == 0) {
            info.interestIndex = accInterestIndex;
        }

        info.borrow = info.borrow.mul(accInterestIndex).div(info.interestIndex).add(addAmount).sub(subAmount);
        info.interestIndex = accInterestIndex;
        _totalBorrow = _totalBorrow.add(addAmount).sub(subAmount);

        info.borrow = (info.borrow < DUST) ? 0 : info.borrow;
        _totalBorrow = (_totalBorrow < DUST) ? 0 : _totalBorrow;
    }

    function updateSupplyInfo(
        address account,
        uint addAmount,
        uint subAmount
    ) internal {
        accountBalances[account] = accountBalances[account].add(addAmount).sub(subAmount);
        totalSupply = totalSupply.add(addAmount).sub(subAmount);

        totalSupply = (totalSupply < DUST) ? 0 : totalSupply;
    }

    function getCashPrior() internal view returns (uint) {
        return
            underlying == address(WBNB)
                ? address(this).balance.sub(msg.value)
                : IBEP20(underlying).balanceOf(address(this));
    }

    function pendingAccrueSnapshot() internal view returns (QConstant.AccrueSnapshot memory) {
        QConstant.AccrueSnapshot memory snapshot;
        snapshot.totalBorrow = _totalBorrow;
        snapshot.totalReserve = totalReserve;
        snapshot.accInterestIndex = accInterestIndex;

        if (block.timestamp > lastAccruedTime && _totalBorrow > 0) {
            uint borrowRate = rateModel.getBorrowRate(getCashPrior(), _totalBorrow, totalReserve);
            uint interestFactor = borrowRate.mul(block.timestamp.sub(lastAccruedTime));
            uint pendingInterest = _totalBorrow.mul(interestFactor).div(1e18);

            snapshot.totalBorrow = _totalBorrow.add(pendingInterest);
            snapshot.totalReserve = totalReserve.add(pendingInterest.mul(reserveFactor).div(1e18));
            snapshot.accInterestIndex = accInterestIndex.add(interestFactor.mul(accInterestIndex).div(1e18));
        }
        return snapshot;
    }
}
