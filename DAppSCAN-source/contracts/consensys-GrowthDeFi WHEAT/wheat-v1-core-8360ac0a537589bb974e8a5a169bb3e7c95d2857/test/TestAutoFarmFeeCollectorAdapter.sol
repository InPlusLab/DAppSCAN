// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { Assert } from "truffle/Assert.sol";

import { Env } from "./Env.sol";

import { AutoFarmFeeCollectorAdapter } from "../contracts/AutoFarmFeeCollectorAdapter.sol";

import { Transfers } from "../contracts/modules/Transfers.sol";

import { $ } from "../contracts/network/$.sol";

contract TestAutoFarmFeeCollectorAdapter is Env
{
	function test01() external
	{
		_burnAll($.AUTO);
		_burnAll($.CAKE);

		_mint($.AUTO, 1e17); // 0.1 AUTO

		address _adapter = AUTO_COLLECTOR;

		Transfers._pushFunds($.AUTO, _adapter, 1e17);

		uint256 _pendingBefore = AutoFarmFeeCollectorAdapter(_adapter).pendingSource();
		Assert.equal(_pendingBefore, 1e17, "AUTO balance before must be 1e17");

		uint256 SLIPPAGE = 1e15; // 0.1%

		uint256 _target =  AutoFarmFeeCollectorAdapter(_adapter).pendingTarget();
		uint256 _minTarget = _target.mul(1e18 - SLIPPAGE).div(1e18);
		AutoFarmFeeCollectorAdapter(_adapter).gulp(_minTarget);

		uint256 _pendingAfter = AutoFarmFeeCollectorAdapter(_adapter).pendingSource();
		Assert.equal(_pendingAfter, 0e18, "AUTO balance after must be 0e18");
	}
}
