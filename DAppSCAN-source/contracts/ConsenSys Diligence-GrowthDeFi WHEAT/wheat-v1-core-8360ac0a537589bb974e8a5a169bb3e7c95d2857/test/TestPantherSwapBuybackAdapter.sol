// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { Assert } from "truffle/Assert.sol";

import { Env } from "./Env.sol";

import { PantherSwapBuybackAdapter } from "../contracts/PantherSwapBuybackAdapter.sol";

import { Transfers } from "../contracts/modules/Transfers.sol";

import { $ } from "../contracts/network/$.sol";

contract TestPantherSwapBuybackAdapter is Env
{
	function test01() external
	{
		_burnAll($.PANTHER);
		_burnAll($.CAKE);

		_mint($.PANTHER, 100e18); // 100 PANTHER

		address _adapter = PANTHER_BUYBACK;

		Transfers._pushFunds($.PANTHER, _adapter, Transfers._getBalance($.PANTHER));

		uint256 _pendingBefore = PantherSwapBuybackAdapter(_adapter).pendingSource();
		Assert.isAtLeast(_pendingBefore, 94e18, "PANTHER balance before must be 94e18");

		uint256 SLIPPAGE = 6e16; // 6%

		uint256 _target =  PantherSwapBuybackAdapter(_adapter).pendingTarget();
		uint256 _minTarget = _target.mul(1e18 - SLIPPAGE).div(1e18);
		PantherSwapBuybackAdapter(_adapter).gulp(_minTarget);

		uint256 _pendingAfter = PantherSwapBuybackAdapter(_adapter).pendingSource();
		Assert.equal(_pendingAfter, 0e18, "AUTO balance after must be 0e18");
	}
}
