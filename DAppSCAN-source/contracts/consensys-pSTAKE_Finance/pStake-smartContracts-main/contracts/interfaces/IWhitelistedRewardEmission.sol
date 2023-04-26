/*
 Copyright [2019] - [2021], PERSISTENCE TECHNOLOGIES PTE. LTD. and the pStake-smartContracts contributors
 SPDX-License-Identifier: Apache-2.0
*/

pragma solidity >=0.7.0;

interface IWhitelistedRewardEmission {

	/*
	 * @dev add the rewards to the sender
	 * @param holderContractAddress: contract address
	 * @param rewardTokenContractAddress: contract address
	 * @param rewardSender: sender address
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

	/**
	 * @dev Set 'contract address', called from constructor
	 *
	 * Emits a {} event with '_contract' set to the stakeLP contract address.
	 *
	 */
	function setStakeLPContract(address stakeLPContract) external;

	/*
	 * @dev set reward pool for user
	 * @param holderContractAddress: contract address
	 * @param rewardTokenContractAddress: contract address
	 * @param accountAddress: account address
	 * @param timestampValue: timestamp value
	 */
	function setRewardPoolUserTimestamp(
		address holderContractAddress,
		address rewardTokenContractAddress,
		address accountAddress,
		uint256 timestampValue
	) external returns (bool success);

	/*
	 * @dev get reward pool for user
	 * @param holderContractAddress: contract address
	 * @param rewardTokenContractAddress: contract address
	 * @param accountAddress: account address
	 */
	function getRewardPoolUserTimestamp(
		address holderContractAddress,
		address rewardTokenContractAddress,
		address accountAddress
	) external view returns (uint256 rewardPoolUserTimestamp);

	/*
	 * @dev set last LP time share
	 * @param lpTokenAddress: contract address
	 * @param timestampValue: timestamp value
	 */
	function setLastLPTimeShareTimestamp(
		address lpTokenAddress,
		uint256 timestampValue
	) external returns (bool success);

	/*
	 * @dev get last LP time share
	 * @param lpTokenAddress: contract address
	 */
	function getLastLPTimeShareTimestamp(address lpTokenAddress)
		external
		view
		returns (uint256 lastLPTimeShareTimestamp);

	/*
	 * @dev set last cummulative supply time share
	 * @param lpTokenAddress: contract address
	 * @param newSupplyLPTimeShare: timestamp value
	 */
	function setLastCummulativeSupplyLPTimeShare(
		address lpTokenAddress,
		uint256 newSupplyLPTimeShare
	) external returns (bool success);

	/*
	 * @dev calculate updated supply time share
	 * @param holderAddress: contract address
	 * @param lpTokenAddress: contract address
	 * @param rewardTokenAddress: contract address
	 * @param accountAddress: account address
	 * @param newSupplyLPTimeShare: timestamp value
	 */
	function calculateUpdatedSupplyLPTimeShare(
		address holderAddress,
		address lpTokenAddress,
		address rewardTokenAddress,
		address accountAddress,
		uint256 newSupplyLPTimeShare
	) external view returns (uint256 updatedSupplyLPTimeShare);

	/*
	 * @dev calculate updated reward pool
	 * @param holderAddress: contract address
	 * @param rewardTokenAddress: contract address
	 * @param accountAddress: account address
	 */
	function calculateUpdatedRewardPool(
		address holderAddress,
		address rewardTokenAddress,
		address accountAddress
	) external view returns (uint256 updatedRewardPool);

	/*
	 * @dev calculate pending reward
	 * @param holderAddress: contract address
	 * @param lpTokenAddress: contract address
	 * @param accountAddress: account address
	  * @param userLPTimeShare: value
	   * @param newSupplyLPTimeShare: value
	 */
	function calculateOtherPendingRewards(
		address holderAddress,
		address lpTokenAddress,
		address accountAddress,
		uint256 userLPTimeShare,
		uint256 newSupplyLPTimeShare
	)
		external
		view
		returns (
			uint256[] memory otherRewardAmounts,
			address[] memory otherRewardTokens
		);

	/*
	 * @dev get reward
	 */
	function getCumulativeRewardValue(
		address holderContractAddress,
		address rewardTokenContractAddress,
		uint256 rewardTimestamp
	) external view returns (uint256 cumulativeRewardValue);

	/*
	 * @dev get supply
	 */
	function getCumulativeSupplyValue(
		address lpTokenAddress,
		uint256 lpSupplyTimestamp
	) external view returns (uint256 cumulativeSupplyValue);

	/**
	 * @dev Check if holder contract is whitelisted
	 * @param holderAddress: holder contract address
	 */
	function isHolderContractWhitelisted(address holderAddress)
		external
		view
		returns (bool result);

	/*
	 * @dev set holder addresses for rewards
	 * @param holderContractAddresses:  contract address in array
	 * @param rewardTokenContractAddresses: token amount in array
	 */
	function setHolderAddressesForRewards(
		address[] memory holderContractAddresses,
		address[] memory rewardTokenContractAddresses
	) external returns (bool success);

	/*
	 * @dev remove holder addresses for rewards
	 * @param holderContractAddresses:  contract address in array
	 */
	function removeHolderAddressesForRewards(
		address[] memory holderContractAddresses
	) external returns (bool success);

	/*
	 * @dev remove token contract for rewards
	 * @param holderContractAddresses:  contract address in array
	 * @param rewardTokenContractAddresses: token amount in array
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
	 * @dev Emitted when rewards are added
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
	 * @dev Emitted when reward pool is set
	 */
	event SetRewardPoolUserTimestamp(
		address indexed holderContractAddress,
		address indexed rewardTokenContractAddress,
		address indexed accountAddress,
		uint256 timestampValue,
		uint256 timestamp
	);

	/**
	 * @dev Emitted when LP timeshare is set
	 */
	event SetLastLPTimeShareTimestamp(
		address indexed lpTokenAddress,
		uint256 indexed timestampValue,
		uint256 timestamp
	);

	/**
	 * @dev Emitted cummulative supply timeshare is set
	 */
	event SetLastCummulativeSupplyLPTimeShare(
		address indexed lpTokenAddress,
		uint256 indexed newSupplyLPTimeShare,
		uint256 timestamp
	);

	/**
	 * @dev Emitted when holder addresses are set for rewards
	 */
	event SetHolderAddressesForRewards(
		address[] holderContractAddresses,
		address[] rewardTokenContractAddress,
		uint256 timestamp
	);

	/**
	 * @dev Emitted when holder addresses are removed for rewards
	 */
	event RemoveHolderAddressesForRewards(
		address[] holderContractAddresses,
		uint256 timestamp
	);

	/**
	 * @dev Emitted when token contract are removed for rewards
	 */
	event RemoveTokenContractsForRewards(
		address[] holderContractAddresses,
		address[] rewardTokenContractAddress,
		uint256 timestamp
	);

	/**
	 * @dev Emitted when contract addresses are set
	 */
	event SetStakeLPContract(address indexed stakeLPContract);
}
