// SPDX-License-Identifier: MIT

pragma solidity =0.6.12;
pragma experimental ABIEncoderV2;

interface IPairOracle {
    function consult(address token, uint256 amountIn) external view returns (uint256 amountOut);

    function update() external;
}
