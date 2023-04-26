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
import "./interfaces/IQToken.sol";
import "./interfaces/IQValidator.sol";

import "./QoreAdmin.sol";

contract Qore is QoreAdmin {
    using SafeMath for uint;

    /* ========== CONSTANT VARIABLES ========== */

    address internal constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;

    /* ========== STATE VARIABLES ========== */

    mapping(address => address[]) public marketListOfUsers; // (account => qTokenAddress[])
    mapping(address => mapping(address => bool)) public usersOfMarket; // (qTokenAddress => (account => joined))
    address[] public totalUserList;

    /* ========== INITIALIZER ========== */

    function initialize() external initializer {
        __Qore_init();
    }

    /* ========== MODIFIERS ========== */

    modifier onlyMemberOfMarket(address qToken) {
        require(usersOfMarket[qToken][msg.sender], "Qore: must enter market");
        _;
    }

    /* ========== VIEWS ========== */

    function allMarkets() external view override returns (address[] memory) {
        return markets;
    }

    function marketInfoOf(address qToken) external view override returns (QConstant.MarketInfo memory) {
        return marketInfos[qToken];
    }

    function marketListOf(address account) external view override returns (address[] memory) {
        return marketListOfUsers[account];
    }

    function checkMembership(address account, address qToken) external view override returns (bool) {
        return usersOfMarket[qToken][account];
    }

    function getTotalUserList() external view override returns (address[] memory) {
        return totalUserList;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function enterMarkets(address[] memory qTokens) public override {
        for (uint i = 0; i < qTokens.length; i++) {
            _enterMarket(payable(qTokens[i]), msg.sender);
        }
    }

    function exitMarket(address qToken) external override onlyListedMarket(qToken) onlyMemberOfMarket(qToken) {
        QConstant.AccountSnapshot memory snapshot = IQToken(qToken).accruedAccountSnapshot(msg.sender);
        require(snapshot.borrowBalance == 0, "Qore: borrow balance must be zero");
        require(
            IQValidator(qValidator).redeemAllowed(qToken, msg.sender, snapshot.qTokenBalance),
            "Qore: cannot redeem"
        );

        delete usersOfMarket[qToken][msg.sender];
        _removeUserMarket(qToken, msg.sender);
        emit MarketExited(qToken, msg.sender);
    }

    function supply(address qToken, uint uAmount)
        external
        payable
        override
        onlyListedMarket(qToken)
        nonReentrant
        returns (uint)
    {
        uAmount = IQToken(qToken).underlying() == address(WBNB) ? msg.value : uAmount;

        uint qAmount = IQToken(qToken).supply{ value: msg.value }(msg.sender, uAmount);
        qDistributor.notifySupplyUpdated(qToken, msg.sender);

        return qAmount;
    }

    function redeemToken(address qToken, uint qAmount)
        external
        override
        onlyListedMarket(qToken)
        nonReentrant
        returns (uint)
    {
        uint uAmountRedeem = IQToken(qToken).redeemToken(msg.sender, qAmount);
        qDistributor.notifySupplyUpdated(qToken, msg.sender);

        return uAmountRedeem;
    }

    function redeemUnderlying(address qToken, uint uAmount)
        external
        override
        onlyListedMarket(qToken)
        nonReentrant
        returns (uint)
    {
        uint uAmountRedeem = IQToken(qToken).redeemUnderlying(msg.sender, uAmount);
        qDistributor.notifySupplyUpdated(qToken, msg.sender);

        return uAmountRedeem;
    }

    function borrow(address qToken, uint amount) external override onlyListedMarket(qToken) nonReentrant {
        _enterMarket(qToken, msg.sender);
        require(IQValidator(qValidator).borrowAllowed(qToken, msg.sender, amount), "Qore: cannot borrow");

        IQToken(payable(qToken)).borrow(msg.sender, amount);
        qDistributor.notifyBorrowUpdated(qToken, msg.sender);
    }

    function repayBorrow(address qToken, uint amount) external payable override onlyListedMarket(qToken) nonReentrant {
        IQToken(payable(qToken)).repayBorrow{ value: msg.value }(msg.sender, amount);
        qDistributor.notifyBorrowUpdated(qToken, msg.sender);
    }

    function repayBorrowBehalf(
        address qToken,
        address borrower,
        uint amount
    ) external payable override onlyListedMarket(qToken) nonReentrant {
        IQToken(payable(qToken)).repayBorrowBehalf{ value: msg.value }(msg.sender, borrower, amount);
        qDistributor.notifyBorrowUpdated(qToken, borrower);
    }

    function liquidateBorrow(
        address qTokenBorrowed,
        address qTokenCollateral,
        address borrower,
        uint amount
    ) external payable override nonReentrant {
        amount = IQToken(qTokenBorrowed).underlying() == address(WBNB) ? msg.value : amount;
        require(marketInfos[qTokenBorrowed].isListed && marketInfos[qTokenCollateral].isListed, "Qore: invalid market");
        require(
            IQValidator(qValidator).liquidateAllowed(qTokenBorrowed, borrower, amount, closeFactor),
            "Qore: cannot liquidate borrow"
        );

        uint qAmountToSeize = IQToken(qTokenBorrowed).liquidateBorrow{ value: msg.value }(
            qTokenCollateral,
            msg.sender,
            borrower,
            amount
        );
        IQToken(qTokenCollateral).seize(msg.sender, borrower, qAmountToSeize);
        qDistributor.notifyBorrowUpdated(qTokenBorrowed, borrower);
    }

    function removeUserFromList(address _account) external onlyKeeper {
        require(marketListOfUsers[_account].length == 0, "Qore: cannot remove user");

        uint length = totalUserList.length;
        for (uint i = 0; i < length; i++) {
            if (totalUserList[i] == _account) {
                totalUserList[i] = totalUserList[length - 1];
                totalUserList.pop();
                break;
            }
        }
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    function _enterMarket(address qToken, address _account) internal onlyListedMarket(qToken) {
        if (!usersOfMarket[qToken][_account]) {
            usersOfMarket[qToken][_account] = true;
            if (marketListOfUsers[_account].length == 0) {
                totalUserList.push(_account);
            }
            marketListOfUsers[_account].push(qToken);
            emit MarketEntered(qToken, _account);
        }
    }

    function _removeUserMarket(address qTokenToExit, address _account) private {
        require(marketListOfUsers[_account].length > 0, "Qore: cannot pop user market");

        uint length = marketListOfUsers[_account].length;
        for (uint i = 0; i < length; i++) {
            if (marketListOfUsers[_account][i] == qTokenToExit) {
                marketListOfUsers[_account][i] = marketListOfUsers[_account][length - 1];
                marketListOfUsers[_account].pop();
                break;
            }
        }
    }
}
