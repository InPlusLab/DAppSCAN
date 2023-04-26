// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";

import { Transfers } from "./Transfers.sol";

import { LendingPool, LendingPoolCore } from "../interop/Aave.sol";

import { $ } from "../network/$.sol";

/**
 * @dev This library abstracts the Aave flash loan functionality. It has a
 *      standardized flash loan interface. See GFlashBorrower.sol,
 *      FlashLoans.sol, and DydxFlashLoanAbstraction.sol for further documentation.
 */
library AaveFlashLoanAbstraction
{
	using SafeMath for uint256;

	uint256 constant FLASH_LOAN_FEE_RATIO = 9e14; // 0.09%

	/**
	 * @dev Estimates the flash loan fee given the reserve token and required amount.
	 * @param _token The ERC-20 token to flash borrow from.
	 * @param _netAmount The amount to be borrowed without considering repay fees.
	 * @param _feeAmount the expected fee to be payed in excees of the loan amount.
	 */
	function _estimateFlashLoanFee(address _token, uint256 _netAmount) internal pure returns (uint256 _feeAmount)
	{
		_token; // silences warnings
		return _netAmount.mul(FLASH_LOAN_FEE_RATIO).div(1e18);
	}

	/**
	 * @dev Retrieves the current market liquidity for a given reserve.
	 * @param _token The reserve token to flash borrow from.
	 * @return _liquidityAmount The reserve token available market liquidity.
	 */
	function _getFlashLoanLiquidity(address _token) internal view returns (uint256 _liquidityAmount)
	{
		address _core = $.Aave_AAVE_LENDING_POOL_CORE;
		return LendingPoolCore(_core).getReserveAvailableLiquidity(_token);
	}

	/**
	 * @dev Triggers a flash loan. The current contract will receive a call
	 *      back with the loan amount and should repay it, including fees,
	 *      before returning. See GFlashBorrow.sol.
	 * @param _token The reserve token to flash borrow from.
	 * @param _netAmount The amount to be borrowed without considering repay fees.
	 * @param _context Additional data to be passed to the call back.
	 * @return _success A boolean indicating whether or not the operation suceeded.
         */
	function _requestFlashLoan(address _token, uint256 _netAmount, bytes memory _context) internal returns (bool _success)
	{
		address _pool = $.Aave_AAVE_LENDING_POOL;
		try LendingPool(_pool).flashLoan(address(this), _token, _netAmount, _context) {
			return true;
		} catch (bytes memory /* _data */) {
			return false;
		}
	}

	/**
	 * @dev This function should be called as the final step of the flash
	 *      loan to properly implement the repay of the loan.
	 * @param _token The reserve token.
	 * @param _grossAmount The amount to be repayed including repay fees.
	 */
	function _paybackFlashLoan(address _token, uint256 _grossAmount) internal
	{
		address _poolCore = $.Aave_AAVE_LENDING_POOL_CORE;
		Transfers._pushFunds(_token, _poolCore, _grossAmount);
	}
}
