// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

import "ds-test/test.sol";

import "./Volatility.sol";

contract VolatilityFake {
    function estimate24H(
        Volatility.PoolMetadata memory metadata,
        Volatility.PoolData memory data,
        Volatility.FeeGrowthGlobals memory a,
        Volatility.FeeGrowthGlobals memory b
    ) external pure returns (uint256) {
        return Volatility.estimate24H(metadata, data, a, b);
    }
}

contract VolatilityTest is DSTest {
    VolatilityFake volatility;

    function setUp() public {
        volatility = new VolatilityFake();
    }

    function test_pure_estimateIV1() public {
        Volatility.PoolMetadata memory metadata = Volatility.PoolMetadata(3600, 3000, 3000, 60);
        Volatility.PoolData memory data = Volatility.PoolData(
            1278673744380353403099539498152303, // sqrtPriceX96
            193789, // currentTick
            193730, // arithmeticMeanTick
            44521837137365694357186, // _secondsPerLiquidityX128
            3600, // _oracleLookback
            19685271204911047580 // poolLiquidity
        );
        uint256 dailyIV = volatility.estimate24H(
            metadata,
            data,
            Volatility.FeeGrowthGlobals(
                1501955347902231987349614320458936,
                527278396421895291380335427321388844898052,
                0
            ),
            Volatility.FeeGrowthGlobals(
                1501968291161650295867029090958139,
                527315901327546020416261134123578344760082,
                8640
            )
        );

        assertEq(dailyIV, 20405953567249984); // 2.041%
    }

    // TODO

    // function test_pure_computeGammaTPositionRevenue(
    //     int24 _arithmeticMeanTick,
    //     uint16 _gamma0,
    //     uint16 _gamma1,
    //     uint128 _tokensOwed0,
    //     uint128 _tokensOwed1
    // ) public {
    //     if (_arithmeticMeanTick < TickMath.MIN_TICK) _arithmeticMeanTick = TickMath.MIN_TICK;
    //     if (_arithmeticMeanTick > TickMath.MAX_TICK) _arithmeticMeanTick = TickMath.MAX_TICK;

    //     // Ensure it doesn't revert
    //     uint256 positionRevenue = oracleExposed.exposed_computeGammaTPositionRevenue(
    //         _arithmeticMeanTick,
    //         _gamma0,
    //         _gamma1,
    //         _tokensOwed0,
    //         _tokensOwed1
    //     );

    //     // Check that it's non-zero in cases where we don't expect truncation
    //     int24 lowerBound = TickMath.MIN_TICK / 2;
    //     int24 upperBound = TickMath.MAX_TICK / 2;
    //     if (
    //         (lowerBound < _arithmeticMeanTick && _arithmeticMeanTick < upperBound) &&
    //         (_tokensOwed0 != 0 || _tokensOwed1 != 0)
    //     ) assertGt(positionRevenue, 0);
    // }

    // function test_pure_computeSqrtPoolRevenue(
    //     uint256 _positionRevenue,
    //     uint128 _positionLiquidity,
    //     uint128 _harmonicMeanLiquidity
    // ) public {
    //     if (_positionLiquidity == 0) return;

    //     uint128 sqrtPoolRevenue = oracleExposed.exposed_computeSqrtPoolRevenue(
    //         _positionRevenue,
    //         _positionLiquidity,
    //         _harmonicMeanLiquidity
    //     );

    //     uint256 ratio = (10 * uint256(_harmonicMeanLiquidity)) / _positionLiquidity;
    //     if (_positionRevenue != 0 && ratio > 1) assertGt(sqrtPoolRevenue, 0);
    // }

    // function test_pure_computeTickTVL(
    //     int24 currentTick,
    //     uint8 tickSpacing,
    //     uint128 tickLiquidity
    // ) public {
    //     if (tickSpacing == 0) return; // Always true in the real world
    //     int24 _tickSpacing = int24(uint24(tickSpacing));

    //     if (currentTick < TickMath.MIN_TICK) currentTick = TickMath.MIN_TICK + _tickSpacing;
    //     if (currentTick > TickMath.MAX_TICK) currentTick = TickMath.MAX_TICK - _tickSpacing;
    //     uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(currentTick);

    //     // Ensure it doesn't revert
    //     uint256 tickTVL = Volatility.computeTickTVLX64(_tickSpacing, currentTick, sqrtPriceX96, tickLiquidity);

    //     // Check that it's non-zero in cases where we don't expect truncation
    //     int24 lowerBound = TickMath.MIN_TICK / 2;
    //     int24 upperBound = TickMath.MAX_TICK / 2;
    //     if (tickLiquidity > 1_000_000 && currentTick < lowerBound && currentTick > upperBound) assertGt(tickTVL, 0);
    // }
}
