// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;
pragma experimental ABIEncoderV2;

interface IPairOracle {
    function consult(uint256 amountIn) external view returns (uint256 amountOut);
}
