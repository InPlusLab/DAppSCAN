// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { IUniswapV3Pool } from '@uniswap/v3-core-0.8-support/contracts/interfaces/IUniswapV3Pool.sol';

import { IClearingHouse } from '../interfaces/IClearingHouse.sol';
import { IExtsload } from '../interfaces/IExtsload.sol';
import { IOracle } from '../interfaces/IOracle.sol';

import { Bytes32 } from '../libraries/Bytes32.sol';

library ClearingHouseExtsload {
    using Bytes32 for bytes32;

    bytes32 constant PROTOCOL_SLOT = bytes32(uint256(100));
    bytes32 constant POOLS_MAPPING_SLOT = PROTOCOL_SLOT;

    function getVPool(IClearingHouse clearingHouse, uint32 poolId) internal view returns (IUniswapV3Pool vPool) {
        bytes32 result = clearingHouse.extsload(keyOfVPool(poolId));
        assembly {
            vPool := result
        }
    }

    function getPoolSettings(IClearingHouse clearingHouse, uint32 poolId)
        internal
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
        bytes32 result = clearingHouse.extsload(keyOfPoolSettings(poolId));

        (initialMarginRatioBps, result) = result.extractUint16();
        (maintainanceMarginRatioBps, result) = result.extractUint16();
        (maxVirtualPriceDeviationRatioBps, result) = result.extractUint16();
        (twapDuration, result) = result.extractUint32();
        (isAllowedForTrade, result) = result.extractBool();
        (isCrossMargined, result) = result.extractBool();
        address oracle_;
        (oracle_, result) = result.extractAddress();
        assembly {
            oracle := oracle_
        }
    }

    function getTwapDuration(IClearingHouse clearingHouse, uint32 poolId) internal view returns (uint32 twapDuration) {
        bytes32 result = clearingHouse.extsload(keyOfPoolSettings(poolId));
        twapDuration = uint32(result.slice(0x30, 0x50));
    }

    function getVPoolAndTwapDuration(IClearingHouse clearingHouse, uint32 poolId)
        internal
        view
        returns (IUniswapV3Pool vPool, uint32 twapDuration)
    {
        bytes32[] memory arr = new bytes32[](2);
        arr[0] = keyOfVPool(poolId);
        arr[1] = keyOfPoolSettings(poolId);
        arr = clearingHouse.extsload(arr);
        address vPool_;
        (vPool_, ) = arr[0].extractAddress();
        assembly {
            vPool := vPool_
        }
        twapDuration = uint32(arr[1].slice(0xB0, 0xD0));
    }

    // KEY GENERATORS

    function keyOfVPool(uint32 poolId) internal pure returns (bytes32) {
        return Bytes32.fromUint(poolId).keccak256Two(POOLS_MAPPING_SLOT).offset(1);
    }

    function keyOfPoolSettings(uint32 poolId) internal pure returns (bytes32) {
        return Bytes32.fromUint(poolId).keccak256Two(POOLS_MAPPING_SLOT).offset(3);
    }
}
