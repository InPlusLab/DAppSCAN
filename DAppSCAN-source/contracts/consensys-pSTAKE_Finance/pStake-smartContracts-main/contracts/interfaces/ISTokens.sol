/*
 Copyright [2019] - [2021], PERSISTENCE TECHNOLOGIES PTE. LTD. and the pStake-smartContracts contributors
 SPDX-License-Identifier: Apache-2.0
*/

pragma solidity >=0.7.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

/**
 * @dev Interface of the ISTokens.
 */
interface ISTokens is IERC20Upgradeable {
	/**
	 * @dev Mints `amount` tokens to the caller's address `to`.
	 *
	 * Returns a boolean value indicating whether the operation succeeded.
	 *
	 * Emits a {Transfer} event.
	 */
	function mint(address to, uint256 tokens) external returns (bool);

	/**
	 * @dev Burns `amount` tokens to the caller's address `from`.
	 *
	 * Returns a boolean value indicating whether the operation succeeded.
	 *
	 * Emits a {Transfer} event.
	 */
	function burn(address from, uint256 tokens) external returns (bool);

	/**
	 * @dev checks if given contract address is whitelisted
	 *
	 */
	function isContractWhitelisted(address lpContractAddress)
		external
		view
		returns (bool result, address holderAddress);

	/**
	 * @dev get holder data
	 *
	 * Returns holderAddress, lpAddress and lastHolderRewardTimestamp
	 */
	function getHolderData(address whitelistedAddress)
		external
		view
		returns (
			address holderAddress,
			address lpAddress,
			uint256 lastHolderRewardTimestamp
		);

	/**
	 * @dev Sets `reward rate`.
	 *
	 * Returns a boolean value indicating whether the operation succeeded.
	 */
	function setRewardRate(uint256 rewardRate) external returns (bool success);

	/**
	 * @dev calculates the reward that is pending to be received.
	 *
	 * Returns pending reward.
	 */
	function calculatePendingRewards(address to)
		external
		view
		returns (uint256 pendingRewards);

	/**
	 * @dev Calculates rewards `amount` tokens to the caller's address `to`.
	 *
	 * Returns a boolean value indicating whether the operation succeeded.
	 *
	 * Emits a {TriggeredCalculateRewards} event.
	 */
	function calculateRewards(address to) external returns (bool success);

	/**
	 * @dev Set UTokens smart contract.
	 *
	 * Emits a {SetContract} event.
	 */
	function setUTokensContract(address uTokenContract) external;

	/**
	 * @dev Set LiquidStaking smart contract.
	 */
	function setLiquidStakingContract(address liquidStakingContract) external;

	/**
	 * @dev Emitted when contract addresses are set
	 */
	event SetUTokensContract(address indexed _contract);

	/**
	 * @dev Emitted when contract addresses are set
	 */
	event SetLiquidStakingContract(address indexed _contract);

	/**
	 * @dev Emitted when a new whitelisted address is added
	 */
	event SetWhitelistedAddress(
		address indexed whitelistedAddress,
		address holderContractAddress,
		address lpContractAddress,
		uint256 timestamp
	);

	/**
	 * @dev Emitted when a new whitelisted address is removed
	 */
	event RemoveWhitelistedAddress(
		address indexed whitelistedAddress,
		address holderContractAddress,
		address lpContractAddress,
		uint256 timestamp
	);

	/**
	 * @dev Emitted when `rewards` tokens are moved to account
	 *
	 * Note that `value` may be zero.
	 */
	event CalculateRewards(
		address indexed accountAddress,
		uint256 tokens,
		uint256 timestamp
	);

	/**
	 * @dev Emitted when `rewards` tokens are moved to holder account
	 *
	 * Note that `value` may be zero.
	 */
	event CalculateHolderRewards(
		address indexed accountAddress,
		uint256 tokens,
		uint256 timestamp
	);

	/**
	 * @dev Emitted when `rewards` tokens are moved to account
	 *
	 * Note that `value` may be zero.
	 */
	event TriggeredCalculateRewards(
		address indexed accountAddress,
		uint256 tokens,
		uint256 timestamp
	);
}
