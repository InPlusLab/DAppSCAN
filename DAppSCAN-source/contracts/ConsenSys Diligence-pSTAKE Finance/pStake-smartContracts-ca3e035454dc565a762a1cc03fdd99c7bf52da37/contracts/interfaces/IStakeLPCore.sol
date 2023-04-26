// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.7.0;

/**
 * @dev Interface of the IStakeLPCore.
 */
interface IStakeLPCore {
	/**
	 * @dev Mints `amount` tokens to the caller's address `to`.
	 *
	 * Returns a boolean value indicating whether the operation succeeded.
	 *
	 * Emits a {Transfer} event.
	 */
	// function mint(address to, uint256 tokens) external returns (bool);

	/**
	 * @dev Burns `amount` tokens to the caller's address `from`.
	 *
	 * Returns a boolean value indicating whether the operation succeeded.
	 *
	 * Emits a {Transfer} event.
	 */
	//function burn(address from, uint256 tokens) external returns (bool);

	/**
	 * @dev adds liquidity
	 *
	 * Returns a uint256
	 */
	function addLiquidity(address lpToken, uint256 amount)
		external
		returns (uint256, uint256);

	/**
	 * @dev remove liquidity
	 *
	 * Returns a uint256
	 */
	function removeLiquidity(address lpToken, uint256 amount)
		external
		returns (uint256, uint256);

	/**
	 * @dev Set UTokens smart contract.
	 *
	 *
	 * Emits a {SetContract} event.
	 */
	function setUTokensContract(address uAddress) external;

	/**
	 * @dev Set UTokens smart contract.
	 *
	 *
	 * Emits a {SetContract} event.
	 */
	function setSTokensContract(address sAddress) external;

	/**
	 * @dev Set UTokens smart contract.
	 *
	 *
	 * Emits a {SetContract} event.
	 */
	function setPSTAKEContract(address sAddress) external;

	/**
	 * @dev Set LiquidStaking smart contract.
	 */
	// function setLiquidStakingContract(address liquidStakingContract) external;

	/**
	 * @dev Emitted when contract addresses are set
	 */
	event SetUTokensContract(address indexed _contract);

	/**
	 * @dev Emitted when contract addresses are set
	 */
	event SetSTokensContract(address indexed _contract);

	/**
	 * @dev Emitted when contract addresses are set
	 */
	event SetPSTAKEContract(address indexed _contract);

	/**
	 * @dev Emitted when a new whitelisted address is added
	 *
	 * Returns a boolean value indicating whether the operation succeeded.
	 */
	event CalculateRewardsAndLiquidity(
		address indexed holderAddress,
		address indexed lpToken,
		address indexed to,
		uint256 liquidity,
		uint256 reward
	);

	/**
	 * @dev Emitted
	 */
	event AddLiquidity(
		address lpToken,
		uint256 amount,
		uint256 rewards,
		uint256 liquidity
	);

	/**
	 * @dev Emitted
	 */
	event RemoveLiquidity(
		address lpToken,
		uint256 amount,
		uint256 rewards,
		uint256 liquidity
	);
}
