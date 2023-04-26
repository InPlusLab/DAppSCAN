/*
 Copyright [2019] - [2021], PERSISTENCE TECHNOLOGIES PTE. LTD. and the pStake-smartContracts contributors
 SPDX-License-Identifier: Apache-2.0
*/

pragma solidity >=0.7.0;

interface IWhitelistedPTokenEmission {

	/**
	 * @dev get holder data
	 */
	function getHolderData(address holderAddress)
		external
		view
		returns (
			address[] memory whitelistedAddresses,
			address[] memory sTokenAddresses,
			address[] memory uTokenAddresses,
			address lpTokenAddress
		);

	/**
	 * @dev check if contract is whitelsited
	 */
	function areContractsWhitelisted(
		address sTokenAddress,
		address[] memory whitelistedAddresses
	) external view returns (bool[] memory areWhitelisted);

	/**
	 * @dev Calculate pending rewards for the provided 'address'. The rate is the moving reward rate.
	 */
	function calculateAllHolderRewards(address holderAddress)
		external
		returns (
			uint256[] memory holderRewards,
			address[] memory sTokenAddresses,
			address[] memory uTokenAddresses,
			address lpTokenAddress
		);

	/**
	 * @dev Calculate pending rewards for the provided 'address'. The rate is the moving reward rate.
	 */
	function calculateAllPendingHolderRewards(address holderAddress)
		external
		view
		returns (
			uint256[] memory holderRewards,
			address[] memory sTokenAddresses,
			address[] memory uTokenAddresses,
			address lpTokenAddress
		);

	/**
	 * @dev set whitelisted address
	 */
	function setWhitelistedAddress(
		address whitelistedAddress,
		address[] memory sTokenAddresses,
		address holderContractAddress,
		address lpContractAddress
	) external returns (bool success);

	/**
	 * @dev remove whitelisted address
	 */
	function removeWhitelistedAddress(address whitelistedAddress)
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
	 * @dev Emitted when address is whitelisted
	 */
	event SetWhitelistedAddress(
		address indexed whitelistedAddress,
		address[] sTokenAddressesLocal,
		address indexed holderContractAddress,
		address indexed lpContractAddress,
		uint256 timestamp
	);

	/**
	 * @dev Emitted when whitelisted address is removed
	 */
	event RemoveWhitelistedAddress(
		address indexed whitelistedAddress,
		address[] sTokenAddressesLocal,
		address indexed holderAddressLocal,
		uint256 indexed timestamp
	);

	/**
	 * @dev Emitted when holder rewards are calculated
	 */
	event CalculateAllHolderRewards(
		address holderAddress,
		uint256[] holderRewards,
		uint256 timestamp
	);
}
