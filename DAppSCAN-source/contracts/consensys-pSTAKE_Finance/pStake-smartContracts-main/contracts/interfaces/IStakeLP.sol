/*
 Copyright [2019] - [2021], PERSISTENCE TECHNOLOGIES PTE. LTD. and the pStake-smartContracts contributors
 SPDX-License-Identifier: Apache-2.0
*/

pragma solidity >=0.7.0;

/**
 * @dev Interface of the IStakeLPCore.
 */
interface IStakeLP {
	/*
	 * @dev calculate liquidity and reward tokens and disburse to user
	 */
	function calculatePendingRewards(
		address holderAddress,
		address accountAddress
	)
		external
		view
		returns (
			uint256[] memory rewardAmounts,
			address[] memory rewardTokens,
			address[] memory sTokenAddresses,
			// address[] memory uTokenAddresses,
			address lpTokenAddress,
			uint256 updatedSupplyLPTimeshare,
			uint256 newSupplyLPTimeShare
		);

	/*
	 * @dev calculate liquidity and reward tokens and disburse to user
	 */
	function calculateSyncedRewards(address holderAddress)
		external
		returns (
			uint256[] memory RewardAmounts,
			address[] memory RewardTokens,
			address[] memory sTokenAddresses,
			address lpTokenAddress
		);

	/**
	 * @dev adds liquidity
	 *
	 * Returns bool
	 */
	function addLiquidity(address holderAddress, uint256 amount)
		external
		returns (bool success);

	/**
	 * @dev remove liquidity
	 *
	 * Returns bool
	 */
	function removeLiquidity(address holderAddress, uint256 amount)
		external
		returns (bool success);

	/**
	 * @dev Set whitelistedPTokenEmissio smart contract.
	 */
	function setWhitelistedPTokenEmissionContract(
		address whitelistedPTokenEmissionContract
	) external;

	/**
	 * @dev Set whitelistedRewardEmission smart contract.
	 */
	function setWhitelistedRewardEmissionContract(
		address whitelistedRewardEmissionContract
	) external;

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
	 * @dev Emitted when add liquidity is called
	 */
	event AddLiquidity(
		address holderAddress,
		address accountAddress,
		uint256 tokens,
		uint256 timestamp
	);

	/**
	 * @dev Emitted when remove liquidity is called
	 */
	event RemoveLiquidity(
		address holderAddress,
		address accountAddress,
		uint256 tokens,
		uint256 timestamp
	);

	/**
	 * @dev Emitted when calculate rewards is called
	 */
	event CalculateRewardsStakeLP(
		address holderAddress,
		address lpToken,
		address accountAddress,
		uint256[] RewardAmounts,
		address[] RewardTokens,
		address[] sTokenAddresses,
		uint256 timestamp
	);

	/**
	 * @dev Emitted when calculate rewards is called
	 */
	event TriggeredCalculateSyncedRewards(
		address holderAddress,
		address accountAddress,
		uint256[] RewardAmounts,
		address[] RewardTokens,
		address[] sTokenAddresses,
		uint256 timestamp
	);

	/**
	 * @dev Emitted when contract addresses are set
	 */
	event SetWhitelistedPTokenEmissionContract(address indexed _contract);

	/**
	 * @dev Emitted when contract addresses are set
	 */
	event SetWhitelistedRewardEmissionContract(address indexed _contract);
}
