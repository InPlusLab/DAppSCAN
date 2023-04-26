// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { FixedPoint128 } from '@uniswap/v3-core-0.8-support/contracts/libraries/FixedPoint128.sol';

import { FundingPayment } from '../libraries/FundingPayment.sol';
import { SignedFullMath } from '../libraries/SignedFullMath.sol';

contract FundingPaymentTest {
    using SignedFullMath for int256;

    using FundingPayment for FundingPayment.Info;

    FundingPayment.Info public fpGlobal;

    function getFundingRate(uint256 realPriceX128, uint256 virtualPriceX128)
        internal
        pure
        returns (int256 fundingRateX128)
    {
        return FundingPayment.getFundingRate(realPriceX128, virtualPriceX128);
    }

    function update(
        int256 vTokenAmount,
        uint256 liquidity,
        uint48 blockTimestamp,
        uint256 realPriceX128,
        uint256 virtualPriceX128
    ) public {
        return
            fpGlobal.update(
                vTokenAmount,
                liquidity,
                blockTimestamp,
                FundingPayment.getFundingRate(realPriceX128, virtualPriceX128),
                virtualPriceX128
            );
    }

    function nextAX128(
        uint48 timestampLast,
        uint48 blockTimestamp,
        uint256 realPriceX128,
        uint256 virtualPriceX128
    ) public pure returns (int256) {
        return
            FundingPayment.nextAX128(
                timestampLast,
                blockTimestamp,
                FundingPayment.getFundingRate(realPriceX128, virtualPriceX128),
                virtualPriceX128
            );
    }

    function extrapolatedSumAX128(
        int256 sumA,
        uint48 timestampLast,
        uint48 blockTimestamp,
        uint256 realPriceX128,
        uint256 virtualPriceX128
    ) public pure returns (int256) {
        return
            FundingPayment.extrapolatedSumAX128(
                sumA,
                timestampLast,
                blockTimestamp,
                FundingPayment.getFundingRate(realPriceX128, virtualPriceX128),
                virtualPriceX128
            );
    }

    function extrapolatedSumFpX128(
        int256 sumAX128,
        int256 sumBX128,
        int256 sumFpX128,
        int256 sumALatestX128
    ) public pure returns (int256) {
        return FundingPayment.extrapolatedSumFpX128(sumAX128, sumBX128, sumFpX128, sumALatestX128);
    }

    function billLp(
        int256 sumAX128,
        int256 sumFpInsideX128,
        int256 sumALastX128,
        int256 sumBInsideLastX128,
        int256 sumFpInsideLastX128,
        uint256 liquidity
    ) internal pure returns (int256) {
        return
            FundingPayment.bill(
                sumAX128,
                sumFpInsideX128,
                sumALastX128,
                sumBInsideLastX128,
                sumFpInsideLastX128,
                liquidity
            );
    }

    function billTrader(
        int256 sumAX128,
        int256 sumALastX128,
        int256 netTraderPosition
    ) internal pure returns (int256) {
        return FundingPayment.bill(sumAX128, sumALastX128, netTraderPosition);
    }
}
