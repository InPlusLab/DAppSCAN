// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.9;

import { SqrtPriceMath } from '@uniswap/v3-core-0.8-support/contracts/libraries/SqrtPriceMath.sol';
import { TickMath } from '@uniswap/v3-core-0.8-support/contracts/libraries/TickMath.sol';
import { SafeCast } from '@uniswap/v3-core-0.8-support/contracts/libraries/SafeCast.sol';
import { FixedPoint96 } from '@uniswap/v3-core-0.8-support/contracts/libraries/FixedPoint96.sol';

import { FixedPoint128 } from '@uniswap/v3-core-0.8-support/contracts/libraries/FixedPoint128.sol';
import { FullMath } from '@uniswap/v3-core-0.8-support/contracts/libraries/FullMath.sol';
import { IUniswapV3Pool } from '@uniswap/v3-core-0.8-support/contracts/interfaces/IUniswapV3Pool.sol';

import { Account } from './Account.sol';
import { PriceMath } from './PriceMath.sol';
import { Protocol } from './Protocol.sol';
import { SignedFullMath } from './SignedFullMath.sol';
import { UniswapV3PoolHelper } from './UniswapV3PoolHelper.sol';
import { FundingPayment } from './FundingPayment.sol';

import { IClearingHouseStructures } from '../interfaces/clearinghouse/IClearingHouseStructures.sol';
import { IClearingHouseEnums } from '../interfaces/clearinghouse/IClearingHouseEnums.sol';
import { IVPoolWrapper } from '../interfaces/IVPoolWrapper.sol';

/// @title Liquidity position functions
library LiquidityPosition {
    using FullMath for uint256;
    using PriceMath for uint160;
    using SafeCast for uint256;
    using SignedFullMath for int256;
    using UniswapV3PoolHelper for IUniswapV3Pool;

    using LiquidityPosition for LiquidityPosition.Info;
    using Protocol for Protocol.Info;

    struct Set {
        // multiple per pool because it's non-fungible, allows for 4 billion LP positions lifetime
        uint48[5] active;
        // concat(tickLow,tickHigh)
        mapping(uint48 => LiquidityPosition.Info) positions;
        uint256[100] _emptySlots; // reserved for adding variables when upgrading logic
    }

    struct Info {
        //Extra boolean to check if it is limit order and uint to track limit price.
        IClearingHouseEnums.LimitOrderType limitOrderType;
        // the tick range of the position;
        int24 tickLower;
        int24 tickUpper;
        // the liquidity of the position
        uint128 liquidity;
        int256 vTokenAmountIn;
        // funding payment checkpoints
        int256 sumALastX128;
        int256 sumBInsideLastX128;
        int256 sumFpInsideLastX128;
        // fee growth inside
        uint256 sumFeeInsideLastX128;
        uint256[100] _emptySlots; // reserved for adding variables when upgrading logic
    }

    error LP_AlreadyInitialized();
    error LP_IneligibleLimitOrderRemoval();

    /**
     *  Internal methods
     */

    function initialize(
        LiquidityPosition.Info storage position,
        int24 tickLower,
        int24 tickUpper
    ) internal {
        if (position.isInitialized()) {
            revert LP_AlreadyInitialized();
        }

        position.tickLower = tickLower;
        position.tickUpper = tickUpper;
    }

    function liquidityChange(
        LiquidityPosition.Info storage position,
        uint256 accountId,
        uint32 poolId,
        int128 liquidityDelta,
        IClearingHouseStructures.BalanceAdjustments memory balanceAdjustments,
        Protocol.Info storage protocol
    ) internal {
        int256 vTokenPrincipal;
        int256 vQuotePrincipal;

        IVPoolWrapper wrapper = protocol.vPoolWrapper(poolId);
        IVPoolWrapper.WrapperValuesInside memory wrapperValuesInside;

        if (liquidityDelta > 0) {
            uint256 vTokenPrincipal_;
            uint256 vQuotePrincipal_;
            (vTokenPrincipal_, vQuotePrincipal_, wrapperValuesInside) = wrapper.mint(
                position.tickLower,
                position.tickUpper,
                uint128(liquidityDelta)
            );
            vTokenPrincipal = vTokenPrincipal_.toInt256();
            vQuotePrincipal = vQuotePrincipal_.toInt256();
        } else {
            uint256 vTokenPrincipal_;
            uint256 vQuotePrincipal_;
            (vTokenPrincipal_, vQuotePrincipal_, wrapperValuesInside) = wrapper.burn(
                position.tickLower,
                position.tickUpper,
                uint128(-liquidityDelta)
            );
            vTokenPrincipal = -vTokenPrincipal_.toInt256();
            vQuotePrincipal = -vQuotePrincipal_.toInt256();
        }

        position.update(accountId, poolId, wrapperValuesInside, balanceAdjustments);

        balanceAdjustments.vQuoteIncrease -= vQuotePrincipal;
        balanceAdjustments.vTokenIncrease -= vTokenPrincipal;

        uint160 sqrtPriceCurrent = protocol.vPool(poolId).sqrtPriceCurrent();

        emitLiquidityChangeEvent(
            position,
            accountId,
            poolId,
            liquidityDelta,
            sqrtPriceCurrent,
            -vTokenPrincipal,
            -vQuotePrincipal
        );

        int256 vTokenAmountCurrent;
        {
            (vTokenAmountCurrent, ) = position.vTokenAmountsInRange(sqrtPriceCurrent, false);
            balanceAdjustments.traderPositionIncrease += (vTokenAmountCurrent - position.vTokenAmountIn);
        }

        if (liquidityDelta > 0) {
            position.liquidity += uint128(liquidityDelta);
        } else if (liquidityDelta < 0) {
            position.liquidity -= uint128(-liquidityDelta);
        }

        position.vTokenAmountIn = vTokenAmountCurrent + vTokenPrincipal;
    }

    function update(
        LiquidityPosition.Info storage position,
        uint256 accountId,
        uint32 poolId,
        IVPoolWrapper.WrapperValuesInside memory wrapperValuesInside,
        IClearingHouseStructures.BalanceAdjustments memory balanceAdjustments
    ) internal {
        int256 fundingPayment = position.unrealizedFundingPayment(
            wrapperValuesInside.sumAX128,
            wrapperValuesInside.sumFpInsideX128
        );
        balanceAdjustments.vQuoteIncrease += fundingPayment;

        int256 unrealizedLiquidityFee = position.unrealizedFees(wrapperValuesInside.sumFeeInsideX128).toInt256();
        balanceAdjustments.vQuoteIncrease += unrealizedLiquidityFee;

        // updating checkpoints
        position.sumALastX128 = wrapperValuesInside.sumAX128;
        position.sumBInsideLastX128 = wrapperValuesInside.sumBInsideX128;
        position.sumFpInsideLastX128 = wrapperValuesInside.sumFpInsideX128;
        position.sumFeeInsideLastX128 = wrapperValuesInside.sumFeeInsideX128;

        emit Account.LiquidityPositionFundingPaymentRealized(
            accountId,
            poolId,
            position.tickLower,
            position.tickUpper,
            fundingPayment,
            wrapperValuesInside.sumAX128,
            wrapperValuesInside.sumBInsideX128,
            wrapperValuesInside.sumFpInsideX128,
            wrapperValuesInside.sumFeeInsideX128
        );

        emit Account.LiquidityPositionEarningsRealized(
            accountId,
            poolId,
            position.tickLower,
            position.tickUpper,
            unrealizedLiquidityFee
        );
    }

    /**
     *  Internal view methods
     */

    function checkValidLimitOrderRemoval(LiquidityPosition.Info storage info, int24 currentTick) internal view {
        if (
            !((currentTick >= info.tickUpper &&
                info.limitOrderType == IClearingHouseEnums.LimitOrderType.UPPER_LIMIT) ||
                (currentTick <= info.tickLower &&
                    info.limitOrderType == IClearingHouseEnums.LimitOrderType.LOWER_LIMIT))
        ) {
            revert LP_IneligibleLimitOrderRemoval();
        }
    }

    function isInitialized(LiquidityPosition.Info storage info) internal view returns (bool) {
        return info.tickLower != 0 || info.tickUpper != 0;
    }

    function longSideRisk(LiquidityPosition.Info storage position, uint160 valuationPriceX96)
        internal
        view
        returns (uint256)
    {
        uint160 sqrtPriceLowerX96 = TickMath.getSqrtRatioAtTick(position.tickLower);
        uint160 sqrtPriceUpperX96 = TickMath.getSqrtRatioAtTick(position.tickUpper);
        uint256 longPositionExecutionPriceX128;
        {
            uint160 sqrtPriceUpperMinX96 = valuationPriceX96 <= sqrtPriceUpperX96
                ? valuationPriceX96
                : sqrtPriceUpperX96;
            uint160 sqrtPriceLowerMinX96 = valuationPriceX96 <= sqrtPriceLowerX96
                ? valuationPriceX96
                : sqrtPriceLowerX96;
            longPositionExecutionPriceX128 = uint256(sqrtPriceLowerMinX96).mulDiv(sqrtPriceUpperMinX96, 1 << 64);
        }

        uint256 maxNetLongPosition;
        {
            uint256 maxLongTokens = SqrtPriceMath.getAmount0Delta(
                sqrtPriceLowerX96,
                sqrtPriceUpperX96,
                position.liquidity,
                true
            );
            //
            if (position.vTokenAmountIn >= 0) {
                //maxLongTokens in range should always be >= amount that got added to range, equality occurs when range was added at pCurrent = pHigh
                assert(maxLongTokens >= uint256(position.vTokenAmountIn));
                maxNetLongPosition = maxLongTokens - uint256(position.vTokenAmountIn);
            } else maxNetLongPosition = maxLongTokens + uint256(-1 * position.vTokenAmountIn);
        }

        return maxNetLongPosition.mulDiv(longPositionExecutionPriceX128, FixedPoint128.Q128);
    }

    function marketValue(
        LiquidityPosition.Info storage position,
        uint160 valuationSqrtPriceX96,
        IVPoolWrapper wrapper
    ) internal view returns (int256 marketValue_) {
        {
            (int256 vTokenAmount, int256 vQuoteAmount) = position.vTokenAmountsInRange(valuationSqrtPriceX96, false);
            uint256 priceX128 = valuationSqrtPriceX96.toPriceX128();
            marketValue_ = vTokenAmount.mulDiv(priceX128, FixedPoint128.Q128) + vQuoteAmount;
        }
        // adding fees
        IVPoolWrapper.WrapperValuesInside memory wrapperValuesInside = wrapper.getExtrapolatedValuesInside(
            position.tickLower,
            position.tickUpper
        );
        marketValue_ += position.unrealizedFees(wrapperValuesInside.sumFeeInsideX128).toInt256();
        marketValue_ += position.unrealizedFundingPayment(
            wrapperValuesInside.sumAX128,
            wrapperValuesInside.sumFpInsideX128
        );
    }

    function maxNetPosition(LiquidityPosition.Info storage position) internal view returns (uint256) {
        uint160 sqrtPriceLowerX96 = TickMath.getSqrtRatioAtTick(position.tickLower);
        uint160 sqrtPriceUpperX96 = TickMath.getSqrtRatioAtTick(position.tickUpper);

        if (position.vTokenAmountIn >= 0)
            return
                SqrtPriceMath.getAmount0Delta(sqrtPriceLowerX96, sqrtPriceUpperX96, position.liquidity, true) -
                uint256(position.vTokenAmountIn);
        else
            return
                SqrtPriceMath.getAmount0Delta(sqrtPriceLowerX96, sqrtPriceUpperX96, position.liquidity, true) +
                uint256(-1 * position.vTokenAmountIn);
    }

    function netPosition(LiquidityPosition.Info storage position, uint160 sqrtPriceCurrent)
        internal
        view
        returns (int256 netTokenPosition)
    {
        int256 vTokenAmountCurrent;
        (vTokenAmountCurrent, ) = position.vTokenAmountsInRange(sqrtPriceCurrent, false);
        netTokenPosition = (vTokenAmountCurrent - position.vTokenAmountIn);
    }

    function vTokenAmountsInRange(
        LiquidityPosition.Info storage position,
        uint160 sqrtPriceCurrent,
        bool roundUp
    ) internal view returns (int256 vTokenAmount, int256 vQuoteAmount) {
        uint160 sqrtPriceLowerX96 = TickMath.getSqrtRatioAtTick(position.tickLower);
        uint160 sqrtPriceUpperX96 = TickMath.getSqrtRatioAtTick(position.tickUpper);

        // If price is outside the range, then consider it at the ends
        // for calculation of amounts
        uint160 sqrtPriceMiddleX96 = sqrtPriceCurrent;
        if (sqrtPriceCurrent < sqrtPriceLowerX96) {
            sqrtPriceMiddleX96 = sqrtPriceLowerX96;
        } else if (sqrtPriceCurrent > sqrtPriceUpperX96) {
            sqrtPriceMiddleX96 = sqrtPriceUpperX96;
        }

        vTokenAmount = SqrtPriceMath
            .getAmount0Delta(sqrtPriceMiddleX96, sqrtPriceUpperX96, position.liquidity, roundUp)
            .toInt256();
        vQuoteAmount = SqrtPriceMath
            .getAmount1Delta(sqrtPriceLowerX96, sqrtPriceMiddleX96, position.liquidity, roundUp)
            .toInt256();
    }

    function unrealizedFundingPayment(
        LiquidityPosition.Info storage position,
        int256 sumAX128,
        int256 sumFpInsideX128
    ) internal view returns (int256 vQuoteIncrease) {
        vQuoteIncrease = -FundingPayment.bill(
            sumAX128,
            sumFpInsideX128,
            position.sumALastX128,
            position.sumBInsideLastX128,
            position.sumFpInsideLastX128,
            position.liquidity
        );
    }

    function unrealizedFees(LiquidityPosition.Info storage position, uint256 sumFeeInsideX128)
        internal
        view
        returns (uint256 vQuoteIncrease)
    {
        vQuoteIncrease = (sumFeeInsideX128 - position.sumFeeInsideLastX128).mulDiv(
            position.liquidity,
            FixedPoint128.Q128
        );
    }

    function emitLiquidityChangeEvent(
        LiquidityPosition.Info storage position,
        uint256 accountId,
        uint32 poolId,
        int128 liquidityDelta,
        uint160 sqrtPriceX96,
        int256 vTokenAmountOut,
        int256 vQuoteAmountOut
    ) internal {
        emit Account.LiquidityChanged(
            accountId,
            poolId,
            position.tickLower,
            position.tickUpper,
            liquidityDelta,
            position.limitOrderType,
            vTokenAmountOut,
            vQuoteAmountOut,
            sqrtPriceX96
        );
    }
}
