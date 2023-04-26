// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

interface IVolatilityOracle {
    function cachedPoolMetadata(address)
        external
        view
        returns (
            uint32 oldestObservation,
            uint24 gamma0,
            uint24 gamma1,
            int24 tickSpacing
        );

    function estimate24H(
        IUniswapV3Pool pool,
        uint160 sqrtPriceX96,
        int24 tick
    ) external returns (uint256 IV);
}
