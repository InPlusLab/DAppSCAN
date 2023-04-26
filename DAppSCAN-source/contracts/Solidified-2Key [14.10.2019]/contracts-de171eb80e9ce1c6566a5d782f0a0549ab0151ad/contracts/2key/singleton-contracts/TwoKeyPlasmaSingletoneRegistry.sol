pragma solidity ^0.4.24;

import "../interfaces/ITwoKeySingletonesRegistry.sol";
import "../interfaces/IStructuredStorage.sol";

import "../upgradability/UpgradabilityProxy.sol";
import "../upgradability/Upgradeable.sol";

/**
 * @author Nikola Madjarevic
 * @title Registry for plasma network
 * @dev This contract works as a registry of versions, it holds the implementations for the registered versions.
 * @notice Will be everything mapped by contract name, so we will easily update and get versions per contract, all stored here
 */
contract TwoKeyPlasmaSingletoneRegistry is ITwoKeySingletonesRegistry {

    address public deployer;

    mapping (string => mapping(string => address)) internal versions;
    mapping (string => address) contractToProxy;
    mapping (string => string) contractNameToLatestVersionName;

    event ProxiesDeployed(
        address logicProxy,
        address storageProxy
    );

    mapping (address => bool) public isMaintainer;

    constructor(address [] _maintainers, address _twoKeyAdmin) public {
        isMaintainer[msg.sender] = true; //for truffle deployment
        for(uint i=0; i<_maintainers.length; i++) {
            isMaintainer[_maintainers[i]] = true;
        }
    }

    modifier onlyMaintainer {
        require(isMaintainer[msg.sender]);
        _;
    }

    /**
     * @dev Registers a new version with its implementation address
     * @param version representing the version name of the new implementation to be registered
     * @param implementation representing the address of the new implementation to be registered
     */
    function addVersion(string contractName, string version, address implementation) public onlyMaintainer {
        require(versions[contractName][version] == 0x0);
        versions[contractName][version] = implementation;
        contractNameToLatestVersionName[contractName] = version;
        emit VersionAdded(version, implementation);
    }

    /**
     * @dev Tells the address of the implementation for a given version
     * @param version to query the implementation of
     * @return address of the implementation registered for the given version
     */
    function getVersion(string contractName, string version) public view returns (address) {
        return versions[contractName][version];
    }

    /**
     * @notice Gets the latest contract version
     * @param contractName is the name of the contract
     * @return string representation of the last version
     */
    function getLatestContractVersion(string contractName) public view returns (string) {
        return contractNameToLatestVersionName[contractName];
    }

    /**
     * @notice Function to return address of proxy for specific contract
     * @param _contractName is the name of the contract we'd like to get proxy address
     * @return is the address of the proxy for the specific contract
     */
    function getContractProxyAddress(string _contractName) public view returns (address) {
        return contractToProxy[_contractName];
    }

    function deployProxy(
        string contractName,
        string version
    )
    internal
    returns (address)
    {
        UpgradeabilityProxy proxy = new UpgradeabilityProxy(contractName, version);
        contractToProxy[contractName] = proxy;
        return address(proxy);
    }

    /**
     * @dev Creates an upgradeable proxy for both Storage and Logic
     * @param version representing the first version to be set for the proxy
     */
    function createProxy(
        string contractName,
        string contractNameStorage,
        string version
    )
    public
    onlyMaintainer
    {
        address logicProxy = deployProxy(contractName, version);
        address storageProxy = deployProxy(contractNameStorage, version);

        IStructuredStorage(storageProxy).setProxyLogicContractAndDeployer(logicProxy, msg.sender);
        emit ProxiesDeployed(logicProxy, storageProxy);
    }

    function upgradeContract(
        string contractName,
        string version
    )
    public
    onlyMaintainer
        //TODO: Change to deployer
    {
        address proxyAddress = getContractProxyAddress(contractName);
        address _impl = getVersion(contractName, version);
        UpgradeabilityProxy(proxyAddress).upgradeTo(contractName, version, _impl);
    }

    function addMaintainers(
        address [] _maintainers
    )
    public
    onlyMaintainer
    {
        //If state variable, .balance, or .length is used several times, holding its value in a local variable is more gas efficient.
        uint numberOfMaintainers = _maintainers.length;
        for(uint i=0; i<numberOfMaintainers; i++) {
            isMaintainer[_maintainers[i]] = true;
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
    onlyMaintainer
    {
        //If state variable, .balance, or .length is used several times, holding its value in a local variable is more gas efficient.
        uint numberOfMaintainers = _maintainers.length;
        for(uint i=0; i<numberOfMaintainers; i++) {
            isMaintainer[_maintainers[i]] = false;
        }
    }
}
