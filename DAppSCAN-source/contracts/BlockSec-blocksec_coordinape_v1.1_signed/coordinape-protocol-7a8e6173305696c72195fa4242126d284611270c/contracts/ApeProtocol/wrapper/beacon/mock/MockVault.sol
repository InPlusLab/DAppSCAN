// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.2;

contract ApeVaultWrapperImplementation1 {

	uint256 public someValue;
	bool public setup;

	function init() external {
		require(!setup);
		setup = true;
	}

	function write() external {
		someValue = 11;
	}

	function version() external view returns(uint256) {
		return 1;
	}
}

contract ApeVaultWrapperImplementation2 {

	uint256 public someValue;
	bool public setup;

	function init() external {
		require(!setup);
		setup = true;
	}

	function write() external {
		someValue = 22;
	}

	function version() external view returns(uint256) {
		return 2;
	}
}

contract ApeVaultWrapperImplementation3 {

	uint256 public someValue;
	bool public setup;

	function init() external {
		require(!setup);
		setup = true;
	}

	function write() external {
		someValue = 33;
	}

	function version() external view returns(uint256) {
		return 3;
	}
}