// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

interface IUniswapAnchoredView {
    function price(string calldata symbol) external view returns (uint);
}