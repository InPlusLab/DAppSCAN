// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.2;

interface IApeVault {
	function tap(uint256 _tapValue, uint256 _slippage, uint8 _type) external;
}