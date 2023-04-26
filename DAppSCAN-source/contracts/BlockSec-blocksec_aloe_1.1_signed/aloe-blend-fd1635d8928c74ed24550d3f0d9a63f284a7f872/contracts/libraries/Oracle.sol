// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.10;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import "./FullMath.sol";
import "./TickMath.sol";

/// @title Oracle
/// @notice Provides functions to integrate with V3 pool oracle
library Oracle {
    /**
     * @notice Calculates time-weighted means of tick and liquidity for a given Uniswap V3 pool
     * @param pool Address of the pool that we want to observe
     * @param secondsAgo Number of seconds in the past from which to calculate the time-weighted means
     * @return arithmeticMeanTick The arithmetic mean tick from (block.timestamp - secondsAgo) to block.timestamp
     * @return secondsPerLiquidityX128 The change in seconds per liquidity from (block.timestamp - secondsAgo)
     * to block.timestamp
     */
    function consult(IUniswapV3Pool pool, uint32 secondsAgo)
        internal
        view
        returns (int24 arithmeticMeanTick, uint160 secondsPerLiquidityX128)
    {
        require(secondsAgo != 0, "BP");

        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = secondsAgo;
        secondsAgos[1] = 0;

        (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s) = pool.observe(
            secondsAgos
        );

        int56 tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];
        arithmeticMeanTick = int24(tickCumulativesDelta / int32(secondsAgo));
        // Always round to negative infinity
        if (tickCumulativesDelta < 0 && (tickCumulativesDelta % int32(secondsAgo) != 0)) arithmeticMeanTick--;

        secondsPerLiquidityX128 = secondsPerLiquidityCumulativeX128s[1] - secondsPerLiquidityCumulativeX128s[0];
    }

    /**
     * @notice Given a pool, it returns the number of seconds ago of the oldest stored observation
     * @param pool Address of Uniswap V3 pool that we want to observe
     * @param observationIndex The observation index from pool.slot0()
     * @param observationCardinality The observationCardinality from pool.slot0()
     * @dev (, , uint16 observationIndex, uint16 observationCardinality, , , ) = pool.slot0();
     * @return secondsAgo The number of seconds ago that the oldest observation was stored
     */
    function getOldestObservation(
        IUniswapV3Pool pool,
        uint16 observationIndex,
        uint16 observationCardinality
    ) internal view returns (uint32 secondsAgo) {
        require(observationCardinality != 0, "NI");

        unchecked {
            (uint32 observationTimestamp, , , bool initialized) = pool.observations(
                (observationIndex + 1) % observationCardinality
            );

            // The next index might not be initialized if the cardinality is in the process of increasing
            // In this case the oldest observation is always in index 0
            if (!initialized) {
                (observationTimestamp, , , ) = pool.observations(0);
            }

            secondsAgo = uint32(block.timestamp) - observationTimestamp;
        }
    }
}
