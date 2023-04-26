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

import "../interfaces/IQDistributor.sol";
import "../library/SafeToken.sol";
import "./QMarket.sol";

contract QToken is QMarket {
    using SafeMath for uint;
    using SafeToken for address;

    /* ========== CONSTANT ========== */

    IQDistributor public constant qDistributor = IQDistributor(0x67B806ab830801348ce719E0705cC2f2718117a1);

    /* ========== STATE VARIABLES ========== */

    string public name;
    string public symbol;
    uint8 public decimals;

    mapping(address => mapping(address => uint)) private _transferAllowances;

    /* ========== EVENT ========== */

    event Mint(address minter, uint mintAmount);
    event Redeem(address account, uint underlyingAmount, uint qTokenAmount);

    event Borrow(address account, uint ammount, uint accountBorrow);
    event RepayBorrow(address payer, address borrower, uint amount, uint accountBorrow);
    event LiquidateBorrow(
        address liquidator,
        address borrower,
        uint amount,
        address qTokenCollateral,
        uint seizeAmount
    );

    event Transfer(address indexed from, address indexed to, uint amount);
    event Approval(address indexed owner, address indexed spender, uint amount);

    /* ========== INITIALIZER ========== */

    function initialize(
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) external initializer {
        __QMarket_init();

        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    /* ========== VIEWS ========== */

    function allowance(address account, address spender) external view override returns (uint) {
        return _transferAllowances[account][spender];
    }

    function getOwner() external view returns (address) {
        return owner();
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function transfer(address dst, uint amount) external override accrue nonReentrant returns (bool) {
        _transferTokens(msg.sender, msg.sender, dst, amount);
        return true;
    }

    function transferFrom(
        address src,
        address dst,
        uint amount
    ) external override accrue nonReentrant returns (bool) {
        _transferTokens(msg.sender, src, dst, amount);
        return true;
    }

    function approve(address spender, uint amount) external override returns (bool) {
        _transferAllowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function supply(address account, uint uAmount) external payable override accrue onlyQore returns (uint) {
        uint exchangeRate = exchangeRate();
        uAmount = underlying == address(WBNB) ? msg.value : uAmount;
        uAmount = _doTransferIn(account, uAmount);
        uint qAmount = uAmount.mul(1e18).div(exchangeRate);

        totalSupply = totalSupply.add(qAmount);
        accountBalances[account] = accountBalances[account].add(qAmount);

        emit Mint(account, qAmount);
        emit Transfer(address(0), account, qAmount);
        return qAmount;
    }

    function redeemToken(address redeemer, uint qAmount) external override accrue onlyQore returns (uint) {
        return _redeem(redeemer, qAmount, 0);
    }

    function redeemUnderlying(address redeemer, uint uAmount) external override accrue onlyQore returns (uint) {
        return _redeem(redeemer, 0, uAmount);
    }

    function borrow(address account, uint amount) external override accrue onlyQore returns (uint) {
        require(getCash() >= amount, "QToken: borrow amount exceeds cash");
        updateBorrowInfo(account, amount, 0);
        _doTransferOut(account, amount);

        emit Borrow(account, amount, borrowBalanceOf(account));
        return amount;
    }

    function repayBorrow(address account, uint amount) external payable override accrue onlyQore returns (uint) {
        if (amount == uint(-1)) {
            amount = borrowBalanceOf(account);
        }
        return _repay(account, account, underlying == address(WBNB) ? msg.value : amount);
    }

    function repayBorrowBehalf(
        address payer,
        address borrower,
        uint amount
    ) external payable override accrue onlyQore returns (uint) {
        return _repay(payer, borrower, underlying == address(WBNB) ? msg.value : amount);
    }

    function liquidateBorrow(
        address qTokenCollateral,
        address liquidator,
        address borrower,
        uint amount
    ) external payable override accrue onlyQore returns (uint qAmountToSeize) {
        require(borrower != liquidator, "QToken: cannot liquidate yourself");

        amount = underlying == address(WBNB) ? msg.value : amount;
        amount = _repay(liquidator, borrower, amount);
        require(amount > 0 && amount < uint(-1), "QToken: invalid repay amount");

        qAmountToSeize = IQValidator(qore.qValidator()).qTokenAmountToSeize(address(this), qTokenCollateral, amount);
        require(
            IQToken(payable(qTokenCollateral)).balanceOf(borrower) >= qAmountToSeize,
            "QToken: too much seize amount"
        );
        emit LiquidateBorrow(liquidator, borrower, amount, qTokenCollateral, qAmountToSeize);
    }

    function seize(
        address liquidator,
        address borrower,
        uint qAmount
    ) external override accrue onlyQore {
        accountBalances[borrower] = accountBalances[borrower].sub(qAmount);
        accountBalances[liquidator] = accountBalances[liquidator].add(qAmount);
        qDistributor.notifyTransferred(address(this), borrower, liquidator);
        emit Transfer(borrower, liquidator, qAmount);
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    function _transferTokens(
        address spender,
        address src,
        address dst,
        uint amount
    ) private {
        require(
            src != dst && IQValidator(qore.qValidator()).redeemAllowed(address(this), src, amount),
            "QToken: cannot transfer"
        );
        require(amount != 0, "QToken: zero amount");

        uint _allowance = spender == src ? uint(-1) : _transferAllowances[src][spender];
        uint _allowanceNew = _allowance.sub(amount, "QToken: transfer amount exceeds allowance");

        accountBalances[src] = accountBalances[src].sub(amount);
        accountBalances[dst] = accountBalances[dst].add(amount);

        qDistributor.notifyTransferred(address(this), src, dst);

        if (_allowance != uint(-1)) {
            _transferAllowances[src][msg.sender] = _allowanceNew;
        }
        emit Transfer(src, dst, amount);
    }

    function _doTransferIn(address from, uint amount) private returns (uint) {
        if (underlying == address(WBNB)) {
            require(msg.value >= amount, "QToken: value mismatch");
            return Math.min(msg.value, amount);
        } else {
            uint balanceBefore = IBEP20(underlying).balanceOf(address(this));
            underlying.safeTransferFrom(from, address(this), amount);
            return IBEP20(underlying).balanceOf(address(this)).sub(balanceBefore);
        }
    }

    function _doTransferOut(address to, uint amount) private {
        if (underlying == address(WBNB)) {
            SafeToken.safeTransferETH(to, amount);
        } else {
            underlying.safeTransfer(to, amount);
        }
    }

    function _redeem(
        address account,
        uint qAmountIn,
        uint uAmountIn
    ) private returns (uint) {
        require(qAmountIn == 0 || uAmountIn == 0, "QToken: one of qAmountIn or uAmountIn must be zero");
        require(totalSupply >= qAmountIn, "QToken: not enough total supply");
        require(getCash() >= uAmountIn || uAmountIn == 0, "QToken: not enough underlying");
        require(
            getCash() >= qAmountIn.mul(exchangeRate()).div(1e18) || qAmountIn == 0,
            "QToken: not enough underlying"
        );

        uint qAmountToRedeem = qAmountIn > 0 ? qAmountIn : uAmountIn.mul(1e18).div(exchangeRate());
        uint uAmountToRedeem = qAmountIn > 0 ? qAmountIn.mul(exchangeRate()).div(1e18) : uAmountIn;

        require(
            IQValidator(qore.qValidator()).redeemAllowed(address(this), account, qAmountToRedeem),
            "QToken: cannot redeem"
        );

        totalSupply = totalSupply.sub(qAmountToRedeem);
        accountBalances[account] = accountBalances[account].sub(qAmountToRedeem);
        _doTransferOut(account, uAmountToRedeem);

        emit Transfer(account, address(0), qAmountToRedeem);
        emit Redeem(account, uAmountToRedeem, qAmountToRedeem);
        return uAmountToRedeem;
    }

    function _repay(
        address payer,
        address borrower,
        uint amount
    ) private returns (uint) {
        uint borrowBalance = borrowBalanceOf(borrower);
        uint repayAmount = Math.min(borrowBalance, amount);
        repayAmount = _doTransferIn(payer, repayAmount);
        updateBorrowInfo(borrower, 0, repayAmount);

        if (underlying == address(WBNB)) {
            uint refundAmount = amount > repayAmount ? amount.sub(repayAmount) : 0;
            if (refundAmount > 0) {
                _doTransferOut(payer, refundAmount);
            }
        }

        emit RepayBorrow(payer, borrower, repayAmount, borrowBalanceOf(borrower));
        return repayAmount;
    }
}
