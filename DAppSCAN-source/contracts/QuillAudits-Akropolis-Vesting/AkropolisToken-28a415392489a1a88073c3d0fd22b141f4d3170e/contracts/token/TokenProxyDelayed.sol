pragma solidity >=0.4.24;

import "./dataStorage/TokenStorage.sol";
import '../upgradeability/DelayedUpgradeabilityProxy.sol';
import '../helpers/Ownable.sol';

/**
* @title TokenProxyDelayed
* @notice A proxy contract that serves the latest implementation of TokenProxy. This proxy
* upgrades only after a set amount of time (denominated in blocks mined) 
*/
contract TokenProxyDelayed is DelayedUpgradeabilityProxy, TokenStorage, Ownable {
    constructor(address _implementation, address _balances, address _allowances, string _name, uint8 _decimals, string _symbol) 
    DelayedUpgradeabilityProxy(_implementation) 
    TokenStorage(_balances, _allowances, _name, _decimals, _symbol) public {}

    /**
    * @dev Upgrade the backing implementation of the proxy.
    * Only the admin can call this function.
    * @param newImplementation Address of the new implementation.
    */
    function upgradeTo(address newImplementation) public onlyOwner {
        _setPendingUpgrade(newImplementation);
    }

    /**
    * @return The address of the implementation.
    */
    function implementation() public view returns (address) {
        return _implementation();
    }
}