// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.2;

import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "./ApeRegistryBeacon.sol";

contract ApeBeacon is BeaconProxy {
	bytes32 private constant _OWNER_SLOT = 0xa7b53796fd2d99cb1f5ae019b54f9e024446c3d12b483f733ccc62ed04eb126a;

	constructor(address _apeBeacon, address _owner, bytes memory data) BeaconProxy(_apeBeacon, data) {
		assert(_OWNER_SLOT == bytes32(uint256(keccak256("eip1967.proxy.owner")) - 1));
		assembly {
            sstore(_OWNER_SLOT, _owner)
        }
	}

	function proxyOwner() public view returns(address owner) {
		assembly {
            owner := sload(_OWNER_SLOT)
        }
	}

	function transferProxyOwnership(address _newOwner) external {
		require(msg.sender == proxyOwner());
		assembly {
            sstore(_OWNER_SLOT, _newOwner)
        }
	}

	function setBeaconDeploymentPrefs(uint256 _value) external {
		require(msg.sender == proxyOwner());
		ApeRegistryBeacon(_beacon()).setDeploymentPrefs(_value);
	}
}