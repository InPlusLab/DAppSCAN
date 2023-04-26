// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @dev Minimal interface for gTokens, implemented by the GTokenBase contract.
 *      See GTokenBase.sol for further documentation.
 */
interface GToken is IERC20
{
	// pure functions
	function calcDepositSharesFromCost(uint256 _cost, uint256 _totalReserve, uint256 _totalSupply, uint256 _depositFee) external pure returns (uint256 _netShares, uint256 _feeShares);
	function calcDepositCostFromShares(uint256 _netShares, uint256 _totalReserve, uint256 _totalSupply, uint256 _depositFee) external pure returns (uint256 _cost, uint256 _feeShares);
	function calcWithdrawalSharesFromCost(uint256 _cost, uint256 _totalReserve, uint256 _totalSupply, uint256 _withdrawalFee) external pure returns (uint256 _grossShares, uint256 _feeShares);
	function calcWithdrawalCostFromShares(uint256 _grossShares, uint256 _totalReserve, uint256 _totalSupply, uint256 _withdrawalFee) external pure returns (uint256 _cost, uint256 _feeShares);

	// view functions
	function reserveToken() external view returns (address _reserveToken);
	function totalReserve() external view returns (uint256 _totalReserve);
	function depositFee() external view returns (uint256 _depositFee);
	function withdrawalFee() external view returns (uint256 _withdrawalFee);

	// open functions
	function deposit(uint256 _cost) external;
	function withdraw(uint256 _grossShares) external;
}
