// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { Assert } from "truffle/Assert.sol";

import { Env } from "./Env.sol";

import { Exchange } from "../contracts/Exchange.sol";

import { Factory } from "../contracts/interop/UniswapV2.sol";

import { Transfers } from "../contracts/modules/Transfers.sol";

import { $ } from "../contracts/network/$.sol";

contract TestExchange is Env
{
	function test01() external
	{
		_testConvertFundsFromInput($.AUTO, $.CAKE, 1e17); // 0.1 AUTO
	}

	function test02() external
	{
		_testConvertFundsFromInput($.PANTHER, $.CAKE, 100e18); // 100 PANTHER
	}

	function test03() external
	{
		_testConvertFundsFromInput($.CAKE, $.GRO, 20e18); // 20 CAKE
	}

	function test04() external
	{
		_testConvertFundsFromInput($.CAKE, $.WHEAT, 20e18); // 20 CAKE
	}

	function test05() external
	{
		_testConvertFundsFromOutput($.AUTO, $.CAKE, 10e18); // 10 CAKE
	}

	function test06() external
	{
		_testConvertFundsFromOutput($.CAKE, $.GRO, 10e18); // 10 GRO
	}

	function test07() external
	{
		_testConvertFundsFromOutput($.CAKE, $.WHEAT, 50e18); // 50 WHEAT
	}

	function test08() external
	{
		_testJoinPoolFromInput($.CAKE, $.WBNB, 20e18); // 20 CAKE
	}

	function test09() external
	{
		_testJoinPoolFromInput($.BUSD, $.WBNB, 100e18); // 100 BUSD
	}

	function test10() external
	{
		_testJoinPoolFromInput($.WBNB, $.PANTHER, 1e18); // 1 WBNB
	}

	function test11() external
	{
		_testJoinPoolFromInput($.PANTHER, $.WBNB, 100e18); // 100 PANTHER
	}

	function test12() external
	{
		_testJoinPoolFromInput($.PANTHER, $.BUSD, 100e18); // 100 PANTHER
	}

	function _testConvertFundsFromInput(address _from, address _to, uint256 _inputAmount) internal
	{
		_burnAll(_from);
		_burnAll(_to);

		_mint(_from, _inputAmount);

		address _exchange = EXCHANGE;

		uint256 SLIPPAGE = 1e15; // 0.1%

		if (_from == $.PANTHER) { // workaround the transfer tax
			_inputAmount = Transfers._getBalance(_from);
			SLIPPAGE = 6e16; // 6%
		}

		uint256 _expectedOutputAmount =  Exchange(_exchange).calcConversionFromInput(_from, _to, _inputAmount);
		uint256 _minOutputAmount = _expectedOutputAmount.mul(1e18 - SLIPPAGE).div(1e18);

		Assert.equal(Transfers._getBalance(_from), _inputAmount, "Balance before must match input");
		Assert.equal(Transfers._getBalance(_to), 0e18, "Balance before must be 0e18");

		Transfers._approveFunds(_from, _exchange, _inputAmount);
		uint256 _outputAmount = Exchange(_exchange).convertFundsFromInput(_from, _to, _inputAmount, _minOutputAmount);

		Assert.equal(Transfers._getBalance(_from), 0e18, "Balance after must be 0e18");
		Assert.equal(Transfers._getBalance(_to), _outputAmount, "Balance after must match output");
	}

	function _testConvertFundsFromOutput(address _from, address _to, uint256 _outputAmount) internal
	{
		_burnAll(_from);
		_burnAll(_to);

		address _exchange = EXCHANGE;

		uint256 SLIPPAGE = 1e15; // 0.1%

		uint256 _expectedInputAmount =  Exchange(_exchange).calcConversionFromOutput(_from, _to, _outputAmount);
		uint256 _maxInputAmount = _expectedInputAmount.mul(1e18 + SLIPPAGE).div(1e18);

		_mint(_from, _maxInputAmount);

		Assert.equal(Transfers._getBalance(_from), _maxInputAmount, "Balance before must match max input");
		Assert.equal(Transfers._getBalance(_to), 0e18, "Balance before must be 0e18");

		Transfers._approveFunds(_from, _exchange, _maxInputAmount);
		uint256 _inputAmount = Exchange(_exchange).convertFundsFromOutput(_from, _to, _outputAmount, _maxInputAmount);

		Assert.equal(Transfers._getBalance(_from), _maxInputAmount - _inputAmount, "Balance after must be the difference");
		Assert.equal(Transfers._getBalance(_to), _outputAmount, "Balance after must match output");
	}

	function _testJoinPoolFromInput(address _token, address _otherToken, uint256 _inputAmount) internal
	{
		address _pool = Factory($.UniswapV2_Compatible_FACTORY).getPair(_token, _otherToken);

		_burnAll(_pool);
		_burnAll(_token);
		_burnAll(_otherToken);

		_mint(_token, _inputAmount);

		address _exchange = EXCHANGE;

		uint256 SLIPPAGE = 1e15; // 0.1%

		if (_token == $.PANTHER) { // workaround the transfer tax
			_inputAmount = Transfers._getBalance(_token);
		}

		if (_token == $.PANTHER || _otherToken == $.PANTHER) { // workaround the transfer tax
			SLIPPAGE = 6e16; // 6%
		}

		uint256 _expectedOutputShares =  Exchange(_exchange).calcJoinPoolFromInput(_pool, _token, _inputAmount);
		uint256 _minOutputShares = _expectedOutputShares.mul(1e18 - SLIPPAGE).div(1e18);

		Assert.equal(Transfers._getBalance(_token), _inputAmount, "Balance before must match input");
		Assert.equal(Transfers._getBalance(_pool), 0e18, "Balance before must be 0e18");

		Transfers._approveFunds(_token, _exchange, _inputAmount);
		uint256 _outputShares = Exchange(_exchange).joinPoolFromInput(_pool, _token, _inputAmount, _minOutputShares);

		Assert.equal(Transfers._getBalance(_token), 0e18, "Balance after must be 0e18");
		Assert.equal(Transfers._getBalance(_pool), _outputShares, "Balance after must match output");
	}
}
