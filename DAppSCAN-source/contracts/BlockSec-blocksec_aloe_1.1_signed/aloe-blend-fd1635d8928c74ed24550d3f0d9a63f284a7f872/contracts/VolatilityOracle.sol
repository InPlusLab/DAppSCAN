// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

import "./libraries/Oracle.sol";
import "./libraries/Volatility.sol";

import "./interfaces/IVolatilityOracle.sol";

contract VolatilityOracle is IVolatilityOracle {
    mapping(address => Volatility.PoolMetadata) public cachedPoolMetadata;

    mapping(address => Volatility.FeeGrowthGlobals[26]) public feeGrowthGlobals;

    mapping(address => uint8) public feeGrowthGlobalsReadIndex;

    mapping(address => uint8) public feeGrowthGlobalsWriteIndex;

    function cacheMetadataFor(IUniswapV3Pool pool) external {
        Volatility.PoolMetadata memory poolMetadata;

        (, , uint16 observationIndex, uint16 observationCardinality, , uint8 feeProtocol, ) = pool.slot0();
        poolMetadata.oldestObservation = Oracle.getOldestObservation(pool, observationIndex, observationCardinality);

        uint24 fee = pool.fee();
        poolMetadata.gamma0 = fee;
        poolMetadata.gamma1 = fee;
        if (feeProtocol % 16 != 0) poolMetadata.gamma0 -= fee / (feeProtocol % 16);
        if (feeProtocol >> 4 != 0) poolMetadata.gamma1 -= fee / (feeProtocol >> 4);

        poolMetadata.tickSpacing = pool.tickSpacing();

        cachedPoolMetadata[address(pool)] = poolMetadata;
    }

    function estimate24H(
        IUniswapV3Pool pool,
        uint160 sqrtPriceX96,
        int24 tick
    ) external returns (uint256 IV) {
        Volatility.FeeGrowthGlobals[26] memory feeGrowthGlobal = feeGrowthGlobals[address(pool)];
        uint8 readIndex = _pickReadIndex(pool, feeGrowthGlobal);

        Volatility.FeeGrowthGlobals memory current;
        (IV, current) = _estimate24H(pool, sqrtPriceX96, tick, feeGrowthGlobal[readIndex]);

        // Write to storage
        feeGrowthGlobalsReadIndex[address(pool)] = readIndex;
        uint8 writeIndex = feeGrowthGlobalsWriteIndex[address(pool)];
        if (current.timestamp - 1 hours > feeGrowthGlobal[writeIndex].timestamp) {
            writeIndex = (writeIndex + 1) % 26;

            feeGrowthGlobals[address(pool)][writeIndex] = current;
            feeGrowthGlobalsWriteIndex[address(pool)] = writeIndex;
        }
    }

    function _estimate24H(
        IUniswapV3Pool pool,
        uint160 sqrtPriceX96,
        int24 tick,
        Volatility.FeeGrowthGlobals memory previous
    ) private view returns (uint256 IV, Volatility.FeeGrowthGlobals memory current) {
        Volatility.PoolMetadata memory poolMetadata = cachedPoolMetadata[address(pool)];

        uint32 secondsAgo = poolMetadata.oldestObservation;
        if (secondsAgo > 1 days) secondsAgo = 1 days;
        // Throws if secondsAgo == 0
        (int24 arithmeticMeanTick, uint160 secondsPerLiquidityX128) = Oracle.consult(pool, secondsAgo);

        current = Volatility.FeeGrowthGlobals(
            pool.feeGrowthGlobal0X128(),
            pool.feeGrowthGlobal1X128(),
            uint32(block.timestamp)
        );
        IV = Volatility.estimate24H(
            poolMetadata,
            Volatility.PoolData(
                sqrtPriceX96,
                tick,
                arithmeticMeanTick,
                secondsPerLiquidityX128,
                secondsAgo,
                pool.liquidity()
            ),
            previous,
            current
        );
    }

    function _pickReadIndex(IUniswapV3Pool pool, Volatility.FeeGrowthGlobals[26] memory feeGrowthGlobal)
        private
        view
        returns (uint8)
    {
        uint8 readIndex = feeGrowthGlobalsReadIndex[address(pool)];
        uint32 timingError = _timingError(block.timestamp - feeGrowthGlobal[readIndex].timestamp);

        for (uint8 counter = readIndex + 1; counter < readIndex + 26; counter++) {
            uint8 newReadIndex = counter % 26;
            uint32 newTimingError = _timingError(block.timestamp - feeGrowthGlobal[newReadIndex].timestamp);

            if (newTimingError < timingError) {
                readIndex = newReadIndex;
                timingError = newTimingError;
            }
        }

        return readIndex;
    }

    function _timingError(uint256 age) private pure returns (uint32) {
        return uint32(age < 24 hours ? 24 hours - age : age - 24 hours);
    }
}
