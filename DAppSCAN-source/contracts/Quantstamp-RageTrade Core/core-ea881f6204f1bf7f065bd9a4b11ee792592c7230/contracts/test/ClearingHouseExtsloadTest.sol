// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { IUniswapV3Pool } from '@uniswap/v3-core-0.8-support/contracts/interfaces/IUniswapV3Pool.sol';

import { IClearingHouse } from '../interfaces/IClearingHouse.sol';
import { IExtsload } from '../interfaces/IExtsload.sol';
import { IOracle } from '../interfaces/IOracle.sol';

import { ClearingHouseExtsload } from '../extsloads/ClearingHouseExtsload.sol';

contract ClearingHouseExtsloadTest {
    modifier notView() {
        assembly {
            if iszero(1) {
                sstore(0, 0)
            }
        }
        _;
    }

    function getVPoolAndTwapDuration(IClearingHouse clearingHouse, uint32 poolId)
        public
        view
        returns (IUniswapV3Pool vPool, uint32 twapDuration)
    {
        (vPool, twapDuration) = ClearingHouseExtsload.getVPoolAndTwapDuration(clearingHouse, poolId);
    }

    function checkVPoolAndTwapDuration(IClearingHouse clearingHouse, uint32 poolId)
        public
        notView
        returns (IUniswapV3Pool vPool, uint32 twapDuration)
    {
        (vPool, twapDuration) = ClearingHouseExtsload.getVPoolAndTwapDuration(clearingHouse, poolId);
        clearingHouse.getPoolInfo(poolId);
    }

    function getVPool(IClearingHouse clearingHouse, uint32 poolId) public view returns (IUniswapV3Pool vPool) {
        vPool = ClearingHouseExtsload.getVPool(clearingHouse, poolId);
    }

    function getPoolSettings(IClearingHouse clearingHouse, uint32 poolId)
        public
        view
        returns (
            uint16 initialMarginRatioBps,
            uint16 maintainanceMarginRatioBps,
            uint16 maxVirtualPriceDeviationRatioBps,
            uint32 twapDuration,
            bool isAllowedForTrade,
            bool isCrossMargined,
            IOracle oracle
        )
    {
        return ClearingHouseExtsload.getPoolSettings(clearingHouse, poolId);
    }
}
