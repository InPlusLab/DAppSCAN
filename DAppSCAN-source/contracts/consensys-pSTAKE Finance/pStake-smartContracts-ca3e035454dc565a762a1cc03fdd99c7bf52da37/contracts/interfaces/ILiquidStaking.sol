// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.7.0;

/**
 * @dev Interface of the ILiquidStaking.
 */
interface ILiquidStaking {
	/**
	 *  @dev Stake utokens over the platform with address 'to' for desired 'utok'(Burn uTokens and Mint sTokens)
	 *
	 * Returns a boolean value indicating whether the operation succeeded.
	 *
	 * Emits a {StakeTokens} event.
	 */
	function stake(address to, uint256 amount) external returns (bool);

	/**
	 *  @dev UnStake stokens over the platform with address 'to' for desired 'stok' (Burn sTokens and Mint uTokens with 21 days locking period)
	 *
	 * Returns a boolean value indicating whether the operation succeeded.
	 *
	 * Emits a {UnstakeTokens} event.
	 */
	function unStake(address to, uint256 amount) external returns (bool);

	/**
	 * @dev returns the nearest epoch milestone in the future
	 */
	function getUnstakeEpochMilestone(uint256 _unstakeTimestamp)
		external
		view
		returns (uint256 unstakeEpochMilestone);

	/**
	 * @dev returns the time left for unbonding to finish
	 */
	function getUnstakeTime(uint256 _unstakeTimestamp)
		external
		view
		returns (
			uint256 unstakeTime,
			uint256 unstakeEpoch,
			uint256 unstakeEpochPrevious
		);

	/**
	 * @dev Lock the unstaked tokens for 21 days, user can withdraw the same (Mint uTokens with 21 days locking period)
	 *
	 * Emits a {WithdrawUnstakeTokens} event.
	 */
	function withdrawUnstakedTokens(address staker) external;

	/**
	 * @dev get Total Unbonded Tokens
	 * @param staker: account address
	 *
	 */
	function getTotalUnbondedTokens(address staker)
		external
		view
		returns (uint256 unbondingTokens);

	/**
	 * @dev get Total Unbonding Tokens
	 * @param staker: account address
	 *
	 */
	function getTotalUnbondingTokens(address staker)
		external
		view
		returns (uint256 unbondingTokens);

	/**
	 * @dev Set UTokens smart contract.
	 * Emits a {SetContract} event.
	 */
	function setUTokensContract(address uAddress) external;

	/**
	 * @dev Set STokens smart contract.
	 *
	 *
	 * Emits a {SetContract} event.
	 */
	function setSTokensContract(address sAddress) external;

	/**
	 * @dev Emitted when fees are set
	 */
	event SetFees(uint256 stakeFee, uint256 unstakeFee);

	/**
	 * @dev Emitted when unstaking lock time is set
	 */
	event SetUnstakingLockTime(uint256 unstakingLockTime);

	/**
	 * @dev Emitted when minimum values are set
	 */
	event SetMinimumValues(uint256 minStake, uint256 minUnstake);

	/**
	 * @dev Emitted when unstakeEpoch is set
	 */
	event SetUnstakeEpoch(
		uint256 unstakeEpoch,
		uint256 unstakeEpochPrevious,
		uint256 epochInterval
	);

	/**
	 * @dev Emitted when contract addresses are set
	 */
	event SetUTokensContract(address indexed _contract);

	/**
	 * @dev Emitted when contract addresses are set
	 */
	event SetSTokensContract(address indexed _contract);

	/**
	 * @dev Emitted when uTokens are staked
	 */
	event StakeTokens(
		address indexed accountAddress,
		uint256 tokens,
		uint256 finalTokens,
		uint256 timestamp
	);

	/**
	 * @dev Emitted when sTokens are unstaked
	 */
	event UnstakeTokens(
		address indexed accountAddress,
		uint256 tokens,
		uint256 finalTokens,
		uint256 timestamp
	);

	/**
	 * @dev Emitted when unstaked tokens are withdrawn
	 */
	event WithdrawUnstakeTokens(
		address indexed accountAddress,
		uint256 tokens,
		uint256 timestamp
	);
}
