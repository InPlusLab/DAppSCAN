pragma solidity ^0.4.18;

import './Proxy.sol';
import '../interfaces/ITwoKeySingletonesRegistry.sol';
import "./UpgradabilityStorage.sol";

/**
 * @title UpgradeabilityProxy
 * @dev This contract represents a proxy where the implementation address to which it will delegate can be upgraded
 */
contract UpgradeabilityProxy is Proxy, UpgradeabilityStorage {

    //TODO: Add event through event source whenever someone calls upgradeTo
    /**
    * @dev Constructor function
    */
    constructor (string _contractName, string _version) public {
        registry = ITwoKeySingletonesRegistry(msg.sender);
        _implementation = registry.getVersion(_contractName, _version);
    }

    /**
    * @dev Upgrades the implementation to the requested version
    * @param _version representing the version name of the new implementation to be set
    */
    function upgradeTo(string _contractName, string _version, address _impl) public {
        require(msg.sender == address(registry));
        _implementation = _impl;
    }

}
