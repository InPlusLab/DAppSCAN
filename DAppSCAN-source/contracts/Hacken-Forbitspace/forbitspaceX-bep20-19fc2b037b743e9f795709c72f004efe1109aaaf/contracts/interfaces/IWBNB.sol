// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import { IBEP20 } from "./IBEP20.sol";

interface IWBNB is IBEP20 {
	/// @notice Deposit ether to get wrapped ether
	function deposit() external payable;

	/// @notice Withdraw wrapped ether to get ether
	function withdraw(uint) external;
}
