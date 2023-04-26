pragma solidity ^0.4.24;

import "./ITwoKeySingletonUtils.sol";
import "../upgradability/Upgradeable.sol";
import "../libraries/Utils.sol";
import "../interfaces/storage-contracts/ITwoKeySignatureValidatorStorage.sol";
import "../libraries/Call.sol";

contract TwoKeySignatureValidator is Upgradeable, Utils, ITwoKeySingletonUtils {

    using Call for *;
    bool initialized;
    ITwoKeySignatureValidatorStorage public PROXY_STORAGE_CONTRACT;

    function setInitialParams(
        address _twoKeySingletonRegistry,
        address _proxyStorage
    )
    public
    {
        require(initialized == false);

        TWO_KEY_SINGLETON_REGISTRY = _twoKeySingletonRegistry;
        PROXY_STORAGE_CONTRACT = ITwoKeySignatureValidatorStorage(_proxyStorage);

        initialized = true;
    }

    function validateSignUserData(
        string _name,
        string _fullName,
        string _email,
        bytes signature
    )
    public
    pure
    returns (address)
    {
        string memory concatenatedValues = strConcat(_name,_fullName,_email);
        bytes32 hash = keccak256(abi.encodePacked(keccak256(abi.encodePacked("bytes binding to name")),
            keccak256(abi.encodePacked(concatenatedValues))));
        address message_signer = Call.recoverHash(hash, signature, 0);
        return message_signer;
    }

    function validateSignName(
        string _name,
        bytes signature
    )
    public
    pure
    returns (address)
    {
        bytes32 hash = keccak256(abi.encodePacked(keccak256(abi.encodePacked("bytes binding to name")),
            keccak256(abi.encodePacked(_name))));
        address eth_address = Call.recoverHash(hash,signature,0);
        return eth_address;
    }

    function validateSignWalletName(
        string memory username,
        string memory _username_walletName,
        bytes signature
    )
    public
    pure
    returns (address)
    {
        string memory concatenatedValues = strConcat(username,_username_walletName,"");

        bytes32 hash = keccak256(abi.encodePacked(keccak256(abi.encodePacked("bytes binding to name")),
            keccak256(abi.encodePacked(concatenatedValues))));
        address message_signer = Call.recoverHash(hash, signature, 0);
    }
}
