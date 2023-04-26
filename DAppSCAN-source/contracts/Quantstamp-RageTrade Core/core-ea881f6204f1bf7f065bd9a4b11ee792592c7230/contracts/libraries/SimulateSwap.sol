// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.9;

import { FullMath } from '@uniswap/v3-core-0.8-support/contracts/libraries/FullMath.sol';
import { FixedPoint128 } from '@uniswap/v3-core-0.8-support/contracts/libraries/FixedPoint128.sol';
import { SwapMath } from '@uniswap/v3-core-0.8-support/contracts/libraries/SwapMath.sol';
import { SafeCast } from '@uniswap/v3-core-0.8-support/contracts/libraries/SafeCast.sol';
import { TickMath } from '@uniswap/v3-core-0.8-support/contracts/libraries/TickMath.sol';
import { TickBitmapExtended } from './TickBitmapExtended.sol';

import { IUniswapV3Pool } from '@uniswap/v3-core-0.8-support/contracts/interfaces/IUniswapV3Pool.sol';

/// @title Simulate Uniswap V3 Swaps
library SimulateSwap {
    using SafeCast for uint256;
    using TickBitmapExtended for function(int16) external view returns (uint256);

    error ZeroAmount();
    error InvalidSqrtPriceLimit(uint160 sqrtPriceLimitX96);

    struct Cache {
        // price at the beginning of the swap
        uint160 sqrtPriceX96Start;
        // tick at the beginning of the swap
        int24 tickStart;
        // the protocol fee for the input token
        uint8 feeProtocol;
        // liquidity at the beginning of the swap
        uint128 liquidityStart;
        // the tick spacing of the pool
        int24 tickSpacing;
        // the lp fee share of the pool
        uint24 fee;
        // extra values for cache, that may be useful for _onSwapStep
        uint256 value1;
        uint256 value2;
    }

    struct State {
        // the amount remaining to be swapped in/out of the input/output asset
        int256 amountSpecifiedRemaining;
        // the amount already swapped out/in of the output/input asset
        int256 amountCalculated;
        // current sqrt(price)
        uint160 sqrtPriceX96;
        // the tick associated with the current price
        int24 tick;
        // the global fee growth of the input token
        uint256 feeGrowthGlobalIncreaseX128;
        // amount of input token paid as protocol fee
        uint128 protocolFee;
        // the current liquidity in range
        uint128 liquidity;
    }

    struct Step {
        // the price at the beginning of the step
        uint160 sqrtPriceStartX96;
        // the next tick to swap to from the current tick in the swap direction
        int24 tickNext;
        // whether tickNext is initialized or not
        bool initialized;
        // sqrt(price) for the next tick (1/0)
        uint160 sqrtPriceNextX96;
        // how much is being swapped in in this step
        uint256 amountIn;
        // how much is being swapped out
        uint256 amountOut;
        // how much fee is being paid in
        uint256 feeAmount;
    }

    /// @notice Simulates a swap over an Uniswap V3 Pool, allowing to handle tick crosses.
    /// @param v3Pool uniswap v3 pool address
    /// @param zeroForOne direction of swap, true means swap zero for one
    /// @param amountSpecified amount to swap in/out
    /// @param sqrtPriceLimitX96 the maximum price to swap to, if this price is reached, then the swap is stopped partially
    /// @param cache the swap cache, can be passed empty or with some values filled in to prevent STATICCALLS to v3Pool
    /// @param onSwapStep function to call for each step of the swap, passing in the swap state and the step computations
    /// @return amount0 token0 amount
    /// @return amount1 token1 amount
    /// @return state swap state at the end of the swap
    function simulateSwap(
        IUniswapV3Pool v3Pool,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        SimulateSwap.Cache memory cache,
        function(bool, SimulateSwap.Cache memory, SimulateSwap.State memory, SimulateSwap.Step memory) onSwapStep
    )
        internal
        returns (
            int256 amount0,
            int256 amount1,
            SimulateSwap.State memory state
        )
    {
        if (amountSpecified == 0) revert ZeroAmount();

        // if cache.sqrtPriceX96Start is not set, then make a STATICCALL to v3Pool
        if (cache.sqrtPriceX96Start == 0) {
            (cache.sqrtPriceX96Start, cache.tickStart, , , , cache.feeProtocol, ) = v3Pool.slot0();
        }

        // if cache.liquidityStart is not set, then make a STATICCALL to v3Pool
        if (cache.liquidityStart == 0) cache.liquidityStart = v3Pool.liquidity();

        // if cache.tickSpacing is not set, then make a STATICCALL to v3Pool
        if (cache.tickSpacing == 0) {
            cache.fee = v3Pool.fee();
            cache.tickSpacing = v3Pool.tickSpacing();
        }

        // ensure that the sqrtPriceLimitX96 makes sense
        if (
            zeroForOne
                ? sqrtPriceLimitX96 > cache.sqrtPriceX96Start || sqrtPriceLimitX96 < TickMath.MIN_SQRT_RATIO
                : sqrtPriceLimitX96 < cache.sqrtPriceX96Start || sqrtPriceLimitX96 > TickMath.MAX_SQRT_RATIO
        ) revert InvalidSqrtPriceLimit(sqrtPriceLimitX96);

        bool exactInput = amountSpecified > 0;

        state = SimulateSwap.State({
            amountSpecifiedRemaining: amountSpecified,
            amountCalculated: 0,
            sqrtPriceX96: cache.sqrtPriceX96Start,
            tick: cache.tickStart,
            feeGrowthGlobalIncreaseX128: 0,
            protocolFee: 0,
            liquidity: cache.liquidityStart
        });

        // continue swapping as long as we haven't used the entire input/output and haven't reached the price limit
        while (state.amountSpecifiedRemaining != 0 && state.sqrtPriceX96 != sqrtPriceLimitX96) {
            SimulateSwap.Step memory step;

            step.sqrtPriceStartX96 = state.sqrtPriceX96;

            (step.tickNext, step.initialized) = v3Pool.tickBitmap.nextInitializedTickWithinOneWord(
                state.tick,
                cache.tickSpacing,
                zeroForOne
            );

            // ensure that we do not overshoot the min/max tick, as the tick bitmap is not aware of these bounds
            if (step.tickNext < TickMath.MIN_TICK) {
                step.tickNext = TickMath.MIN_TICK;
            } else if (step.tickNext > TickMath.MAX_TICK) {
                step.tickNext = TickMath.MAX_TICK;
            }

            // get the price for the next tick
            step.sqrtPriceNextX96 = TickMath.getSqrtRatioAtTick(step.tickNext);

            // compute values to swap to the target tick, price limit, or point where input/output amount is exhausted
            (state.sqrtPriceX96, step.amountIn, step.amountOut, step.feeAmount) = SwapMath.computeSwapStep(
                state.sqrtPriceX96,
                (zeroForOne ? step.sqrtPriceNextX96 < sqrtPriceLimitX96 : step.sqrtPriceNextX96 > sqrtPriceLimitX96)
                    ? sqrtPriceLimitX96
                    : step.sqrtPriceNextX96,
                state.liquidity,
                state.amountSpecifiedRemaining,
                cache.fee
            );

            if (exactInput) {
                state.amountSpecifiedRemaining -= (step.amountIn + step.feeAmount).toInt256();
                state.amountCalculated = state.amountCalculated - step.amountOut.toInt256();
            } else {
                state.amountSpecifiedRemaining += step.amountOut.toInt256();
                state.amountCalculated = state.amountCalculated + (step.amountIn + step.feeAmount).toInt256();
            }

            // update global fee tracker
            if (state.liquidity > 0) {
                state.feeGrowthGlobalIncreaseX128 += FullMath.mulDiv(
                    step.feeAmount,
                    FixedPoint128.Q128,
                    state.liquidity
                );
            }

            // jump to the method that handles the swap step
            onSwapStep(zeroForOne, cache, state, step);

            // shift tick if we reached the next price
            if (state.sqrtPriceX96 == step.sqrtPriceNextX96) {
                // if the tick is initialized, adjust the liquidity
                if (step.initialized) {
                    (, int128 liquidityNet, , , , , , ) = v3Pool.ticks(step.tickNext);
                    // if we're moving leftward, we interpret liquidityNet as the opposite sign
                    // safe because liquidityNet cannot be type(int128).min
                    if (zeroForOne) liquidityNet = -liquidityNet;
                    state.liquidity = liquidityNet < 0
                        ? state.liquidity - uint128(-liquidityNet)
                        : state.liquidity + uint128(liquidityNet);
                }

                state.tick = zeroForOne ? step.tickNext - 1 : step.tickNext;
            } else if (state.sqrtPriceX96 != step.sqrtPriceStartX96) {
                // recompute unless we're on a lower tick boundary (i.e. already transitioned ticks), and haven't moved
                state.tick = TickMath.getTickAtSqrtRatio(state.sqrtPriceX96);
            }
        }

        (amount0, amount1) = zeroForOne == exactInput
            ? (amountSpecified - state.amountSpecifiedRemaining, state.amountCalculated)
            : (state.amountCalculated, amountSpecified - state.amountSpecifiedRemaining);
    }

    /// @notice Overloads simulate swap to prevent passing a cache input
    /// @param v3Pool uniswap v3 pool address
    /// @param zeroForOne direction of swap, true means swap zero for one
    /// @param amountSpecified amount to swap in/out
    /// @param sqrtPriceLimitX96 the maximum price to swap to, if this price is reached, then the swap is stopped partially
    /// @param onSwapStep function to call for each step of the swap, passing in the swap state and the step computations
    /// @return amount0 token0 amount
    /// @return amount1 token1 amount
    /// @return state swap state at the end of the swap
    /// @return cache swap cache populated with values, can be used for subsequent simulations
    function simulateSwap(
        IUniswapV3Pool v3Pool,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        function(bool, SimulateSwap.Cache memory, SimulateSwap.State memory, SimulateSwap.Step memory) onSwapStep
    )
        internal
        returns (
            int256 amount0,
            int256 amount1,
            SimulateSwap.State memory state,
            SimulateSwap.Cache memory cache
        )
    {
        (amount0, amount1, state) = simulateSwap(
            v3Pool,
            zeroForOne,
            amountSpecified,
            sqrtPriceLimitX96,
            cache,
            onSwapStep
        );
    }
}
