// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @dev An interface to extend gTokens with locked liquidity pools.
 *      See GTokenBase.sol for further documentation.
 */
interface GPooler
{
	// view functions
	function stakesToken() external view returns (address _stakesToken);
	function liquidityPool() external view returns (address _liquidityPool);
	function liquidityPoolBurningRate() external view returns (uint256 _burningRate);
	function liquidityPoolLastBurningTime() external view returns (uint256 _lastBurningTime);
	function liquidityPoolMigrationRecipient() external view returns (address _migrationRecipient);
	function liquidityPoolMigrationUnlockTime() external view returns (uint256 _migrationUnlockTime);

	// priviledged functions
	function allocateLiquidityPool(uint256 _stakesAmount, uint256 _sharesAmount) external;
	function setLiquidityPoolBurningRate(uint256 _burningRate) external;
	function burnLiquidityPoolPortion() external;
	function initiateLiquidityPoolMigration(address _migrationRecipient) external;
	function cancelLiquidityPoolMigration() external;
	function completeLiquidityPoolMigration() external;

	// emitted events
	event BurnLiquidityPoolPortion(uint256 _stakesAmount, uint256 _sharesAmount);
	event InitiateLiquidityPoolMigration(address indexed _migrationRecipient);
	event CancelLiquidityPoolMigration(address indexed _migrationRecipient);
	event CompleteLiquidityPoolMigration(address indexed _migrationRecipient, uint256 _stakesAmount, uint256 _sharesAmount);
}
