// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface MyNFT  {
    function createFromERC20(address sender, uint256 category) external returns (uint256);
}