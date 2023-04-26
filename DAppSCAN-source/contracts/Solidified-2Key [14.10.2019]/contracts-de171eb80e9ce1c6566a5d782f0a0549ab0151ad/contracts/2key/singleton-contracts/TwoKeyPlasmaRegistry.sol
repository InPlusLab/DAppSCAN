pragma solidity ^0.4.24;

import "../upgradability/Upgradeable.sol";

import "../interfaces/storage-contracts/ITwoKeyPlasmaRegistryStorage.sol";
import "../interfaces/ITwoKeyMaintainersRegistry.sol";
import "../interfaces/ITwoKeySingletoneRegistryFetchAddress.sol";
import "../interfaces/ITwoKeyPlasmaEvents.sol";
import "../libraries/Call.sol";

contract TwoKeyPlasmaRegistry is Upgradeable {

    using Call for *;

    address public TWO_KEY_PLASMA_SINGLETON_REGISTRY;
    bool initialized;

    ITwoKeyPlasmaRegistryStorage public PROXY_STORAGE_CONTRACT;

    function setInitialParams(
        address _twoKeyPlasmaSingletonRegistry,
        address _proxyStorage
    )
    public
    {
        require(initialized == false);

        TWO_KEY_PLASMA_SINGLETON_REGISTRY = _twoKeyPlasmaSingletonRegistry;
        PROXY_STORAGE_CONTRACT = ITwoKeyPlasmaRegistryStorage(_proxyStorage);

        initialized = true;
    }

    // Internal function to fetch address from TwoKeyRegTwoistry
    function getAddressFromTwoKeySingletonRegistry(string contractName) internal view returns (address) {
        return ITwoKeySingletoneRegistryFetchAddress(TWO_KEY_PLASMA_SINGLETON_REGISTRY)
        .getContractProxyAddress(contractName);
    }

    function onlyMaintainer() internal view returns (bool) {
        address twoKeyPlasmaMaintainersRegistry = getAddressFromTwoKeySingletonRegistry("TwoKeyPlasmaMaintainersRegistry");
        return ITwoKeyMaintainersRegistry(twoKeyPlasmaMaintainersRegistry).onlyMaintainer(msg.sender);
    }

    /**
     * @notice Function to link username and address once signature is validated
     */
    function linkUsernameAndAddress(bytes signature, address plasma_address, string username) public {
        require(msg.sender == plasma_address || onlyMaintainer());
        bytes32 hash = keccak256(abi.encodePacked(keccak256(abi.encodePacked("bytes binding to plasma address")),keccak256(abi.encodePacked(plasma_address))));
        require (signature.length == 65);
        address plasma = Call.recoverHash(hash,signature,0);
        require(plasma == plasma_address);

        PROXY_STORAGE_CONTRACT.setString(keccak256("addressToUsername", plasma_address), username);
        PROXY_STORAGE_CONTRACT.setAddress(keccak256("usernameToAddress",username), plasma_address);

        emitPlasma2Handle(plasma_address, username);
    }

    function add_plasma2ethereum(address plasma_address, bytes sig) public {
        require(msg.sender == plasma_address || onlyMaintainer());
        bytes32 hash = keccak256(abi.encodePacked(keccak256(abi.encodePacked("bytes binding to plasma address")),keccak256(abi.encodePacked(plasma_address))));
        require (sig.length == 65);
        address eth_address = Call.recoverHash(hash,sig,0);
        address ethereum = PROXY_STORAGE_CONTRACT.getAddress(keccak256("plasma2ethereum", plasma_address));
        require(ethereum == address(0) || ethereum == eth_address);
        PROXY_STORAGE_CONTRACT.setAddress(keccak256("plasma2ethereum", plasma_address), eth_address);
        PROXY_STORAGE_CONTRACT.setAddress(keccak256("ethereum2plasma",eth_address), plasma_address);

        emitPlasma2Ethereum(plasma_address, eth_address);
    }

    function emitPlasma2Ethereum(address plasma, address ethereum) internal {
        address twoKeyPlasmaEvents = getAddressFromTwoKeySingletonRegistry("TwoKeyPlasmaEvents");
        ITwoKeyPlasmaEvents(twoKeyPlasmaEvents).emitPlasma2EthereumEvent(plasma, ethereum);
    }

    function emitPlasma2Handle(address plasma, string handle) internal {
        address twoKeyPlasmaEvents = getAddressFromTwoKeySingletonRegistry("TwoKeyPlasmaEvents");
        ITwoKeyPlasmaEvents(twoKeyPlasmaEvents).emitPlasma2HandleEvent(plasma, handle);
    }

    function plasma2ethereum(
        address _plasma
    )
    public
    view
    returns (address) {
        return PROXY_STORAGE_CONTRACT.getAddress(keccak256("plasma2ethereum", _plasma));
    }

    function ethereum2plasma(
        address _ethereum
    )
    public
    view
    returns (address) {
        return PROXY_STORAGE_CONTRACT.getAddress(keccak256("ethereum2plasma", _ethereum));
    }

    /**
     * @notice Function to validate if signature is valid
     * @param signature is the signature
     */
    function recover(
        bytes signature
    )
    public
    view
    returns (address)
    {
        bytes32 hash = keccak256(abi.encodePacked(keccak256(abi.encodePacked("bytes binding referrer to plasma")),
            keccak256(abi.encodePacked("GET_REFERRER_REWARDS"))));
        address recoveredAddress = Call.recoverHash(hash, signature, 0);
        return recoveredAddress;
    }

}
