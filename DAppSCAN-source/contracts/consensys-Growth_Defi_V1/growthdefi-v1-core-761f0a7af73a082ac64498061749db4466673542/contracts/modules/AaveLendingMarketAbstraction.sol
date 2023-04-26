// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";

import { Math } from "./Math.sol";
import { Wrapping } from "./Wrapping.sol";
import { Transfers } from "./Transfers.sol";

import { LendingPoolAddressesProvider, LendingPool, LendingPoolCore, AToken, APriceOracle } from "../interop/Aave.sol";

import { $ } from "../network/$.sol";

/**
 * @dev This library abstracts the Aave lending market. It has a standardized
 *      lending market interface. See CompoundLendingMarket.sol.
 */
library AaveLendingMarketAbstraction
{
	using SafeMath for uint256;

	uint16 constant AAVE_REFERRAL_CODE = 0; // referral program ignored

	/**
	 * @dev Retreives an underlying token given an aToken.
	 * @param _atoken The Aave aToken address.
	 * @return _token The underlying reserve token.
	 */
	function _getUnderlyingToken(address _atoken) internal view returns (address _token)
	{
		if (_atoken == $.aETH) return $.WETH;
		return AToken(_atoken).underlyingAssetAddress();
	}

	/**
	 * @dev Retrieves the maximum collateralization ratio for a given aToken.
	 * @param _atoken The Aave aToken address.
	 * @return _collateralRatio The percentual ratio normalized to 1e18 (100%).
	 */
	function _getCollateralRatio(address _atoken) internal view returns (uint256 _collateralRatio)
	{
		address _pool = $.Aave_AAVE_LENDING_POOL;
		address _token = AToken(_atoken).underlyingAssetAddress();
		(_collateralRatio,,,,,,,) = LendingPool(_pool).getReserveConfigurationData(_token);
		return _collateralRatio.mul(1e16);
	}

	/**
	 * @dev Retrieves the current market liquidity for a given aToken.
	 * @param _atoken The Aave aToken address.
	 * @return _marketAmount The underlying reserve token available
	 *                       market liquidity.
	 */
	function _getMarketAmount(address _atoken) internal view returns (uint256 _marketAmount)
	{
		address _core = $.Aave_AAVE_LENDING_POOL_CORE;
		address _token = AToken(_atoken).underlyingAssetAddress();
		return LendingPoolCore(_core).getReserveAvailableLiquidity(_token);
	}

	/**
	 * @dev Retrieves the current account liquidity in terms of an aToken
	 *      underlying reserve.
	 * @param _atoken The Aave aToken address.
	 * @return _liquidityAmount The available account liquidity for the
	 *                          underlying reserve token.
	 */
	function _getLiquidityAmount(address _atoken) internal view returns (uint256 _liquidityAmount)
	{
		address _pool = $.Aave_AAVE_LENDING_POOL;
		address _token = AToken(_atoken).underlyingAssetAddress();
		(,,,,_liquidityAmount,,,) = LendingPool(_pool).getUserAccountData(address(this));
		if (_atoken == $.aETH) {
			return _liquidityAmount;
		} else {
			address _provider = $.Aave_AAVE_LENDING_POOL_ADDRESSES_PROVIDER;
			address _priceOracle = LendingPoolAddressesProvider(_provider).getPriceOracle();
			uint256 _price = APriceOracle(_priceOracle).getAssetPrice(_token);
			address _core = $.Aave_AAVE_LENDING_POOL_CORE;
			uint256 _decimals = LendingPoolCore(_core).getReserveDecimals(_token);
			if (_decimals > 18) {
				uint256 _factor = 10 ** (_decimals - 18);
				return _liquidityAmount.mul(uint256(1e18).mul(_factor)).div(_price);
			}
			if (_decimals < 18) {
				uint256 _factor = 10 ** (18 - _decimals);
				return _liquidityAmount.mul(1e18).div(_price.mul(_factor));
			}
			return _liquidityAmount.mul(1e18).div(_price);
		}
	}

	/**
	 * @dev Retrieves the calculated account liquidity in terms of an aToken
	 *      underlying reserve. It also considers the current market liquidity.
	 *      A safety margin can be provided to deflate the actual liquidity amount.
	 * @param _atoken The Aave aToken address.
	 * @param _marginAmount The safety room to be left in terms of the
	 *                      underlying reserve token.
	 * @return _availableAmount The safe available liquidity in terms of the
	 *                          underlying reserve token.
	 */
	function _getAvailableAmount(address _atoken, uint256 _marginAmount) internal view returns (uint256 _availableAmount)
	{
		uint256 _liquidityAmount = _getLiquidityAmount(_atoken);
		if (_liquidityAmount <= _marginAmount) return 0;
		return Math._min(_liquidityAmount.sub(_marginAmount), _getMarketAmount(_atoken));
	}

	/**
	 * @dev Retrieves the last read-only exchange rate between the aToken
	 *      and its underlying reserve token.
	 * @param _atoken The Aave aToken address.
	 * @return _exchangeRate The exchange rate between the aToken and its
	 *                       underlying reserve token.
	 */
	function _getExchangeRate(address _atoken) internal pure returns (uint256 _exchangeRate)
	{
		return _fetchExchangeRate(_atoken);
	}

	/**
	 * @dev Retrieves the last up-to-date exchange rate between the aToken
	 *      and its underlying reserve token.
	 * @param _atoken The Aave aToken address.
	 * @return _exchangeRate The exchange rate between the aToken and its
	 *                       underlying reserve token.
	 */
	function _fetchExchangeRate(address _atoken) internal pure returns (uint256 _exchangeRate)
	{
		_atoken; // silences warning
		return 1e18;
	}

	/**
	 * @dev Retrieves the last read-only value for the aToken lending
	 *      balance in terms of its underlying reserve token.
	 * @param _atoken The Aave aToken address.
	 * @return _amount The lending balance in terms of the underlying
	 *                 reserve token.
	 */
	function _getLendAmount(address _atoken) internal view returns (uint256 _amount)
	{
		return _fetchLendAmount(_atoken);
	}

	/**
	 * @dev Retrieves the last up-to-date value for the aToken lending
	 *      balance in terms of its underlying reserve token.
	 * @param _atoken The Aave aToken address.
	 * @return _amount The lending balance in terms of the underlying
	 *                 reserve token.
	 */
	function _fetchLendAmount(address _atoken) internal view returns (uint256 _amount)
	{
		address _pool = $.Aave_AAVE_LENDING_POOL;
		address _token = AToken(_atoken).underlyingAssetAddress();
		(_amount,,,,,,,,,) = LendingPool(_pool).getUserReserveData(_token, address(this));
		return _amount;
	}

	/**
	 * @dev Retrieves the last read-only value for the aToken borrowing
	 *      balance in terms of its underlying reserve token.
	 * @param _atoken The Aave aToken address.
	 * @return _amount The borrowing balance in terms of the underlying
	 *                 reserve token.
	 */
	function _getBorrowAmount(address _atoken) internal view returns (uint256 _amount)
	{
		return _fetchBorrowAmount(_atoken);
	}

	/**
	 * @dev Retrieves the last up-to-date value for the aToken borrowing
	 *      balance in terms of its underlying reserve token.
	 * @param _atoken The Aave aToken address.
	 * @return _amount The borrowing balance in terms of the underlying
	 *                 reserve token.
	 */
	function _fetchBorrowAmount(address _atoken) internal view returns (uint256 _amount)
	{
		address _pool = $.Aave_AAVE_LENDING_POOL;
		address _token = AToken(_atoken).underlyingAssetAddress();
		(,uint256 _netAmount,,,,,uint256 _feeAmount,,,) = LendingPool(_pool).getUserReserveData(_token, address(this));
		return _netAmount.add(_feeAmount);
	}

	/**
	 * @dev Signals the usage of a given aToken underlying reserve as
	 *      collateral for borrowing funds in the lending market.
	 * @param _atoken The Aave aToken address.
	 * @return _success A boolean indicating whether or not the operation suceeded.
	 */
	function _enter(address _atoken) internal pure returns (bool _success)
	{
		_atoken; // silences warnings
		return true;
	}

	/**
	 * @dev Lend funds to a given aToken's market.
	 * @param _atoken The Aave aToken address.
	 * @param _amount The amount of the underlying token to lend.
	 * @return _success A boolean indicating whether or not the operation suceeded.
	 */
	function _lend(address _atoken, uint256 _amount) internal returns (bool _success)
	{
		if (_amount == 0) return true;
		address _pool = $.Aave_AAVE_LENDING_POOL;
		address _token = AToken(_atoken).underlyingAssetAddress();
		if (_atoken == $.aETH) {
			if (!Wrapping._unwrap(_amount)) return false;
			try LendingPool(_pool).deposit{value: _amount}(_token, _amount, AAVE_REFERRAL_CODE) {
				return true;
			} catch (bytes memory /* _data */) {
				assert(Wrapping._wrap(_amount));
				return false;
			}
		} else {
			address _core = $.Aave_AAVE_LENDING_POOL_CORE;
			Transfers._approveFunds(_token, _core, _amount);
			try LendingPool(_pool).deposit(_token, _amount, AAVE_REFERRAL_CODE) {
				return true;
			} catch (bytes memory /* _data */) {
				Transfers._approveFunds(_token, _core, 0);
				return false;
			}
		}
	}

	/**
	 * @dev Redeem funds lent to a given aToken's market.
	 * @param _atoken The Aave aToken address.
	 * @param _amount The amount of the underlying token to redeem.
	 * @return _success A boolean indicating whether or not the operation suceeded.
	 */
	function _redeem(address _atoken, uint256 _amount) internal returns (bool _success)
	{
		if (_amount == 0) return true;
		if (_atoken == $.aETH) {
			try AToken(_atoken).redeem(_amount) {
				assert(Wrapping._wrap(_amount));
				return true;
			} catch (bytes memory /* _data */) {
				return false;
			}
		} else {
			try AToken(_atoken).redeem(_amount) {
				return true;
			} catch (bytes memory /* _data */) {
				return false;
			}
		}
	}

	/**
	 * @dev Borrow funds from a given aToken's market.
	 * @param _atoken The Aave aToken address.
	 * @param _amount The amount of the underlying token to borrow.
	 * @return _success A boolean indicating whether or not the operation suceeded.
	 */
	function _borrow(address _atoken, uint256 _amount) internal returns (bool _success)
	{
		if (_amount == 0) return true;
		address _pool = $.Aave_AAVE_LENDING_POOL;
		address _token = AToken(_atoken).underlyingAssetAddress();
		if (_atoken == $.aETH) {
			try LendingPool(_pool).borrow(_token, _amount, 2, AAVE_REFERRAL_CODE) {
				assert(Wrapping._wrap(_amount));
				return true;
			} catch (bytes memory /* _data */) {
				return false;
			}
		} else {
			try LendingPool(_pool).borrow(_token, _amount, 2, AAVE_REFERRAL_CODE) {
				return true;
			} catch (bytes memory /* _data */) {
				return false;
			}
		}
	}

	/**
	 * @dev Repays a loan taken from a given aToken's market.
	 * @param _atoken The Aave aToken address.
	 * @param _amount The amount of the underlying token to repay.
	 * @return _success A boolean indicating whether or not the operation suceeded.
	 */
	function _repay(address _atoken, uint256 _amount) internal returns (bool _success)
	{
		if (_amount == 0) return true;
		address _pool = $.Aave_AAVE_LENDING_POOL;
		address _token = AToken(_atoken).underlyingAssetAddress();
		address payable _self = payable(address(this));
		if (_atoken == $.aETH) {
			if (!Wrapping._unwrap(_amount)) return false;
			try LendingPool(_pool).repay{value: _amount}(_token, _amount, _self) {
				return true;
			} catch (bytes memory /* _data */) {
				assert(Wrapping._wrap(_amount));
				return false;
			}
		} else {
			address _core = $.Aave_AAVE_LENDING_POOL_CORE;
			Transfers._approveFunds(_token, _core, _amount);
			try LendingPool(_pool).repay(_token, _amount, _self) {
				return true;
			} catch (bytes memory /* _data */) {
				Transfers._approveFunds(_token, _core, 0);
				return false;
			}
		}
	}

	/**
	 * @dev Signals the usage of a given aToken underlying reserve as
	 *      collateral for borrowing funds in the lending market. This
	 *      operation will revert if it does not succeed.
	 * @param _atoken The Aave aToken address.
	 */
	function _safeEnter(address _atoken) internal pure
	{
		require(_enter(_atoken), "enter failed");
	}

	/**
	 * @dev Lend funds to a given aToken's market. This
	 *      operation will revert if it does not succeed.
	 * @param _atoken The Aave aToken address.
	 * @param _amount The amount of the underlying token to lend.
	 */
	function _safeLend(address _atoken, uint256 _amount) internal
	{
		require(_lend(_atoken, _amount), "lend failure");
	}

	/**
	 * @dev Redeem funds lent to a given aToken's market. This
	 *      operation will revert if it does not succeed.
	 * @param _atoken The Aave aToken address.
	 * @param _amount The amount of the underlying token to redeem.
	 */
	function _safeRedeem(address _atoken, uint256 _amount) internal
	{
		require(_redeem(_atoken, _amount), "redeem failure");
	}

	/**
	 * @dev Borrow funds from a given aToken's market. This
	 *      operation will revert if it does not succeed.
	 * @param _atoken The Aave aToken address.
	 * @param _amount The amount of the underlying token to borrow.
	 */
	function _safeBorrow(address _atoken, uint256 _amount) internal
	{
		require(_borrow(_atoken, _amount), "borrow failure");
	}

	/**
	 * @dev Repays a loan taken from a given aToken's market. This
	 *      operation will revert if it does not succeed.
	 * @param _atoken The Aave aToken address.
	 * @param _amount The amount of the underlying token to repay.
	 */
	function _safeRepay(address _atoken, uint256 _amount) internal
	{
		require(_repay(_atoken, _amount), "repay failure");
	}
}
