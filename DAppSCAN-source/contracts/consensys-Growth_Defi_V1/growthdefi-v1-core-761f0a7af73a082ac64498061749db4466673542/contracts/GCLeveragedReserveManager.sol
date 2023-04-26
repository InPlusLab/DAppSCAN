// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";

import { G } from "./G.sol";
import { GC } from "./GC.sol";

/**
 * @dev This library implements data structure abstraction for the leveraged
 *      reserve management code in order to circuvent the EVM contract size limit.
 *      It is therefore a public library shared by all gcToken Type 1 contracts and
 *      needs to be published alongside them. See GCTokenType1.sol for further
 *      documentation.
 */
library GCLeveragedReserveManager
{
	using SafeMath for uint256;
	using GCLeveragedReserveManager for GCLeveragedReserveManager.Self;

	uint256 constant MAXIMUM_COLLATERALIZATION_RATIO = 98e16; // 98% of 75% = 73.5%
	uint256 constant DEFAULT_COLLATERALIZATION_RATIO = 94e16; // 94% of 75% = 70.5%
	uint256 constant DEFAULT_COLLATERALIZATION_MARGIN = 2e16; // 2% of 75% = 1.5%

	struct Self {
		address reserveToken;
		address underlyingToken;

		address exchange;

		address miningToken;
		uint256 miningMinGulpAmount;
		uint256 miningMaxGulpAmount;

		uint256 collateralizationRatio;
		uint256 collateralizationMargin;
	}

	/**
	 * @dev Initializes the data structure. This method is exposed publicly.
	 * @param _reserveToken The ERC-20 token address of the reserve token (cToken).
	 * @param _miningToken The ERC-20 token address to be collected from
	 *                     liquidity mining (COMP).
	 */
	function init(Self storage _self, address _reserveToken, address _miningToken) public
	{
		address _underlyingToken = GC.getUnderlyingToken(_reserveToken);

		_self.reserveToken = _reserveToken;
		_self.underlyingToken = _underlyingToken;

		_self.exchange = address(0);

		_self.miningToken = _miningToken;
		_self.miningMinGulpAmount = 0;
		_self.miningMaxGulpAmount = 0;

		_self.collateralizationRatio = DEFAULT_COLLATERALIZATION_RATIO;
		_self.collateralizationMargin = DEFAULT_COLLATERALIZATION_MARGIN;

		GC.safeEnter(_reserveToken);
	}

	/**
	 * @dev Sets the contract address for asset conversion delegation.
	 *      This library converts the miningToken into the underlyingToken
	 *      and use the assets to back the reserveToken. See GExchange.sol
	 *      for further documentation. This method is exposed publicly.
	 * @param _exchange The address of the contract that implements the
	 *                  GExchange interface.
	 */
	function setExchange(Self storage _self, address _exchange) public
	{
		_self.exchange = _exchange;
	}

	/**
	 * @dev Sets the range for converting liquidity mining assets. This
	 *      method is exposed publicly.
	 * @param _miningMinGulpAmount The minimum amount, funds will only be
	 *                             converted once the minimum is accumulated.
	 * @param _miningMaxGulpAmount The maximum amount, funds beyond this
	 *                             limit will not be converted and are left
	 *                             for future rounds of conversion.
	 */
	function setMiningGulpRange(Self storage _self, uint256 _miningMinGulpAmount, uint256 _miningMaxGulpAmount) public
	{
		require(_miningMinGulpAmount <= _miningMaxGulpAmount, "invalid range");
		_self.miningMinGulpAmount = _miningMinGulpAmount;
		_self.miningMaxGulpAmount = _miningMaxGulpAmount;
	}

	/**
	 * @dev Sets the collateralization ratio and margin. These values are
	 *      percentual and relative to the maximum collateralization ratio
	 *      provided by the underlying asset. This method is exposed publicly.
	 * @param _collateralizationRatio The target collateralization ratio,
	 *                                between lend and borrow, that the
	 *                                reserve will try to maintain.
	 * @param _collateralizationMargin The deviation from the target ratio
	 *                                 that should be accepted.
	 */
	function setCollateralizationRatio(Self storage _self, uint256 _collateralizationRatio, uint256 _collateralizationMargin) public
	{
		require(_collateralizationMargin <= _collateralizationRatio && _collateralizationRatio.add(_collateralizationMargin) <= MAXIMUM_COLLATERALIZATION_RATIO, "invalid ratio");
		_self.collateralizationRatio = _collateralizationRatio;
		_self.collateralizationMargin = _collateralizationMargin;
	}

	/**
	 * @dev Performs the reserve adjustment actions leaving a liquidity room,
	 *      if necessary. It will attempt to incorporate the liquidity mining
	 *      assets into the reserve and adjust the collateralization
	 *      targeting the configured ratio. This method is exposed publicly.
	 * @param _roomAmount The underlying token amount to be available after the
	 *                    operation. This is revelant for withdrawals, once the
	 *                    room amount is withdrawn the reserve should reflect
	 *                    the configured collateralization ratio.
	 * @return _success A boolean indicating whether or not both actions suceeded.
	 */
	function adjustReserve(Self storage _self, uint256 _roomAmount) public returns (bool _success)
	{
		bool success1 = _self._gulpMiningAssets();
		bool success2 = _self._adjustLeverage(_roomAmount);
		return success1 && success2;
	}

	/**
	 * @dev Calculates the collateralization ratio and range relative to the
	 *      maximum collateralization ratio provided by the underlying asset.
	 * @return _collateralizationRatio The target absolute collateralization ratio.
	 * @return _minCollateralizationRatio The minimum absolute collateralization ratio.
	 * @return _maxCollateralizationRatio The maximum absolute collateralization ratio.
	 */
	function _calcCollateralizationRatio(Self storage _self) internal view returns (uint256 _collateralizationRatio, uint256 _minCollateralizationRatio, uint256 _maxCollateralizationRatio)
	{
		uint256 _collateralRatio = GC.getCollateralRatio(_self.reserveToken);
		_collateralizationRatio = _collateralRatio.mul(_self.collateralizationRatio).div(1e18);
		_minCollateralizationRatio = _collateralRatio.mul(_self.collateralizationRatio.sub(_self.collateralizationMargin)).div(1e18);
		_maxCollateralizationRatio = _collateralRatio.mul(_self.collateralizationRatio.add(_self.collateralizationMargin)).div(1e18);
		return (_collateralizationRatio, _minCollateralizationRatio, _maxCollateralizationRatio);
	}

	/**
	 * @dev Incorporates the liquidity mining assets into the reserve. Assets
	 *      are converted to the underlying asset and then added to the reserve.
	 *      If the amount available is below the minimum, or if the exchange
	 *      contract is not set, nothing is done. Otherwise the operation is
	 *      performed, limited to the maximum amount. Note that this operation
	 *      will incorporate to the reserve all the underlying token balance
	 *      including funds sent to it or left over somehow.
	 * @return _success A boolean indicating whether or not the action succeeded.
	 */
	function _gulpMiningAssets(Self storage _self) internal returns (bool _success)
	{
		if (_self.exchange == address(0)) return true;
		if (_self.miningMaxGulpAmount == 0) return true;
		uint256 _miningAmount = G.getBalance(_self.miningToken);
		if (_miningAmount == 0) return true;
		if (_miningAmount < _self.miningMinGulpAmount) return true;
		_self._convertMiningToUnderlying(G.min(_miningAmount, _self.miningMaxGulpAmount));
		return GC.lend(_self.reserveToken, G.getBalance(_self.underlyingToken));
	}

	/**
	 * @dev Adjusts the reserve to match the configured collateralization
	 *      ratio. It calculates how much the collateralization must be
	 *      increased or decreased and either: 1) lend/borrow, or
	 *      2) repay/redeem, respectivelly. The funds required to perform
	 *      the operation are obtained via FlashLoan to avoid having to
	 *      maneuver around margin when moving in/out of leverage.
	 * @param _roomAmount The amount of underlying token to be liquid after
	 *                    the operation.
	 * @return _success A boolean indicating whether or not the action succeeded.
	 */
	function _adjustLeverage(Self storage _self, uint256 _roomAmount) internal returns (bool _success)
	{
		// the reserve is the diference between lend and borrow
		uint256 _lendAmount = GC.fetchLendAmount(_self.reserveToken);
		uint256 _borrowAmount = GC.fetchBorrowAmount(_self.reserveToken);
		uint256 _reserveAmount = _lendAmount.sub(_borrowAmount);
		// caps the room in case it is larger than the reserve
		_roomAmount = G.min(_roomAmount, _reserveAmount);
		// The new reserve must deduct the room requested
		uint256 _newReserveAmount = _reserveAmount.sub(_roomAmount);
		// caculates the assumed lend amount deducting the requested room
		uint256 _oldLendAmount = _lendAmount.sub(_roomAmount);
		// the new lend amount is the new reserve with leverage applied
		uint256 _newLendAmount;
		uint256 _minNewLendAmount;
		uint256 _maxNewLendAmount;
		{
			(uint256 _collateralizationRatio, uint256 _minCollateralizationRatio, uint256 _maxCollateralizationRatio) = _self._calcCollateralizationRatio();
			_newLendAmount = _newReserveAmount.mul(1e18).div(uint256(1e18).sub(_collateralizationRatio));
			_minNewLendAmount = _newReserveAmount.mul(1e18).div(uint256(1e18).sub(_minCollateralizationRatio));
			_maxNewLendAmount = _newReserveAmount.mul(1e18).div(uint256(1e18).sub(_maxCollateralizationRatio));
		}
		// adjust the reserve by:
		// 1- increasing collateralization by the difference
		// 2- decreasing collateralization by the difference
		// the adjustment is capped by the liquidity available on the market
		uint256 _liquidityAmount = G.getFlashLoanLiquidity(_self.underlyingToken);
		if (_minNewLendAmount > _oldLendAmount) {
			{
				uint256 _minAmount = _minNewLendAmount.sub(_oldLendAmount);
				require(_liquidityAmount >= _minAmount, "cannot maintain collateralization ratio");
			}
			uint256 _amount = _newLendAmount.sub(_oldLendAmount);
			return _self._dispatchFlashLoan(G.min(_amount, _liquidityAmount), 1);
		}
		if (_maxNewLendAmount < _oldLendAmount) {
			{
				uint256 _minAmount = _oldLendAmount.sub(_maxNewLendAmount);
				require(_liquidityAmount >= _minAmount, "cannot maintain collateralization ratio");
			}
			uint256 _amount = _oldLendAmount.sub(_newLendAmount);
			return _self._dispatchFlashLoan(G.min(_amount, _liquidityAmount), 2);
		}
		return true;
	}

	/**
	 * @dev This is the continuation of _adjustLeverage once funds are
	 *      borrowed via the FlashLoan callback.
	 * @param _amount The borrowed amount as requested.
	 * @param _fee The additional fee that needs to be paid for the FlashLoan.
	 * @param _which A flag indicating whether the funds were borrowed to
	 *               1) increase or 2) decrease the collateralization ratio.
	 * @return _success A boolean indicating whether or not the action succeeded.
	 */
	function _continueAdjustLeverage(Self storage _self, uint256 _amount, uint256 _fee, uint256 _which) internal returns (bool _success)
	{
		// note that the reserve adjustment is not 100% accurate as we
		// did not account for FlashLoan fees in the initial calculation
		if (_which == 1) {
			bool _success1 = GC.lend(_self.reserveToken, _amount.sub(_fee));
			bool _success2 = GC.borrow(_self.reserveToken, _amount);
			return _success1 && _success2;
		}
		if (_which == 2) {
			bool _success1 = GC.repay(_self.reserveToken, _amount);
			bool _success2 = GC.redeem(_self.reserveToken, _amount.add(_fee));
			return _success1 && _success2;
		}
		assert(false);
	}

	/**
	 * @dev Abstracts the details of dispatching the FlashLoan by encoding
	 *      the extra parameters.
	 * @param _amount The amount to be borrowed.
	 * @param _which A flag indicating whether the funds are borrowed to
	 *               1) increase or 2) decrease the collateralization ratio.
	 * @return _success A boolean indicating whether or not the action succeeded.
	 */
	function _dispatchFlashLoan(Self storage _self, uint256 _amount, uint256 _which) internal returns (bool _success)
	{
		return G.requestFlashLoan(_self.underlyingToken, _amount, abi.encode(_which));
	}

	/**
	 * @dev Abstracts the details of receiving a FlashLoan by decoding
	 *      the extra parameters.
	 * @param _token The asset being borrowed.
	 * @param _amount The borrowed amount.
	 * @param _fee The fees to be paid along with the borrowed amount.
	 * @param _params Additional encoded parameters to be decoded.
	 * @return _success A boolean indicating whether or not the action succeeded.
	 */
	function _receiveFlashLoan(Self storage _self, address _token, uint256 _amount, uint256 _fee, bytes memory _params) external returns (bool _success)
	{
		assert(_token == _self.underlyingToken);
		uint256 _which = abi.decode(_params, (uint256));
		return _self._continueAdjustLeverage(_amount, _fee, _which);
	}

	/**
	 * @dev Converts a given amount of the mining token to the underlying
	 *      token using the external exchange contract. Both amounts are
	 *      deducted and credited, respectively, from the current contract.
	 * @param _inputAmount The amount to be converted.
	 */
	function _convertMiningToUnderlying(Self storage _self, uint256 _inputAmount) internal
	{
		G.dynamicConvertFunds(_self.exchange, _self.miningToken, _self.underlyingToken, _inputAmount, 0);
	}
}
