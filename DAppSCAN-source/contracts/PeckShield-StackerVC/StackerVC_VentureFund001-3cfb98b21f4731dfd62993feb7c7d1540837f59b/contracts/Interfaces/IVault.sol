// SPDX-License-Identifier: MIT

pragma solidity ^0.6.11;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol"; // call ERC20 safely

interface IVault {
	using SafeERC20 for IERC20;
	
	function deposit(uint256 _amount) external;
	function depositETH() payable external;
	function withdraw(uint256 _shares) external;
	function withdrawETH(uint256 _shares) external;
	function token() external view returns (IERC20);
}
