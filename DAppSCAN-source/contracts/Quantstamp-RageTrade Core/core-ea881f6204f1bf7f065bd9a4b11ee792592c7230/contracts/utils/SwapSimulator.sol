// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.9;

import { IUniswapV3Pool } from '@uniswap/v3-core-0.8-support/contracts/interfaces/IUniswapV3Pool.sol';
import { TickMath } from '@uniswap/v3-core-0.8-support/contracts/libraries/TickMath.sol';

import { IClearingHouse } from '../interfaces/IClearingHouse.sol';
import { IClearingHouseStructures } from '../interfaces/clearinghouse/IClearingHouseStructures.sol';
import { IVPoolWrapper } from '../interfaces/IVPoolWrapper.sol';
import { IVToken } from '../interfaces/IVToken.sol';

import { SimulateSwap } from '../libraries/SimulateSwap.sol';
import { SwapMath } from '../libraries/SwapMath.sol';
import { UniswapV3PoolHelper } from '../libraries/UniswapV3PoolHelper.sol';

contract SwapSimulator {
    using SimulateSwap for IUniswapV3Pool;

    struct SwapStepAndState {
        SimulateSwap.Step step;
        SimulateSwap.State state;
    }

    SwapStepAndState[] _steps;

    function simulateSwap(
        IClearingHouse clearingHouse,
        uint32 poolId,
        int256 amount,
        uint160 sqrtPriceLimitX96,
        bool isNotional
    )
        public
        returns (
            IVPoolWrapper.SwapResult memory swapResult,
            SimulateSwap.Cache memory cache,
            SwapStepAndState[] memory steps
        )
    {
        IClearingHouseStructures.Pool memory poolInfo = clearingHouse.getPoolInfo(poolId);

        (swapResult, cache) = _simulateSwap(
            poolInfo.vPool,
            poolInfo.vPoolWrapper.liquidityFeePips(),
            poolInfo.vPoolWrapper.protocolFeePips(),
            amount < 0,
            isNotional ? amount : -amount,
            sqrtPriceLimitX96,
            _onSwapStep
        );

        steps = _steps;

        swapResult.sqrtPriceX96Start = cache.sqrtPriceX96Start;
        swapResult.sqrtPriceX96End = steps[steps.length - 1].state.sqrtPriceX96;
    }

    function _simulateSwap(
        IUniswapV3Pool vPool,
        uint24 liquidityFeePips,
        uint24 protocolFeePips,
        bool swapVTokenForVQuote, // zeroForOne
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        function(bool, SimulateSwap.Cache memory, SimulateSwap.State memory, SimulateSwap.Step memory) onSwapStep
    ) internal returns (IVPoolWrapper.SwapResult memory swapResult, SimulateSwap.Cache memory cache) {
        delete _steps;

        if (sqrtPriceLimitX96 == 0) {
            sqrtPriceLimitX96 = swapVTokenForVQuote ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1;
        }

        swapResult.amountSpecified = amountSpecified;
        bool exactIn = amountSpecified >= 0;
        uint24 uniswapFeePips = vPool.fee();

        SwapMath.beforeSwap(
            exactIn,
            swapVTokenForVQuote,
            uniswapFeePips,
            liquidityFeePips,
            protocolFeePips,
            swapResult
        );

        // simulate swap and update our tick states

        (swapResult.vTokenIn, swapResult.vQuoteIn, , cache) = vPool.simulateSwap(
            swapVTokenForVQuote,
            amountSpecified,
            sqrtPriceLimitX96,
            onSwapStep
        );

        SwapMath.afterSwap(exactIn, swapVTokenForVQuote, uniswapFeePips, liquidityFeePips, protocolFeePips, swapResult);
    }

    function _onSwapStep(
        bool,
        SimulateSwap.Cache memory,
        SimulateSwap.State memory state,
        SimulateSwap.Step memory step
    ) internal {
        // for reading
        _steps.push(SwapStepAndState({ state: state, step: step }));
    }
}
