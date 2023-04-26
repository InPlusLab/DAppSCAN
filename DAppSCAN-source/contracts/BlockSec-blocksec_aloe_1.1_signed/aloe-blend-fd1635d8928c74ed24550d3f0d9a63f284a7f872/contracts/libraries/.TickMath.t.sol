// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

import "ds-test/test.sol";

import "./TickMath.sol";

contract TickMathFake {
    function floor(int24 tick, int24 tickSpacing) external pure returns (int24) {
        return TickMath.floor(tick, tickSpacing);
    }

    function ceil(int24 tick, int24 tickSpacing) external pure returns (int24) {
        return TickMath.ceil(tick, tickSpacing);
    }
}

contract TickMathTest is DSTest {
    TickMathFake tickMath;

    function setUp() public {
        tickMath = new TickMathFake();
    }

    function test_floor(int24 tick, uint8 tickSpacing) public {
        if (tick > TickMath.MAX_TICK || tick < TickMath.MIN_TICK) return;
        if (tickSpacing == 0) return;
        int24 _tickSpacing = int24(uint24(tickSpacing));

        int24 flooredTick = tickMath.floor(tick, _tickSpacing);

        assertEq(flooredTick % _tickSpacing, 0);
        assertLe(flooredTick, tick);
    }

    function test_spec_floor() public {
        assertEq(tickMath.floor(10, 10), 10);
        assertEq(tickMath.floor(9, 10), 0);
        assertEq(tickMath.floor(1, 10), 0);
        assertEq(tickMath.floor(0, 10), 0);
        assertEq(tickMath.floor(-1, 10), -10);
        assertEq(tickMath.floor(-9, 10), -10);
        assertEq(tickMath.floor(-10, 10), -10);
        assertEq(tickMath.floor(-11, 10), -20);

        assertEq(tickMath.floor(3, 1), 3);
        assertEq(tickMath.floor(-3, 1), -3);
    }

    function test_ceil(int24 tick, uint8 tickSpacing) public {
        if (tick > TickMath.MAX_TICK || tick < TickMath.MIN_TICK) return;
        if (tickSpacing == 0) return;
        int24 _tickSpacing = int24(uint24(tickSpacing));

        int24 flooredTick = tickMath.ceil(tick, _tickSpacing);

        assertEq(flooredTick % _tickSpacing, 0);
        assertGe(flooredTick, tick);
    }

    function test_spec_ceil() public {
        assertEq(tickMath.ceil(11, 10), 20);
        assertEq(tickMath.ceil(10, 10), 10);
        assertEq(tickMath.ceil(1, 10), 10);
        assertEq(tickMath.ceil(0, 10), 0);
        assertEq(tickMath.ceil(-1, 10), 0);
        assertEq(tickMath.ceil(-9, 10), 0);
        assertEq(tickMath.ceil(-10, 10), -10);
        assertEq(tickMath.ceil(-11, 10), -10);

        assertEq(tickMath.ceil(3, 1), 3);
        assertEq(tickMath.ceil(-3, 1), -3);
    }
}
