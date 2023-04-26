/*
 Copyright [2019] - [2021], PERSISTENCE TECHNOLOGIES PTE. LTD. and the pStake-smartContracts contributors
 SPDX-License-Identifier: Apache-2.0
*/

pragma solidity >=0.7.0;

/**
 * @dev Interface of the ITokenWrapper.
 */
interface ITokenWrapperV2 {
	/**
	 * @dev Set UTokens smart contract.
	 * Emits a {SetUTokensContract} event.
	 */
	function setUTokensContract(address uAddress) external;

	/**
	 * @dev checks if the address is Bech32 valid
	 *
	 */
	function isBech32Valid(string memory toChainAddress)
		external
		view
		returns (bool isAddressValid);

	/**
	 * @dev Generates `amount` tokens to the caller's address `to`.
	 *
	 * Emits a {GenerateUTokens} event.
	 */
	function generateUTokens(address to, uint256 amount) external;

	/**
	 * @dev Generates `amount` tokens to the caller's addresses `to`.
	 *
	 * Emits a {GenerateUTokens} event.
	 */
	function generateUTokensInBatch(
		address[] memory to,
		uint256[] memory amount
	) external;

	/**
	 * @dev Withdraws `amount` tokens to the caller's address `to`.
	 *
	 * Emits a {WithdrawUTokens} event.
	 */
	function withdrawUTokens(
		address from,
		uint256 tokens,
		string memory toChainAddress
	) external;

	/**
	 * @dev Emitted when fees are set
	 */
	event SetFees(uint256 indexed depositFee, uint256 indexed withdrawFee);

	/**
	 * @dev Emitted when minimum values are set
	 */
	event SetMinimumValues(
		uint256 indexed minDeposit,
		uint256 indexed minWithdraw
	);

	/**
	 * @dev Emitted when contract addresses are set
	 */
	event SetUTokensContract(address indexed _contract);

	/**
	 * @dev Emitted when uTokens are generated
	 */
	event GenerateUTokens(
		address indexed accountAddress,
		uint256 indexed tokens,
		uint256 indexed finalTokens,
		uint256 timestamp
	);

	/**
	 * @dev Emitted when UTokens are withdrawn
	 */
	event WithdrawUTokens(
		address indexed accountAddress,
		uint256 indexed tokens,
		uint256 finalTokens,
		string indexed toChainAddress,
		uint256 timestamp
	);

	function setFees(uint256 depositFee, uint256 withdrawFee)
		external
		returns (bool success);

	/**
	 * @dev get fees, minimum set values and value divisor
	 *
	 */
	function getProps()
		external
		view
		returns (
			uint256 depositFee,
			uint256 withdrawFee,
			uint256 minDeposit,
			uint256 minWithdraw,
			uint256 valueDivisor
		);

	/**
	 * @dev Set 'minimum values', called from admin
	 * @param minDeposit: deposit minimum value
	 * @param minWithdraw: withdraw minimum value
	 *
	 * Emits a {SetMinimumValues} event with 'minimum value' set to withdraw.
	 *
	 */
	function setMinimumValues(uint256 minDeposit, uint256 minWithdraw)
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
	 * @dev Emitted when uTokens are generated in batch
	 */
	event GenerateUTokensInBatch(
		address[] accountAddress,
		uint256[] tokens,
		uint256[] finalTokens,
		uint256 timestamp
	);

	/**
	 * @dev Emitted when UTokens are withdrawn
	 */
	event WithdrawUTokensV2(
		address indexed accountAddress,
		uint256 indexed tokens,
		uint256 indexed finalTokens,
		string toChainAddress,
		uint256 timestamp
	);
}
