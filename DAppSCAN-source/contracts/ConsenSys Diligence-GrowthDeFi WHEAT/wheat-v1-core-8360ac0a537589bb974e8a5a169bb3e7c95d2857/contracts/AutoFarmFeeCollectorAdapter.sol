// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { IExchange } from "./IExchange.sol";
import { WhitelistGuard } from "./WhitelistGuard.sol";

import { Transfers } from "./modules/Transfers.sol";

/**
 * @notice This contract implements a fee collector adapter to be used with AutoFarm
 *         strategies, it converts the source reward token (AUTO) into the target
 *         reward token (CAKE) whenever the gulp function is called.
 */
contract AutoFarmFeeCollectorAdapter is ReentrancyGuard, WhitelistGuard
{
	// adapter token configuration
	address public immutable sourceToken;
	address public immutable targetToken;

	// addresses receiving tokens
	address public treasury;
	address public collector;

	// exchange contract address
	address public exchange;

	/**
	 * @dev Constructor for this adapter contract.
	 * @param _sourceToken The input reward token for this contract, to be converted.
	 * @param _targetToken The output reward token for this contract, to convert to.
	 * @param _treasury The treasury address used to recover lost funds.
	 * @param _collector The fee collector address to send converted funds.
	 * @param _exchange The exchange contract used to convert funds.
	 */
	constructor (address _sourceToken, address _targetToken,
		address _treasury, address _collector, address _exchange) public
	{
		require(_sourceToken != _targetToken, "invalid token");
		sourceToken = _sourceToken;
		targetToken = _targetToken;
		treasury = _treasury;
		collector = _collector;
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
	 *                      to be sent to the fee collector after conversion.
	 */
	function pendingTarget() external view returns (uint256 _totalTarget)
	{
		require(exchange != address(0), "exchange not set");
		uint256 _totalSource = Transfers._getBalance(sourceToken);
		_totalTarget = IExchange(exchange).calcConversionFromInput(sourceToken, targetToken, _totalSource);
		return _totalTarget;
	}

	/**
	 * Performs the conversion of the accumulated source reward token into
	 * the target reward token and sends to the fee collector.
	 * @param _minTotalTarget The minimum amount expected to be sent to the
	 *                        fee collector.
	 */
	function gulp(uint256 _minTotalTarget) external onlyEOAorWhitelist nonReentrant
	{
		require(exchange != address(0), "exchange not set");
		uint256 _totalSource = Transfers._getBalance(sourceToken);
		Transfers._approveFunds(sourceToken, exchange, _totalSource);
		IExchange(exchange).convertFundsFromInput(sourceToken, targetToken, _totalSource, 1);
		uint256 _totalTarget = Transfers._getBalance(targetToken);
		require(_totalTarget >= _minTotalTarget, "high slippage");
		Transfers._pushFunds(targetToken, collector, _totalTarget);
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
	 * @notice Updates the fee collector address used to send converted funds.
	 *         This is a privileged function.
	 * @param _newCollector The new fee collector address.
	 */
	function setCollector(address _newCollector) external onlyOwner
	{
		require(_newCollector != address(0), "invalid address");
		address _oldCollector = collector;
		collector = _newCollector;
		emit ChangeCollector(_oldCollector, _newCollector);
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

	// events emitted by this contract
	event ChangeCollector(address _oldCollector, address _newCollector);
	event ChangeTreasury(address _oldTreasury, address _newTreasury);
	event ChangeExchange(address _oldExchange, address _newExchange);
}
