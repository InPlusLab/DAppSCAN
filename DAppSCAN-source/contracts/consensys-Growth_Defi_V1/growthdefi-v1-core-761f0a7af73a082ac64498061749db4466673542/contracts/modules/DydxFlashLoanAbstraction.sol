// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { Transfers } from "./Transfers.sol";

import { SoloMargin, Account, Actions, Types } from "../interop/Dydx.sol";

import { $ } from "../network/$.sol";

/**
 * @dev This library abstracts the Dydx flash loan functionality. It has a
 *      standardized flash loan interface. See GFlashBorrower.sol,
 *      FlashLoans.sol, and AaveFlashLoanAbstraction.sol for further documentation.
 */
library DydxFlashLoanAbstraction
{
	using SafeMath for uint256;

	/**
	 * @dev Estimates the flash loan fee given the reserve token and required amount.
	 * @param _token The ERC-20 token to flash borrow from.
	 * @param _netAmount The amount to be borrowed without considering repay fees.
	 * @param _feeAmount the expected fee to be payed in excees of the loan amount.
	 */
	function _estimateFlashLoanFee(address _token, uint256 _netAmount) internal pure returns (uint256 _feeAmount)
	{
		_token; _netAmount; // silences warnings
		return 2; // dydx has no fees, 2 wei is just a recommendation
	}

	/**
	 * @dev Retrieves the current market liquidity for a given reserve.
	 * @param _token The reserve token to flash borrow from.
	 * @return _liquidityAmount The reserve token available market liquidity.
	 */
	function _getFlashLoanLiquidity(address _token) internal view returns (uint256 _liquidityAmount)
	{
		address _solo = $.Dydx_SOLO_MARGIN;
		return IERC20(_token).balanceOf(_solo);
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
		address _solo = $.Dydx_SOLO_MARGIN;
		uint256 _feeAmount = 2;
		uint256 _grossAmount = _netAmount.add(_feeAmount);
		// attempts to find the market id given a reserve token
		uint256 _marketId = uint256(-1);
		uint256 _numMarkets = SoloMargin(_solo).getNumMarkets();
		// SWC-128-DoS With Block Gas Limit: L64-70
		for (uint256 _i = 0; _i < _numMarkets; _i++) {
			address _address = SoloMargin(_solo).getMarketTokenAddress(_i);
			if (_address == _token) {
				_marketId = _i;
				break;
			}
		}
		if (_marketId == uint256(-1)) return false;
		// a flash loan on Dydx is achieved by the following sequence of
		// actions: withdrawal, user call back, and finally a deposit;
		// which is configured below
		Account.Info[] memory _accounts = new Account.Info[](1);
		_accounts[0] = Account.Info({ owner: address(this), number: 1 });
		Actions.ActionArgs[] memory _actions = new Actions.ActionArgs[](3);
		_actions[0] = Actions.ActionArgs({
			actionType: Actions.ActionType.Withdraw,
			accountId: 0,
			amount: Types.AssetAmount({
				sign: false,
				denomination: Types.AssetDenomination.Wei,
				ref: Types.AssetReference.Delta,
				value: _netAmount
			}),
			primaryMarketId: _marketId,
			secondaryMarketId: 0,
			otherAddress: address(this),
			otherAccountId: 0,
			data: ""
		});
		_actions[1] = Actions.ActionArgs({
			actionType: Actions.ActionType.Call,
			accountId: 0,
			amount: Types.AssetAmount({
				sign: false,
				denomination: Types.AssetDenomination.Wei,
				ref: Types.AssetReference.Delta,
				value: 0
			}),
			primaryMarketId: 0,
			secondaryMarketId: 0,
			otherAddress: address(this),
			otherAccountId: 0,
			data: abi.encode(_token, _netAmount, _feeAmount, _context)
		});
		_actions[2] = Actions.ActionArgs({
			actionType: Actions.ActionType.Deposit,
			accountId: 0,
			amount: Types.AssetAmount({
				sign: true,
				denomination: Types.AssetDenomination.Wei,
				ref: Types.AssetReference.Delta,
				value: _grossAmount
			}),
			primaryMarketId: _marketId,
			secondaryMarketId: 0,
			otherAddress: address(this),
			otherAccountId: 0,
			data: ""
		});
		try SoloMargin(_solo).operate(_accounts, _actions) {
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
		address _solo = $.Dydx_SOLO_MARGIN;
		Transfers._approveFunds(_token, _solo, _grossAmount);
	}
}
