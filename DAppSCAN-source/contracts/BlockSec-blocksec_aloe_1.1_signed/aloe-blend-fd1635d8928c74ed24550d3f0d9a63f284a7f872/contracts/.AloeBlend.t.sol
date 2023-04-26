// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

import "ds-test/test.sol";

import "./AloeBlend.sol";

contract AloeBlendFake is AloeBlend {
    constructor(
        IUniswapV3Pool _uniPool,
        ISilo _silo0,
        ISilo _silo1
    ) AloeBlend(_uniPool, _silo0, _silo1) {}

    function computeNextPositionWidth(uint256 IV) external pure returns (uint24 width) {
        width = _computeNextPositionWidth(IV);
    }

    function computeAmountsForPrimary(
        uint256 inventory0,
        uint256 inventory1,
        uint224 priceX96,
        uint24 halfWidth
    )
        external
        pure
        returns (
            uint256,
            uint256,
            uint96
        )
    {
        return _computeAmountsForPrimary(inventory0, inventory1, priceX96, halfWidth);
    }
}

contract VolatilityOracleFake is IVolatilityOracle {
    function cachedPoolMetadata(address)
        external
        pure
        returns (
            uint32,
            uint24,
            uint24,
            int24
        )
    {
        return (1 hours, 0, 0, 0);
    }

    function estimate24H(
        IUniswapV3Pool,
        uint160,
        int24
    ) external pure returns (uint256 IV) {
        return 2e18;
    }
}

contract FactoryFake {
    IVolatilityOracle public immutable VOLATILITY_ORACLE;

    constructor(IVolatilityOracle _volatilityOracle) {
        VOLATILITY_ORACLE = _volatilityOracle;
    }

    function create(
        IUniswapV3Pool _uniPool,
        ISilo _silo0,
        ISilo _silo1
    ) external returns (AloeBlendFake) {
        return new AloeBlendFake(_uniPool, _silo0, _silo1);
    }
}

contract AloeBlendTest is DSTest {
    AloeBlendFake blend;

    function setUp() public {
        IVolatilityOracle oracle = new VolatilityOracleFake();
        FactoryFake factory = new FactoryFake(oracle);
        blend = factory.create(
            IUniswapV3Pool(0xF1B63cD9d80f922514c04b0fD0a30373316dd75b),
            ISilo(0x8E35ec3f2C8e14bf7A0E67eA6667F6965938aD2d),
            ISilo(0x908f6DF3df3c25365172F350670d055541Ec362E)
        );
    }

    function test_computeNextPositionWidth(uint256 IV) public {
        uint24 width = blend.computeNextPositionWidth(IV);

        assertGe(width, blend.MIN_WIDTH());
        assertLe(width, blend.MAX_WIDTH());
    }

    function test_spec_computeNextPositionWidth() public {
        assertEq(blend.computeNextPositionWidth(5e15), 201);
        assertEq(blend.computeNextPositionWidth(1e17), 4054);
        assertEq(blend.computeNextPositionWidth(2e17), 8473);
        assertEq(blend.computeNextPositionWidth(4e17), 13864);
    }

    function test_computeAmountsForPrimary(
        uint128 inventory0,
        uint128 inventory1,
        uint224 priceX96,
        uint24 halfWidth
    ) public {
        if (halfWidth < blend.MIN_WIDTH() / 2) return;
        if (halfWidth > blend.MAX_WIDTH() / 2) return;

        (uint256 amount0, uint256 amount1, uint96 magic) = blend.computeAmountsForPrimary(
            inventory0,
            inventory1,
            priceX96,
            halfWidth
        );

        assertLt(amount0, inventory0);
        assertLt(amount1, inventory1);
        assertLt(magic, 2**96);
    }

    function test_spec_computeAmountsForPrimary() public {
        uint256 amount0;
        uint256 amount1;
        uint96 magic;

        (amount0, amount1, magic) = blend.computeAmountsForPrimary(0, 0, 100000, blend.MIN_WIDTH());
        assertEq(amount0, 0);
        assertEq(amount1, 0);
        assertEq(magic, 792215870747104703836069196);

        (amount0, amount1, magic) = blend.computeAmountsForPrimary(1111111, 2222222, 2 * 2**96, blend.MAX_WIDTH());
        assertEq(amount0, 555565);
        assertEq(amount1, 1111130);
        assertEq(magic, 39614800711660855234216192339);
    }
}
