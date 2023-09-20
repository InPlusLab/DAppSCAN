pragma solidity ^0.4.24;

import "../interfaces/ITwoKeySingletoneRegistryFetchAddress.sol";
import "../interfaces/storage-contracts/ITwoKeyMaintainersRegistryStorage.sol";
import "../upgradability/Upgradeable.sol";

/**
 * @author Nikola Madjarevic
 * @notice This is maintaining pattern supporting maintainers and twoKeyAdmin as ``central authority`` which is only eligible
 * to edit maintainers list
 */

contract TwoKeyMaintainersRegistry is Upgradeable {
    /**
     * Flag which will make function setInitialParams callable only once
     */
    bool initialized;

    address public TWO_KEY_SINGLETON_REGISTRY;

    ITwoKeyMaintainersRegistryStorage public PROXY_STORAGE_CONTRACT;

    /**
     * @notice Function which can be called only once, and is used as replacement for a constructor
     * @param _maintainers is the array of initial maintainers we'll kick off contract with
     */
    function setInitialParams(
        address _twoKeySingletonRegistry,
        address _proxyStorage,
        address [] _maintainers
    )
    public
    {
        require(initialized == false);


        TWO_KEY_SINGLETON_REGISTRY = _twoKeySingletonRegistry;

        PROXY_STORAGE_CONTRACT = ITwoKeyMaintainersRegistryStorage(_proxyStorage);


        //Set deployer to be also a maintainer
        addMaintainer(msg.sender);

        //Set initial maintainers
        for(uint i=0; i<_maintainers.length; i++) {
            addMaintainer(_maintainers[i]);
        }

        //Once this executes, this function will not be possible to call again.
        initialized = true;
    }


    /**
     * @notice Modifier to restrict calling the method to anyone but twoKeyAdmin
     */
    function onlyTwoKeyAdmin(address sender) public view returns (bool) {
        address twoKeyAdmin = getAddressFromTwoKeySingletonRegistry("TwoKeyAdmin");
        require(sender == address(twoKeyAdmin));
        return true;
    }

    function onlyMaintainer(address _sender) public view returns (bool) {
        return isMaintainer(_sender);
    }

    /**
     * @notice Function which can add new maintainers, in general it's array because this supports adding multiple addresses in 1 trnx
     * @dev only twoKeyAdmin contract is eligible to mutate state of maintainers
     * @param _maintainers is the array of maintainer addresses
     */
    function addMaintainers(
        address [] _maintainers
    )
    public
    {
        require(onlyTwoKeyAdmin(msg.sender) == true);
        //If state variable, .balance, or .length is used several times, holding its value in a local variable is more gas efficient.
        uint numberOfMaintainers = _maintainers.length;
        // SWC-128-DoS With Block Gas Limit: L82 - L84
        for(uint i=0; i<numberOfMaintainers; i++) {
            addMaintainer(_maintainers[i]);
        }
    }

    /**
     * @notice Function which can remove some maintainers, in general it's array because this supports adding multiple addresses in 1 trnx
     * @dev only twoKeyAdmin contract is eligible to mutate state of maintainers
     * @param _maintainers is the array of maintainer addresses
     */
    function removeMaintainers(
        address [] _maintainers
    )
    public
    {
        require(onlyTwoKeyAdmin(msg.sender) == true);
        //If state variable, .balance, or .length is used several times, holding its value in a local variable is more gas efficient.
        uint numberOfMaintainers = _maintainers.length;
        // SWC-128-DoS With Block Gas Limit: L101 - L104
        for(uint i=0; i<numberOfMaintainers; i++) {

            removeMaintainer(_maintainers[i]);
        }
    }


    function isMaintainer(
        address _address
    )
    internal
    view
    returns (bool)
    {
        bytes32 keyHash = keccak256("isMaintainer", _address);
        return PROXY_STORAGE_CONTRACT.getBool(keyHash);
    }

    function addMaintainer(
        address _maintainer
    )
    internal
    {
        bytes32 keyHash = keccak256("isMaintainer", _maintainer);
        PROXY_STORAGE_CONTRACT.setBool(keyHash, true);
    }

    function removeMaintainer(
        address _maintainer
    )
    internal
    {
        bytes32 keyHash = keccak256("isMaintainer", _maintainer);
        PROXY_STORAGE_CONTRACT.setBool(keyHash, false);
    }

    // Internal function to fetch address from TwoKeyRegistry
    function getAddressFromTwoKeySingletonRegistry(string contractName) internal view returns (address) {
        return ITwoKeySingletoneRegistryFetchAddress(TWO_KEY_SINGLETON_REGISTRY)
        .getContractProxyAddress(contractName);
    }

}
