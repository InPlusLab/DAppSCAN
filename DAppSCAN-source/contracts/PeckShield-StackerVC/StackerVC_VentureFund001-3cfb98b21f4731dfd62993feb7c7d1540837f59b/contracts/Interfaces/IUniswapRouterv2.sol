// SPDX-License-Identifier: MIT
pragma solidity ^0.6.11;

interface IUniswapRouterv2 {
	function swapExactTokensForTokens(uint amountIn,uint amountOutMin, address[] calldata path, address to, uint deadline) external returns (uint[] memory amounts);
}