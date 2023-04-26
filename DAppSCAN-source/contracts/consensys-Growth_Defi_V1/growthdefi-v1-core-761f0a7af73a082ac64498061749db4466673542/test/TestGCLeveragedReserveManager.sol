// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { Assert } from "truffle/Assert.sol";
import { DeployedAddresses } from "truffle/DeployedAddresses.sol";

import { Env } from "./Env.sol";

import { GCLeveragedReserveManager } from "../contracts/GCLeveragedReserveManager.sol";

contract TestGCLeveragedReserveManager is Env
{
	using GCLeveragedReserveManager for GCLeveragedReserveManager.Self;

	GCLeveragedReserveManager.Self lrm;

	constructor () public
	{
		lrm.init(cDAI, COMP);

		address exchange = DeployedAddresses.GSushiswapExchange();
		lrm.setExchange(exchange);
	}

	function test01() public
	{
		_burnAll(COMP);
		_burnAll(DAI);
		_mint(COMP, 3e18);

		Assert.equal(_getBalance(COMP), 3e18, "COMP balance must be 3e18");
		Assert.equal(_getBalance(DAI), 0e18, "DAI balance must be 0e18");

		lrm._convertMiningToUnderlying(2e18);

		Assert.equal(_getBalance(COMP), 1e18, "COMP balance must be 1e18");
		Assert.isAbove(_getBalance(DAI), 0e18, "DAI balance must be above 0e18");
	}

	function test02() public
	{
		_burnAll(COMP);
		_burnAll(DAI);
		_burnAll(cDAI);

		Assert.equal(_getBalance(COMP), 0e18, "COMP balance must be 0e18");
		Assert.equal(_getBalance(DAI), 0e18, "DAI balance must be 0e18");
		Assert.equal(_getBalance(cDAI), 0e8, "cDAI balance must be 0e8");

		lrm._gulpMiningAssets();

		Assert.equal(_getBalance(COMP), 0e18, "COMP balance must be 0e18");
		Assert.equal(_getBalance(DAI), 0e18, "DAI balance must be 0e18");
		Assert.equal(_getBalance(cDAI), 0e8, "cDAI balance must be 0e8");
	}

	function test03() public
	{
		_burnAll(COMP);
		_burnAll(DAI);
		_burnAll(cDAI);
		_mint(COMP, 5e18);

		Assert.equal(_getBalance(COMP), 5e18, "COMP balance must be 5e18");
		Assert.equal(_getBalance(DAI), 0e18, "DAI balance must be 0e18");
		Assert.equal(_getBalance(cDAI), 0e8, "cDAI balance must be 0e8");

		lrm.setMiningGulpRange(0e18, 100e18);
		lrm._gulpMiningAssets();

		Assert.equal(_getBalance(COMP), 0e18, "COMP balance must be 0e18");
		Assert.equal(_getBalance(DAI), 0e18, "DAI balance must be 0e18");
		Assert.isAbove(_getBalance(cDAI), 0e8, "cDAI balance must be above 0e8");
	}

	function test04() public
	{
		_burnAll(COMP);
		_burnAll(DAI);
		_burnAll(cDAI);
		_mint(COMP, 5e18);

		Assert.equal(_getBalance(COMP), 5e18, "COMP balance must be 5e18");
		Assert.equal(_getBalance(DAI), 0e18, "DAI balance must be 0e18");
		Assert.equal(_getBalance(cDAI), 0e8, "cDAI balance must be 0e8");

		lrm.setMiningGulpRange(0e18, 1e18);

		uint256 _rounds = 0;
		while (_getBalance(COMP) > 0) {
			lrm._gulpMiningAssets();
			_rounds++;
		}

		Assert.equal(_getBalance(COMP), 0e18, "COMP balance must be 0e18");
		Assert.equal(_getBalance(DAI), 0e18, "DAI balance must be 0e18");
		Assert.isAbove(_getBalance(cDAI), 0e8, "cDAI balance must be above 0e8");
		Assert.equal(_rounds, 5, "rounds be 5");
	}
}
