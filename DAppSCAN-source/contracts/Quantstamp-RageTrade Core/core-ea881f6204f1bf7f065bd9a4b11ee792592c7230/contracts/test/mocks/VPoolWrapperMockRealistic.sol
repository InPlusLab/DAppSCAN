// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { SafeCast } from '@uniswap/v3-core-0.8-support/contracts/libraries/SafeCast.sol';
import { FixedPoint128 } from '@uniswap/v3-core-0.8-support/contracts/libraries/FixedPoint128.sol';
import { FullMath } from '@uniswap/v3-core-0.8-support/contracts/libraries/FullMath.sol';
import { TickMath } from '@uniswap/v3-core-0.8-support/contracts/libraries/TickMath.sol';
import { IUniswapV3Pool } from '@uniswap/v3-core-0.8-support/contracts/interfaces/IUniswapV3Pool.sol';
import { IUniswapV3PoolDeployer } from '@uniswap/v3-core-0.8-support/contracts/interfaces/IUniswapV3PoolDeployer.sol';
import { IUniswapV3MintCallback } from '@uniswap/v3-core-0.8-support/contracts/interfaces/callback/IUniswapV3MintCallback.sol';
import { IUniswapV3SwapCallback } from '@uniswap/v3-core-0.8-support/contracts/interfaces/callback/IUniswapV3SwapCallback.sol';

import { IVPoolWrapper } from '../../interfaces/IVPoolWrapper.sol';
import { IVQuote } from '../../interfaces/IVQuote.sol';
import { IVToken } from '../../interfaces/IVToken.sol';
import { IOracle } from '../../interfaces/IOracle.sol';
import { IVToken } from '../../interfaces/IVToken.sol';

import { FundingPayment } from '../../libraries/FundingPayment.sol';
import { SimulateSwap } from '../../libraries/SimulateSwap.sol';
import { PriceMath } from '../../libraries/PriceMath.sol';
import { SignedMath } from '../../libraries/SignedMath.sol';
import { SignedFullMath } from '../../libraries/SignedFullMath.sol';
import { UniswapV3PoolHelper } from '../../libraries/UniswapV3PoolHelper.sol';

import { VPoolWrapper } from '../../protocol/wrapper/VPoolWrapper.sol';

contract VPoolWrapperMockRealistic is VPoolWrapper {
    uint48 public blockTimestamp;

    constructor() VPoolWrapper() {
        fpGlobal.timestampLast = 0;
    }

    function setFpGlobalLastTimestamp(uint48 timestamp) external {
        fpGlobal.timestampLast = timestamp;
    }

    function setBlockTimestamp(uint48 timestamp) external {
        blockTimestamp = timestamp;
    }

    function _blockTimestamp() internal view virtual override returns (uint48) {
        return blockTimestamp;
    }
}
