// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { GExchange } from "./GExchange.sol";
import { G } from "./G.sol";

import { SushiswapExchangeAbstraction } from "./modules/SushiswapExchangeAbstraction.sol";

/**
 * @notice This contract implements the GExchange interface routing token
 *         conversions via Sushiswap.
 */
contract GSushiswapExchange is GExchange
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
		return SushiswapExchangeAbstraction._calcConversionOutputFromInput(_from, _to, _inputAmount);
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
		return SushiswapExchangeAbstraction._calcConversionInputFromOutput(_from, _to, _outputAmount);
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
		_outputAmount = SushiswapExchangeAbstraction._convertFunds(_from, _to, _inputAmount, _minOutputAmount);
		G.pushFunds(_to, _sender, _outputAmount);
		return _outputAmount;
	}
}
