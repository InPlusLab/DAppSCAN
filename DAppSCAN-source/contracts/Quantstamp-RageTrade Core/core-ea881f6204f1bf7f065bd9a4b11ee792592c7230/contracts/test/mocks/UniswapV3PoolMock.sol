// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

contract UniswapV3PoolMock {
    struct Tick {
        uint128 liquidityGross;
        int128 liquidityNet;
        uint256 feeGrowthOutside0X128;
        uint256 feeGrowthOutside1X128;
        int56 tickCumulativeOutside;
        uint160 secondsPerLiquidityOutsideX128;
        uint32 secondsOutside;
        bool initialized;
    }

    mapping(int24 => Tick) public ticks;

    function setTick(
        int24 tick,
        uint128 liquidityGross,
        int128 liquidityNet,
        uint256 feeGrowthOutside0X128,
        uint256 feeGrowthOutside1X128,
        int56 tickCumulativeOutside,
        uint160 secondsPerLiquidityOutsideX128,
        uint32 secondsOutside,
        bool initialized
    ) external {
        ticks[tick].liquidityGross = liquidityGross;
        ticks[tick].liquidityNet = liquidityNet;
        ticks[tick].feeGrowthOutside0X128 = feeGrowthOutside0X128;
        ticks[tick].feeGrowthOutside1X128 = feeGrowthOutside1X128;
        ticks[tick].tickCumulativeOutside = tickCumulativeOutside;
        ticks[tick].secondsPerLiquidityOutsideX128 = secondsPerLiquidityOutsideX128;
        ticks[tick].secondsOutside = secondsOutside;
        ticks[tick].initialized = initialized;
    }

    uint256 public feeGrowthGlobal0X128;
    uint256 public feeGrowthGlobal1X128;

    function setFeeGrowth(uint256 _feeGrowthGlobal0X128, uint256 _feeGrowthGlobal1X128) external {
        feeGrowthGlobal0X128 = _feeGrowthGlobal0X128;
        feeGrowthGlobal1X128 = _feeGrowthGlobal1X128;
    }
}
