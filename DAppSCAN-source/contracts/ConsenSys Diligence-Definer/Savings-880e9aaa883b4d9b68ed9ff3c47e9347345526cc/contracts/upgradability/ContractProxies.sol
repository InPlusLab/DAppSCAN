pragma solidity 0.5.14;

import "@openzeppelin/upgrades/contracts/upgradeability/InitializableAdminUpgradeabilityProxy.sol";

contract SavingAccountProxy is InitializableAdminUpgradeabilityProxy {

    /**
     * @dev Overriding Proxy's fallback function to allow it to receive ETH
     * @notice https://forum.openzeppelin.com/t/openzeppelin-upgradeable-contracts-affected-by-istanbul-hardfork/1616
     * @notice After Istanbul hardfork ZOS upgradable contracts were not able receive ETH with fallback functions
     * Hence, we have added a possible fix for this issue
     */
    function () external payable {
        // When no function call is invoked for delegatecall, assume that ETH is sent to the contract
        // Hence, just return and accept ETH at Proxy, which are sent from other contract
        if(msg.data.length == 0) return;
        // When data is present, follow the normal Proxy calls
        super._fallback();
    }
}