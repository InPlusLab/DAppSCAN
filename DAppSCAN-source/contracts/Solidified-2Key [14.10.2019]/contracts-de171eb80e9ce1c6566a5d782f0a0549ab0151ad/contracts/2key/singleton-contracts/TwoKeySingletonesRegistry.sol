pragma solidity ^0.4.24;

import "../UpgradabilityProxyAcquisition.sol";

import '../interfaces/ITwoKeySingletonesRegistry.sol';
import "../interfaces/IHandleCampaignDeployment.sol";
import "../interfaces/ITwoKeyCampaignValidator.sol";
import "../interfaces/ITwoKeyMaintainersRegistry.sol";
import "../interfaces/IStructuredStorage.sol";

import "../upgradability/UpgradabilityProxy.sol";
import "../upgradability/Upgradeable.sol";



/**
 * @author Nikola Madjarevic
 * @title Registry
 * @dev This contract works as a registry of versions, it holds the implementations for the registered versions.
 * @notice Will be everything mapped by contract name, so we will easily update and get versions per contract, all stored here
 */
contract TwoKeySingletonesRegistry is ITwoKeySingletonesRegistry {

    address public deployer;

    mapping (string => mapping(string => address)) internal versions;
    mapping (string => address) contractNameToProxyAddress;
    mapping (string => string) contractNameToLatestVersion;
    mapping (string => address) nonUpgradableContractToAddress;


    event ProxiesDeployed(
        address logicProxy,
        address storageProxy
    );

    /**
     * @notice Calling super constructor from maintaining pattern
     */
    constructor()
    public
    {
        deployer = msg.sender;
    }

    modifier onlyMaintainer {
        address twoKeyMaintainersRegistry = contractNameToProxyAddress["TwoKeyMaintainersRegistry"];
        require(msg.sender == deployer || ITwoKeyMaintainersRegistry(twoKeyMaintainersRegistry).onlyMaintainer(msg.sender));
        _;
    }

    /**
     * @notice Function to add non upgradable contract in registry of all contracts
     * @param contractName is the name of the contract
     * @param contractAddress is the contract address
     * @dev only maintainer can issue call to this method
     */
    function addNonUpgradableContractToAddress(
        string contractName,
        address contractAddress
    )
    public
    onlyMaintainer
    {
        nonUpgradableContractToAddress[contractName] = contractAddress;
    }


    /**
     * @dev Registers a new version with its implementation address
     * @param version representing the version name of the new implementation to be registered
     * @param implementation representing the address of the new implementation to be registered
     */
    function addVersion(
        string contractName,
        string version,
        address implementation
    )
    public
    onlyMaintainer
    {
        require(versions[contractName][version] == 0x0);
        versions[contractName][version] = implementation;
        contractNameToLatestVersion[contractName] = version;
        emit VersionAdded(version, implementation);
    }

    /**
     * @dev Tells the address of the implementation for a given version
     * @param version to query the implementation of
     * @return address of the implementation registered for the given version
     */
    function getVersion(
        string contractName,
        string version
    )
    public
    view
    returns (address)
    {
        return versions[contractName][version];
    }



    /**
     * @notice Gets the latest contract version
     * @param contractName is the name of the contract
     * @return string representation of the last version
     */
    function getLatestContractVersion(
        string contractName
    )
    public
    view
    returns (string)
    {
        return contractNameToLatestVersion[contractName];
    }


    function getNonUpgradableContractAddress(
        string contractName
    )
    public
    view
    returns (address)
    {
        return nonUpgradableContractToAddress[contractName];
    }

    /**
     * @notice Function to return address of proxy for specific contract
     * @param _contractName is the name of the contract we'd like to get proxy address
     * @return is the address of the proxy for the specific contract
     */
    function getContractProxyAddress(
        string _contractName
    )
    public
    view
    returns (address)
    {
        return contractNameToProxyAddress[_contractName];
    }


    function deployProxy(
        string contractName,
        string version
    )
    internal
    returns (address)
    {
        UpgradeabilityProxy proxy = new UpgradeabilityProxy(contractName, version);
        contractNameToProxyAddress[contractName] = proxy;
        emit ProxyCreated(proxy);
        return address(proxy);
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

}
