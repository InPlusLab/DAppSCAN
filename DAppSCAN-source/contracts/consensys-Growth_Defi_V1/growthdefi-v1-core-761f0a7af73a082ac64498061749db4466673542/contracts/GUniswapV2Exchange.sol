// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { GExchange } from "./GExchange.sol";
import { G } from "./G.sol";

import { Router02 } from "./interop/UniswapV2.sol";
import { WETH } from "./interop/WrappedEther.sol";

import { UniswapV2ExchangeAbstraction } from "./modules/UniswapV2ExchangeAbstraction.sol";

import { $ } from "./network/$.sol";

/**
 * @notice This contract implements the GExchange interface routing token
 *         conversions via UniswapV2.
 */
contract GUniswapV2Exchange is GExchange
{
	/**
	 * @notice Computes the amount of tokens to be received upon conversion.
	 * @param _from The contract address of the ERC-20 token to convert from.
	 * @param _to The contract address of the ERC-20 token to convert to.
	 * @param _inputAmount The amount of the _from token to be provided (may be 0).
	 * @return _outputAmount The amount of the _to token to be received (may be 0).
	 */
	function calcConversionOutputFromInput(address _from, address _to, uint256 _inputAmount) public view override returns (uint256 _outputAmount)
	{
		return UniswapV2ExchangeAbstraction._calcConversionOutputFromInput(_from, _to, _inputAmount);
	}

	/**
	 * @notice Computes the amount of tokens to be provided upon conversion.
	 * @param _from The contract address of the ERC-20 token to convert from.
	 * @param _to The contract address of the ERC-20 token to convert to.
	 * @param _outputAmount The amount of the _to token to be received (may be 0).
	 * @return _inputAmount The amount of the _from token to be provided (may be 0).
	 */
	function calcConversionInputFromOutput(address _from, address _to, uint256 _outputAmount) public view override returns (uint256 _inputAmount)
	{
		return UniswapV2ExchangeAbstraction._calcConversionInputFromOutput(_from, _to, _outputAmount);
	}

	/**
	 * @notice Converts a given token amount to another token, as long as it
	 *         meets the minimum taken amount. Amounts are debited from and
	 *         and credited to the caller contract. It may fail if the
	 *         minimum output amount cannot be met.
	 * @param _from The contract address of the ERC-20 token to convert from.
	 * @param _to The contract address of the ERC-20 token to convert to.
	 * @param _inputAmount The amount of the _from token to be provided (may be 0).
	 * @param _minOutputAmount The minimum amount of the _to token to be received (may be 0).
	 * @return _outputAmount The amount of the _to token received (may be 0).
	 */
	function convertFunds(address _from, address _to, uint256 _inputAmount, uint256 _minOutputAmount) public override returns (uint256 _outputAmount)
	{
		address _sender = msg.sender;
		G.pullFunds(_from, _sender, _inputAmount);
		_outputAmount = UniswapV2ExchangeAbstraction._convertFunds(_from, _to, _inputAmount, _minOutputAmount);
		G.pushFunds(_to, _sender, _outputAmount);
		return _outputAmount;
	}

	/* This method is only used by stress-test to easily mint any ERC-20
	 * supported by UniswapV2.
	 */
	function faucet(address _token, uint256 _amount) public payable {
		address payable _from = msg.sender;
		uint256 _value = msg.value;
		address _router = $.UniswapV2_ROUTER02;
		address _WETH = Router02(_router).WETH();
		uint256 _spent;
		if (_token == _WETH) {
			WETH(_token).deposit{value: _amount}();
			WETH(_token).transfer(_from, _amount);
			_spent = _amount;
		} else {
			address[] memory _path = new address[](2);
			_path[0] = _WETH;
			_path[1] = _token;
			_spent = Router02(_router).swapETHForExactTokens{value: _value}(_amount, _path, _from, block.timestamp)[0];
		}
		_from.transfer(_value - _spent);
	}
	receive() external payable {}
}
