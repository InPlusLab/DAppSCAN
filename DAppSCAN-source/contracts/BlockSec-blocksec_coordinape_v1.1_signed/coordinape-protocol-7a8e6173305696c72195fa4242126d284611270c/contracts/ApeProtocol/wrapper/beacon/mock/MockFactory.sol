// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.2;

import "./MockVault.sol";
import "../ApeBeacon.sol";

contract MockVaultFactoryBeacon {
	mapping(address => bool) public vaultRegistry;

	address public yearnRegistry;
	address public apeRegistry;
	address public beacon;

	event VaultCreated(address vault);

	constructor(address _reg, address _apeReg, address _beacon) {
		apeRegistry = _apeReg;
		yearnRegistry = _reg;
		beacon = _beacon;
	}

	function createApeVault() external {
		bytes memory data = abi.encodeWithSignature("init()");
		ApeBeacon proxy = new ApeBeacon(beacon, msg.sender, data);
		vaultRegistry[address(proxy)] = true;
		emit VaultCreated(address(proxy));
	}
}
