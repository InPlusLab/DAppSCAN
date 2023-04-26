// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.9;

import { FixedPoint128 } from '@uniswap/v3-core-0.8-support/contracts/libraries/FixedPoint128.sol';
import { FullMath } from '@uniswap/v3-core-0.8-support/contracts/libraries/FullMath.sol';
import { SignedFullMath } from './SignedFullMath.sol';

/// @title Funding payment functions
/// @notice Funding Payment Logic used to distribute the FP bill paid by traders among the LPs in the liquidity range
library FundingPayment {
    using FullMath for uint256;
    using SignedFullMath for int256;

    struct Info {
        // FR * P * dt
        int256 sumAX128;
        // trade token amount / liquidity
        int256 sumBX128;
        // sum(a * sumB)
        int256 sumFpX128;
        // time when state was last updated
        uint48 timestampLast;
    }

    event FundingPaymentStateUpdated(
        FundingPayment.Info fundingPayment,
        int256 fundingRateX128,
        uint256 virtualPriceX128
    );

    /// @notice Calculates the funding rate based on prices
    /// @param realPriceX128 spot price of token
    /// @param virtualPriceX128 futures price of token
    function getFundingRate(uint256 realPriceX128, uint256 virtualPriceX128)
        internal
        pure
        returns (int256 fundingRateX128)
    {
        return (int256(realPriceX128) - int256(virtualPriceX128)).mulDiv(FixedPoint128.Q128, realPriceX128) / 1 days;
    }

    /// @notice Used to update the state of the funding payment whenever a trade takes place
    /// @param info pointer to the funding payment state
    /// @param vTokenAmount trade token amount
    /// @param liquidity active liquidity in the range during the trade (step)
    /// @param blockTimestamp timestamp of current block
    /// @param fundingRateX128 the constant funding rate to apply for the duration between timestampLast and blockTimestamp
    /// @param virtualPriceX128 futures price of token
    function update(
        FundingPayment.Info storage info,
        int256 vTokenAmount,
        uint256 liquidity,
        uint48 blockTimestamp,
        int256 fundingRateX128,
        uint256 virtualPriceX128
    ) internal {
        int256 a = nextAX128(info.timestampLast, blockTimestamp, fundingRateX128, virtualPriceX128);
        info.sumFpX128 += a.mulDivRoundingDown(info.sumBX128, int256(FixedPoint128.Q128));
        info.sumAX128 += a;
        info.sumBX128 += vTokenAmount.mulDiv(int256(FixedPoint128.Q128), int256(liquidity));
        info.timestampLast = blockTimestamp;

        emit FundingPaymentStateUpdated(info, fundingRateX128, virtualPriceX128);
    }

    /// @notice Used to get the rate of funding payment for the duration between last trade and this trade
    /// @dev Positive A value means at this duration, longs pay shorts. Negative means shorts pay longs.
    /// @param timestampLast start timestamp of duration
    /// @param blockTimestamp end timestamp of duration
    /// @param virtualPriceX128 futures price of token
    /// @param fundingRateX128 the constant funding rate to apply for the duration between timestampLast and blockTimestamp
    /// @return aX128 value called "a" (see funding payment math documentation)
    function nextAX128(
        uint48 timestampLast,
        uint48 blockTimestamp,
        int256 fundingRateX128,
        uint256 virtualPriceX128
    ) internal pure returns (int256 aX128) {
        return fundingRateX128.mulDiv(virtualPriceX128, FixedPoint128.Q128) * int48(blockTimestamp - timestampLast);
    }

    function extrapolatedSumAX128(
        int256 sumAX128,
        uint48 timestampLast,
        uint48 blockTimestamp,
        int256 fundingRateX128,
        uint256 virtualPriceX128
    ) internal pure returns (int256) {
        return sumAX128 + nextAX128(timestampLast, blockTimestamp, fundingRateX128, virtualPriceX128);
    }

    /// @notice Extrapolates (updates) the value of sumFp by adding the missing component to it using sumAGlobalX128
    /// @param sumAX128 sumA value that is recorded from global at some point in time
    /// @param sumBX128 sumB value that is recorded from global at same point in time as sumA
    /// @param sumFpX128 sumFp value that is recorded from global at same point in time as sumA and sumB
    /// @param sumAGlobalX128 latest sumA value (taken from global), used to extrapolate the sumFp
    function extrapolatedSumFpX128(
        int256 sumAX128,
        int256 sumBX128,
        int256 sumFpX128,
        int256 sumAGlobalX128
    ) internal pure returns (int256) {
        return sumFpX128 + sumBX128.mulDiv(sumAGlobalX128 - sumAX128, int256(FixedPoint128.Q128));
    }

    /// @notice Positive bill is rewarded to LPs, Negative bill is charged from LPs
    /// @param sumAX128 latest value of sumA (to be taken from global state)
    /// @param sumFpInsideX128 latest value of sumFp inside range (to be computed using global state + tick state)
    /// @param sumALastX128 value of sumA when LP updated their liquidity last time
    /// @param sumBInsideLastX128 value of sumB inside range when LP updated their liquidity last time
    /// @param sumFpInsideLastX128 value of sumFp inside range when LP updated their liquidity last time
    /// @param liquidity amount of liquidity which was constant for LP in the time duration
    function bill(
        int256 sumAX128,
        int256 sumFpInsideX128,
        int256 sumALastX128,
        int256 sumBInsideLastX128,
        int256 sumFpInsideLastX128,
        uint256 liquidity
    ) internal pure returns (int256) {
        return
            (sumFpInsideX128 - extrapolatedSumFpX128(sumALastX128, sumBInsideLastX128, sumFpInsideLastX128, sumAX128))
                .mulDivRoundingDown(liquidity, FixedPoint128.Q128);
    }

    /// @notice Positive bill is rewarded to Traders, Negative bill is charged from Traders
    /// @param sumAX128 latest value of sumA (to be taken from global state)
    /// @param sumALastX128 value of sumA when trader updated their netTraderPosition
    /// @param netTraderPosition oken amount which should be constant for time duration since sumALastX128 was recorded
    function bill(
        int256 sumAX128,
        int256 sumALastX128,
        int256 netTraderPosition
    ) internal pure returns (int256) {
        return netTraderPosition.mulDiv((sumAX128 - sumALastX128), int256(FixedPoint128.Q128));
    }
}
