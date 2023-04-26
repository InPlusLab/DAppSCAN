// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";

import { G } from "./G.sol";

import { FlashLoanReceiver } from "./interop/Aave.sol";
import { ICallee, Account } from "./interop/Dydx.sol";

import { FlashLoans } from "./modules/FlashLoans.sol";

import { $ } from "./network/$.sol";

/**
 * @dev This abstract contract provides an uniform interface for receiving
 *      flash loans. It encapsulates the required functionality provided by
 *      both Aave and Dydx. It performs the basic validation to ensure that
 *      only Aave/Dydx contracts can dispatch the operation and only the
 *      current contract (that inherits from it) can initiate it.
 */
abstract contract GFlashBorrower is FlashLoanReceiver, ICallee
{
	using SafeMath for uint256;

	uint256 private allowOperationLevel = 0;

	/**
	 * @dev Handy definition to ensure that flash loans are only initiated
	 *      from within the current contract.
	 */
	modifier mayFlashBorrow()
	{
		allowOperationLevel++;
		_;
		allowOperationLevel--;
	}

	/**
	 * @dev Handles Aave callback. Delegates the processing of the funds
	 *      to the virtual function _processFlashLoan and later takes care
	 *      of paying it back.
	 * @param _token The ERC-20 contract address.
	 * @param _amount The amount being borrowed.
	 * @param _fee The fee, in addition to the amount borrowed, to be repaid.
	 * @param _params Additional user parameters provided when the flash
	 *                loan was requested.
	 */
	function executeOperation(address _token, uint256 _amount, uint256 _fee, bytes calldata _params) external override
	{
		assert(allowOperationLevel > 0);
		address _from = msg.sender;
		address _pool = $.Aave_AAVE_LENDING_POOL;
		assert(_from == _pool);
		require(_processFlashLoan(_token, _amount, _fee, _params)/*, "failure processing flash loan"*/);
		G.paybackFlashLoan(FlashLoans.Provider.Aave, _token, _amount.add(_fee));
	}

	/**
	 * @dev Handles Dydx callback. Delegates the processing of the funds
	 *      to the virtual function _processFlashLoan and later takes care
	 *      of paying it back.
	 * @param _sender The contract address of the initiator of the flash
	 *                loan, expected to be the current contract.
	 * @param _account Dydx account info provided in the callback.
	 * @param _data Aditional external data provided to the Dydx callback,
	 *              this is used by the Dydx module to pass the ERC-20 token
	 *              address, the amount and fee, as well as user parameters.
	 */
	function callFunction(address _sender, Account.Info memory _account, bytes memory _data) external override
	{
		assert(allowOperationLevel > 0);
		address _from = msg.sender;
		address _solo = $.Dydx_SOLO_MARGIN;
		assert(_from == _solo);
		assert(_sender == address(this));
		assert(_account.owner == address(this));
		(address _token, uint256 _amount, uint256 _fee, bytes memory _params) = abi.decode(_data, (address,uint256,uint256,bytes));
		require(_processFlashLoan(_token, _amount, _fee, _params)/*, "failure processing flash loan"*/);
		G.paybackFlashLoan(FlashLoans.Provider.Dydx, _token, _amount.add(_fee));
	}

	/**
	 * @dev Internal function that abstracts the algorithm to be performed
	 *      with borrowed funds. It receives the funds, deposited in the
	 *      current contract, and must ensure they are available as balance
	 *      of the current contract, including fees, before it returns.
	 * @param _token The ERC-20 contract address.
	 * @param _amount The amount being borrowed.
	 * @param _fee The fee, in addition to the amount borrowed, to be repaid.
	 * @param _params Additional user parameters provided when the flash
	 *                loan was requested.
	 * @return _success A boolean indicating success.
	 */
	function _processFlashLoan(address _token, uint256 _amount, uint256 _fee, bytes memory _params) internal virtual returns (bool _success);
}
