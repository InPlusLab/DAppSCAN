// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { Transfers } from "./Transfers.sol";

import { Router02 } from "../interop/UniswapV2.sol";

import { $ } from "../network/$.sol";

/**
 * @dev This library abstracts the Uniswap V2 token conversion functionality.
 */
library UniswapV2ExchangeAbstraction
{
	/**
	 * @dev Calculates how much output to be received from the given input
	 *      when converting between two assets.
	 * @param _from The input asset address.
	 * @param _to The output asset address.
	 * @param _inputAmount The input asset amount to be provided.
	 * @return _outputAmount The output asset amount to be received.
	 */
	function _calcConversionOutputFromInput(address _from, address _to, uint256 _inputAmount) internal view returns (uint256 _outputAmount)
	{
		address _router = $.UniswapV2_ROUTER02;
		address _WETH = Router02(_router).WETH();
		address[] memory _path = _buildPath(_from, _WETH, _to);
		return Router02(_router).getAmountsOut(_inputAmount, _path)[_path.length - 1];
	}

	/**
	 * @dev Calculates how much input to be received the given the output
	 *      when converting between two assets.
	 * @param _from The input asset address.
	 * @param _to The output asset address.
	 * @param _outputAmount The output asset amount to be received.
	 * @return _inputAmount The input asset amount to be provided.
	 */
	function _calcConversionInputFromOutput(address _from, address _to, uint256 _outputAmount) internal view returns (uint256 _inputAmount)
	{
		address _router = $.UniswapV2_ROUTER02;
		address _WETH = Router02(_router).WETH();
		address[] memory _path = _buildPath(_from, _WETH, _to);
		return Router02(_router).getAmountsIn(_outputAmount, _path)[0];
	}

	/**
	 * @dev Convert funds between two assets.
	 * @param _from The input asset address.
	 * @param _to The output asset address.
	 * @param _inputAmount The input asset amount to be provided.
	 * @param _minOutputAmount The output asset minimum amount to be received.
	 * @return _outputAmount The output asset amount received.
	 */
	function _convertFunds(address _from, address _to, uint256 _inputAmount, uint256 _minOutputAmount) internal returns (uint256 _outputAmount)
	{
		address _router = $.UniswapV2_ROUTER02;
		address _WETH = Router02(_router).WETH();
		address[] memory _path = _buildPath(_from, _WETH, _to);
		Transfers._approveFunds(_from, _router, _inputAmount);
		return Router02(_router).swapExactTokensForTokens(_inputAmount, _minOutputAmount, _path, address(this), uint256(-1))[_path.length - 1];
	}

	/**
	 * @dev Builds a routing path for conversion using WETH as intermediate.
	 *      Deals with the special case where WETH is also the input or the
	 *      output asset.
	 * @param _from The input asset address.
	 * @param _WETH The Wrapped Ether address.
	 * @param _to The output asset address.
	 * @return _path The route to perform conversion.
	 */
	function _buildPath(address _from, address _WETH, address _to) internal pure returns (address[] memory _path)
	{
		if (_from == _WETH || _to == _WETH) {
			_path = new address[](2);
			_path[0] = _from;
			_path[1] = _to;
			return _path;
		} else {
			_path = new address[](3);
			_path[0] = _from;
			_path[1] = _WETH;
			_path[2] = _to;
			return _path;
		}
	}
}
