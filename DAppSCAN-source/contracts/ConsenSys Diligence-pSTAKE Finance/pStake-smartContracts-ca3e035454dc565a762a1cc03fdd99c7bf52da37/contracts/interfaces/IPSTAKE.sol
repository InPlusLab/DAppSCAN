// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.7.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

/**
 * @dev Interface of the IPSTAKE.
 */
interface IPSTAKE is IERC20Upgradeable {
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
	// function burn(address from, uint256 tokens) external returns (bool);

	/**
	 * @dev Set LiquidStaking smart contract.
	 */
	function setStakeLPCoreContract(address stakeLPCoreContract) external;

	/**
	 * @dev Emitted when contract addresses are set
	 */
	event SetStakeLPCoreContract(address indexed _contract);

	/**
	 * @dev Emitted when contract addresses are set
	 */
	event SetUTokensContract(address indexed _contract);

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
	 * @dev Emitted when `rewards` tokens are moved to account
	 *
	 * Note that `value` may be zero.
	 */
	event TriggeredCalculateRewards(
		address indexed accountAddress,
		uint256 tokens,
		uint256 timestamp
	);

	/**
	 * @dev Emitted when contract addresses are set
	 */
	event SetTokenWrapperContract(address indexed _contract);

	/**
	 * @dev Emitted when contract addresses are set
	 */
	event SetLiquidStakingContract(address indexed _contract);
}
