// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";

/**
 * @dev Pure implementation of deposit/minting and withdrawal/burning formulas
 *      for gTokens.
 *      All operations assume that, if total supply is 0, then the total
 *      reserve is also 0, and vice-versa.
 *      Fees are calculated percentually based on the gross amount.
 *      See GTokenBase.sol for further documentation.
 */
library GFormulae
{
	using SafeMath for uint256;

	/* deposit(cost):
	 *   price = reserve / supply
	 *   gross = cost / price
	 *   net = gross * 0.99	# fee is assumed to be 1% for simplicity
	 *   fee = gross - net
	 *   return net, fee
	 */
	function _calcDepositSharesFromCost(uint256 _cost, uint256 _totalReserve, uint256 _totalSupply, uint256 _depositFee) internal pure returns (uint256 _netShares, uint256 _feeShares)
	{
		uint256 _grossShares = _totalSupply == _totalReserve ? _cost : _cost.mul(_totalSupply).div(_totalReserve);
		_netShares = _grossShares.mul(uint256(1e18).sub(_depositFee)).div(1e18);
		_feeShares = _grossShares.sub(_netShares);
		return (_netShares, _feeShares);
	}

	/* deposit_reverse(net):
	 *   price = reserve / supply
	 *   gross = net / 0.99	# fee is assumed to be 1% for simplicity
	 *   cost = gross * price
	 *   fee = gross - net
	 *   return cost, fee
	 */
	function _calcDepositCostFromShares(uint256 _netShares, uint256 _totalReserve, uint256 _totalSupply, uint256 _depositFee) internal pure returns (uint256 _cost, uint256 _feeShares)
	{
		uint256 _grossShares = _netShares.mul(1e18).div(uint256(1e18).sub(_depositFee));
		_cost = _totalReserve == _totalSupply ? _grossShares : _grossShares.mul(_totalReserve).div(_totalSupply);
		_feeShares = _grossShares.sub(_netShares);
		return (_cost, _feeShares);
	}

	/* withdrawal_reverse(cost):
	 *   price = reserve / supply
	 *   net = cost / price
	 *   gross = net / 0.99	# fee is assumed to be 1% for simplicity
	 *   fee = gross - net
	 *   return gross, fee
	 */
	function _calcWithdrawalSharesFromCost(uint256 _cost, uint256 _totalReserve, uint256 _totalSupply, uint256 _withdrawalFee) internal pure returns (uint256 _grossShares, uint256 _feeShares)
	{
		uint256 _netShares = _cost == _totalReserve ? _totalSupply : _cost.mul(_totalSupply).div(_totalReserve);
		_grossShares = _netShares.mul(1e18).div(uint256(1e18).sub(_withdrawalFee));
		_feeShares = _grossShares.sub(_netShares);
		return (_grossShares, _feeShares);
	}

	/* withdrawal(gross):
	 *   price = reserve / supply
	 *   net = gross * 0.99	# fee is assumed to be 1% for simplicity
	 *   cost = net * price
	 *   fee = gross - net
	 *   return cost, fee
	 */
	function _calcWithdrawalCostFromShares(uint256 _grossShares, uint256 _totalReserve, uint256 _totalSupply, uint256 _withdrawalFee) internal pure returns (uint256 _cost, uint256 _feeShares)
	{
		uint256 _netShares = _grossShares.mul(uint256(1e18).sub(_withdrawalFee)).div(1e18);
		_cost = _netShares == _totalSupply ? _totalReserve : _netShares.mul(_totalReserve).div(_totalSupply);
		_feeShares = _grossShares.sub(_netShares);
		return (_cost, _feeShares);
	}
}
