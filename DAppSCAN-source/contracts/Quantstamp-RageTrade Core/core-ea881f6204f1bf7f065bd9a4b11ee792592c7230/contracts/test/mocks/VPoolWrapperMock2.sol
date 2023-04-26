// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { VPoolWrapper } from '../../protocol/wrapper/VPoolWrapper.sol';
import { SwapMath } from '../../libraries/SwapMath.sol';

contract VPoolWrapperMock2 is VPoolWrapper {
    uint48 public blockTimestamp;

    constructor() {
        blockTimestamp = uint48(block.timestamp);
    }

    function _blockTimestamp() internal view override returns (uint48) {
        // constructor of VPoolWrapper runs first, there _blockTimestamp() returns zero
        if (blockTimestamp == 0) return uint48(block.timestamp);
        else return blockTimestamp;
    }

    function increaseTimestamp(uint48 secs) external {
        blockTimestamp += secs;
    }

    function calculateFees(int256 amount, SwapMath.AmountTypeEnum amountTypeEnum)
        public
        view
        returns (uint256 liquidityFees, uint256 protocolFees)
    {
        return SwapMath.calculateFees(amount, amountTypeEnum, liquidityFeePips, protocolFeePips);
    }
}
