/*
 Copyright [2019] - [2021], PERSISTENCE TECHNOLOGIES PTE. LTD. and the pStake-smartContracts contributors
 SPDX-License-Identifier: Apache-2.0
*/

pragma solidity >=0.7.0;

/**
 * @dev Interface of the IHolder.
 */
interface IHolder {
	/**
	 * @dev Set UTokens smart contract.
	 *
	 * Emits a {SetSTokensContract} event.
	 */
	function setSTokensContract(address utokenContract) external;

	/**
	 * @dev Set stakeLP smart contract.
	 *
	 * Emits a {SetStakeLPContract} event.
	 */
	function setStakeLPContract(address stakeLPContract) external;

	/**
	 * @dev returns stoken supply
	 */
	function getSTokenSupply(
		address to,
		address from,
		uint256 amount
	) external view returns (uint256);

	/**
	 * @dev transfers token amount
	*/
	function safeTransfer(
		address token,
		address to,
		uint256 value
	) external;

	/**
	 * @dev Emitted when contract addresses are set
	 */
	event SetSTokensContract(address indexed _contract);

	/**
	 * @dev Emitted when contract addresses are set
	 */
	event SetStakeLPContract(address indexed _contract);
}