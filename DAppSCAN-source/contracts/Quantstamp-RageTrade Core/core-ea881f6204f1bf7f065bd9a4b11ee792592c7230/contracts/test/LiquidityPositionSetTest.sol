// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { LiquidityPositionSet, LiquidityPosition } from '../libraries/LiquidityPositionSet.sol';
import { VPoolWrapperMock } from './mocks/VPoolWrapperMock.sol';

contract LiquidityPositionSetTest {
    using LiquidityPositionSet for LiquidityPosition.Set;
    using LiquidityPosition for LiquidityPosition.Info;

    LiquidityPosition.Set liquidityPositions;
    VPoolWrapperMock public wrapper;

    constructor() {
        wrapper = new VPoolWrapperMock();
    }

    function isPositionActive(int24 tickLower, int24 tickUpper) public view returns (bool) {
        return liquidityPositions.isPositionActive(tickLower, tickUpper);
    }

    function createEmptyPosition(int24 tickLower, int24 tickUpper)
        external
        returns (LiquidityPosition.Info memory info)
    {
        info = liquidityPositions.activate(tickLower, tickUpper);
    }
}
