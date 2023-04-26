// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";

import { Math } from "./Math.sol";
import { Wrapping } from "./Wrapping.sol";
import { Transfers } from "./Transfers.sol";

import { Comptroller, CPriceOracle, CToken } from "../interop/Compound.sol";

import { $ } from "../network/$.sol";

/**
 * @dev This library abstracts the Compound lending market. It has a standardized
 *      lending market interface. See AaveLendingMarket.sol.
 */
library CompoundLendingMarketAbstraction
{
	using SafeMath for uint256;

	/**
	 * @dev Retreives an underlying token given a cToken.
	 * @param _ctoken The Compound cToken address.
	 * @return _token The underlying reserve token.
	 */
	function _getUnderlyingToken(address _ctoken) internal view returns (address _token)
	{
		if (_ctoken == $.cETH) return $.WETH;
		return CToken(_ctoken).underlying();
	}

	/**
	 * @dev Retrieves the maximum collateralization ratio for a given cToken.
	 * @param _ctoken The Compound cToken address.
	 * @return _collateralRatio The percentual ratio normalized to 1e18 (100%).
	 */
	function _getCollateralRatio(address _ctoken) internal view returns (uint256 _collateralRatio)
	{
		address _comptroller = $.Compound_COMPTROLLER;
		(, _collateralRatio) = Comptroller(_comptroller).markets(_ctoken);
		return _collateralRatio;
	}

	/**
	 * @dev Retrieves the current market liquidity for a given cToken.
	 * @param _ctoken The Compound cToken address.
	 * @return _marketAmount The underlying reserve token available
	 *                       market liquidity.
	 */
	function _getMarketAmount(address _ctoken) internal view returns (uint256 _marketAmount)
	{
		return CToken(_ctoken).getCash();
	}

	/**
	 * @dev Retrieves the current account liquidity in terms of a cToken
	 *      underlying reserve.
	 * @param _ctoken The Compound cToken address.
	 * @return _liquidityAmount The available account liquidity for the
	 *                          underlying reserve token.
	 */
	function _getLiquidityAmount(address _ctoken) internal view returns (uint256 _liquidityAmount)
	{
		address _comptroller = $.Compound_COMPTROLLER;
		(uint256 _result, uint256 _liquidity, uint256 _shortfall) = Comptroller(_comptroller).getAccountLiquidity(address(this));
		if (_result != 0) return 0;
		if (_shortfall > 0) return 0;
		address _priceOracle = Comptroller(_comptroller).oracle();
		uint256 _price = CPriceOracle(_priceOracle).getUnderlyingPrice(_ctoken);
		return _liquidity.mul(1e18).div(_price);
	}

	/**
	 * @dev Retrieves the calculated account liquidity in terms of a cToken
	 *      underlying reserve. It also considers the current market liquidity.
	 *      A safety margin can be provided to deflate the actual liquidity amount.
	 * @param _ctoken The Compound cToken address.
	 * @param _marginAmount The safety room to be left in terms of the
	 *                      underlying reserve token.
	 * @return _availableAmount The safe available liquidity in terms of the
	 *                          underlying reserve token.
	 */
	function _getAvailableAmount(address _ctoken, uint256 _marginAmount) internal view returns (uint256 _availableAmount)
	{
		uint256 _liquidityAmount = _getLiquidityAmount(_ctoken);
		if (_liquidityAmount <= _marginAmount) return 0;
		return Math._min(_liquidityAmount.sub(_marginAmount), _getMarketAmount(_ctoken));
	}

	/**
	 * @dev Retrieves the last read-only exchange rate between the cToken
	 *      and its underlying reserve token.
	 * @param _ctoken The Compound cToken address.
	 * @return _exchangeRate The exchange rate between the cToken and its
	 *                       underlying reserve token.
	 */
	function _getExchangeRate(address _ctoken) internal view returns (uint256 _exchangeRate)
	{
		return CToken(_ctoken).exchangeRateStored();
	}

	/**
	 * @dev Retrieves the last up-to-date exchange rate between the cToken
	 *      and its underlying reserve token.
	 * @param _ctoken The Compound cToken address.
	 * @return _exchangeRate The exchange rate between the cToken and its
	 *                       underlying reserve token.
	 */
	function _fetchExchangeRate(address _ctoken) internal returns (uint256 _exchangeRate)
	{
		return CToken(_ctoken).exchangeRateCurrent();
	}

	/**
	 * @dev Retrieves the last read-only value for the cToken lending
	 *      balance in terms of its underlying reserve token.
	 * @param _ctoken The Compound cToken address.
	 * @return _amount The lending balance in terms of the underlying
	 *                 reserve token.
	 */
	function _getLendAmount(address _ctoken) internal view returns (uint256 _amount)
	{
		return CToken(_ctoken).balanceOf(address(this)).mul(_getExchangeRate(_ctoken)).div(1e18);
	}

	/**
	 * @dev Retrieves the last up-to-date value for the cToken lending
	 *      balance in terms of its underlying reserve token.
	 * @param _ctoken The Compound cToken address.
	 * @return _amount The lending balance in terms of the underlying
	 *                 reserve token.
	 */
	function _fetchLendAmount(address _ctoken) internal returns (uint256 _amount)
	{
		return CToken(_ctoken).balanceOfUnderlying(address(this));
	}

	/**
	 * @dev Retrieves the last read-only value for the cToken borrowing
	 *      balance in terms of its underlying reserve token.
	 * @param _ctoken The Compound cToken address.
	 * @return _amount The borrowing balance in terms of the underlying
	 *                 reserve token.
	 */
	function _getBorrowAmount(address _ctoken) internal view returns (uint256 _amount)
	{
		return CToken(_ctoken).borrowBalanceStored(address(this));
	}

	/**
	 * @dev Retrieves the last up-to-date value for the cToken borrowing
	 *      balance in terms of its underlying reserve token.
	 * @param _ctoken The Compound cToken address.
	 * @return _amount The borrowing balance in terms of the underlying
	 *                 reserve token.
	 */
	function _fetchBorrowAmount(address _ctoken) internal returns (uint256 _amount)
	{
		return CToken(_ctoken).borrowBalanceCurrent(address(this));
	}

	/**
	 * @dev Signals the usage of a given cToken underlying reserve as
	 *      collateral for borrowing funds in the lending market.
	 * @param _ctoken The Compound cToken address.
	 * @return _success A boolean indicating whether or not the operation suceeded.
	 */
	function _enter(address _ctoken) internal returns (bool _success)
	{
		address _comptroller = $.Compound_COMPTROLLER;
		address[] memory _ctokens = new address[](1);
		_ctokens[0] = _ctoken;
		try Comptroller(_comptroller).enterMarkets(_ctokens) returns (uint256[] memory _errorCodes) {
			return _errorCodes[0] == 0;
		} catch (bytes memory /* _data */) {
			return false;
		}
	}

	/**
	 * @dev Lend funds to a given cToken's market.
	 * @param _ctoken The Compound cToken address.
	 * @param _amount The amount of the underlying token to lend.
	 * @return _success A boolean indicating whether or not the operation suceeded.
	 */
	function _lend(address _ctoken, uint256 _amount) internal returns (bool _success)
	{
		if (_ctoken == $.cETH) {
			if (!Wrapping._unwrap(_amount)) return false;
			try CToken(_ctoken).mint{value: _amount}() {
				return true;
			} catch (bytes memory /* _data */) {
				assert(Wrapping._wrap(_amount));
				return false;
			}
		} else {
			address _token = _getUnderlyingToken(_ctoken);
			Transfers._approveFunds(_token, _ctoken, _amount);
			try CToken(_ctoken).mint(_amount) returns (uint256 _errorCode) {
				return _errorCode == 0;
			} catch (bytes memory /* _data */) {
				Transfers._approveFunds(_token, _ctoken, 0);
				return false;
			}
		}
	}

	/**
	 * @dev Redeem funds lent to a given cToken's market.
	 * @param _ctoken The Compound cToken address.
	 * @param _amount The amount of the underlying token to redeem.
	 * @return _success A boolean indicating whether or not the operation suceeded.
	 */
	function _redeem(address _ctoken, uint256 _amount) internal returns (bool _success)
	{
		if (_ctoken == $.cETH) {
			try CToken(_ctoken).redeemUnderlying(_amount) returns (uint256 _errorCode) {
				if (_errorCode == 0) {
					assert(Wrapping._wrap(_amount));
					return true;
				} else {
					return false;
				}
			} catch (bytes memory /* _data */) {
				return false;
			}
		} else {
			try CToken(_ctoken).redeemUnderlying(_amount) returns (uint256 _errorCode) {
				return _errorCode == 0;
			} catch (bytes memory /* _data */) {
				return false;
			}
		}
	}

	/**
	 * @dev Borrow funds from a given cToken's market.
	 * @param _ctoken The Compound cToken address.
	 * @param _amount The amount of the underlying token to borrow.
	 * @return _success A boolean indicating whether or not the operation suceeded.
	 */
	function _borrow(address _ctoken, uint256 _amount) internal returns (bool _success)
	{
		if (_ctoken == $.cETH) {
			try CToken(_ctoken).borrow(_amount) returns (uint256 _errorCode) {
				if (_errorCode == 0) {
					assert(Wrapping._wrap(_amount));
					return true;
				} else {
					return false;
				}
			} catch (bytes memory /* _data */) {
				return false;
			}
		} else {
			try CToken(_ctoken).borrow(_amount) returns (uint256 _errorCode) {
				return _errorCode == 0;
			} catch (bytes memory /* _data */) {
				return false;
			}
		}
	}

	/**
	 * @dev Repays a loan taken from a given cToken's market.
	 * @param _ctoken The Compound cToken address.
	 * @param _amount The amount of the underlying token to repay.
	 * @return _success A boolean indicating whether or not the operation suceeded.
	 */
	function _repay(address _ctoken, uint256 _amount) internal returns (bool _success)
	{
		if (_ctoken == $.cETH) {
			if (!Wrapping._unwrap(_amount)) return false;
			try CToken(_ctoken).repayBorrow{value: _amount}() {
				return true;
			} catch (bytes memory /* _data */) {
				assert(Wrapping._wrap(_amount));
				return false;
			}
		} else {
			address _token = _getUnderlyingToken(_ctoken);
			Transfers._approveFunds(_token, _ctoken, _amount);
			try CToken(_ctoken).repayBorrow(_amount) returns (uint256 _errorCode) {
				return _errorCode == 0;
			} catch (bytes memory /* _data */) {
				Transfers._approveFunds(_token, _ctoken, 0);
				return false;
			}
		}
	}

	/**
	 * @dev Signals the usage of a given cToken underlying reserve as
	 *      collateral for borrowing funds in the lending market. This
	 *      operation will revert if it does not succeed.
	 * @param _ctoken The Compound cToken address.
	 */
	function _safeEnter(address _ctoken) internal
	{
		require(_enter(_ctoken), "enter failed");
	}

	/**
	 * @dev Lend funds to a given cToken's market. This
	 *      operation will revert if it does not succeed.
	 * @param _ctoken The Compound cToken address.
	 * @param _amount The amount of the underlying token to lend.
	 */
	function _safeLend(address _ctoken, uint256 _amount) internal
	{
		require(_lend(_ctoken, _amount), "lend failure");
	}

	/**
	 * @dev Redeem funds lent to a given cToken's market. This
	 *      operation will revert if it does not succeed.
	 * @param _ctoken The Compound cToken address.
	 * @param _amount The amount of the underlying token to redeem.
	 */
	function _safeRedeem(address _ctoken, uint256 _amount) internal
	{
		require(_redeem(_ctoken, _amount), "redeem failure");
	}

	/**
	 * @dev Borrow funds from a given cToken's market. This
	 *      operation will revert if it does not succeed.
	 * @param _ctoken The Compound cToken address.
	 * @param _amount The amount of the underlying token to borrow.
	 */
	function _safeBorrow(address _ctoken, uint256 _amount) internal
	{
		require(_borrow(_ctoken, _amount), "borrow failure");
	}

	/**
	 * @dev Repays a loan taken from a given cToken's market. This
	 *      operation will revert if it does not succeed.
	 * @param _ctoken The Compound cToken address.
	 * @param _amount The amount of the underlying token to repay.
	 */
	function _safeRepay(address _ctoken, uint256 _amount) internal
	{
		require(_repay(_ctoken, _amount), "repay failure");
	}
}
