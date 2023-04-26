pragma solidity ^0.6.2;

import "./ERC20.sol";
import "@openzeppelin/contracts/proxy/TransparentUpgradeableProxy.sol";


contract TokenProxy is TransparentUpgradeableProxy, ERC20 {
	/**
	 * Contract constructor.
	 * @param _logic address of the initial implementation.
	 * @param _admin Address of the proxy administrator.
	 * @param _data Optional data for executing after deployment
	 */
	constructor(address _logic, address _admin, bytes memory _data) TransparentUpgradeableProxy(_logic, _admin, _data) public payable {}
}
