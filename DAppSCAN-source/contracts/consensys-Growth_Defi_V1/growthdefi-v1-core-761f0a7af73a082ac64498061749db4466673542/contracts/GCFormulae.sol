// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";

import { GFormulae } from "./GFormulae.sol";

/**
 * @dev Pure implementation of deposit/minting and withdrawal/burning formulas
 *      for gTokens calculated based on the cToken underlying asset
 *      (e.g. DAI for cDAI). See GFormulae.sol and GCTokenBase.sol for further
 *      documentation.
 */
library GCFormulae
{
	using SafeMath for uint256;

	/**
	 * @dev Simple token to cToken formula from Compound
	 */
	function _calcCostFromUnderlyingCost(uint256 _underlyingCost, uint256 _exchangeRate) internal pure returns (uint256 _cost)
	{
		return _underlyingCost.mul(1e18).div(_exchangeRate);
	}

	/**
	 * @dev Simple cToken to token formula from Compound
	 */
	function _calcUnderlyingCostFromCost(uint256 _cost, uint256 _exchangeRate) internal pure returns (uint256 _underlyingCost)
	{
		return _cost.mul(_exchangeRate).div(1e18);
	}

	/**
	 * @dev Composition of the gToken deposit formula with the Compound
	 *      conversion formula to obtain the gcToken deposit formula in
	 *      terms of the cToken underlying asset.
	 */
	function _calcDepositSharesFromUnderlyingCost(uint256 _underlyingCost, uint256 _totalReserve, uint256 _totalSupply, uint256 _depositFee, uint256 _exchangeRate) internal pure returns (uint256 _netShares, uint256 _feeShares)
	{
		uint256 _cost = _calcCostFromUnderlyingCost(_underlyingCost, _exchangeRate);
		return GFormulae._calcDepositSharesFromCost(_cost, _totalReserve, _totalSupply, _depositFee);
	}

	/**
	 * @dev Composition of the gToken reserve deposit formula with the
	 *      Compound conversion formula to obtain the gcToken reverse
	 *      deposit formula in terms of the cToken underlying asset.
	 */
	function _calcDepositUnderlyingCostFromShares(uint256 _netShares, uint256 _totalReserve, uint256 _totalSupply, uint256 _depositFee, uint256 _exchangeRate) internal pure returns (uint256 _underlyingCost, uint256 _feeShares)
	{
		uint256 _cost;
		(_cost, _feeShares) = GFormulae._calcDepositCostFromShares(_netShares, _totalReserve, _totalSupply, _depositFee);
		return (_calcUnderlyingCostFromCost(_cost, _exchangeRate), _feeShares);
	}

	/**
	 * @dev Composition of the gToken reserve withdrawal formula with the
	 *      Compound conversion formula to obtain the gcToken reverse
	 *      withdrawal formula in terms of the cToken underlying asset.
	 */
	function _calcWithdrawalSharesFromUnderlyingCost(uint256 _underlyingCost, uint256 _totalReserve, uint256 _totalSupply, uint256 _withdrawalFee, uint256 _exchangeRate) internal pure returns (uint256 _grossShares, uint256 _feeShares)
	{
		uint256 _cost = _calcCostFromUnderlyingCost(_underlyingCost, _exchangeRate);
		return GFormulae._calcWithdrawalSharesFromCost(_cost, _totalReserve, _totalSupply, _withdrawalFee);
	}

	/**
	 * @dev Composition of the gToken withdrawal formula with the Compound
	 *      conversion formula to obtain the gcToken withdrawal formula in
	 *      terms of the cToken underlying asset.
	 */
	function _calcWithdrawalUnderlyingCostFromShares(uint256 _grossShares, uint256 _totalReserve, uint256 _totalSupply, uint256 _withdrawalFee, uint256 _exchangeRate) internal pure returns (uint256 _underlyingCost, uint256 _feeShares)
	{
		uint256 _cost;
		(_cost, _feeShares) = GFormulae._calcWithdrawalCostFromShares(_grossShares, _totalReserve, _totalSupply, _withdrawalFee);
		return (_calcUnderlyingCostFromCost(_cost, _exchangeRate), _feeShares);
	}
}
