// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/EnumerableSet.sol";

import { GCToken } from "./GCToken.sol";
import { G } from "./G.sol";

/**
 * @dev This library implements data structure abstraction for the portfolio
 *      reserve management code in order to circuvent the EVM contract size limit.
 *      It is therefore a public library shared by all gToken Type 0 contracts and
 *      needs to be published alongside them. See GTokenType0.sol for further
 *      documentation.
 */
library GPortfolioReserveManager
{
	using SafeMath for uint256;
	using EnumerableSet for EnumerableSet.AddressSet;
	using GPortfolioReserveManager for GPortfolioReserveManager.Self;

	uint256 constant DEFAULT_LIQUID_REBALANCE_MARGIN = 10e16; // 10%
	uint256 constant DEFAULT_PORTFOLIO_REBALANCE_MARGIN = 1e16; // 1%
	uint256 constant MAXIMUM_TOKEN_COUNT = 5;

	struct Self {
		address reserveToken;
		EnumerableSet.AddressSet tokens;
		mapping (address => uint256) percents;
		uint256 liquidRebalanceMargin;
		uint256 portfolioRebalanceMargin;
	}

	/**
	 * @dev Initializes the data structure. This method is exposed publicly.
	 * @param _reserveToken The ERC-20 token address of the reserve token.
	 */
	function init(Self storage _self, address _reserveToken) public
	{
		_self.reserveToken = _reserveToken;
		_self.percents[_reserveToken] = 1e18;
		_self.liquidRebalanceMargin = DEFAULT_LIQUID_REBALANCE_MARGIN;
		_self.portfolioRebalanceMargin = DEFAULT_PORTFOLIO_REBALANCE_MARGIN;
	}

	/**
	 * @dev The total number of gTokens added to the portfolio. This method
	 *      is exposed publicly.
	 * @return _count The number of gTokens that make up the portfolio.
	 */
	function tokenCount(Self storage _self) public view returns (uint256 _count)
	{
		return _self.tokens.length();
	}

	/**
	 * @dev Returns one of the gTokens that makes up the portfolio. This
	 *      method is exposed publicly.
	 * @param _index The desired index, must be less than the token count.
	 * @return _token The gToken currently present at the given index.
	 */
	function tokenAt(Self storage _self, uint256 _index) public view returns (address _token)
	{
		require(_index < _self.tokens.length(), "Invalid index");
		return _self.tokens.at(_index);
	}

	/**
	 * @dev Returns the percentual participation of a token (including
	 *      the reserve token) in the portfolio composition. This method is
	 *      exposed publicly.
	 * @param _token The given token address.
	 * @return _percent The token percentual share of the portfolio.
	 */
	function tokenPercent(Self storage _self, address _token) public view returns (uint256 _percent)
	{
		return _self.percents[_token];
	}

	/**
	 * @dev Inserts a new gToken into the portfolio. The new gToken must
	 *      have the reserve token as its underlying token. The initial
	 *      portfolio share of the new token will be 0%. This method is
	 *      exposed publicly.
	 * @param _token The contract address of the new gToken to be incorporated
	 *               into the portfolio.
	 */
	function insertToken(Self storage _self, address _token) public
	{
		require(_self.tokens.length() < MAXIMUM_TOKEN_COUNT, "Limit reached");
		address _underlyingToken = GCToken(_token).underlyingToken();
		require(_underlyingToken == _self.reserveToken, "Mismatched token");
		require(_self.tokens.add(_token), "Duplicate token");
	}

	/**
	 * @dev Removes a gToken from the portfolio. The portfolio share of the
	 *      token must be 0% before it can be removed. The underlying reserve
	 *      is redeemed upon removal. This method is exposed publicly.
	 * @param _token The contract address of the gToken to be removed from
	 *               the portfolio.
	 */
	function removeToken(Self storage _self, address _token) public
	{
		require(_self.percents[_token] == 0, "Positive percent");
		require(_self.tokens.remove(_token), "Unknown token");
		_self._withdrawUnderlying(_token, _self._getUnderlyingReserve(_token));
	}

	/**
	 * @dev Shifts a percentual share of the portfolio allocation from
	 *      one gToken to another gToken. The reserve token can also be
	 *      used as source or target of the operation. This does not
	 *      actually shifts funds, only reconfigures the allocation.
	 *      This method is exposed publicly.
	 * @param _sourceToken The token address to provide the share.
	 * @param _targetToken The token address to receive the share.
	 * @param _percent The percentual share to shift.
	 */
	function transferTokenPercent(Self storage _self, address _sourceToken, address _targetToken, uint256 _percent) public
	{
		require(_percent <= _self.percents[_sourceToken], "Invalid percent");
		require(_sourceToken != _targetToken, "Invalid transfer");
		require(_targetToken == _self.reserveToken || _self.tokens.contains(_targetToken), "Unknown token");
		_self.percents[_sourceToken] -= _percent;
		_self.percents[_targetToken] += _percent;
	}

	/**
	 * @dev Sets the percentual margins tolerable before triggering a
	 *      rebalance action (i.e. an underlying deposit or withdrawal).
	 *      This method is exposed publicly.
	 * @param _liquidRebalanceMargin The liquid percentual rebalance margin,
	 *                               to be configured by the owner.
	 * @param _portfolioRebalanceMargin The portfolio percentual rebalance
	 *                                  margin, to be configured by the owner.
	 */
	function setRebalanceMargins(Self storage _self, uint256 _liquidRebalanceMargin, uint256 _portfolioRebalanceMargin) public
	{
		require(0 <= _liquidRebalanceMargin && _liquidRebalanceMargin <= 1e18, "Invalid margin");
		require(0 <= _portfolioRebalanceMargin && _portfolioRebalanceMargin <= 1e18, "Invalid margin");
		_self.liquidRebalanceMargin = _liquidRebalanceMargin;
		_self.portfolioRebalanceMargin = _portfolioRebalanceMargin;
	}

	/**
	 * @dev Returns the total reserve amount held liquid by the contract
	 *      summed up with the underlying reserve of all gTokens that make up
	 *      the portfolio. This method is exposed publicly.
	 * @return _totalReserve The computed total reserve amount.
	 */
	function totalReserve(Self storage _self) public view returns (uint256 _totalReserve)
	{
		return _self._calcTotalReserve();
	}

	/**
	 * @dev Performs the reserve adjustment actions leaving a liquidity room,
	 *      if necessary. It will attempt to perform the operation using the
	 *      liquid pool and, if necessary, either withdrawal from an underlying
	 *      gToken to get more liquidity, or deposit/withdrawal from an
	 *      underlying gToken to move towards the desired reserve allocation
	 *      if any of them falls beyond the rebalance margin thresholds.
	 *      To save on gas costs the reserve adjusment will request at most
	 *      one operation from any of the underlying gTokens. This method is
	 *      exposed publicly.
	 * @param _roomAmount The underlying token amount to be available after the
	 *                    operation. This is revelant for withdrawals, once the
	 *                    room amount is withdrawn the reserve should reflect
	 *                    the configured collateralization ratio.
	 * @return _success A boolean indicating whether or not both actions suceeded.
	 */
	function adjustReserve(Self storage _self, uint256 _roomAmount) public returns (bool _success)
	{
		// the reserve amount must deduct the room requested
		uint256 _reserveAmount = _self._calcTotalReserve();
		_roomAmount = G.min(_roomAmount, _reserveAmount);
		_reserveAmount = _reserveAmount.sub(_roomAmount);

		// the liquid amount must deduct the room requested
		uint256 _liquidAmount = G.getBalance(_self.reserveToken);
		uint256 _blockedAmount = G.min(_roomAmount, _liquidAmount);
		_liquidAmount = _liquidAmount.sub(_blockedAmount);

		// if the liquid amount is not enough to process a withdrawal
		// we will need to withdraw the missing amount from one of the
		// underlying gTokens (actually we will choose the one for which
		// the withdrawal will produce the least impact in terms of
		// percentual share deviation from its configured target)
		uint256 _requiredAmount = _roomAmount.sub(_blockedAmount);
		if (_requiredAmount > 0) {
			(address _adjustToken, uint256 _adjustAmount) = _self._findRequiredWithdrawal(_reserveAmount, _requiredAmount);
			if (_adjustToken == address(0)) return false;
			return _self._withdrawUnderlying(_adjustToken, _adjustAmount);
		}

		// calculates whether or not the liquid amount exceeds the
		// configured range and requires either a deposit or a withdrawal
		// to be performed
		(uint256 _depositAmount, uint256 _withdrawalAmount) = _self._calcLiquidAdjustment(_reserveAmount, _liquidAmount);

		// finds the gToken that will have benefited more of this deposit
		// in terms of its target percentual share deviation and performs
		// the deposit on it
		if (_depositAmount > 0) {
			(address _adjustToken, uint256 _adjustAmount) = _self._findDeposit(_reserveAmount);
			if (_adjustToken == address(0)) return true;
			return _self._depositUnderlying(_adjustToken, G.min(_adjustAmount, _depositAmount));
		}

		// finds the gToken that will have benefited more of this withdrawal
		// in terms of its target percentual share deviation and performs
		// the withdrawal on it
		if (_withdrawalAmount > 0) {
			(address _adjustToken, uint256 _adjustAmount) = _self._findWithdrawal(_reserveAmount);
			if (_adjustToken == address(0)) return true;
			return _self._withdrawUnderlying(_adjustToken, G.min(_adjustAmount, _withdrawalAmount));
		}

		return true;
	}

	/**
	 * @dev Calculates the total reserve amount. It sums up the reserve held
	 *      by the contract with the underlying reserve held by the gTokens
	 *      that make up the portfolio.
	 * @return _totalReserve The computed total reserve amount.
	 */
	function _calcTotalReserve(Self storage _self) internal view returns (uint256 _totalReserve)
	{
		_totalReserve = G.getBalance(_self.reserveToken);
		uint256 _tokenCount = _self.tokens.length();
		for (uint256 _index = 0; _index < _tokenCount; _index++) {
			address _token = _self.tokens.at(_index);
			uint256 _tokenReserve = _self._getUnderlyingReserve(_token);
			_totalReserve = _totalReserve.add(_tokenReserve);
		}
		return _totalReserve;
	}

	/**
	 * @dev Calculates the amount that falls either above or below
	 *      the rebalance margin for the liquid pool. If we have more
	 *      liquid amount than its configured share plus the rebalance
	 *      margin it returns that amount paired with zero. If we have less
	 *      liquid amount than its configured share minus the rebalance
	 *      margin it returns zero paired with that amount. If none of these
	 *      two situations happen, then the liquid amount falls within the
	 *      acceptable parameters, and it returns a pair of zeros.
	 * @param _reserveAmount The total reserve amount used for calculation.
	 * @param _liquidAmount The liquid amount available used for calculation.
	 * @return _depositAmount The amount to be deposited or zero.
	 * @return _withdrawalAmount The amount to be withdrawn or zero.
	 */
	function _calcLiquidAdjustment(Self storage _self, uint256 _reserveAmount, uint256 _liquidAmount) internal view returns (uint256 _depositAmount, uint256 _withdrawalAmount)
	{
		uint256 _tokenPercent = _self.percents[_self.reserveToken];
		uint256 _tokenReserve = _reserveAmount.mul(_tokenPercent).div(1e18);
		if (_liquidAmount > _tokenReserve) {
			uint256 _upperPercent = G.min(1e18, _tokenPercent.add(_self.liquidRebalanceMargin));
			uint256 _upperReserve = _reserveAmount.mul(_upperPercent).div(1e18);
			if (_liquidAmount > _upperReserve) return (_liquidAmount.sub(_tokenReserve), 0);
		}
		else
		if (_liquidAmount < _tokenReserve) {
			uint256 _lowerPercent = _tokenPercent.sub(G.min(_tokenPercent, _self.liquidRebalanceMargin));
			uint256 _lowerReserve = _reserveAmount.mul(_lowerPercent).div(1e18);
			if (_liquidAmount < _lowerReserve) return (0, _tokenReserve.sub(_liquidAmount));
		}
		return (0, 0);
	}

	/**
	 * @dev Search the list of gTokens and selects the one that has enough
	 *      liquidity and for which the withdrawal of the required amount
	 *      will yield the least deviation from its target share.
	 * @param _reserveAmount The total reserve amount used for calculation.
	 * @param _requiredAmount The required liquidity amount used for calculation.
	 * @return _adjustToken The gToken to withdraw from.
	 * @return _adjustAmount The amount to be withdrawn.
	 */
	function _findRequiredWithdrawal(Self storage _self, uint256 _reserveAmount, uint256 _requiredAmount) internal view returns (address _adjustToken, uint256 _adjustAmount)
	{
		uint256 _minPercent = 1e18;
		_adjustToken = address(0);
		_adjustAmount = 0;

		uint256 _tokenCount = _self.tokens.length();
		for (uint256 _index = 0; _index < _tokenCount; _index++) {
			address _token = _self.tokens.at(_index);
			uint256 _tokenReserve = _self._getUnderlyingReserve(_token);
			if (_tokenReserve < _requiredAmount) continue;

			uint256 _oldTokenReserve = _tokenReserve.sub(_requiredAmount);
			uint256 _oldTokenPercent = _oldTokenReserve.mul(1e18).div(_reserveAmount);
			uint256 _newTokenPercent = _self.percents[_token];

			uint256 _percent = 0;
			if (_newTokenPercent > _oldTokenPercent) _percent = _newTokenPercent.sub(_oldTokenPercent);
			else
			if (_newTokenPercent < _oldTokenPercent) _percent = _oldTokenPercent.sub(_newTokenPercent);

			if (_percent < _minPercent) {
				_minPercent = _percent;
				_adjustToken = _token;
				_adjustAmount = _requiredAmount;
			}
		}

		return (_adjustToken, _adjustAmount);
	}

	/**
	 * @dev Search the list of gTokens and selects the one for which the
	 *      deposit will provide the best correction of deviation from
	 *      its target share.
	 * @param _reserveAmount The total reserve amount used for calculation.
	 * @return _adjustToken The gToken to deposit to.
	 * @return _adjustAmount The amount to be deposited.
	 */
	function _findDeposit(Self storage _self, uint256 _reserveAmount) internal view returns (address _adjustToken, uint256 _adjustAmount)
	{
		uint256 _maxPercent = _self.portfolioRebalanceMargin;
		_adjustToken = address(0);
		_adjustAmount = 0;

		uint256 _tokenCount = _self.tokens.length();
		for (uint256 _index = 0; _index < _tokenCount; _index++) {
			address _token = _self.tokens.at(_index);

			uint256 _oldTokenReserve = _self._getUnderlyingReserve(_token);
			uint256 _oldTokenPercent = _oldTokenReserve.mul(1e18).div(_reserveAmount);
			uint256 _newTokenPercent = _self.percents[_token];

			if (_newTokenPercent > _oldTokenPercent) {
				uint256 _percent = _newTokenPercent.sub(_oldTokenPercent);
				if (_percent > _maxPercent) {
					uint256 _newTokenReserve = _reserveAmount.mul(_newTokenPercent).div(1e18);
					uint256 _amount = _newTokenReserve.sub(_oldTokenReserve);

					_maxPercent = _percent;
					_adjustToken = _token;
					_adjustAmount = _amount;
				}
			}
		}

		return (_adjustToken, _adjustAmount);
	}

	/**
	 * @dev Search the list of gTokens and selects the one for which the
	 *      withdrawal will provide the best correction of deviation from
	 *      its target share.
	 * @param _reserveAmount The total reserve amount used for calculation.
	 * @return _adjustToken The gToken to withdraw from.
	 * @return _adjustAmount The amount to be withdrawn.
	 */
	function _findWithdrawal(Self storage _self, uint256 _reserveAmount) internal view returns (address _adjustToken, uint256 _adjustAmount)
	{
		uint256 _maxPercent = _self.portfolioRebalanceMargin;
		_adjustToken = address(0);
		_adjustAmount = 0;

		uint256 _tokenCount = _self.tokens.length();
		for (uint256 _index = 0; _index < _tokenCount; _index++) {
			address _token = _self.tokens.at(_index);

			uint256 _oldTokenReserve = _self._getUnderlyingReserve(_token);
			uint256 _oldTokenPercent = _oldTokenReserve.mul(1e18).div(_reserveAmount);
			uint256 _newTokenPercent = _self.percents[_token];

			if (_newTokenPercent < _oldTokenPercent) {
				uint256 _percent = _oldTokenPercent.sub(_newTokenPercent);
				if (_percent > _maxPercent) {
					uint256 _newTokenReserve = _reserveAmount.mul(_newTokenPercent).div(1e18);
					uint256 _amount = _oldTokenReserve.sub(_newTokenReserve);

					_maxPercent = _percent;
					_adjustToken = _token;
					_adjustAmount = _amount;
				}
			}
		}

		return (_adjustToken, _adjustAmount);
	}

	/**
	 * @dev Performs a deposit of the reserve asset to the given gToken.
	 * @param _token The gToken to deposit to.
	 * @param _amount The amount to be deposited.
	 * @return _success A boolean indicating whether or not the action succeeded.
	 */
	function _depositUnderlying(Self storage _self, address _token, uint256 _amount) internal returns (bool _success)
	{
		_amount = G.min(_amount, G.getBalance(_self.reserveToken));
		if (_amount == 0) return true;
		G.approveFunds(_self.reserveToken, _token, _amount);
		try GCToken(_token).depositUnderlying(_amount) {
			return true;
		} catch (bytes memory /* _data */) {
			G.approveFunds(_self.reserveToken, _token, 0);
			return false;
		}
	}

	/**
	 * @dev Performs a withdrawal of the reserve asset from the given gToken.
	 * @param _token The gToken to withdraw from.
	 * @param _amount The amount to be withdrawn.
	 * @return _success A boolean indicating whether or not the action succeeded.
	 */
	function _withdrawUnderlying(Self storage _self, address _token, uint256 _amount) internal returns (bool _success)
	{
		uint256 _grossShares = _self._calcWithdrawalSharesFromUnderlyingCost(_token, _amount);
		_grossShares = G.min(_grossShares, G.getBalance(_token));
		if (_grossShares == 0) return true;
		try GCToken(_token).withdrawUnderlying(_grossShares) {
			return true;
		} catch (bytes memory /* _data */) {
			return false;
		}
	}

	/**
	 * @dev Calculates how much of the reserve token is available for
	 *      withdrawal by the current contract for the given gToken.
	 * @param _token The gToken to withdraw from.
	 * @return _underlyingCost The total amount redeemable by the current
	 *                         contract from the given gToken.
	 */
	function _getUnderlyingReserve(Self storage _self, address _token) internal view returns (uint256 _underlyingCost)
	{
		uint256 _grossShares = G.getBalance(_token);
		return _self._calcWithdrawalUnderlyingCostFromShares(_token, _grossShares);
	}

	/**
	 * @dev Calculates how much will be received for withdrawing the provided
	 *      number of shares from a given gToken.
	 * @param _token The gToken to withdraw from.
	 * @param _grossShares The number of shares to be provided.
	 * @return _underlyingCost The amount to be received.
	 */
	function _calcWithdrawalUnderlyingCostFromShares(Self storage /* _self */, address _token, uint256 _grossShares) internal view returns (uint256 _underlyingCost)
	{
		uint256 _totalReserve = GCToken(_token).totalReserve();
		uint256 _totalSupply = GCToken(_token).totalSupply();
		uint256 _withdrawalFee = GCToken(_token).withdrawalFee();
		uint256 _exchangeRate = GCToken(_token).exchangeRate();
		(_underlyingCost,) = GCToken(_token).calcWithdrawalUnderlyingCostFromShares(_grossShares, _totalReserve, _totalSupply, _withdrawalFee, _exchangeRate);
		return _underlyingCost;
	}

	/**
	 * @dev Calculates how many shares are required to withdraw so much from
	 *      a given gToken.
	 * @param _token The gToken to withdraw from.
	 * @param _underlyingCost The desired amount to be withdrawn.
	 * @return _grossShares The number of shares required to withdraw the desired amount.
	 */
	function _calcWithdrawalSharesFromUnderlyingCost(Self storage /* _self */, address _token, uint256 _underlyingCost) internal view returns (uint256 _grossShares)
	{
		uint256 _totalReserve = GCToken(_token).totalReserve();
		uint256 _totalSupply = GCToken(_token).totalSupply();
		uint256 _withdrawalFee = GCToken(_token).withdrawalFee();
		uint256 _exchangeRate = GCToken(_token).exchangeRate();
		(_grossShares,) = GCToken(_token).calcWithdrawalSharesFromUnderlyingCost(_underlyingCost, _totalReserve, _totalSupply, _withdrawalFee, _exchangeRate);
		return _grossShares;
	}
}
