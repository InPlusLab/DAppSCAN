/*
 Copyright [2019] - [2021], PERSISTENCE TECHNOLOGIES PTE. LTD. and the pStake-smartContracts contributors
 SPDX-License-Identifier: Apache-2.0
*/

pragma solidity >=0.7.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

/**
 * @dev Interface of the IUTokens.
 */
interface IUTokensV2 is IERC20Upgradeable {
	/**
	 * @dev Mints `amount` tokens to the caller's address `to`.
	 *
	 * Returns a boolean value indicating whether the operation succeeded.
	 *
	 * Emits a {Transfer} event.
	 */
	function mint(address to, uint256 tokens) external returns (bool success);

	/**
	 * @dev Burns `amount` tokens to the caller's address `from`.
	 *
	 * Returns a boolean value indicating whether the operation succeeded.
	 *
	 * Emits a {Transfer} event.
	 */
	function burn(address from, uint256 tokens) external returns (bool success);

	/**
	 * @dev Set LiquidStaking smart contract.
	 */
	function setLiquidStakingContract(address liquidStakingContract) external;

	/**
	 * @dev Set STokens smart contract.
	 */
	function setSTokenContract(address stokenContract) external;

	/**
	 * @dev Set token wrapper smart contract.
	 */
	function setWrapperContract(address wrapperTokensContract) external;

	/**
	 * @dev Emitted when contract addresses are set
	 */
	event SetSTokensContract(address indexed _contract);

	/**
	 * @dev Emitted when contract addresses are set
	 */
	event SetWrapperContract(address indexed _contract);

	/**
	 * @dev Emitted when contract addresses are set
	 */
	event SetLiquidStakingContract(address indexed _contract);

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
}
