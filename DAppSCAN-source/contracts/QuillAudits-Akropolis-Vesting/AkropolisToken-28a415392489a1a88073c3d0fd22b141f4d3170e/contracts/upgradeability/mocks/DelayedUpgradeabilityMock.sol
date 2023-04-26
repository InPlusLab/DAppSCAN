pragma solidity >=0.4.24;

import "../DelayedUpgradeabilityProxy.sol";
import '../../helpers/Ownable.sol';

contract DelayedUpgradeabilityProxyMock is DelayedUpgradeabilityProxy, Ownable {
    constructor(address _implementation) public DelayedUpgradeabilityProxy(_implementation) {}

    function upgradeTo(address implementation) public onlyOwner {
        _setPendingUpgrade(implementation);
    }
}