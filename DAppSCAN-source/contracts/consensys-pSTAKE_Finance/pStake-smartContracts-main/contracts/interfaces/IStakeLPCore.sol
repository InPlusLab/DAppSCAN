/*
 Copyright [2019] - [2021], PERSISTENCE TECHNOLOGIES PTE. LTD. and the pStake-smartContracts contributors
 SPDX-License-Identifier: Apache-2.0
*/

pragma solidity >=0.7.0;

/**
 * @dev Interface of the IStakeLPCore.
 */
interface IStakeLPCore {
	/*
	 * @dev calculate liquidity and reward tokens and disburse to user
	 * @param holderContractAddress:  contract address
	 * @param rewardTokenContractAddress: contract address
	 * @param rewardSender: contract address
	 * @param rewardAmount: token amount
	 */
	function addRewards(
		address holderContractAddress,
		address rewardTokenContractAddress,
		address rewardSender,
		uint256 rewardAmount
	) external returns (bool success);

	/*
	 * @dev set reward emission
	 * @param holderContractAddress: contract address
	 * @param rewardTokenContractAddress: contract address
	 * @param rewardTokenEmission: token amount
	 */
	function setRewardEmission(
		address holderContractAddress,
		address rewardTokenContractAddress,
		uint256 rewardTokenEmission
	) external returns (bool success);

	/*
	 * @dev get emission data
	 */
	function getEmissionData(
		address holderContractAddress,
		address rewardTokenContractAddress
	)
		external
		view
		returns (
			uint256[] memory cummulativeRewardAmount,
			uint256[] memory rewardTokenEmission,
			uint256[] memory rewardEmissionTimestamp
		);

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
			address[] memory uTokenAddresses,
			address lpTokenAddress,
			uint256 updatedSupplyLPTimeshare
		);

	/*
	 * @dev calculate liquidity and reward tokens and disburse to user
	 */
	function calculateSyncedRewards(address holderAddress)
		external
		returns (
			uint256[] memory RewardAmounts,
			address[] memory RewardTokens,
			address[] memory uTokenAddresses,
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
	 * @dev Set WhitelistedEmission smart contract.
	 */
	function setWhitelistedEmissionContract(address whitelistedEmission)
		external;

	/**
	 * @dev Calculate pending rewards for the provided 'address'. The rate is the moving reward rate.
	 * @param holderAddress: holder contract address
	 */
	function isHolderContractWhitelisted(address holderAddress)
		external
		view
		returns (bool result);

	/*
	 * @dev set holder addresses for rewards
	 * @param holderContractAddresses: addresses in array
	 * @param rewardTokenContractAddresses: reward token addresses in array
	 */
	function setHolderAddressesForRewards(
		address[] memory holderContractAddresses,
		address[] memory rewardTokenContractAddresses
	) external returns (bool success);

	/*
	 * @dev remove holder addresses for rewards
	 * @param holderContractAddresses: addresses in array
	 */
	function removeHolderAddressesForRewards(
		address[] memory holderContractAddresses
	) external returns (bool success);

	/*
	 * @dev remove token addresses for rewards
	 * @param holderContractAddresses: addresses in array
	 * @param rewardTokenContractAddresses: reward token addresses in array
	 */
	function removeTokenContractsForRewards(
		address[] memory holderContractAddresses,
		address[] memory rewardTokenContractAddresses
	) external returns (bool success);

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
	 * @dev Emitted when add rewards is called
	 */
	event AddRewards(
		address holderContractAddress,
		address rewardTokenContractAddress,
		address rewardSender,
		uint256 tokens,
		uint256 timestamp
	);

	/**
	 * @dev Emitted when reward emission is set
	 */
	event SetRewardEmission(
		address holderContractAddress,
		address rewardTokenContractAddress,
		uint256 rewardTokenEmission,
		uint256 valueDivisor,
		uint256 timestamp
	);

	/**
	 * @dev Emitted when rewards are calculated
	 */
	event CalculateRewardsStakeLP(
		address holderAddress,
		address lpToken,
		address accountAddress,
		uint256[] RewardAmounts,
		address[] RewardTokens,
		address[] uTokenAddresses,
		uint256 timestamp
	);

	/**
	 * @dev Emitted when rewards are calculated
	 */
	event TriggeredCalculateSyncedRewards(
		address holderAddress,
		address accountAddress,
		uint256[] RewardAmounts,
		address[] RewardTokens,
		address[] uTokenAddresses,
		uint256 holderReward,
		uint256 timestamp
	);

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
	 * @dev Emitted when contract addresses are set
	 */
	event SetWhitelistedEmissionContract(address indexed _contract);

	/**
	 * @dev Emitted when holder addresses are set
	 */
	event SetHolderAddressesForRewards(
		address[] holderContractAddresses,
		address[] rewardTokenContractAddress,
		uint256 timestamp
	);

	/**
	 * @dev Emitted holder addresses are removed
	 */
	event RemoveHolderAddressesForRewards(
		address[] holderContractAddresses,
		uint256 timestamp
	);

	/**
	 * @dev Emitted token contracts are removed
	 */
	event RemoveTokenContractsForRewards(
		address[] holderContractAddresses,
		address[] rewardTokenContractAddress,
		uint256 timestamp
	);
}
