// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./Roles.sol";

abstract contract RequestSigning is Ownable, Roles {
    using ECDSA for bytes32;

    event AssignWhitelistSigningKey(address indexed _address);
    event AssignOgSigningKey(address indexed _address);

    // The key(s) used to sign whitelist signatures.
    // We will check to ensure that the key that signed the signature
    // is this one that we expect.
    address public whitelistKey = address(0);
    address public ogKey = address(0);

    // Domain Separator is the EIP-712 defined structure that defines what contract
    // and chain these signatures can be used for.  This ensures people can't take
    // a signature used to mint on one contract and use it for another, or a signature
    // from testnet to replay on mainnet.
    // It has to be created in the constructor so we can dynamically grab the chainId.
    // https://github.com/ethereum/EIPs/blob/master/EIPS/eip-712.md#definition-of-domainseparator
    bytes32 public domainSeparator;

    // The typehash for the data type specified in the structured data
    // https://github.com/ethereum/EIPs/blob/master/EIPS/eip-712.md#rationale-for-typehash
    // This should match whats in the client side whitelist signing code
    bytes32 public constant MINTER_TYPEHASH =
        keccak256("Minter(address wallet)");

    constructor(string memory _schemeName) {
        // This should match whats in the client side whitelist signing code
        domainSeparator = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                // This should match the domain you set in your client side signing.
                keccak256(bytes.concat(bytes(_schemeName), bytes("Whitelist"))),
                keccak256(bytes("1")),
                block.chainid,
                address(this)
            )
        );
    }

    function setWhitelistSigningKey(address newSigningKey)
        external
        onlyOperator
    {
        whitelistKey = newSigningKey;
        emit AssignWhitelistSigningKey(newSigningKey);
    }

    function setOgSigningKey(address newSigningKey) external onlyOperator {
        ogKey = newSigningKey;
        emit AssignOgSigningKey(newSigningKey);
    }

    function isWhiteListed(bytes calldata signature)
        public
        view
        returns (bool)
    {
        require(whitelistKey != address(0), "WL key not assigned");
        return getEIP712RecoverAddress(signature) == whitelistKey;
    }

    function isOG(bytes calldata signature) public view returns (bool) {
        require(ogKey != address(0), "OG key not assigned");
        return getEIP712RecoverAddress(signature) == ogKey;
    }

    function getEIP712RecoverAddress(bytes calldata signature)
        internal
        view
        returns (address)
    {
        // Verify EIP-712 signature by recreating the data structure
        // that we signed on the client side, and then using that to recover
        // the address that signed the signature for this data.
        // Signature begin with \x19\x01, see: https://eips.ethereum.org/EIPS/eip-712
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                keccak256(abi.encode(MINTER_TYPEHASH, msg.sender))
            )
        );

        // Use the recover method to see what address was used to create
        // the signature on this data.
        // Note that if the digest doesn't exactly match what was signed we'll
        // get a random recovered address.
        return digest.recover(signature);
    }
}
