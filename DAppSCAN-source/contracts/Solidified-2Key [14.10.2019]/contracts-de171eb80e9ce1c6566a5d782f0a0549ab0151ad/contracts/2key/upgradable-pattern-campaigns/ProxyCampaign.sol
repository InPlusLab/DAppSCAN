pragma solidity ^0.4.0;


import "./UpgradabilityCampaignStorage.sol";
import "../upgradability/Proxy.sol";


contract ProxyCampaign is Proxy, UpgradeabilityCampaignStorage {

    constructor (string _contractName, string _version, address twoKeySingletonRegistry) public {
        twoKeyFactory = msg.sender;
        registry = ITwoKeySingletonesRegistry(twoKeySingletonRegistry);
        _implementation = registry.getVersion(_contractName, _version);
    }
}
