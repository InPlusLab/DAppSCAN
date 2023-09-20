// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { Assert } from "truffle/Assert.sol";

import { Env } from "./Env.sol";

import { PancakeSwapFeeCollector } from "../contracts/PancakeSwapFeeCollector.sol";

import { Transfers } from "../contracts/modules/Transfers.sol";

import { $ } from "../contracts/network/$.sol";

contract TestPancakeSwapFeeCollector is Env
{
	function test01() external
	{
		_burnAll($.CAKE);

		_mint($.CAKE, 20e18); // 20 CAKE

		address _collector = CAKE_COLLECTOR;

		Transfers._pushFunds($.CAKE, _collector, 20e18);

		uint256 SLIPPAGE = 1e15; // 0.1%

		uint256 _depositAmountBefore =  PancakeSwapFeeCollector(_collector).pendingDeposit();
		Assert.isAbove(_depositAmountBefore, 0e18, "CAKE balance before must be greater than 0e18");

		uint256 _minDepositAmount = _depositAmountBefore.mul(1e18 - SLIPPAGE).div(1e18);
		PancakeSwapFeeCollector(_collector).gulp(_minDepositAmount);

		uint256 _depositAmountAfter = PancakeSwapFeeCollector(_collector).pendingDeposit();
		Assert.equal(_depositAmountAfter, 0e18, "CAKE balance after must be 0e18");
	}
}
