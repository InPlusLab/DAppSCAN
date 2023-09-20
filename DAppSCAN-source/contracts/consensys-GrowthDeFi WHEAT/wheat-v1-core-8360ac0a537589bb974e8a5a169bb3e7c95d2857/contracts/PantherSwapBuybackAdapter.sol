// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { IExchange } from "./IExchange.sol";
import { WhitelistGuard } from "./WhitelistGuard.sol";

import { Transfers } from "./modules/Transfers.sol";

import { PantherToken } from "./interop/PantherSwap.sol";

/**
 * @notice This contract implements a buyback adapter to be used with PantherSwap
 *         strategies, it converts the source reward token (PANTHER) into the target
 *         reward token (BNB) whenever the gulp function is called.
 */
contract PantherSwapBuybackAdapter is ReentrancyGuard, WhitelistGuard
{
	// adapter token configuration
	address public immutable sourceToken;
	address public immutable targetToken;

	// addresses receiving tokens
	address public treasury;
	address public buyback;

	// exchange contract address
	address public exchange;

	/**
	 * @dev Constructor for this adapter contract.
	 * @param _sourceToken The input reward token for this contract, to be converted.
	 * @param _targetToken The output reward token for this contract, to convert to.
	 * @param _treasury The treasury address used to recover lost funds.
	 * @param _buyback The buyback contract address to send converted funds.
	 * @param _exchange The exchange contract used to convert funds.
	 */
	constructor (address _sourceToken, address _targetToken,
		address _treasury, address _buyback, address _exchange) public
	{
		require(_sourceToken != _targetToken, "invalid token");
		sourceToken = _sourceToken;
		targetToken = _targetToken;
		treasury = _treasury;
		buyback = _buyback;
		exchange = _exchange;
	}

	/**
	 * @notice Allows for the beforehand calculation of the amount of
	 *         source reward token to be converted on the next gulp call.
	 * @return _totalSource The amount of the source reward token to be converted.
	 */
	function pendingSource() external view returns (uint256 _totalSource)
	{
		return Transfers._getBalance(sourceToken);
	}

	/**
	 * @notice Allows for the beforehand calculation of the amount of
	 *         target reward token to be converted on the next gulp call.
	 * @return _totalTarget The expected amount of the target reward token
	 *                      to be sent to the buyback contract after conversion.
	 */
	function pendingTarget() external view returns (uint256 _totalTarget)
	{
		require(exchange != address(0), "exchange not set");
		uint256 _totalSource = Transfers._getBalance(sourceToken);
		uint256 _limitSource = _calcMaxRewardTransferAmount();
		if (_totalSource > _limitSource) {
			_totalSource = _limitSource;
		}
		_totalTarget = IExchange(exchange).calcConversionFromInput(sourceToken, targetToken, _totalSource);
		return _totalTarget;
	}

	/**
	 * Performs the conversion of the accumulated source reward token into
	 * the target reward token and sends to the buyback contract.
	 * @param _minTotalTarget The minimum amount expected to be sent to the
	 *                        buyback contract.
	 */
	function gulp(uint256 _minTotalTarget) external onlyEOAorWhitelist nonReentrant
	{
		require(exchange != address(0), "exchange not set");
		uint256 _totalSource = Transfers._getBalance(sourceToken);
		uint256 _limitSource = _calcMaxRewardTransferAmount();
		if (_totalSource > _limitSource) {
			_totalSource = _limitSource;
		}
		Transfers._approveFunds(sourceToken, exchange, _totalSource);
		IExchange(exchange).convertFundsFromInput(sourceToken, targetToken, _totalSource, 1);
		uint256 _totalTarget = Transfers._getBalance(targetToken);
		require(_totalTarget >= _minTotalTarget, "high slippage");
		Transfers._pushFunds(targetToken, buyback, _totalTarget);
	}

	/**
	 * @notice Allows the recovery of tokens sent by mistake to this
	 *         contract, excluding tokens relevant to its operations.
	 *         The full balance is sent to the treasury address.
	 *         This is a privileged function.
	 * @param _token The address of the token to be recovered.
	 */
	function recoverLostFunds(address _token) external onlyOwner
	{
		require(_token != sourceToken, "invalid token");
		uint256 _balance = Transfers._getBalance(_token);
		Transfers._pushFunds(_token, treasury, _balance);
	}

	/**
	 * @notice Updates the treasury address used to recover lost funds.
	 *         This is a privileged function.
	 * @param _newTreasury The new treasury address.
	 */
	function setTreasury(address _newTreasury) external onlyOwner
	{
		require(_newTreasury != address(0), "invalid address");
		address _oldTreasury = treasury;
		treasury = _newTreasury;
		emit ChangeTreasury(_oldTreasury, _newTreasury);
	}

	/**
	 * @notice Updates the buyback contract address used to send converted funds.
	 *         This is a privileged function.
	 * @param _newBuyback The new buyback contract address.
	 */
	function setBuyback(address _newBuyback) external onlyOwner
	{
		require(_newBuyback != address(0), "invalid address");
		address _oldBuyback = buyback;
		buyback = _newBuyback;
		emit ChangeBuyback(_oldBuyback, _newBuyback);
	}

	/**
	 * @notice Updates the exchange address used to convert funds. A zero
	 *         address can be used to temporarily pause conversions.
	 *         This is a privileged function.
	 * @param _newExchange The new exchange address.
	 */
	function setExchange(address _newExchange) external onlyOwner
	{
		address _oldExchange = exchange;
		exchange = _newExchange;
		emit ChangeExchange(_oldExchange, _newExchange);
	}

	/// @dev Returns the max transfer amount as permitted by the PANTHER token.
	function _calcMaxRewardTransferAmount() internal view returns (uint256 _maxRewardTransferAmount)
	{
		return PantherToken(sourceToken).maxTransferAmount();
	}

	// events emitted by this contract
	event ChangeBuyback(address _oldBuyback, address _newBuyback);
	event ChangeTreasury(address _oldTreasury, address _newTreasury);
	event ChangeExchange(address _oldExchange, address _newExchange);
}
