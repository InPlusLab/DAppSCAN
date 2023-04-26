pragma solidity 0.7.5;

import "../interfaces/IUpgradeabilityOwnerStorage.sol";

contract Upgradeable {
    // Avoid using onlyUpgradeabilityOwner name to prevent issues with implementation from proxy contract
    modifier onlyIfUpgradeabilityOwner() {
        require(msg.sender == IUpgradeabilityOwnerStorage(address(this)).upgradeabilityOwner());
        _;
    }
}
