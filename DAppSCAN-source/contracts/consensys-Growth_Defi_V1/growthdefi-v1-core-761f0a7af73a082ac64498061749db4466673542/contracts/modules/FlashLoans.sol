// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { Math } from "./Math.sol";
import { AaveFlashLoanAbstraction } from "./AaveFlashLoanAbstraction.sol";
import { DydxFlashLoanAbstraction } from "./DydxFlashLoanAbstraction.sol";

import { $ } from "../network/$.sol";

/**
 * @dev This library abstracts the flash loan request combining both Aave/Dydx.
 *      See GFlashBorrower.sol, AaveFlashLoanAbstraction.sol, and
 *      DydxFlashLoanAbstraction.sol for further documentation.
 */
library FlashLoans
{
	enum Provider { Aave, Dydx }

	/**
	 * @dev Estimates the flash loan fee given the reserve token and required amount.
	 * @param _provider The flash loan provider, either Aave or Dydx.
	 * @param _token The ERC-20 token to flash borrow from.
	 * @param _netAmount The amount to be borrowed without considering repay fees.
	 * @param _feeAmount the expected fee to be payed in excees of the loan amount.
	 */
	function _estimateFlashLoanFee(Provider _provider, address _token, uint256 _netAmount) internal pure returns (uint256 _feeAmount)
	{
		if (_provider == Provider.Aave) return AaveFlashLoanAbstraction._estimateFlashLoanFee(_token, _netAmount);
		if (_provider == Provider.Dydx) return DydxFlashLoanAbstraction._estimateFlashLoanFee(_token, _netAmount);
	}

	/**
	 * @dev Retrieves the maximum market liquidity for a given reserve on
	 *      both Aave and Dydx.
	 * @param _token The reserve token to flash borrow from.
	 * @return _liquidityAmount The reserve token available market liquidity.
	 */
	function _getFlashLoanLiquidity(address _token) internal view returns (uint256 _liquidityAmount)
	{
		uint256 _liquidityAmountDydx = 0;
		if ($.NETWORK == $.Network.Mainnet || $.NETWORK == $.Network.Kovan) {
			_liquidityAmountDydx = DydxFlashLoanAbstraction._getFlashLoanLiquidity(_token);
		}
		uint256 _liquidityAmountAave = 0;
		if ($.NETWORK == $.Network.Mainnet || $.NETWORK == $.Network.Ropsten || $.NETWORK == $.Network.Kovan) {
			_liquidityAmountAave = AaveFlashLoanAbstraction._getFlashLoanLiquidity(_token);
		}
		return Math._max(_liquidityAmountDydx, _liquidityAmountAave);
	}

	/**
	 * @dev Triggers a flash loan on Dydx and, if unsuccessful, on Aave.
	 *      The current contract will receive a call back with the loan
	 *      amount and should repay it, including fees, before returning.
	 *      See GFlashBorrow.sol.
	 * @param _token The reserve token to flash borrow from.
	 * @param _netAmount The amount to be borrowed without considering repay fees.
	 * @param _context Additional data to be passed to the call back.
	 * @return _success A boolean indicating whether or not the operation suceeded.
         */
	function _requestFlashLoan(address _token, uint256 _netAmount, bytes memory _context) internal returns (bool _success)
	{
		if ($.NETWORK == $.Network.Mainnet || $.NETWORK == $.Network.Kovan) {
			_success = DydxFlashLoanAbstraction._requestFlashLoan(_token, _netAmount, _context);
			if (_success) return true;
		}
		if ($.NETWORK == $.Network.Mainnet || $.NETWORK == $.Network.Ropsten || $.NETWORK == $.Network.Kovan) {
			_success = AaveFlashLoanAbstraction._requestFlashLoan(_token, _netAmount, _context);
			if (_success) return true;
		}
		return false;
	}

	/**
	 * @dev This function should be called as the final step of the flash
	 *      loan to properly implement the repay of the loan.
	 * @param _provider The flash loan provider, either Aave or Dydx.
	 * @param _token The reserve token.
	 * @param _grossAmount The amount to be repayed including repay fees.
	 */
	function _paybackFlashLoan(Provider _provider, address _token, uint256 _grossAmount) internal
	{
		if (_provider == Provider.Aave) return AaveFlashLoanAbstraction._paybackFlashLoan(_token, _grossAmount);
		if (_provider == Provider.Dydx) return DydxFlashLoanAbstraction._paybackFlashLoan(_token, _grossAmount);
	}
}
