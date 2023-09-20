// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { IExchange } from "./IExchange.sol";
import { WhitelistGuard } from "./WhitelistGuard.sol";

import { Transfers } from "./modules/Transfers.sol";

/**
 * @notice This contract implements an "universal" buyback contract. It accumulates
 *         the reward token, send from fee collectors and/or strategies; converts
 *         into the two desired buyback tokens, according to the configured splitting;
 *         and burn these amounts.
 */
contract UniversalBuyback is ReentrancyGuard, WhitelistGuard
{
	using SafeMath for uint256;

	uint256 constant DEFAULT_REWARD_BUYBACK1_SHARE = 70e16; // 70%
	uint256 constant DEFAULT_REWARD_BUYBACK2_SHARE = 30e16; // 30%

	// dead address to receive "burnt" tokens
	address constant public FURNACE = 0x000000000000000000000000000000000000dEaD;

	// buyback token configuration
	address public immutable rewardToken;
	address public immutable buybackToken1;
	address public immutable buybackToken2;

	// addresses receiving tokens
	address public treasury;

	// exchange contract address
	address public exchange;

	// split configuration
	uint256 public rewardBuyback1Share = DEFAULT_REWARD_BUYBACK1_SHARE;
	uint256 public rewardBuyback2Share = DEFAULT_REWARD_BUYBACK2_SHARE;

	/**
	 * @dev Constructor for this buyback contract.
	 * @param _rewardToken The input reward token for this contract, to be converted.
	 * @param _buybackToken1 The first buyback token for this contract, to convert to and burn accorting to rewardBuyback1Share.
	 * @param _buybackToken2 The second buyback token for this contract, to convert to and burn according to rewardBuyback2Share.
	 * @param _treasury The treasury address used to recover lost funds.
	 * @param _exchange The exchange contract used to convert funds.
	 */
	constructor (address _rewardToken, address _buybackToken1, address _buybackToken2, address _treasury, address _exchange) public
	{
		rewardToken = _rewardToken;
		buybackToken1 = _buybackToken1;
		buybackToken2 = _buybackToken2;
		treasury = _treasury;
		exchange = _exchange;
	}

	/**
	 * @notice Allows for the beforehand calculation of the amount of
	 *         reward token to be converted on the next gulp call.
	 * @return _buybackAmount The amount of the reward token to be converted.
	 */
	function pendingBuyback() external view returns (uint256 _buybackAmount)
	{
		return Transfers._getBalance(rewardToken);
	}

	/**
	 * @notice Allows for the beforehand calculation of the amount of
	 *         buyback tokens to be burned on the next gulp call.
	 * @return _burning1 The amount of the first buyback token to be burned.
	 * @return _burning2 The amount of the second buyback token to be burned.
	 */
	function pendingBurning() external view returns (uint256 _burning1, uint256 _burning2)
	{
		require(exchange != address(0), "exchange not set");
		uint256 _balance = Transfers._getBalance(rewardToken);
		uint256 _amount1 = _balance.mul(DEFAULT_REWARD_BUYBACK1_SHARE) / 1e18;
		uint256 _amount2 = _balance.mul(DEFAULT_REWARD_BUYBACK2_SHARE) / 1e18;
		_burning1 = IExchange(exchange).calcConversionFromInput(rewardToken, buybackToken1, _amount1);
		_burning2 = IExchange(exchange).calcConversionFromInput(rewardToken, buybackToken2, _amount2);
		return (_burning1, _burning2);
	}

	/**
	 * Performs the conversion of the accumulated reward token into
	 * the buyback tokens, according to the defined splitting, and burns them.
	 * @param _minBurning1 The minimum amount expected to be burned from the first buyback token.
	 * @param _minBurning2 The minimum amount expected to be burned from the second buyback token.
	 */
	function gulp(uint256 _minBurning1, uint256 _minBurning2) external onlyEOAorWhitelist nonReentrant
	{
		require(exchange != address(0), "exchange not set");
		uint256 _balance = Transfers._getBalance(rewardToken);
		uint256 _amount1 = _balance.mul(DEFAULT_REWARD_BUYBACK1_SHARE) / 1e18;
		uint256 _amount2 = _balance.mul(DEFAULT_REWARD_BUYBACK2_SHARE) / 1e18;
		Transfers._approveFunds(rewardToken, exchange, _amount1 + _amount2);
		IExchange(exchange).convertFundsFromInput(rewardToken, buybackToken1, _amount1, 1);
		IExchange(exchange).convertFundsFromInput(rewardToken, buybackToken2, _amount2, 1);
		uint256 _burning1 = Transfers._getBalance(buybackToken1);
		uint256 _burning2 = Transfers._getBalance(buybackToken2);
		require(_burning1 >= _minBurning1, "high slippage");
		require(_burning2 >= _minBurning2, "high slippage");
		_burn(buybackToken1, _burning1);
		_burn(buybackToken2, _burning2);
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
		require(_token != rewardToken, "invalid token");
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

	/**
	 * @notice Updates the split share for the buyback and burn tokens.
	 *         The sum must add up to 100%.
	 *         This is a privileged function.
	 * @param _newRewardBuyback1Share The first token share.
	 * @param _newRewardBuyback2Share The second token share.
	 */
	function setRewardSplit(uint256 _newRewardBuyback1Share, uint256 _newRewardBuyback2Share) external onlyOwner
	{
		require(_newRewardBuyback1Share <= 1e18, "invalid rate");
		require(_newRewardBuyback2Share <= 1e18, "invalid rate");
		require(_newRewardBuyback1Share + _newRewardBuyback2Share == 1e18, "invalid split");
		uint256 _oldRewardBuyback1Share = rewardBuyback1Share;
		uint256 _oldRewardBuyback2Share = rewardBuyback2Share;
		rewardBuyback1Share = _newRewardBuyback1Share;
		rewardBuyback2Share = _newRewardBuyback2Share;
		emit ChangeRewardSplit(_oldRewardBuyback1Share, _oldRewardBuyback2Share, _newRewardBuyback1Share, _newRewardBuyback2Share);
	}

	/// @dev Implements token burning by sending to a dead address
	function _burn(address _token, uint256 _amount) internal
	{
		Transfers._pushFunds(_token, FURNACE, _amount);
	}

	// events emitted by this contract
	event ChangeExchange(address _oldExchange, address _newExchange);
	event ChangeTreasury(address _oldTreasury, address _newTreasury);
	event ChangeRewardSplit(uint256 _oldRewardBuyback1Share, uint256 _oldRewardBuyback2Share, uint256 _newRewardBuyback1Share, uint256 _newRewardBuyback2Share);
}
