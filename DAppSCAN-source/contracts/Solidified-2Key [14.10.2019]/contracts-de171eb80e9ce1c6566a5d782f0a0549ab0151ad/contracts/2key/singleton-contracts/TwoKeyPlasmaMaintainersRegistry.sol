pragma solidity ^0.4.24;

import "../interfaces/storage-contracts/ITwoKeyPlasmaMaintainersRegistryStorage.sol";
import "../upgradability/Upgradeable.sol";

contract TwoKeyPlasmaMaintainersRegistry is Upgradeable {
    bool initialized;

    address public TWO_KEY_PLASMA_SINGLETON_REGISTRY;

    ITwoKeyPlasmaMaintainersRegistryStorage public PROXY_STORAGE_CONTRACT;


    function setInitialParams(
        address _twoKeySingletonRegistryPlasma,
        address _proxyStorage,
        address[] _maintainers
    )
    public
    {
        require(initialized == false);

        TWO_KEY_PLASMA_SINGLETON_REGISTRY = _twoKeySingletonRegistryPlasma;

        PROXY_STORAGE_CONTRACT = ITwoKeyPlasmaMaintainersRegistryStorage(_proxyStorage);

        //Set deployer to be also a maintainer
        addMaintainer(msg.sender);

        for(uint i=0; i<_maintainers.length; i++) {
            addMaintainer(_maintainers[i]);
        }

        initialized = true;
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
        require(onlyMaintainer(msg.sender) == true);
        //If state variable, .balance, or .length is used several times, holding its value in a local variable is more gas efficient.
        uint numberOfMaintainers = _maintainers.length;
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
        require(onlyMaintainer(msg.sender) == true);
        //If state variable, .balance, or .length is used several times, holding its value in a local variable is more gas efficient.
        uint numberOfMaintainers = _maintainers.length;
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
}
