// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.9;

import { SignedMath } from './SignedMath.sol';

import { IVPoolWrapper } from '../interfaces/IVPoolWrapper.sol';

/// @title Swap computation functions
library SwapMath {
    using SignedMath for int256;

    /// @notice Executed before swap call to uniswap, to inflate the swap result values
    /// @param exactIn Whether user specified in amount or out amount
    /// @param swapVTokenForVQuote swap direction
    /// @param uniswapFeePips fee ratio that will be collected by uniswap
    /// @param liquidityFeePips fee ratio to be applied in rage trade for paying to liquidity providers
    /// @param protocolFeePips fee ratio to be applied in rage trade for protocol treasury
    /// @param swapResult pointer to the swap result struct
    /// @dev this method mutates the data pointed by swapResult
    function beforeSwap(
        bool exactIn,
        bool swapVTokenForVQuote,
        uint24 uniswapFeePips,
        uint24 liquidityFeePips,
        uint24 protocolFeePips,
        IVPoolWrapper.SwapResult memory swapResult
    ) internal pure {
        // inflate or deinfate to undo uniswap fees if necessary, and account for our fees
        if (exactIn) {
            if (swapVTokenForVQuote) {
                // CASE: exactIn vToken
                // fee: not now, will collect fee in vQuote after swap
                // inflate: for undoing the uniswap fees
                swapResult.amountSpecified = inflate(swapResult.amountSpecified, uniswapFeePips);
            } else {
                // CASE: exactIn vQuote
                // fee: remove fee and do smaller swap, so trader gets less vTokens
                // here, amountSpecified == swap amount + fee
                (swapResult.liquidityFees, swapResult.protocolFees) = calculateFees(
                    swapResult.amountSpecified,
                    AmountTypeEnum.VQUOTE_AMOUNT_PLUS_FEES,
                    liquidityFeePips,
                    protocolFeePips
                );
                swapResult.amountSpecified = includeFees(
                    swapResult.amountSpecified,
                    swapResult.liquidityFees + swapResult.protocolFees,
                    IncludeFeeEnum.SUBTRACT_FEE
                );
                // inflate: uniswap will collect fee so inflate to undo it
                swapResult.amountSpecified = inflate(swapResult.amountSpecified, uniswapFeePips);
            }
        } else {
            if (!swapVTokenForVQuote) {
                // CASE: exactOut vToken
                // fee: no need to collect fee as we want to collect fee in vQuote later
                // inflate: no need to inflate as uniswap collects fees in tokenIn
            } else {
                // CASE: exactOut vQuote
                // fee: buy more vQuote (short more vToken) so that fee can be removed in vQuote
                // here, amountSpecified + fee == swap amount
                (swapResult.liquidityFees, swapResult.protocolFees) = calculateFees(
                    swapResult.amountSpecified,
                    AmountTypeEnum.VQUOTE_AMOUNT_MINUS_FEES,
                    liquidityFeePips,
                    protocolFeePips
                );
                swapResult.amountSpecified = includeFees(
                    swapResult.amountSpecified,
                    swapResult.liquidityFees + swapResult.protocolFees,
                    IncludeFeeEnum.ADD_FEE
                );
            }
        }
    }

    /// @notice Executed after swap call to uniswap, to deinflate the swap result values
    /// @param exactIn Whether user specified in amount or out amount
    /// @param swapVTokenForVQuote swap direction
    /// @param uniswapFeePips fee that will be collected by uniswap
    /// @param liquidityFeePips fee ratio to be applied in rage trade for paying to liquidity providers
    /// @param protocolFeePips fee ratio to be applied in rage trade for protocol treasury
    /// @param swapResult pointer to the swap result struct
    /// @dev This method mutates the data pointed by swapResult
    function afterSwap(
        bool exactIn,
        bool swapVTokenForVQuote,
        uint24 uniswapFeePips,
        uint24 liquidityFeePips,
        uint24 protocolFeePips,
        IVPoolWrapper.SwapResult memory swapResult
    ) internal pure {
        // swap is done so now adjusting vTokenIn and vQuoteIn amounts to remove uniswap fees and add our fees
        if (exactIn) {
            if (swapVTokenForVQuote) {
                // CASE: exactIn vToken
                // deinflate: vToken amount was inflated so that uniswap can collect fee
                swapResult.vTokenIn = deinflate(swapResult.vTokenIn, uniswapFeePips);

                // fee: collect the fee, give less vQuote to trader
                // here, vQuoteIn == swap amount
                (swapResult.liquidityFees, swapResult.protocolFees) = calculateFees(
                    swapResult.vQuoteIn,
                    AmountTypeEnum.ZERO_FEE_VQUOTE_AMOUNT,
                    liquidityFeePips,
                    protocolFeePips
                );
                swapResult.vQuoteIn = includeFees(
                    swapResult.vQuoteIn,
                    swapResult.liquidityFees + swapResult.protocolFees,
                    IncludeFeeEnum.SUBTRACT_FEE
                );
            } else {
                // CASE: exactIn vQuote
                // deinflate: vQuote amount was inflated, hence need to deinflate for generating final statement
                swapResult.vQuoteIn = deinflate(swapResult.vQuoteIn, uniswapFeePips);
                // fee: fee is already removed before swap, lets include it to the final bill, so that trader pays for it
                swapResult.vQuoteIn = includeFees(
                    swapResult.vQuoteIn,
                    swapResult.liquidityFees + swapResult.protocolFees,
                    IncludeFeeEnum.ADD_FEE
                );
            }
        } else {
            if (!swapVTokenForVQuote) {
                // CASE: exactOut vToken
                // deinflate: uniswap want to collect fee in vQuote and hence ask more, so need to deinflate it
                swapResult.vQuoteIn = deinflate(swapResult.vQuoteIn, uniswapFeePips);
                // fee: collecting fees in vQuote
                // here, vQuoteIn == swap amount
                (swapResult.liquidityFees, swapResult.protocolFees) = calculateFees(
                    swapResult.vQuoteIn,
                    AmountTypeEnum.ZERO_FEE_VQUOTE_AMOUNT,
                    liquidityFeePips,
                    protocolFeePips
                );
                swapResult.vQuoteIn = includeFees(
                    swapResult.vQuoteIn,
                    swapResult.liquidityFees + swapResult.protocolFees,
                    IncludeFeeEnum.ADD_FEE
                );
            } else {
                // CASE: exactOut vQuote
                // deinflate: uniswap want to collect fee in vToken and hence ask more, so need to deinflate it
                swapResult.vTokenIn = deinflate(swapResult.vTokenIn, uniswapFeePips);
                // fee: already calculated before, subtract now
                swapResult.vQuoteIn = includeFees(
                    swapResult.vQuoteIn,
                    swapResult.liquidityFees + swapResult.protocolFees,
                    IncludeFeeEnum.SUBTRACT_FEE
                );
            }
        }
    }

    /// @notice Inflates the amount such that when uniswap collects the fee, it will get the same amount
    /// @param amount user specified amount
    /// @param uniswapFeePips fee that will be collected by uniswap
    /// @return inflated amount, on which applying uniswap fee gives the user specifed amount
    function inflate(int256 amount, uint24 uniswapFeePips) internal pure returns (int256 inflated) {
        int256 fees = (amount * int256(uint256(uniswapFeePips))) / int24(1e6 - uniswapFeePips) + 1; // round up
        inflated = amount + fees;
    }

    /// @notice Undoes the inflation of the amount
    /// @param inflated amount from uniswap after the swap call
    /// @param uniswapFeePips fee that will be collected by uniswap
    /// @return amount that is deinflated, which can be given to user
    function deinflate(int256 inflated, uint24 uniswapFeePips) internal pure returns (int256 amount) {
        amount = (inflated * int24(1e6 - uniswapFeePips)) / 1e6;
    }

    enum AmountTypeEnum {
        ZERO_FEE_VQUOTE_AMOUNT,
        VQUOTE_AMOUNT_MINUS_FEES,
        VQUOTE_AMOUNT_PLUS_FEES
    }

    /// @notice Calculates the fees to be collected by rage trade protocol
    /// @param amount should be in vQuote denomination, since fees to be collected only in vQuote
    /// @param amountTypeEnum type of amount
    /// @param liquidityFeePips fee ratio to be applied in rage trade for paying to liquidity providers
    /// @param protocolFeePips fee ratio to be applied in rage trade for protocol treasury
    /// @return liquidityFees calculated fees in vQuote, to be given to liquidity providers
    /// @return protocolFees calculated fees in vQuote, to be given to protocol treasury
    function calculateFees(
        int256 amount,
        AmountTypeEnum amountTypeEnum,
        uint24 liquidityFeePips,
        uint24 protocolFeePips
    ) internal pure returns (uint256 liquidityFees, uint256 protocolFees) {
        uint256 amountAbs = uint256(amount.abs());
        if (amountTypeEnum == AmountTypeEnum.VQUOTE_AMOUNT_MINUS_FEES) {
            // when amount is already subtracted by fees, we need to scale it up, so that
            // on calculating and subtracting fees on the scaled up value, we should get same amount
            amountAbs = (amountAbs * 1e6) / uint256(1e6 - liquidityFeePips - protocolFeePips);
        } else if (amountTypeEnum == AmountTypeEnum.VQUOTE_AMOUNT_PLUS_FEES) {
            // when amount is already added with fees, we need to scale it down, so that
            // on calculating and adding fees on the scaled down value, we should get same amount
            amountAbs = (amountAbs * 1e6) / uint256(1e6 + liquidityFeePips + protocolFeePips);
        }
        uint256 fees = (amountAbs * (liquidityFeePips + protocolFeePips)) / 1e6 + 1; // round up
        liquidityFees = (amountAbs * liquidityFeePips) / 1e6 + 1; // round up
        protocolFees = fees - liquidityFees;
    }

    enum IncludeFeeEnum {
        ADD_FEE,
        SUBTRACT_FEE
    }

    /// @notice Applies the fees in the amount, based on sign of the amount
    /// @param amount amount to which fees are to be applied
    /// @param includeFeeEnum procedure to apply the fee
    /// @return amountAfterFees amount after applying fees
    function includeFees(
        int256 amount,
        uint256 fees,
        IncludeFeeEnum includeFeeEnum
    ) internal pure returns (int256 amountAfterFees) {
        if ((amount > 0) == (includeFeeEnum == IncludeFeeEnum.ADD_FEE)) {
            amountAfterFees = amount + int256(fees);
        } else {
            amountAfterFees = amount - int256(fees);
        }
    }
}
