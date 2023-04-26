pragma solidity 0.5.5;

/**
 * @title ProxyAdmin
 * @dev This contract is the admin of a proxy, and is in charge
 * of upgrading it as well as transferring it to another admin.
 * The ProxyAdmin contract is from https://github.com/OpenZeppelin/openzeppelin-sdk/blob/master/packages/lib/contracts/upgradeability/ProxyAdmin.sol
 * branch: master commit: 71c9ad77e0326db079e6a643eca8568ab316d4a9 modified to:
 * 1) Inherit from our custom Ownable contract
 * 2) Adds initializer that lets us set number of allowed upgrades
 * 3) Prevents contract from being upgraded more than allowedUpgrade times
 * 4) Removes ability to change admin (to prevent contract from being upgraded further)
 */

import "@openzeppelin/upgrades/contracts/upgradeability/AdminUpgradeabilityProxy.sol";
import "@openzeppelin/upgrades/contracts/ownership/Ownable.sol";

contract LimitedUpgradesProxyAdmin is OpenZeppelinUpgradesOwnable {
    uint256 public allowedUpgradesPerProxy;
    mapping(address => uint256) internal upgradeCounts;
    bool internal initialized;

    function initialize(address _owner, uint256 _allowedUpgradesPerProxy) public {
        require(!initialized);

        _transferOwnership(_owner);
        allowedUpgradesPerProxy = _allowedUpgradesPerProxy;
        initialized = true;
    }

    /**
     * @dev Returns the current implementation of a proxy.
     * This is needed because only the proxy admin can query it.
     * @return The address of the current implementation of the proxy.
     */
    function getProxyImplementation(AdminUpgradeabilityProxy proxy) public view returns (address) {
        // We need to manually run the static call since the getter cannot be flagged as view
        // bytes4(keccak256("implementation()")) == 0x5c60da1b
        (bool success, bytes memory returndata) = address(proxy).staticcall(hex"5c60da1b");
        require(success);
        return abi.decode(returndata, (address));
    }

    /**
     * @dev Returns the admin of a proxy. Only the admin can query it.
     * @return The address of the current admin of the proxy.
     */
    function getProxyAdmin(AdminUpgradeabilityProxy proxy) public view returns (address) {
        // We need to manually run the static call since the getter cannot be flagged as view
        // bytes4(keccak256("admin()")) == 0xf851a440
        (bool success, bytes memory returndata) = address(proxy).staticcall(hex"f851a440");
        require(success);
        return abi.decode(returndata, (address));
    }

    /**
     * @dev Upgrades a proxy to the newest implementation of a contract.
     * @param proxy Proxy to be upgraded.
     * @param implementation the address of the Implementation.
     */
    function upgrade(AdminUpgradeabilityProxy proxy, address implementation) public onlyOwner {
        require(upgradeCounts[address(proxy)] < allowedUpgradesPerProxy);
        upgradeCounts[address(proxy)] += 1;
        proxy.upgradeTo(implementation);
    }

    /**
     * @dev Upgrades a proxy to the newest implementation of a contract and forwards a function call to it.
     * This is useful to initialize the proxied contract.
     * @param proxy Proxy to be upgraded.
     * @param implementation Address of the Implementation.
     * @param data Data to send as msg.data in the low level call.
     * It should include the signature and the parameters of the function to be called, as described in
     * https://solidity.readthedocs.io/en/v0.4.24/abi-spec.html#function-selector-and-argument-encoding.
     */
    function upgradeAndCall(AdminUpgradeabilityProxy proxy, address implementation, bytes memory data) payable public onlyOwner {
        require(upgradeCounts[address(proxy)] < allowedUpgradesPerProxy);
        upgradeCounts[address(proxy)] += 1;
        proxy.upgradeToAndCall.value(msg.value)(implementation, data);
    }
}
