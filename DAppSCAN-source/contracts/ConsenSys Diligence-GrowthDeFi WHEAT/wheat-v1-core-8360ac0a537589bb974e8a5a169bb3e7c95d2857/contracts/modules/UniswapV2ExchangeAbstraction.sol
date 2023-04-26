// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { Transfers } from "./Transfers.sol";

import { Router02 } from "../interop/UniswapV2.sol";

/**
 * @dev This library abstracts the Uniswap V2 token conversion functionality.
 */
library UniswapV2ExchangeAbstraction
{
	/**
	 * @dev Calculates how much output to be received from the given input
	 *      when converting between two assets.
	 * @param _router The router address.
	 * @param _from The input asset address.
	 * @param _to The output asset address.
	 * @param _inputAmount The input asset amount to be provided.
	 * @return _outputAmount The output asset amount to be received.
	 */
	function _calcConversionFromInput(address _router, address _from, address _to, uint256 _inputAmount) internal view returns (uint256 _outputAmount)
	{
		address _WBNB = Router02(_router).WETH();
		address[] memory _path = _buildPath(_from, _WBNB, _to);
		return Router02(_router).getAmountsOut(_inputAmount, _path)[_path.length - 1];
	}

	/**
	 * @dev Calculates how much input to be received the given the output
	 *      when converting between two assets.
	 * @param _router The router address.
	 * @param _from The input asset address.
	 * @param _to The output asset address.
	 * @param _outputAmount The output asset amount to be received.
	 * @return _inputAmount The input asset amount to be provided.
	 */
	function _calcConversionFromOutput(address _router, address _from, address _to, uint256 _outputAmount) internal view returns (uint256 _inputAmount)
	{
		address _WBNB = Router02(_router).WETH();
		address[] memory _path = _buildPath(_from, _WBNB, _to);
		return Router02(_router).getAmountsIn(_outputAmount, _path)[0];
	}

	/**
	 * @dev Convert funds between two assets given the exact input amount.
	 * @param _router The router address.
	 * @param _from The input asset address.
	 * @param _to The output asset address.
	 * @param _inputAmount The input asset amount to be provided.
	 * @param _minOutputAmount The output asset minimum amount to be received.
	 * @return _outputAmount The output asset amount received.
	 */
	function _convertFundsFromInput(address _router, address _from, address _to, uint256 _inputAmount, uint256 _minOutputAmount) internal returns (uint256 _outputAmount)
	{
		address _WBNB = Router02(_router).WETH();
		address[] memory _path = _buildPath(_from, _WBNB, _to);
		Transfers._approveFunds(_from, _router, _inputAmount);
		uint256 _oldBalance = Transfers._getBalance(_path[_path.length - 1]);
		Router02(_router).swapExactTokensForTokensSupportingFeeOnTransferTokens(_inputAmount, _minOutputAmount, _path, address(this), uint256(-1));
		uint256 _newBalance = Transfers._getBalance(_path[_path.length - 1]);
		assert(_newBalance >= _oldBalance);
		return _newBalance - _oldBalance;
	}

	/**
	 * @dev Convert funds between two assets given the exact output amount.
	 * @param _router The router address.
	 * @param _from The input asset address.
	 * @param _to The output asset address.
	 * @param _outputAmount The output asset amount to be received.
	 * @param _maxInputAmount The input asset maximum amount to be provided.
	 * @return _inputAmount The input asset amount provided.
	 */
	function _convertFundsFromOutput(address _router, address _from, address _to, uint256 _outputAmount, uint256 _maxInputAmount) internal returns (uint256 _inputAmount)
	{
		address _WBNB = Router02(_router).WETH();
		address[] memory _path = _buildPath(_from, _WBNB, _to);
		Transfers._approveFunds(_from, _router, _maxInputAmount);
		_inputAmount = Router02(_router).swapTokensForExactTokens(_outputAmount, _maxInputAmount, _path, address(this), uint256(-1))[0];
		Transfers._approveFunds(_from, _router, 0);
		return _inputAmount;
	}

	/**
	 * @dev Builds a routing path for conversion possibly using an asset as intermediate.
	 * @param _from The input asset address.
	 * @param _through The middle asset address.
	 * @param _to The output asset address.
	 * @return _path The route to perform conversion.
	 */
	function _buildPath(address _from, address _through, address _to) private pure returns (address[] memory _path)
	{
		assert(_from != _to);
		if (_from == _through || _to == _through) {
			_path = new address[](2);
			_path[0] = _from;
			_path[1] = _to;
			return _path;
		} else {
			_path = new address[](3);
			_path[0] = _from;
			_path[1] = _through;
			_path[2] = _to;
			return _path;
		}
	}
}
