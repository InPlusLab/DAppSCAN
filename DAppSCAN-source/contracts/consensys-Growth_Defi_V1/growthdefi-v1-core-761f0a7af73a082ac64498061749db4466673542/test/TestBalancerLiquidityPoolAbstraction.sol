// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { Assert } from "truffle/Assert.sol";

import { Env } from "./Env.sol";

import { BalancerLiquidityPoolAbstraction } from "../contracts/modules/BalancerLiquidityPoolAbstraction.sol";

contract TestBalancerLiquidityPoolAbstraction is Env
{
	function test01() public
	{
		_burnAll(GRO);
		_burnAll(DAI);
		_mint(GRO, 10e18);
		_mint(DAI, 100e18);
		Assert.equal(_getBalance(GRO), 10e18, "GRO balance must be 10e18");
		Assert.equal(_getBalance(DAI), 100e18, "DAI balance must be 100e18");

		address _pool = BalancerLiquidityPoolAbstraction._createPool(GRO, 10e18, DAI, 100e18);

		Assert.equal(_getBalance(GRO), 0e18, "GRO balance must be 0e18");
		Assert.equal(_getBalance(DAI), 0e18, "DAI balance must be 0e18");

		_burnAll(_pool);

		BalancerLiquidityPoolAbstraction._joinPool(_pool, DAI, 0e18);

		Assert.equal(_getBalance(GRO), 0e18, "GRO balance must be 0e18");
		Assert.equal(_getBalance(DAI), 0e18, "DAI balance must be 0e18");

		_mint(DAI, 20e18);
		Assert.equal(_getBalance(GRO), 0e18, "GRO balance must be 0e18");
		Assert.equal(_getBalance(DAI), 20e18, "DAI balance must be 20e18");

		BalancerLiquidityPoolAbstraction._joinPool(_pool, DAI, 20e18);

		Assert.equal(_getBalance(GRO), 0e18, "GRO balance must be 0e18");
		Assert.equal(_getBalance(DAI), 0e18, "DAI balance must be 0e18");

		BalancerLiquidityPoolAbstraction._exitPool(_pool, 0e18);

		Assert.equal(_getBalance(GRO), 0e18, "GRO balance must be 0e18");
		Assert.equal(_getBalance(DAI), 0e18, "DAI balance must be 0e18");

		BalancerLiquidityPoolAbstraction._exitPool(_pool, 1e18);

		Assert.equal(_getBalance(GRO), 833015029829494720, "GRO balances must be 833015029829494720");
		Assert.equal(_getBalance(DAI), 9996180357953936640, "DAI balances must be 9996180357953936640");
	}

	function test02() public
	{
		_burnAll(GRO);
		_burnAll(DAI);
		_mint(GRO, 10e18);
		_mint(DAI, 100e18);
		Assert.equal(_getBalance(GRO), 10e18, "GRO balance must be 10e18");
		Assert.equal(_getBalance(DAI), 100e18, "DAI balance must be 100e18");

		address _pool = BalancerLiquidityPoolAbstraction._createPool(GRO, 10e18, DAI, 100e18);

		Assert.equal(_getBalance(GRO), 0e18, "GRO balance must be 0e18");
		Assert.equal(_getBalance(DAI), 0e18, "DAI balance must be 0e18");

		_burnAll(_pool);

		_mint(DAI, 51e18);
		Assert.equal(_getBalance(GRO), 0e18, "GRO balance must be 0e18");
		Assert.equal(_getBalance(DAI), 51e18, "DAI balance must be 51e18");

		BalancerLiquidityPoolAbstraction._joinPool(_pool, DAI, 51e18);

		Assert.equal(_getBalance(GRO), 0e18, "GRO balance must be 0e18");
		Assert.equal(_getBalance(DAI), 1e18, "DAI balance must be 1e18");
	}

	function test03() public
	{
		_burnAll(GRO);
		_burnAll(DAI);
		_mint(GRO, 10e18);
		_mint(DAI, 100e18);
		Assert.equal(_getBalance(GRO), 10e18, "GRO balance must be 10e18");
		Assert.equal(_getBalance(DAI), 100e18, "DAI balance must be 100e18");

		address _pool = BalancerLiquidityPoolAbstraction._createPool(GRO, 10e18, DAI, 100e18);

		Assert.equal(_getBalance(GRO), 0e18, "GRO balance must be 0e18");
		Assert.equal(_getBalance(DAI), 0e18, "DAI balance must be 0e18");

		BalancerLiquidityPoolAbstraction._exitPool(_pool, 1e18);

		Assert.equal(_getBalance(GRO), 10e18, "GRO balance must be 10e18");
		Assert.equal(_getBalance(DAI), 100e18, "DAI balance must be 100e18");
	}

	function test04() public
	{
		_burnAll(GRO);
		_burnAll(DAI);
		_mint(GRO, 1e6);
		_mint(DAI, 1e6);
		Assert.equal(_getBalance(GRO), 1e6, "GRO balance must be 1e6");
		Assert.equal(_getBalance(DAI), 1e6, "DAI balance must be 1e6");

		address _pool = BalancerLiquidityPoolAbstraction._createPool(GRO, 1e6, DAI, 1e6);

		Assert.equal(_getBalance(GRO), 0e18, "GRO balance must be 0e18");
		Assert.equal(_getBalance(DAI), 0e18, "DAI balance must be 0e18");

		BalancerLiquidityPoolAbstraction._exitPool(_pool, 1e18);

		Assert.equal(_getBalance(GRO), 1e6, "GRO balance must be 1e6");
		Assert.equal(_getBalance(DAI), 1e6, "DAI balance must be 1e6");

		BalancerLiquidityPoolAbstraction._joinPool(_pool, DAI, 1e6);

		Assert.equal(_getBalance(GRO), 1e6, "GRO balance must be 1e6");
		Assert.equal(_getBalance(DAI), 1e6, "DAI balance must be 1e6");
	}
}
