// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @dev Minimal set of declarations for WBNB interoperability.
 */
interface WrappedToken is IERC20
{
	function deposit() external payable;
	function withdraw(uint256 _amount) external;
}
