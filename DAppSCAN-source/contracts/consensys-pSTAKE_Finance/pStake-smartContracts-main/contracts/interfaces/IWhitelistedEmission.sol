/*
 Copyright [2019] - [2021], PERSISTENCE TECHNOLOGIES PTE. LTD. and the pStake-smartContracts contributors
 SPDX-License-Identifier: Apache-2.0
*/

pragma solidity >=0.7.0;

interface IWhitelistedEmission {

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
	 * @dev get whitelisted address
	 * @param whitelistedAddress: contract address
	 */
	function getWhitelistedSTokens(address whitelistedAddress)
		external
		view
		returns (address[] memory sTokenAddresses);

	/**
	 * @dev set whitelisted addresses
	 */
	function setWhitelistedAddress(
		address whitelistedAddress,
		address[] memory sTokenAddresses,
		address holderContractAddress,
		address lpContractAddress
	) external returns (bool success);

	/**
	 * @dev remove whitelsited address
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
}
