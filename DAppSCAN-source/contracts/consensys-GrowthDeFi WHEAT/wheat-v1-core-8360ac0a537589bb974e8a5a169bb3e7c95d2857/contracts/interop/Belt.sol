// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

/**
 * @dev Minimal set of declarations for Belt interoperability.
 */
interface BeltStrategyToken
{
	function amountToShares(uint256 _amount) external view returns (uint256 _shares);
	function token() external view returns (address _token);

	function deposit(uint256 _amount, uint256 _minShares) external;
}

interface BeltStrategyPool
{
	function calc_token_amount(uint256[4] calldata _amounts, bool _deposit) external view returns (uint256 _tokenAmount);
	function coins(int128 _index) external view returns (address _coin);
	function pool_token() external view returns (address _token);
	function underlying_coins(int128 _index) external view returns (address _coin);

	function add_liquidity(uint256[4] calldata _amounts, uint256 _minTokenAmount) external;
}
