// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../security/ReentrancyGuard.sol";
import "../utils/NonZeroAddressGuard.sol";
import { ErrorReporter, TokenErrorReporter } from "../utils/ErrorReporter.sol";

import "../utils/Exponential.sol";
import "../utils/Counters.sol";

abstract contract Borrowable is ReentrancyGuard, NonZeroAddressGuard, Exponential, TokenErrorReporter {
    using Counters for Counters.Counter;

    Counters.Counter private _loanIds;

    struct CreditLine {
        address borrower;
        uint256 borrowCap;
        uint256 borrowIndex;
        uint256 principal;
        uint256 lockedAsset;
        uint256 interestRate;
        uint256 accrualBlockNumber;
        bool isClosed;
    }

    struct PenaltyInfo {
        uint256 maturity;
        uint256 index;
        uint256 timestamp;
        bool isOpened;
    }

    CreditLine[] public creditLines;
    mapping(uint256 => PenaltyInfo) public penaltyInfo;

    mapping(uint256 => bool) public lockedAssetsIds;
    mapping(address => uint256[]) internal loansIdsByAddress;

    event CreditLineOpened(uint256 indexed loanId, uint256 indexed tokenId, address borrower, uint256 amount, uint256 maturity, uint256 interestRate);
    event CreditLineClosed(uint256 indexed loanId);
    event Borrowed(uint256 indexed loanId, uint256 _amount);
    event Repayed(uint256 indexed loanId, uint256 _amount, uint256 penaltyAmount);
    event AssetUnlocked(uint256 indexed tokenId);

    modifier onlyIfActive(uint256 _loanId, address borrower_) {
        _isActive(_loanId, borrower_);
        _;
    }

    function _isActive(uint256 _loanId, address borrower_) internal view {
        require(creditLines[_loanId].isClosed == false, toString(Error.LOAN_IS_ALREADY_CLOSED));
        require(creditLines[_loanId].borrower == borrower_, toString(Error.WRONG_BORROWER));
    }

    function totalPrincipal() public virtual view returns (uint256) {
        uint256 total = 0;
        for (uint8 i = 0; i < creditLines.length; i++) {
            total += creditLines[i].principal;
        }
        return total;
    }

    function totalInterestRate() public virtual view returns (uint256) {
        uint256 total = 0;
        for (uint8 i = 0; i < creditLines.length; i++) {
            total += creditLines[i].interestRate;
        }
        if (total != 0){
            return total / creditLines.length;
        }
        return total;
    }

    /** @dev used by rewards contract */
    function getBorrowerTotalPrincipal(address _borrower) external view returns (uint256) {
        uint256 balance;

        for(uint8 i=0; i < loansIdsByAddress[_borrower].length; i++) {
            uint256 loanId = loansIdsByAddress[_borrower][i];

            uint256 principal = creditLines[loanId].principal;
            bool penaltyStarted = penaltyInfo[loanId].isOpened;
            balance += penaltyStarted ? 0 : principal;
        }
        return balance;
    }

    function getBorrowerBalance(address _borrower) external view returns (uint256) {
        uint256 balance;

        for(uint8 i=0; i < loansIdsByAddress[_borrower].length; i++) {
            balance += borrowBalanceSnapshot(loansIdsByAddress[_borrower][i]);
        }
        return balance;
    }

    function borrowerSnapshot(uint256 loanId) external view returns (uint256, uint256) {
        (,uint256 penaltyAmount) = getPenaltyIndexAndFee(loanId);
        return (borrowBalanceSnapshot(loanId), penaltyAmount);
    }

    function getBorrowerLoans(address _borrower) external view returns(uint256[] memory) {
        return loansIdsByAddress[_borrower];
    }

    function createCreditLineInternal(address borrower, uint256 tokenId, uint256 borrowCap, uint256 interestRate, uint256 maturity) internal returns (uint256) {
        require(lockedAssetsIds[tokenId] == false, toString(Error.LOAN_ASSET_ALREADY_USED));
        uint256 loanId = _loanIds.current();
        _loanIds;

        lockedAssetsIds[tokenId] = true;
        loansIdsByAddress[borrower].push(loanId);

        creditLines.push(CreditLine({
            borrower: borrower,
            borrowCap: borrowCap,
            borrowIndex: mantissaOne,
            principal: 0,
            lockedAsset: tokenId,
            interestRate: interestRate,
            accrualBlockNumber: getBlockNumber(),
            isClosed: false
        }));

        penaltyInfo[loanId] = PenaltyInfo({
            maturity: maturity,
            index: mantissaOne,
            timestamp: maturity + 30 days,
            isOpened: false
        });

        emit CreditLineOpened(loanId, tokenId, borrower, borrowCap, maturity, interestRate);

        _loanIds.increment();
        return uint256(Error.NO_ERROR);
    }

    function closeCreditLineInternal(address borrower, uint256 loanId) internal onlyIfActive(loanId, borrower) returns (uint256) {
        CreditLine storage creditLine = creditLines[loanId];
        require(creditLine.principal == 0, "Debt should be 0");

        lockedAssetsIds[creditLine.lockedAsset] = false;
        creditLine.isClosed = true;
        delete penaltyInfo[loanId];

        emit CreditLineClosed(loanId);
        return redeemAsset(creditLine.lockedAsset);
    }

    function unlockAssetInternal(address borrower, uint256 loanId) internal returns (MathError, uint256) {
        CreditLine storage creditLine = creditLines[loanId];

        require(creditLine.borrower == borrower, toString(Error.WRONG_BORROWER));
        require(creditLine.isClosed == true, toString(Error.LOAN_IS_NOT_CLOSED));

        uint256 lockedAsset = creditLine.lockedAsset;
        // remove loan from the list
        delete creditLines[loanId];
        delete penaltyInfo[loanId];

        emit AssetUnlocked(lockedAsset);
        return (MathError.NO_ERROR, lockedAsset);
    }

    struct BorrowLocalVars {
        MathError mathErr;
        uint256 availableAmount;
        uint256 currentBorrowBalance;
        uint256 newBorrowIndex;
        uint256 newPrincipal;
        uint256 currentTimestamp;
    }
    function borrowInternal(uint256 loanId, address borrower, uint256 amount) internal nonReentrant onlyIfActive(loanId, borrower) returns (uint256) {
        uint256 allowed = borrowAllowed(address(this), borrower, amount);
        require(allowed == 0, ErrorReporter.uint2str(allowed));
        
        CreditLine storage creditLine = creditLines[loanId];
        BorrowLocalVars memory vars;

        vars.currentTimestamp = getBlockTimestamp();
        require(vars.currentTimestamp < penaltyInfo[loanId].maturity, toString(Error.LOAN_IS_OVERDUE));

        (vars.mathErr, vars.availableAmount) = subUInt(creditLine.borrowCap, creditLine.principal);
        ErrorReporter.check(uint256(vars.mathErr));
        require(vars.availableAmount >= amount, toString(Error.INSUFFICIENT_FUNDS));

        vars.currentBorrowBalance = borrowBalanceSnapshot(loanId);
        vars.newBorrowIndex = getBorrowIndex(loanId);

        (vars.mathErr, vars.newPrincipal) = addUInt(vars.currentBorrowBalance, amount);
        require(vars.mathErr == MathError.NO_ERROR, "borrow: principal failed");

        creditLine.principal = vars.newPrincipal;
        creditLine.borrowIndex = vars.newBorrowIndex;
        creditLine.accrualBlockNumber = getBlockNumber();

        assert(_transferTokensOnBorrow(address(this), borrower, amount));
        emit Borrowed(loanId, amount);

        return uint256(Error.NO_ERROR);
    }

    struct RepayLocalVars {
        MathError mathErr;
        uint256 currentBorrowBalance;
        uint256 actualRepayAmount;
        uint256 penaltyIndex;
        uint256 penaltyAmount;
    }
    function repayInternal(uint256 loanId, address payer, address borrower, uint256 amount) internal onlyIfActive(loanId, borrower) nonReentrant returns (uint256) {
        uint256 allowed = repayAllowed(address(this), payer, borrower, amount);
        require(allowed == 0, toString(Error.C_REPAY_REJECTION));

        CreditLine storage creditLine = creditLines[loanId];
        PenaltyInfo storage _penaltyInfo = penaltyInfo[loanId];
        RepayLocalVars memory vars;

        vars.currentBorrowBalance = borrowBalanceSnapshot(loanId);
        (vars.penaltyIndex, vars.penaltyAmount) = getPenaltyIndexAndFee(loanId);

        if (vars.penaltyIndex - 1e18 > 1) {
            if (!_penaltyInfo.isOpened) {
                _penaltyInfo.isOpened = true;
            }
            _penaltyInfo.timestamp = getBlockTimestamp();
            (vars.mathErr, vars.actualRepayAmount) = addUInt(vars.currentBorrowBalance, vars.penaltyAmount);
            require(vars.mathErr == MathError.NO_ERROR, "repay: penalty amount failed");
        } else {
            vars.actualRepayAmount = vars.currentBorrowBalance;
        }

        if (amount == type(uint256).max) {
            amount = vars.actualRepayAmount;
        }
        require(vars.actualRepayAmount >= amount, toString(Error.AMOUNT_HIGHER));

        (vars.mathErr, creditLine.principal) = subUInt(vars.actualRepayAmount, amount);
        require(vars.mathErr == MathError.NO_ERROR, "repay: principal failed");
        
        creditLine.borrowIndex = getBorrowIndex(loanId);
        creditLine.accrualBlockNumber = getBlockNumber();
        _penaltyInfo.index = vars.penaltyIndex;

        assert(_transferTokensOnRepay(payer, address(this), amount, vars.penaltyAmount));
        
        emit Repayed(loanId, amount, vars.penaltyAmount);
        if (creditLine.principal == 0) {
            require(closeCreditLineInternal(borrower, loanId) == 0, "close failed");
        }

        return uint256(Error.NO_ERROR);
    }
    
    struct BorrowBalanceLocalVars {
        MathError mathErr;
        uint256 principalTimesIndex;
        uint256 borrowBalance;
        uint256 borrowIndex;
    }
    function borrowBalanceSnapshot(uint256 loanId) internal view returns (uint256) {
        CreditLine storage creditLine = creditLines[loanId];
        if(creditLine.principal == 0) {
            return 0;
        }

        BorrowBalanceLocalVars memory vars;

        vars.borrowIndex = getBorrowIndex(loanId);
        (vars.mathErr, vars.principalTimesIndex) = mulUInt(creditLine.principal, vars.borrowIndex);
        require(vars.mathErr == MathError.NO_ERROR, "principal times failed");

        (vars.mathErr, vars.borrowBalance) = divUInt(vars.principalTimesIndex, creditLine.borrowIndex);
        require(vars.mathErr == MathError.NO_ERROR, "borrowBalance failed");

        return vars.borrowBalance;
    }

    function _transferTokensOnBorrow(address from, address to, uint256 amount) internal virtual returns (bool);
    function _transferTokensOnRepay(address from, address to, uint256 amount, uint256 penaltyAmount) internal virtual returns (bool);

    function borrowAllowed(address _pool, address _borrower, uint256 _amount) internal virtual returns (uint256);
    function repayAllowed(address _pool, address _payer, address _borrower, uint256 _amount) internal virtual returns (uint256);
    function redeemAsset(uint256 tokenId) internal virtual returns (uint256);

    function getBorrowIndex(uint256 loanId) public virtual view returns (uint256);
    function getTotalBorrowBalance() public virtual view returns (uint256);
    function getPenaltyIndexAndFee(uint256 loanId) public virtual view returns (uint256, uint256);
    function getBlockNumber() public virtual returns(uint256);
    function getBlockTimestamp() public virtual returns(uint256);
}