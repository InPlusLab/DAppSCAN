// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";

import { Math } from "./Math.sol";
import { Transfers } from "./Transfers.sol";

import { BFactory, BPool } from "../interop/Balancer.sol";

import { $ } from "../network/$.sol";

/**
 * @dev This library abstracts the Balancer liquidity pool operations.
 */
library BalancerLiquidityPoolAbstraction
{
	using SafeMath for uint256;

	uint256 constant MIN_AMOUNT = 1e6; // transported from Balancer
	uint256 constant TOKEN0_WEIGHT = 25e18; // 25/50 = 50%
	uint256 constant TOKEN1_WEIGHT = 25e18; // 25/50 = 50%
	uint256 constant SWAP_FEE = 10e16; // 10%

	/**
	 * @dev Creates a two-asset liquidity pool and funds it by depositing
	 *      both assets. The create pool is public with a 50%/50%
	 *      distribution and 10% swap fee.
	 * @param _token0 The ERC-20 token for the first asset of the pair.
	 * @param _amount0 The amount of the first asset of the pair to be deposited.
	 * @param _token1 The ERC-20 token for the second asset of the pair.
	 * @param _amount1 The amount of the second asset of the pair to be deposited.
	 * @return _pool The address of the newly created pool.
	 */
	function _createPool(address _token0, uint256 _amount0, address _token1, uint256 _amount1) internal returns (address _pool)
	{
		require(_amount0 >= MIN_AMOUNT && _amount1 >= MIN_AMOUNT, "amount below the minimum");
		_pool = BFactory($.Balancer_FACTORY).newBPool();
		Transfers._approveFunds(_token0, _pool, _amount0);
		Transfers._approveFunds(_token1, _pool, _amount1);
		BPool(_pool).bind(_token0, _amount0, TOKEN0_WEIGHT);
		BPool(_pool).bind(_token1, _amount1, TOKEN1_WEIGHT);
		BPool(_pool).setSwapFee(SWAP_FEE);
		BPool(_pool).finalize();
		return _pool;
	}

	/**
	 * @dev Deposits a single asset into the liquidity pool.
	 * @param _pool The liquidity pool address.
	 * @param _token The ERC-20 token for the asset being deposited.
	 * @param _maxAmount The maximum amount to be deposited.
	 * @return _amount The actual amount deposited.
	 */
	function _joinPool(address _pool, address _token, uint256 _maxAmount) internal returns (uint256 _amount)
	{
		if (_maxAmount == 0) return 0;
		uint256 _balanceAmount = BPool(_pool).getBalance(_token);
		if (_balanceAmount == 0) return 0;
		// caps the deposit amount to half the liquidity to mitigate error
		uint256 _limitAmount = _balanceAmount.div(2);
		_amount = Math._min(_maxAmount, _limitAmount);
		Transfers._approveFunds(_token, _pool, _amount);
		BPool(_pool).joinswapExternAmountIn(_token, _amount, 0);
		return _amount;
	}

	/**
	 * @dev Withdraws a percentage of the pool shares.
	 * @param _pool The liquidity pool address.
	 * @param _percent The percent amount normalized to 1e18 (100%).
	 * @return _amount0 The amount received of the first asset of the pair.
	 * @return _amount1 The amount received of the second asset of the pair.
	 */
	function _exitPool(address _pool, uint256 _percent) internal returns (uint256 _amount0, uint256 _amount1)
	{
		if (_percent == 0) return (0, 0);
		address[] memory _tokens = BPool(_pool).getFinalTokens();
		_amount0 = Transfers._getBalance(_tokens[0]);
		_amount1 = Transfers._getBalance(_tokens[1]);
		uint256 _poolAmount = Transfers._getBalance(_pool);
		uint256 _poolExitAmount = _poolAmount.mul(_percent).div(1e18);
		uint256[] memory _minAmountsOut = new uint256[](2);
		_minAmountsOut[0] = 0;
		_minAmountsOut[1] = 0;
		BPool(_pool).exitPool(_poolExitAmount, _minAmountsOut);
		_amount0 = Transfers._getBalance(_tokens[0]).sub(_amount0);
		_amount1 = Transfers._getBalance(_tokens[1]).sub(_amount1);
		return (_amount0, _amount1);
	}
}
