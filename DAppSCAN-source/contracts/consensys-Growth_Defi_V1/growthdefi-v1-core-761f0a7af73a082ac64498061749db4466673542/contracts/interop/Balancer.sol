// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @dev Minimal set of declarations for Balancer interoperability.
 */
interface BFactory
{
	function newBPool() external returns (address _pool);
}

interface BPool is IERC20
{
	function getFinalTokens() external view returns (address[] memory _tokens);
	function getBalance(address _token) external view returns (uint256 _balance);
	function setSwapFee(uint256 _swapFee) external;
	function finalize() external;
	function bind(address _token, uint256 _balance, uint256 _denorm) external;
	function exitPool(uint256 _poolAmountIn, uint256[] calldata _minAmountsOut) external;
	function joinswapExternAmountIn(address _tokenIn, uint256 _tokenAmountIn, uint256 _minPoolAmountOut) external returns (uint256 _poolAmountOut);
}
