// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./PoolToken.sol";

import "../security/ReentrancyGuard.sol";
import "../utils/NonZeroAddressGuard.sol";
import { ErrorReporter, TokenErrorReporter } from "../utils/ErrorReporter.sol";
import "../utils/Exponential.sol";

abstract contract Lendable is ReentrancyGuard, NonZeroAddressGuard, Exponential, TokenErrorReporter {
    uint256 internal constant initialExchangeRate = 2e16;
    uint256 public minDeposit;

    PoolToken public lpToken;

    event Lend(address indexed account, uint256 amount, uint256 tokensAmount);
    event Redeem(address indexed account, uint256 amount, uint256 tokensAmount);

    struct LendLocalVars {
        MathError mathErr;
        uint256 exchangeRateMantissa;
        uint256 mintedTokens;
    }

    function lendInternal(address payer, address lender, uint256 amount) internal nonReentrant nonZeroAddress(lender) returns(uint256) {
        require(amount >= minDeposit, toString(Error.AMOUNT_LOWER_THAN_MIN_DEPOSIT));
        uint256 allowed = lendAllowed(address(this), lender, amount);
        require(allowed == 0, ErrorReporter.uint2str(allowed));

        LendLocalVars memory vars;

        (vars.mathErr, vars.exchangeRateMantissa) = exchangeRateInternal();
        ErrorReporter.check(uint256(vars.mathErr));

        require(_transferTokens(payer, address(this), amount));

        (vars.mathErr, vars.mintedTokens) = divScalarByExpTruncate(amount, Exp({mantissa: vars.exchangeRateMantissa}));
        ErrorReporter.check(uint256(vars.mathErr));
        
        lpToken.mint(lender, vars.mintedTokens);

        emit Lend(lender, amount, vars.mintedTokens);
        return uint256(Error.NO_ERROR);
    }

    struct RedeemLocalVars {
        MathError mathErr;
        uint256 exchangeRateMantissa;
        uint256 redeemTokens;
        uint256 redeemAmount;
    }

    function redeemInternal(address redeemer, uint256 _amount, uint256 _tokenAmount) internal nonReentrant returns(uint256) {
        require(_amount == 0 || _tokenAmount == 0, "one of _amount or _tokenAmount must be zero");

        RedeemLocalVars memory vars;

        (vars.mathErr, vars.exchangeRateMantissa) = exchangeRateInternal();
        ErrorReporter.check(uint256(vars.mathErr));


        if (_tokenAmount > 0) {
            vars.redeemTokens = _tokenAmount;

            (vars.mathErr, vars.redeemAmount) = mulScalarTruncate(Exp({mantissa: vars.exchangeRateMantissa}), _tokenAmount);
            ErrorReporter.check(uint256(vars.mathErr));
        } else {
            (vars.mathErr, vars.redeemTokens) = divScalarByExpTruncate(_amount, Exp({mantissa: vars.exchangeRateMantissa}));
            ErrorReporter.check(uint256(vars.mathErr));

            vars.redeemAmount = _amount;
        }

        uint256 allowed = redeemAllowed(address(this), redeemer, vars.redeemTokens);
        require(allowed == 0, ErrorReporter.uint2str(allowed));

        require(balanceOf(redeemer) >= vars.redeemTokens, toString(Error.AMOUNT_HIGHER));
        require(this.getCash() >= vars.redeemAmount, toString(Error.NOT_ENOUGH_CASH));

        lpToken.burnFrom(redeemer, vars.redeemTokens);
        _transferTokens(address(this), redeemer, vars.redeemAmount);

        emit Redeem(redeemer, vars.redeemAmount, vars.redeemTokens);
        return uint256(Error.NO_ERROR);
    }

    function exchangeRate() public view returns (uint256) {
        (MathError err, uint256 result) = exchangeRateInternal();
        ErrorReporter.check(uint256(err));
        return result;
    }

    function exchangeRateInternal() internal view returns (MathError, uint256) {
        uint256 _totalSupply = totalSupply();
        if (_totalSupply == 0) {
            return (MathError.NO_ERROR, initialExchangeRate);
        } else {
            Exp memory _exchangeRate;

            uint256 totalCash = getCash();
            uint256 totalBorrowed = getTotalBorrowBalance();

            (MathError mathErr, uint256 cashPlusBorrows) = addUInt(totalCash, totalBorrowed);
            if (mathErr != MathError.NO_ERROR) {
                return (mathErr, 0);
            }
            
            (mathErr, _exchangeRate) = getExp(cashPlusBorrows, _totalSupply);
            if (mathErr != MathError.NO_ERROR) {
                return (mathErr, 0);
            }

            return (MathError.NO_ERROR, _exchangeRate.mantissa);
        }
    }

    function balanceOf(address account) public view returns (uint256) {
        return lpToken.balanceOf(account);
    }

    function balanceOfUnderlying(address owner) external view returns (uint256) {
        Exp memory _exchangeRate = Exp({ mantissa: exchangeRate() });
        (MathError mErr, uint balance) = mulScalarTruncate(_exchangeRate, balanceOf(owner));
        ErrorReporter.check(uint256(mErr));
        return balance;
    }

    function totalSupply() public virtual view returns (uint256) {
        return lpToken.totalSupply();
    }

    function getCash() public virtual view returns (uint256);
    function getTotalBorrowBalance() public virtual view returns (uint256);

    function _transferTokens(address from, address to, uint256 amount) internal virtual returns (bool);

    function lendAllowed(address _pool, address _lender, uint256 _amount) internal virtual returns (uint256);
    function redeemAllowed(address _pool, address _redeemer, uint256 _tokenAmount) internal virtual returns (uint256);
}