// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.9;

import { IUniswapV3Pool } from '@uniswap/v3-core-0.8-support/contracts/interfaces/IUniswapV3Pool.sol';

import { FundingPayment } from './FundingPayment.sol';

import { IVToken } from '../interfaces/IVToken.sol';

/// @title Extended tick state for VPoolWrapper
library TickExtended {
    struct Info {
        int256 sumALastX128;
        int256 sumBOutsideX128;
        int256 sumFpOutsideX128;
        uint256 sumFeeOutsideX128;
    }

    /// @notice Calculates the extended tick state inside a tick range
    /// @param self mapping of tick index to tick extended state
    /// @param tickLower lower tick index
    /// @param tickUpper upper tick index
    /// @param tickCurrent current tick index
    /// @param fpGlobal global funding payment state
    /// @param sumFeeGlobalX128 global sum of fees for liquidity providers
    /// @return sumBInsideX128 sum of all B values for trades that took place inside the tick range
    /// @return sumFpInsideX128 sum of all FP values for trades that took place inside the tick range
    /// @return sumFeeInsideX128 sum of all fee values for trades that took place inside the tick range
    function getTickExtendedStateInside(
        mapping(int24 => TickExtended.Info) storage self,
        int24 tickLower,
        int24 tickUpper,
        int24 tickCurrent,
        FundingPayment.Info memory fpGlobal,
        uint256 sumFeeGlobalX128
    )
        internal
        view
        returns (
            int256 sumBInsideX128,
            int256 sumFpInsideX128,
            uint256 sumFeeInsideX128
        )
    {
        Info storage lower = self[tickLower];
        Info storage upper = self[tickUpper];

        int256 sumBBelowX128 = lower.sumBOutsideX128;
        int256 sumFpBelowX128 = FundingPayment.extrapolatedSumFpX128(
            lower.sumALastX128,
            sumBBelowX128, // lower.sumBOutsideX128,
            lower.sumFpOutsideX128,
            fpGlobal.sumAX128
        );
        uint256 sumFeeBelowX128 = lower.sumFeeOutsideX128;
        if (tickLower > tickCurrent) {
            sumBBelowX128 = fpGlobal.sumBX128 - sumBBelowX128;
            sumFpBelowX128 = fpGlobal.sumFpX128 - sumFpBelowX128;
            sumFeeBelowX128 = sumFeeGlobalX128 - sumFeeBelowX128;
        }

        int256 sumBAboveX128 = upper.sumBOutsideX128;
        int256 sumFpAboveX128 = FundingPayment.extrapolatedSumFpX128(
            upper.sumALastX128,
            sumBAboveX128, // upper.sumBOutsideX128,
            upper.sumFpOutsideX128,
            fpGlobal.sumAX128
        );
        uint256 sumFeeAboveX128 = upper.sumFeeOutsideX128;
        if (tickUpper <= tickCurrent) {
            sumBAboveX128 = fpGlobal.sumBX128 - sumBAboveX128;
            sumFpAboveX128 = fpGlobal.sumFpX128 - sumFpAboveX128;
            sumFeeAboveX128 = sumFeeGlobalX128 - sumFeeAboveX128;
        }

        sumBInsideX128 = fpGlobal.sumBX128 - sumBBelowX128 - sumBAboveX128;
        sumFpInsideX128 = fpGlobal.sumFpX128 - sumFpBelowX128 - sumFpAboveX128;
        sumFeeInsideX128 = sumFeeGlobalX128 - sumFeeBelowX128 - sumFeeAboveX128;
    }

    /// @notice Updates the extended tick state whenever liquidity is updated
    /// @param self mapping of tick index to tick extended state
    /// @param tick to update
    /// @param tickCurrent current tick index
    /// @param liquidityDelta delta of liquidity
    /// @param sumAGlobalX128 global funding payment state sumA
    /// @param sumBGlobalX128 global funding payment state sumB
    /// @param sumFpGlobalX128 global funding payment state sumFp
    /// @param sumFeeGlobalX128 global sum of fees for liquidity providers
    /// @param vPool uniswap v3 pool contract
    /// @return flipped whether the tick was flipped or no
    function update(
        mapping(int24 => TickExtended.Info) storage self,
        int24 tick,
        int24 tickCurrent,
        int128 liquidityDelta,
        int256 sumAGlobalX128,
        int256 sumBGlobalX128,
        int256 sumFpGlobalX128,
        uint256 sumFeeGlobalX128,
        IUniswapV3Pool vPool
    ) internal returns (bool flipped) {
        TickExtended.Info storage info = self[tick];

        (uint128 liquidityGrossBefore, , , , , , , ) = vPool.ticks(tick);
        uint128 liquidityGrossAfter = liquidityDelta < 0
            ? liquidityGrossBefore - uint128(-liquidityDelta)
            : liquidityGrossBefore + uint128(liquidityDelta);

        flipped = (liquidityGrossAfter == 0) != (liquidityGrossBefore == 0);

        if (liquidityGrossBefore == 0) {
            // by convention, we assume that all growth before a tick was initialized happened _below_ the tick
            if (tick <= tickCurrent) {
                info.sumALastX128 = sumAGlobalX128;
                info.sumBOutsideX128 = sumBGlobalX128;
                info.sumFpOutsideX128 = sumFpGlobalX128;
                info.sumFeeOutsideX128 = sumFeeGlobalX128;
            }
        }
    }

    /// @notice Updates the extended tick state whenever tick is crossed in a swap
    /// @param self mapping of tick index to tick extended state
    /// @param tick to update
    /// @param fpGlobal global funding payment state
    /// @param sumFeeGlobalX128 global sum of fees for liquidity providers
    function cross(
        mapping(int24 => TickExtended.Info) storage self,
        int24 tick,
        FundingPayment.Info memory fpGlobal,
        uint256 sumFeeGlobalX128
    ) internal {
        TickExtended.Info storage info = self[tick];
        int256 sumFpOutsideX128 = FundingPayment.extrapolatedSumFpX128(
            info.sumALastX128,
            info.sumBOutsideX128,
            info.sumFpOutsideX128,
            fpGlobal.sumAX128
        );
        info.sumALastX128 = fpGlobal.sumAX128;
        info.sumBOutsideX128 = fpGlobal.sumBX128 - info.sumBOutsideX128;
        info.sumFpOutsideX128 = fpGlobal.sumFpX128 - sumFpOutsideX128;
        info.sumFeeOutsideX128 = sumFeeGlobalX128 - info.sumFeeOutsideX128;
    }

    /// @notice Clears tick data
    /// @param self The mapping containing all initialized tick information for initialized ticks
    /// @param tick The tick that will be cleared
    function clear(mapping(int24 => TickExtended.Info) storage self, int24 tick) internal {
        delete self[tick];
    }
}
