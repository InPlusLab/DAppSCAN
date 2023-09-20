// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { Assert } from "truffle/Assert.sol";

import { Env } from "./Env.sol";

import { PancakeSwapCompoundingStrategyToken } from "../contracts/PancakeSwapCompoundingStrategyToken.sol";

import { Transfers } from "../contracts/modules/Transfers.sol";

import { $ } from "../contracts/network/$.sol";

contract TestPancakeSwapCompoundingStrategyToken is Env
{
	function test01() external
	{
		address _strategy = CAKE_STRATEGY;

		_burnAll($.CAKE);
		_burnAll(_strategy);

		_mint($.CAKE, 20e18); // 20 CAKE

		Assert.equal(Transfers._getBalance($.CAKE), 20e18, "CAKE balance before deposit must be 20e18");
		Assert.equal(Transfers._getBalance(_strategy), 0e18, "Shares balance before deposit must be 0e18");

		uint256 SLIPPAGE = 1e15; // 0.1%

		uint256 _expectedShares =  PancakeSwapCompoundingStrategyToken(_strategy).calcSharesFromAmount(20e18);
		uint256 _minShares = _expectedShares.mul(1e18 - SLIPPAGE).div(1e18);
		Transfers._approveFunds($.CAKE, _strategy, 20e18);
		PancakeSwapCompoundingStrategyToken(_strategy).deposit(20e18, _minShares);

		Assert.equal(Transfers._getBalance($.CAKE), 0e18, "CAKE balance after must be 0e18");
		Assert.isAtLeast(Transfers._getBalance(_strategy), _minShares, "Shares balance after deposit must be at least the minimum");

		uint256 _shares = Transfers._getBalance(_strategy);

		uint256 _expectedAmount =  PancakeSwapCompoundingStrategyToken(_strategy).calcAmountFromShares(_shares);
		uint256 _minAmount = _expectedAmount.mul(1e18 - SLIPPAGE).div(1e18);
		PancakeSwapCompoundingStrategyToken(_strategy).withdraw(_shares, _minAmount);

		Assert.isAtLeast(Transfers._getBalance($.CAKE), _minAmount, "CAKE balance after wthdrawal must be at least the minimum");
		Assert.equal(Transfers._getBalance(_strategy), 0e18, "Shares balance after withdrawal must be 0e18");
	}
}
