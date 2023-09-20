// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @dev Minimal set of declarations for Uniswap V2 interoperability.
 */
interface Factory
{
	function getPair(address _tokenA, address _tokenB) external view returns (address _pair);

	function createPair(address _tokenA, address _tokenB) external returns (address _pair);
}

interface PoolToken is IERC20
{
}

interface Pair is PoolToken
{
	function getReserves() external view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast);
	function token0() external view returns (address _token0);
	function token1() external view returns (address _token1);

	function mint(address _to) external returns (uint256 _liquidity);
}

interface Router01
{
	function WETH() external pure returns (address _token);
	function getAmountOut(uint256 _amountIn, uint256 _reserveIn, uint256 _reserveOut) external pure returns (uint256 _amountOut);
	function getAmountsIn(uint256 _amountOut, address[] calldata _path) external view returns (uint[] memory _amounts);
	function getAmountsOut(uint256 _amountIn, address[] calldata _path) external view returns (uint[] memory _amounts);

	function addLiquidity(address _tokenA, address _tokenB, uint256 _amountADesired, uint256 _amountBDesired, uint256 _amountAMin, uint256 _amountBMin, address _to, uint256 _deadline) external returns (uint256 _amountA, uint256 _amountB, uint256 _liquidity);
	function removeLiquidity(address _tokenA, address _tokenB, uint256 _liquidity, uint256 _amountAMin, uint256 _amountBMin, address _to, uint256 _deadline) external returns (uint256 _amountA, uint256 _amountB);
	function swapETHForExactTokens(uint256 _amountOut, address[] calldata _path, address _to, uint256 _deadline) external payable returns (uint256[] memory _amounts);
	function swapTokensForExactTokens(uint256 _amountOut, uint256 _amountInMax, address[] calldata _path, address _to, uint256 _deadline) external returns (uint256[] memory _amounts);
}

interface Router02 is Router01
{
	function swapExactTokensForTokensSupportingFeeOnTransferTokens(uint256 _amountIn, uint256 _amountOutMin, address[] calldata _path, address _to, uint256 _deadline) external;
}
