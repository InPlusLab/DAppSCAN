/*
 Copyright [2019] - [2021], PERSISTENCE TECHNOLOGIES PTE. LTD. and the pStake-smartContracts contributors
 SPDX-License-Identifier: Apache-2.0
*/

pragma solidity >=0.7.0;

/**
 * @dev Interface of the ILiquidStakingV2.
 */
interface ILiquidStakingV2 {
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
	event SetFees(uint256 indexed stakeFee, uint256 indexed unstakeFee);

	/**
	 * @dev Emitted when unstaking lock time is set
	 */
	event SetUnstakingLockTime(uint256 indexed unstakingLockTime);

	/**
	 * @dev Emitted when minimum values are set
	 */
	event SetMinimumValues(uint256 indexed minStake, uint256 indexed minUnstake);

	/**
	 * @dev Emitted when unstakeEpoch is set
	 */
	event SetUnstakeEpoch(
		uint256 indexed unstakeEpoch,
		uint256 indexed unstakeEpochPrevious,
		uint256 indexed epochInterval
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
		uint256 indexed tokens,
		uint256 indexed finalTokens,
		uint256 timestamp
	);

	/**
	 * @dev Emitted when sTokens are unstaked
	 */
	event UnstakeTokens(
		address indexed accountAddress,
		uint256 indexed tokens,
		uint256 indexed finalTokens,
		uint256 timestamp
	);

	/**
	 * @dev Emitted when unstaked tokens are withdrawn
	 */
	event WithdrawUnstakeTokens(
		address indexed accountAddress,
		uint256 indexed tokens,
		uint256 timestamp
	);

	/**
	 * @dev get batching limit
	 *
	 */
	function getBatchingLimit() external view returns (uint256 batchingLimit);

	/**
	 * @dev get fees, min values, value divisor and epoch props
	 *
	 */
	function getStakeUnstakeProps()
		external
		view
		returns (
			uint256 stakeFee,
			uint256 unstakeFee,
			uint256 minStake,
			uint256 minUnstake,
			uint256 valueDivisor,
			uint256 epochInterval,
			uint256 unstakeEpoch,
			uint256 unstakeEpochPrevious,
			uint256 unstakingLockTime
		);

	/**
	 * @dev Set 'fees', called from admin
	 * @param stakeFee: stake fee
	 * @param unstakeFee: unstake fee
	 *
	 * Emits a {SetFees} event with 'fee' set to the stake and unstake.
	 *
	 */
	function setFees(uint256 stakeFee, uint256 unstakeFee)
		external
		returns (bool success);

	/**
	 * @dev Set 'unstake props', called from admin
	 * @param unstakingLockTime: varies from 21 hours to 21 days
	 *
	 * Emits a {SetUnstakeProps} event with 'fee' set to the stake and unstake.
	 *
	 */
	function setUnstakingLockTime(uint256 unstakingLockTime)
		external
		returns (bool success);

	/**
	 * @dev Set 'unstake epoch', called from admin
	 * @param unstakeEpoch: unstake epoch
	 * @param unstakeEpochPrevious: unstake epoch previous(initially set to same value as unstakeEpoch)
	 * @param epochInterval: varies from 3 hours to 3 days
	 *
	 * Emits a {SetUnstakeEpoch} event with 'unstakeEpoch'
	 *
	 */
	function setUnstakeEpoch(
		uint256 unstakeEpoch,
		uint256 unstakeEpochPrevious,
		uint256 epochInterval
	) external returns (bool success);

	/**
	 * @dev Set 'minimum values', called from admin
	 * @param minStake: stake minimum value
	 * @param minUnstake: unstake minimum value
	 *
	 * Emits a {SetMinimumValues} event with 'minimum value' set to the stake and unstake.
	 *
	 */
	function setMinimumValues(uint256 minStake, uint256 minUnstake)
		external
		returns (bool success);

	/**
	 * @dev Triggers stopped state.
	 *
	 * Requirements:
	 *
	 * - The contract must not be paused.
	 */
	function pause() external returns (bool success);

	/**
	 * @dev Returns to normal state.
	 *
	 * Requirements:
	 *
	 * - The contract must be paused.
	 */
	function unpause() external returns (bool success);

	/**
	 * @dev Set 'batchingLimit', called from admin
	 * Emits a {SetBatchingLimit} event
	 *
	 */
	function setBatchingLimit(uint256 batchingLimit)
		external
		returns (bool success);

	/**
	 * @dev Emitted when batching limit is set
	 */
	event SetBatchingLimit(uint256 indexed batchingLimit, uint256 timestamp);
}
