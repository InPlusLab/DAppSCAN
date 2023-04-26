// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

/**
 * @dev An interface to extend gTokens with liquidity mining capabilities.
 *      See GCTokenBase.sol and GATokenBase.sol for further documentation.
 */
interface GMining
{
	// view functions
	function miningToken() external view returns (address _miningToken);
	function growthToken() external view returns (address _growthToken);
	function exchange() external view returns (address _exchange);
	function miningGulpRange() external view returns (uint256 _miningMinGulpAmount, uint256 _miningMaxGulpAmount);
	function growthGulpRange() external view returns (uint256 _growthMinGulpAmount, uint256 _growthMaxGulpAmount);

	// priviledged functions
	function setExchange(address _exchange) external;
	function setMiningGulpRange(uint256 _miningMinGulpAmount, uint256 _miningMaxGulpAmount) external;
	function setGrowthGulpRange(uint256 _growthMinGulpAmount, uint256 _growthMaxGulpAmount) external;
}
