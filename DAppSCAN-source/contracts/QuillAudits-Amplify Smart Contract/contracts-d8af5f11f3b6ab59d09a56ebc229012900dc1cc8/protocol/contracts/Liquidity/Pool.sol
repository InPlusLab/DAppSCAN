// SPDX-License-Identifier: MIT
/// @dev size: 24.033 Kbytes
pragma solidity ^0.8.0;

import "./Lender.sol";
import "./Borrower.sol";
import "./PoolToken.sol";
import "../InterestRate/InterestRateModel.sol";

import "../security/Ownable.sol";

import "../Controller/ControllerInterface.sol";
import { IERC20Metadata } from "../ERC20/IERC20.sol";

contract Pool is Ownable, Lendable, Borrowable {
    bool public isInitialized;
    string public name;

    ControllerInterface public controller;
    IERC20Metadata public stableCoin;

    enum Access {
        Public,
        Private
    }
    uint8 public access;

    event AccessChanged(uint8 newAccess);

    function initialize(address _admin, address _stableCoin, string memory _name, uint256 _minDeposit, Access _access) external {
        _initialize(_admin, _stableCoin, _name, _minDeposit, _access);
    }

    function _initialize(address _admin, address _stableCoin, string memory _name, uint256 _minDeposit, Access _access) internal nonReentrant {
        require(!isInitialized, "already initialized");
        isInitialized = true;

        name = _name;
        minDeposit = _minDeposit;
        access = uint8(_access);

        // Set the admin address
        owner = _admin;

        // set the controller
        controller = ControllerInterface(msg.sender);

        // Set the stable coin contract
        stableCoin = IERC20Metadata(_stableCoin);

        lpToken = new PoolToken("PoolToken", stableCoin.symbol());
    }

    function changeAccess(Access _access) external onlyOwner {
        access = uint8(_access);
        emit AccessChanged(access);
    }

    /// lender override methods
    function lend(uint256 amount) external returns (uint256) {
        return lendInternal(msg.sender, msg.sender, amount);
    }
    /// @dev Controller based function for whitelisted lenders
    function _lend(uint256 amount, address lender) external returns (uint256) {
        require(msg.sender == address(controller), "wrong address");
        return lendInternal(msg.sender, lender, amount);
    }

    function redeem(uint256 tokens) external returns (uint256) {
        return redeemInternal(msg.sender, 0, tokens);
    }

    function redeemUnderlying(uint256 amount) external returns (uint256) {
        return redeemInternal(msg.sender, amount, 0);
    }

    function _transferTokens(address from, address to, uint256 amount) internal override returns (bool) {
        require(stableCoin.balanceOf(from) >= amount, toString(Error.INSUFFICIENT_FUNDS));
        if (from == address(this)) {
            require(stableCoin.transfer(to, amount), toString(Error.TRANSFER_FAILED));
        } else {
            require(stableCoin.transferFrom(from, to, amount), toString(Error.TRANSFER_FAILED));
        }
        return true;
    }

    function getCash() public override virtual view returns (uint256) {
        return stableCoin.balanceOf(address(this));
    }

    function lendAllowed(address _pool, address _lender, uint256 _amount) internal override returns (uint256) {
        return controller.lendAllowed(_pool, _lender, _amount);
    }

    function redeemAllowed(address _pool, address _redeemer, uint256 _tokenAmount) internal override returns (uint256) {
        return controller.redeemAllowed(_pool, _redeemer, _tokenAmount);
    }

    // borrower override methods
    struct CreditLineLocalVars {
        uint256 allowed;
        uint256 assetValue;
        uint256 borrowCap;
        uint256 interestRate;
        uint256 advanceRate;
        uint256 maturity;
    }
    function createCreditLine(uint256 tokenId) external nonReentrant returns (uint256) {
        CreditLineLocalVars memory vars;
        (
            vars.allowed, 
            vars.assetValue, 
            vars.maturity, 
            vars.interestRate, 
            vars.advanceRate
        ) = controller.createCreditLineAllowed(address(this), msg.sender, tokenId);
        if (vars.allowed != 0) {
            return uint256(Error.C_CREATE_REJECTION);
        }

        vars.borrowCap = vars.assetValue * vars.advanceRate / 100;
        return createCreditLineInternal(msg.sender, tokenId, vars.borrowCap, vars.interestRate, vars.maturity);
    }

    function closeCreditLine(uint256 loanId) external nonReentrant returns (uint256) {
        return closeCreditLineInternal(msg.sender, loanId);
    }

    function redeemAsset(uint256 tokenId) internal override returns (uint256) {
        controller.assetsFactory().markAsRedeemed(tokenId);
        return uint256(Error.NO_ERROR);
    }

    struct UnlockLocalVars {
        MathError mathErr;
        uint256 lockedAsset;
    }
    function unlockAsset(uint256 loanId) external nonReentrant returns (uint256) {
        UnlockLocalVars memory vars;

        (vars.mathErr, vars.lockedAsset) = unlockAssetInternal(msg.sender, loanId);
        ErrorReporter.check((uint256(vars.mathErr)));

        controller.assetsFactory().transferFrom(address(this), msg.sender, vars.lockedAsset);
        return uint256(Error.NO_ERROR);
    }

    function borrow(uint256 loanId, uint256 amount) external returns (uint256) {
        return borrowInternal(loanId, msg.sender, amount);
    }

    function repay(uint256 loanId, uint256 amount) external returns (uint256) {
        return repayInternal(loanId, msg.sender, msg.sender, amount);
    }

    function repayBehalf(address borrower, uint256 loanId, uint256 amount) external returns (uint256) {
        return repayInternal(loanId, msg.sender, borrower, amount);
    }

    function getTotalBorrowBalance() public virtual override(Lendable, Borrowable) view returns (uint256) {
        uint256 total;
        for (uint8 i = 0; i < creditLines.length; i++) {
            total += borrowBalanceSnapshot(i);
        }
        return total;
    }

    struct BorrowIndexLocalVars {
        MathError mathErr;
        uint256 blockNumber;
        uint256 accrualBlockNumber;
        uint256 priorBorrowIndex;
        uint256 newBorrowIndex;
        uint256 borrowRateMantissa;
        uint256 blockDelta;
        Exp interestFactor;
    }
    function getBorrowIndex(uint256 loanId) public override view returns (uint256) {
        CreditLine storage creditLine = creditLines[loanId];
        BorrowIndexLocalVars memory vars;

        vars.accrualBlockNumber = creditLine.accrualBlockNumber;
        vars.priorBorrowIndex = creditLine.borrowIndex;
        vars.blockNumber = getBlockNumber();

        /* Short-circuit accumulating 0 interest */
        if (vars.accrualBlockNumber == vars.blockNumber || vars.accrualBlockNumber == 0) {
            return vars.priorBorrowIndex;
        }

        vars.borrowRateMantissa = controller.interestRateModel().getBorrowRate(creditLine.interestRate);
        (vars.mathErr, vars.blockDelta) = subUInt(vars.blockNumber, vars.accrualBlockNumber);
        ErrorReporter.check((uint256(vars.mathErr)));

        (vars.mathErr, vars.interestFactor) = mulScalar(Exp({mantissa: vars.borrowRateMantissa}), vars.blockDelta);
        ErrorReporter.check((uint256(vars.mathErr)));

        (vars.mathErr, vars.newBorrowIndex) = mulScalarTruncateAddUInt(vars.interestFactor, vars.priorBorrowIndex, vars.priorBorrowIndex);
        ErrorReporter.check((uint256(vars.mathErr)));

        return vars.newBorrowIndex;
    }

    struct PenaltyIndexLocalVars {
        MathError mathErr;
        uint256 fee;
        uint256 principal;
        uint256 daysDelta;
        uint256 interestBlocksPerYear;
        uint256 penaltyIndex;
        uint256 penaltyAmount;
        uint256 accrualTimestamp;
        uint256 timestamp;
    }
    function getPenaltyIndexAndFee(uint256 loanId) public override view returns(uint256, uint256) {
        PenaltyInfo storage _penaltyInfo = penaltyInfo[loanId];

        if (creditLines[loanId].isClosed) {
            return (0, 0);
        }

        PenaltyIndexLocalVars memory vars;
        InterestRateModel.GracePeriod[] memory _gracePeriod;

        uint256 day = 24 * 60 * 60;
        vars.principal = creditLines[loanId].principal;
        vars.accrualTimestamp = _penaltyInfo.timestamp;
        vars.penaltyIndex = _penaltyInfo.index;
        vars.timestamp = getBlockTimestamp();

        (_gracePeriod, vars.interestBlocksPerYear) = controller.interestRateModel().getGracePeriodSnapshot();
        for(uint8 i=0; i < _gracePeriod.length; i++) {
            uint256 _start = _gracePeriod[i].start * day + _penaltyInfo.maturity;
            uint256 _end = _gracePeriod[i].end * day + _penaltyInfo.maturity;

            if (vars.timestamp >= _start) {
                if(vars.timestamp > _end) {
                    vars.daysDelta = _calculateDaysDelta(_end, vars.accrualTimestamp, _start, day);
                } else {
                    vars.daysDelta = _calculateDaysDelta(vars.timestamp, vars.accrualTimestamp, _start, day);
                }

                vars.penaltyIndex = calculatePenaltyIndexPerPeriod(_gracePeriod[i].fee, vars.interestBlocksPerYear, vars.daysDelta, vars.penaltyIndex);
                (vars.mathErr, vars.fee) = mulScalarTruncateAddUInt(Exp({mantissa: vars.penaltyIndex }), vars.principal, vars.fee);
                ErrorReporter.check((uint256(vars.mathErr)));
            }
        }

        if (vars.fee > 0) {
            (vars.mathErr, vars.penaltyAmount) = subUInt(vars.fee, vars.principal);
            ErrorReporter.check((uint256(vars.mathErr)));
        }
        return (vars.penaltyIndex, vars.penaltyAmount);
    }

    function _calculateDaysDelta(uint256 timestamp, uint256 acrrualTimestamp, uint256 _start, uint256 day) internal pure returns (uint256) {
        MathError mathErr;
        uint256 daysDelta;
        if (acrrualTimestamp > _start) {
            (mathErr, daysDelta) = subThenDivUInt(timestamp, acrrualTimestamp, day);
            ErrorReporter.check((uint256(mathErr)));
        } else {
            (mathErr, daysDelta) = subThenDivUInt(timestamp, _start, day);
            ErrorReporter.check((uint256(mathErr)));
        }
        return daysDelta;
    }

    function calculatePenaltyIndexPerPeriod(uint fee, uint256 blockPerYear, uint256 daysDelta, uint256 currentPenaltyIndex) internal pure returns (uint256) {
        Exp memory simpleInterestFactor;
        MathError mathErr;
        uint256 penaltyIndex;

        (mathErr, simpleInterestFactor) = mulScalar(Exp({mantissa: fee / blockPerYear }), daysDelta);
        ErrorReporter.check((uint256(mathErr)));

        (mathErr, penaltyIndex) = mulScalarTruncateAddUInt(simpleInterestFactor, currentPenaltyIndex, currentPenaltyIndex);
        ErrorReporter.check((uint256(mathErr)));

        return penaltyIndex;
    }

    struct TransferLocalVars {
        MathError mathError;
        uint256 feesMantissa;
        uint256 feesAmount;
        uint256 amountWithoutFees;
    }
    function _transferTokensOnBorrow(address from, address to, uint256 amount) internal override returns (bool) {
        require(stableCoin.balanceOf(from) >= amount, toString(Error.INSUFFICIENT_FUNDS));

        TransferLocalVars memory vars;

        vars.feesMantissa = controller.provisionPool().getFeesPercent();

        (vars.mathError, vars.feesAmount) = mulScalarTruncate(Exp({ mantissa: vars.feesMantissa }), amount);
        ErrorReporter.check(uint256(vars.mathError));

        (vars.mathError, vars.amountWithoutFees) = subUInt(amount, vars.feesAmount);
        ErrorReporter.check(uint256(vars.mathError));

        require(stableCoin.transfer(to, vars.amountWithoutFees), toString(Error.TRANSFER_FAILED));
        require(stableCoin.transfer(controller.provisionPool.address, vars.feesAmount), toString(Error.LPP_TRANSFER_FAILED));
        return true;
    }

    function _transferTokensOnRepay(address from, address to, uint256 amount, uint256 penaltyAmount) internal override returns (bool) {
        require(_transferTokens(from, to, amount), toString(Error.TRANSFER_FAILED));

        if (penaltyAmount > 0) {
            return _transferTokens(to, controller.provisionPool.address, penaltyAmount);
        }
        return true;
    }

    function borrowAllowed(address _pool, address _lender, uint256 _amount) internal override returns (uint256) {
        return controller.borrowAllowed(_pool, _lender, _amount);
    }

    function repayAllowed(address _pool, address _payer, address _borrower, uint256 _amount) internal override returns (uint256) {
        return controller.repayAllowed(_pool, _payer, _borrower, _amount);
    }

    function getBlockNumber() public virtual override view returns(uint256) {
        return block.number;
    }

    function getBlockTimestamp() public virtual override view returns(uint256) {
        // SWC-116-Block values as a proxy for time: L330
        return block.timestamp;
    }
}