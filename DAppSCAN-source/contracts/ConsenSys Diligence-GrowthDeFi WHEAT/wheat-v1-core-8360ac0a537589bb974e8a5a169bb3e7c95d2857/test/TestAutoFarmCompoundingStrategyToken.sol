// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { Assert } from "truffle/Assert.sol";

import { Env } from "./Env.sol";

import { Exchange } from "../contracts/Exchange.sol";
import { AutoFarmCompoundingStrategyToken } from "../contracts/AutoFarmCompoundingStrategyToken.sol";

import { Transfers } from "../contracts/modules/Transfers.sol";

import { BeltStrategyToken, BeltStrategyPool } from "../contracts/interop/Belt.sol";

import { $ } from "../contracts/network/$.sol";

contract TestAutoFarmCompoundingStrategyToken is Env
{
	// had to break this test in 3 parts to work around web3/truffle/ganache timeout bug
	function test01Part1() external
	{
		address _strategy = AUTO_STRATEGY;

		address _beltPool = 0xAEA4f7dcd172997947809CE6F12018a6D5c1E8b6; // 4Belt
		int128 _index = 3; // BUSD
		address _poolToken = BeltStrategyPool(_beltPool).pool_token();
		address _beltToken = BeltStrategyPool(_beltPool).coins(_index);

		_burnAll($.BUSD);
		_burnAll(_strategy);
		_burnAll(_beltToken);
		_burnAll(_poolToken);

		_mint($.BUSD, 100e18); // 100 BUSD
		Assert.equal(Transfers._getBalance($.BUSD), 100e18, "BUSD balance before deposit must be 100e18");
		Assert.equal(Transfers._getBalance(_strategy), 0e18, "Shares balance before deposit must be 0e18");

		Transfers._approveFunds($.BUSD, _beltToken, 100e18);
		BeltStrategyToken(_beltToken).deposit(100e18, 1);
		uint256 _beltAmount = Transfers._getBalance(_beltToken);

		{
			Transfers._approveFunds(_beltToken, _beltPool, _beltAmount);
			uint256[4] memory _amounts;
			_amounts[uint256(_index)] = _beltAmount; 
			BeltStrategyPool(_beltPool).add_liquidity(_amounts, 1);
		}
		uint256 _lpshares = Transfers._getBalance(_poolToken);

		Assert.equal(Transfers._getBalance($.BUSD), 0e18, "BUSD balance before deposit must be 0e18");
		Assert.equal(Transfers._getBalance(_poolToken), _lpshares, "LP shares balance before deposit must match expected");
	}

	function test01Part2() external
	{
		address _strategy = AUTO_STRATEGY;

		address _beltPool = 0xAEA4f7dcd172997947809CE6F12018a6D5c1E8b6; // 4Belt
		address _poolToken = BeltStrategyPool(_beltPool).pool_token();

		uint256 _lpshares = Transfers._getBalance(_poolToken);

		uint256 SLIPPAGE = 1e15; // 0.1%

		uint256 _expectedShares =  AutoFarmCompoundingStrategyToken(_strategy).calcSharesFromAmount(_lpshares);
		uint256 _minShares = _expectedShares.mul(1e18 - SLIPPAGE).div(1e18);
		Transfers._approveFunds(_poolToken, _strategy, _lpshares);
		AutoFarmCompoundingStrategyToken(_strategy).deposit(_lpshares, _minShares);

		Assert.equal(Transfers._getBalance(_poolToken), 0e18, "LP shares balance after deposit must be 0e18");
		Assert.isAtLeast(Transfers._getBalance(_strategy), _minShares, "Shares balance after deposit must be at least the minimum");
	}

	function test01Part3() external
	{
		address _strategy = AUTO_STRATEGY;

		address _beltPool = 0xAEA4f7dcd172997947809CE6F12018a6D5c1E8b6; // 4Belt
		address _poolToken = BeltStrategyPool(_beltPool).pool_token();

		uint256 _shares = Transfers._getBalance(_strategy);

		uint256 SLIPPAGE = 1e15; // 0.1%

		uint256 _expectedAmount =  AutoFarmCompoundingStrategyToken(_strategy).calcAmountFromShares(_shares);
		uint256 _minAmount = _expectedAmount.mul(1e18 - SLIPPAGE).div(1e18);
		AutoFarmCompoundingStrategyToken(_strategy).withdraw(_shares, _minAmount);

		Assert.equal(Transfers._getBalance(_strategy), 0e18, "Shares balance after withdrawal must be 0e18");
		Assert.isAtLeast(Transfers._getBalance(_poolToken), _minAmount, "LP shares balance after wthdrawal must be at least the minimum");
	}
}
