// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.9;

import { Initializable } from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';

import { IUniswapV3Pool } from '@uniswap/v3-core-0.8-support/contracts/interfaces/IUniswapV3Pool.sol';
import { IUniswapV3MintCallback } from '@uniswap/v3-core-0.8-support/contracts/interfaces/callback/IUniswapV3MintCallback.sol';
import { IUniswapV3SwapCallback } from '@uniswap/v3-core-0.8-support/contracts/interfaces/callback/IUniswapV3SwapCallback.sol';
import { FixedPoint128 } from '@uniswap/v3-core-0.8-support/contracts/libraries/FixedPoint128.sol';
import { FullMath } from '@uniswap/v3-core-0.8-support/contracts/libraries/FullMath.sol';
import { TickMath } from '@uniswap/v3-core-0.8-support/contracts/libraries/TickMath.sol';

import { IVPoolWrapper } from '../../interfaces/IVPoolWrapper.sol';
import { IVQuote } from '../../interfaces/IVQuote.sol';
import { IVToken } from '../../interfaces/IVToken.sol';
import { IVToken } from '../../interfaces/IVToken.sol';
import { IClearingHouse } from '../../interfaces/IClearingHouse.sol';
import { IClearingHouseStructures } from '../../interfaces/clearinghouse/IClearingHouseStructures.sol';

import { AddressHelper } from '../../libraries/AddressHelper.sol';
import { FundingPayment } from '../../libraries/FundingPayment.sol';
import { SimulateSwap } from '../../libraries/SimulateSwap.sol';
import { TickExtended } from '../../libraries/TickExtended.sol';
import { PriceMath } from '../../libraries/PriceMath.sol';
import { SafeCast } from '../../libraries/SafeCast.sol';
import { SignedMath } from '../../libraries/SignedMath.sol';
import { SignedFullMath } from '../../libraries/SignedFullMath.sol';
import { SwapMath } from '../../libraries/SwapMath.sol';
import { UniswapV3PoolHelper } from '../../libraries/UniswapV3PoolHelper.sol';

import { Extsload } from '../../utils/Extsload.sol';

import { UNISWAP_V3_DEFAULT_TICKSPACING, UNISWAP_V3_DEFAULT_FEE_TIER } from '../../utils/constants.sol';

contract VPoolWrapper is IVPoolWrapper, IUniswapV3MintCallback, IUniswapV3SwapCallback, Initializable, Extsload {
    using AddressHelper for IVToken;
    using FullMath for uint256;
    using FundingPayment for FundingPayment.Info;
    using SignedMath for int256;
    using SignedFullMath for int256;
    using PriceMath for uint160;
    using SafeCast for uint256;
    using SafeCast for uint128;
    using SimulateSwap for IUniswapV3Pool;
    using TickExtended for IUniswapV3Pool;
    using TickExtended for mapping(int24 => TickExtended.Info);
    using UniswapV3PoolHelper for IUniswapV3Pool;

    IClearingHouse public clearingHouse;
    IVToken public vToken;
    IVQuote public vQuote;
    IUniswapV3Pool public vPool;

    // fee paid to liquidity providers, in 1e6
    uint24 public liquidityFeePips;
    // fee paid to DAO treasury
    uint24 public protocolFeePips;

    uint256 public accruedProtocolFee;

    FundingPayment.Info public fpGlobal;
    uint256 public sumFeeGlobalX128;

    int256 constant FUNDING_RATE_OVERRIDE_NULL_VALUE = type(int256).max;
    int256 public fundingRateOverrideX128;

    mapping(int24 => TickExtended.Info) public ticksExtended;

    error NotClearingHouse();
    error NotGovernance();
    error NotUniswapV3Pool();
    error InvalidTicks(int24 tickLower, int24 tickUpper);

    modifier onlyClearingHouse() {
        if (msg.sender != address(clearingHouse)) {
            revert NotClearingHouse();
        }
        _;
    }

    modifier onlyGovernance() {
        if (msg.sender != clearingHouse.governance()) {
            revert NotGovernance();
        }
        _;
    }

    modifier onlyUniswapV3Pool() {
        if (msg.sender != address(vPool)) {
            revert NotUniswapV3Pool();
        }
        _;
    }

    modifier checkTicks(int24 tickLower, int24 tickUpper) {
        if (
            tickLower >= tickUpper ||
            tickLower < TickMath.MIN_TICK ||
            tickUpper > TickMath.MAX_TICK ||
            tickLower % UNISWAP_V3_DEFAULT_TICKSPACING != 0 ||
            tickUpper % UNISWAP_V3_DEFAULT_TICKSPACING != 0
        ) revert InvalidTicks(tickLower, tickUpper);
        _;
    }

    /**
        PLATFORM FUNCTIONS
     */

    function initialize(InitializeVPoolWrapperParams calldata params) external initializer {
        clearingHouse = params.clearingHouse;
        vToken = params.vToken;
        vQuote = params.vQuote;
        vPool = params.vPool;

        liquidityFeePips = params.liquidityFeePips;
        protocolFeePips = params.protocolFeePips;

        fundingRateOverrideX128 = type(int256).max;

        // initializes the funding payment state by zeroing the funding payment for time 0 to blockTimestamp
        fpGlobal.update({
            vTokenAmount: 0,
            liquidity: 1,
            blockTimestamp: _blockTimestamp(),
            virtualPriceX128: 1,
            fundingRateX128: 0 // causes zero funding payment
        });
    }

    function collectAccruedProtocolFee() external onlyClearingHouse returns (uint256 accruedProtocolFeeLast) {
        accruedProtocolFeeLast = accruedProtocolFee - 1;
        accruedProtocolFee = 1;
        emit AccruedProtocolFeeCollected(accruedProtocolFeeLast);
    }

    /// @notice Update the global funding state, from clearing house
    /// @dev Done when clearing house is paused or unpaused, to prevent funding payments from being received
    ///     or paid when clearing house is in paused mode.
    function updateGlobalFundingState(bool useZeroFundingRate) public onlyClearingHouse {
        (int256 fundingRateX128, uint256 virtualPriceX128) = getFundingRateAndVirtualPrice();
        fpGlobal.update({
            vTokenAmount: 0,
            liquidity: 1,
            blockTimestamp: _blockTimestamp(),
            virtualPriceX128: virtualPriceX128,
            fundingRateX128: useZeroFundingRate ? int256(0) : fundingRateX128
        });
    }

    /**
        ADMIN FUNCTIONS
     */

    function setLiquidityFee(uint24 liquidityFeePips_) external onlyGovernance {
        liquidityFeePips = liquidityFeePips_;
        emit LiquidityFeeUpdated(liquidityFeePips_);
    }

    function setProtocolFee(uint24 protocolFeePips_) external onlyGovernance {
        protocolFeePips = protocolFeePips_;
        emit ProtocolFeeUpdated(protocolFeePips_);
    }

    function setFundingRateOverride(int256 fundingRateOverrideX128_) external onlyGovernance {
        fundingRateOverrideX128 = fundingRateOverrideX128_;
        emit FundingRateOverrideUpdated(fundingRateOverrideX128_);
    }

    /**
        EXTERNAL UTILITY METHODS
     */

    /// @notice Swap vToken for vQuote, or vQuote for vToken
    /// @param swapVTokenForVQuote: The direction of the swap, true for vToken to vQuote, false for vQuote to vToken
    /// @param amountSpecified: The amount of the swap, which implicitly configures the swap as exact input (positive), or exact output (negative)
    /// @param sqrtPriceLimitX96: The Q64.96 sqrt price limit. If zero for one, the price cannot be less than this
    /// value after the swap. If one for zero, the price cannot be greater than this value after the swap.
    /// @return swapResult swap return values, which contain the execution details of the swap
    function swap(
        bool swapVTokenForVQuote, // zeroForOne
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96
    ) public onlyClearingHouse returns (SwapResult memory swapResult) {
        bool exactIn = amountSpecified >= 0;

        if (sqrtPriceLimitX96 == 0) {
            sqrtPriceLimitX96 = swapVTokenForVQuote ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1;
        }

        swapResult.amountSpecified = amountSpecified;

        SwapMath.beforeSwap(
            exactIn,
            swapVTokenForVQuote,
            UNISWAP_V3_DEFAULT_FEE_TIER,
            liquidityFeePips,
            protocolFeePips,
            swapResult
        );

        {
            SimulateSwap.Cache memory cache;
            cache.tickSpacing = UNISWAP_V3_DEFAULT_TICKSPACING;
            cache.fee = UNISWAP_V3_DEFAULT_FEE_TIER;
            (int256 fundingRateX128, uint256 virtualPriceX128) = getFundingRateAndVirtualPrice();
            _writeCacheExtraValues(cache, virtualPriceX128, fundingRateX128);

            // simulate swap and update our tick states
            (int256 vTokenIn_simulated, int256 vQuoteIn_simulated, SimulateSwap.State memory state) = vPool
                .simulateSwap(swapVTokenForVQuote, swapResult.amountSpecified, sqrtPriceLimitX96, cache, _onSwapStep);

            // store prices for the simulated swap in the swap result
            swapResult.sqrtPriceX96Start = cache.sqrtPriceX96Start;
            swapResult.sqrtPriceX96End = state.sqrtPriceX96;

            // execute actual swap on uniswap
            (swapResult.vTokenIn, swapResult.vQuoteIn) = vPool.swap(
                address(this),
                swapVTokenForVQuote,
                swapResult.amountSpecified,
                sqrtPriceLimitX96,
                ''
            );

            // simulated swap should be identical to actual swap
            assert(vTokenIn_simulated == swapResult.vTokenIn && vQuoteIn_simulated == swapResult.vQuoteIn);
        }

        SwapMath.afterSwap(
            exactIn,
            swapVTokenForVQuote,
            UNISWAP_V3_DEFAULT_FEE_TIER,
            liquidityFeePips,
            protocolFeePips,
            swapResult
        );

        // record the protocol fee, for withdrawal in future
        accruedProtocolFee += swapResult.protocolFees;

        // burn the tokens received from the swap
        _vBurn();

        emit Swap(swapResult);
    }

    function mint(
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    )
        external
        onlyClearingHouse
        checkTicks(tickLower, tickUpper)
        returns (
            uint256 vTokenPrincipal,
            uint256 vQuotePrincipal,
            WrapperValuesInside memory wrapperValuesInside
        )
    {
        // records the funding payment for last updated timestamp to blockTimestamp using current price difference
        _updateGlobalFundingState();

        wrapperValuesInside = _updateTicks(tickLower, tickUpper, liquidity.toInt128(), vPool.tickCurrent());

        (uint256 _amount0, uint256 _amount1) = vPool.mint({
            recipient: address(this),
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount: liquidity,
            data: ''
        });

        vTokenPrincipal = _amount0;
        vQuotePrincipal = _amount1;
    }

    function burn(
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    )
        external
        onlyClearingHouse
        checkTicks(tickLower, tickUpper)
        returns (
            uint256 vTokenPrincipal,
            uint256 vQuotePrincipal,
            WrapperValuesInside memory wrapperValuesInside
        )
    {
        // records the funding payment for last updated timestamp to blockTimestamp using current price difference
        _updateGlobalFundingState();

        wrapperValuesInside = _updateTicks(tickLower, tickUpper, -liquidity.toInt128(), vPool.tickCurrent());

        (uint256 _amount0, uint256 _amount1) = vPool.burn({
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount: liquidity
        });

        vTokenPrincipal = _amount0;
        vQuotePrincipal = _amount1;
        _collect(tickLower, tickUpper);
    }

    /**
        UNISWAP V3 POOL CALLBACkS
     */

    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata
    ) external virtual onlyUniswapV3Pool {
        if (amount0Delta > 0) {
            IVToken(vPool.token0()).mint(address(vPool), uint256(amount0Delta));
        }
        if (amount1Delta > 0) {
            IVToken(vPool.token1()).mint(address(vPool), uint256(amount1Delta));
        }
    }

    function uniswapV3MintCallback(
        uint256 vTokenAmount,
        uint256 vQuoteAmount,
        bytes calldata
    ) external override onlyUniswapV3Pool {
        if (vQuoteAmount > 0) vQuote.mint(msg.sender, vQuoteAmount);
        if (vTokenAmount > 0) vToken.mint(msg.sender, vTokenAmount);
    }

    /**
        VIEW METHODS
     */

    function getFundingRateAndVirtualPrice() public view returns (int256 fundingRateX128, uint256 virtualPriceX128) {
        int256 _fundingRateOverrideX128 = fundingRateOverrideX128;
        bool shouldUseActualPrices = _fundingRateOverrideX128 == FUNDING_RATE_OVERRIDE_NULL_VALUE;

        uint32 poolId = vToken.truncate();
        virtualPriceX128 = clearingHouse.getVirtualTwapPriceX128(poolId);

        if (shouldUseActualPrices) {
            // uses actual price to calculate funding rate
            uint256 realPriceX128 = clearingHouse.getRealTwapPriceX128(poolId);
            fundingRateX128 = FundingPayment.getFundingRate(realPriceX128, virtualPriceX128);
        } else {
            // uses funding rate override
            fundingRateX128 = _fundingRateOverrideX128;
        }
    }

    function getSumAX128() external view returns (int256) {
        return fpGlobal.sumAX128;
    }

    function getExtrapolatedSumAX128() public view returns (int256) {
        (int256 fundingRateX128, uint256 virtualPriceX128) = getFundingRateAndVirtualPrice();
        return
            FundingPayment.extrapolatedSumAX128(
                fpGlobal.sumAX128,
                fpGlobal.timestampLast,
                _blockTimestamp(),
                fundingRateX128,
                virtualPriceX128
            );
    }

    function getValuesInside(int24 tickLower, int24 tickUpper)
        public
        view
        checkTicks(tickLower, tickUpper)
        returns (WrapperValuesInside memory wrapperValuesInside)
    {
        (, int24 currentTick, , , , , ) = vPool.slot0();
        FundingPayment.Info memory _fpGlobal = fpGlobal;
        wrapperValuesInside.sumAX128 = _fpGlobal.sumAX128;
        (
            wrapperValuesInside.sumBInsideX128,
            wrapperValuesInside.sumFpInsideX128,
            wrapperValuesInside.sumFeeInsideX128
        ) = ticksExtended.getTickExtendedStateInside(tickLower, tickUpper, currentTick, _fpGlobal, sumFeeGlobalX128);
    }

    function getExtrapolatedValuesInside(int24 tickLower, int24 tickUpper)
        external
        view
        returns (WrapperValuesInside memory wrapperValuesInside)
    {
        (, int24 currentTick, , , , , ) = vPool.slot0();
        FundingPayment.Info memory _fpGlobal = fpGlobal;

        ///@dev update sumA and sumFP to extrapolated values according to current timestamp
        _fpGlobal.sumAX128 = getExtrapolatedSumAX128();
        _fpGlobal.sumFpX128 = FundingPayment.extrapolatedSumFpX128(
            fpGlobal.sumAX128,
            fpGlobal.sumBX128,
            fpGlobal.sumFpX128,
            _fpGlobal.sumAX128
        );

        wrapperValuesInside.sumAX128 = _fpGlobal.sumAX128;
        (
            wrapperValuesInside.sumBInsideX128,
            wrapperValuesInside.sumFpInsideX128,
            wrapperValuesInside.sumFeeInsideX128
        ) = ticksExtended.getTickExtendedStateInside(tickLower, tickUpper, currentTick, _fpGlobal, sumFeeGlobalX128);
    }

    /**
        INTERNAL HELPERS
     */

    function _collect(int24 tickLower, int24 tickUpper) internal {
        // (uint256 amount0, uint256 amount1) =
        vPool.collect({
            recipient: address(this),
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Requested: type(uint128).max,
            amount1Requested: type(uint128).max
        });

        _vBurn();
    }

    function _readCacheExtraValues(SimulateSwap.Cache memory cache)
        private
        pure
        returns (uint256 virtualPriceX128, int256 fundingRateX128)
    {
        uint256 value1 = cache.value1;
        uint256 value2 = cache.value2;
        assembly {
            virtualPriceX128 := value1
            fundingRateX128 := value2
        }
    }

    function _writeCacheExtraValues(
        SimulateSwap.Cache memory cache,
        uint256 virtualPriceX128,
        int256 fundingRateX128
    ) private pure {
        uint256 value1;
        uint256 value2;
        assembly {
            value1 := virtualPriceX128
            value2 := fundingRateX128
        }
        cache.value1 = value1;
        cache.value2 = value2;
    }

    function _onSwapStep(
        bool swapVTokenForVQuote,
        SimulateSwap.Cache memory cache,
        SimulateSwap.State memory state,
        SimulateSwap.Step memory step
    ) internal {
        // these vQuote and vToken amounts are zero fee swap amounts (fee collected by uniswaop is ignored and burned later)
        (uint256 vTokenAmount, uint256 vQuoteAmount) = swapVTokenForVQuote
            ? (step.amountIn, step.amountOut)
            : (step.amountOut, step.amountIn);

        // here, vQuoteAmount == swap amount
        (uint256 liquidityFees, ) = SwapMath.calculateFees(
            vQuoteAmount.toInt256(),
            SwapMath.AmountTypeEnum.ZERO_FEE_VQUOTE_AMOUNT,
            liquidityFeePips,
            protocolFeePips
        );

        // vQuote amount with fees
        // vQuoteAmount = _includeFees(
        //     vQuoteAmount,
        //     liquidityFees + protocolFees,
        //     swapVTokenForVQuote ? IncludeFeeEnum.SUBTRACT_FEE : IncludeFeeEnum.ADD_FEE
        // );

        if (state.liquidity > 0 && vTokenAmount > 0) {
            (uint256 virtualPriceX128, int256 fundingRateX128) = _readCacheExtraValues(cache);
            fpGlobal.update({
                vTokenAmount: swapVTokenForVQuote ? vTokenAmount.toInt256() : -vTokenAmount.toInt256(), // when trader goes long, LP goes short
                liquidity: state.liquidity,
                blockTimestamp: _blockTimestamp(),
                virtualPriceX128: virtualPriceX128,
                fundingRateX128: fundingRateX128
            });

            sumFeeGlobalX128 += liquidityFees.mulDiv(FixedPoint128.Q128, state.liquidity);
        }

        // if we have reached the end price of tick
        if (state.sqrtPriceX96 == step.sqrtPriceNextX96) {
            // if the tick is initialized, run the tick transition
            if (step.initialized) {
                ticksExtended.cross(step.tickNext, fpGlobal, sumFeeGlobalX128);
            }
        }
    }

    /// @notice Update global funding payment, by getting prices from Clearing House
    function _updateGlobalFundingState() internal {
        (int256 fundingRateX128, uint256 virtualPriceX128) = getFundingRateAndVirtualPrice();
        fpGlobal.update({
            vTokenAmount: 0,
            liquidity: 1,
            blockTimestamp: _blockTimestamp(),
            virtualPriceX128: virtualPriceX128,
            fundingRateX128: fundingRateX128
        });
    }

    function _updateTicks(
        int24 tickLower,
        int24 tickUpper,
        int128 liquidityDelta,
        int24 tickCurrent
    ) private returns (WrapperValuesInside memory wrapperValuesInside) {
        FundingPayment.Info memory _fpGlobal = fpGlobal; // SLOAD
        uint256 _sumFeeGlobalX128 = sumFeeGlobalX128;

        // if we need to update the ticks, do it
        bool flippedLower;
        bool flippedUpper;
        if (liquidityDelta != 0) {
            flippedLower = ticksExtended.update(
                tickLower,
                tickCurrent,
                liquidityDelta,
                _fpGlobal.sumAX128,
                _fpGlobal.sumBX128,
                _fpGlobal.sumFpX128,
                _sumFeeGlobalX128,
                vPool
            );
            flippedUpper = ticksExtended.update(
                tickUpper,
                tickCurrent,
                liquidityDelta,
                _fpGlobal.sumAX128,
                _fpGlobal.sumBX128,
                _fpGlobal.sumFpX128,
                _sumFeeGlobalX128,
                vPool
            );
        }

        wrapperValuesInside = getValuesInside(tickLower, tickUpper);

        // clear any tick data that is no longer needed
        if (liquidityDelta < 0) {
            if (flippedLower) {
                ticksExtended.clear(tickLower);
            }
            if (flippedUpper) {
                ticksExtended.clear(tickUpper);
            }
        }
    }

    function _vBurn() internal {
        uint256 vQuoteBal = vQuote.balanceOf(address(this));
        if (vQuoteBal > 0) {
            vQuote.burn(vQuoteBal);
        }
        uint256 vTokenBal = vToken.balanceOf(address(this));
        if (vTokenBal > 0) {
            vToken.burn(vTokenBal);
        }
    }

    // used to set time in tests
    function _blockTimestamp() internal view virtual returns (uint48) {
        return uint48(block.timestamp);
    }
}
