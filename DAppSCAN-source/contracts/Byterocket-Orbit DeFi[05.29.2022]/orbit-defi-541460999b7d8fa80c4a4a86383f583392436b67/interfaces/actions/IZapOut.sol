// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

interface IZapOut {
    function zapOut(uint256 tokenId, address tokenOut) external returns (uint256);
}
