// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { IUniswapV3Pool } from '@uniswap/v3-core-0.8-support/contracts/interfaces/IUniswapV3Pool.sol';

import { FundingPayment } from '../libraries/FundingPayment.sol';
import { TickExtended } from '../libraries/TickExtended.sol';

import { IVToken } from '../interfaces/IVToken.sol';

import { UniswapV3PoolMock } from './mocks/UniswapV3PoolMock.sol';

contract TickExtendedTest {
    using FundingPayment for FundingPayment.Info;
    using TickExtended for mapping(int24 => TickExtended.Info);
    using TickExtended for IUniswapV3Pool;

    mapping(int24 => TickExtended.Info) public ticksExtended;

    FundingPayment.Info public fpGlobal;
    uint256 public sumFeeGlobalX128;

    int256 fundingRateOverrideX128 = type(int256).max;

    IUniswapV3Pool public vPool;

    constructor() {
        vPool = IUniswapV3Pool(address(new UniswapV3PoolMock()));
    }

    function setTick(int24 tickIndex, TickExtended.Info memory tick) external {
        ticksExtended[tickIndex] = tick;
    }

    function setFpGlobal(FundingPayment.Info calldata fpGlobal_) external {
        fpGlobal = fpGlobal_;
    }

    function setFeeGrowthOutsideX128(uint256 _extendedFeeGrowthOutsideX128) external {
        sumFeeGlobalX128 = _extendedFeeGrowthOutsideX128;
    }

    function getNetPositionInside(
        int24 tickLower,
        int24 tickUpper,
        int24 tickCurrent
    ) public view returns (int256 netPositionGrowthX128) {
        (netPositionGrowthX128, , ) = ticksExtended.getTickExtendedStateInside(
            tickLower,
            tickUpper,
            tickCurrent,
            fpGlobal,
            sumFeeGlobalX128
        );
    }

    function getFundingPaymentGrowthInside(
        int24 tickLower,
        int24 tickUpper,
        int24 tickCurrent
    ) public view returns (int256 fundingPaymentGrowth) {
        (, fundingPaymentGrowth, ) = ticksExtended.getTickExtendedStateInside(
            tickLower,
            tickUpper,
            tickCurrent,
            fpGlobal,
            sumFeeGlobalX128
        );
    }

    function getFeeGrowthInside(
        int24 tickLower,
        int24 tickUpper,
        int24 tickCurrent
    ) public view returns (uint256 extendedFeeGrowthInside) {
        (, , extendedFeeGrowthInside) = ticksExtended.getTickExtendedStateInside(
            tickLower,
            tickUpper,
            tickCurrent,
            fpGlobal,
            sumFeeGlobalX128
        );
    }

    function registerTrade(
        int256 vTokenAmount,
        uint256 liquidity,
        uint48 blockTimestamp,
        uint256 virtualPriceX128,
        int256 fundingRateX128
    ) public {
        fpGlobal.update(vTokenAmount, liquidity, blockTimestamp, fundingRateX128, virtualPriceX128);
    }

    function cross(int24 tickNext) external {
        ticksExtended.cross(tickNext, fpGlobal, sumFeeGlobalX128);
    }
}
