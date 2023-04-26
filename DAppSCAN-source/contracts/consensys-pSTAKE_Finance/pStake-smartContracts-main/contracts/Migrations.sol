/*
 Copyright [2019] - [2021], PERSISTENCE TECHNOLOGIES PTE. LTD. and the pStake-smartContracts contributors
 SPDX-License-Identifier: Apache-2.0
*/

pragma solidity >=0.7.0;

contract Migrations {
	address public owner = msg.sender;
	uint256 public last_completed_migration;

	modifier restricted() {
		require(
			msg.sender == owner,
			"This function is restricted to the contract's owner"
		);
		_;
	}

	function setCompleted(uint256 completed) public restricted {
		last_completed_migration = completed;
	}
}
