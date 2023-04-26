pragma solidity ^0.5.4;

/// @title Opium.Lib.LibEIP712 contract implements the domain of EIP712 for meta transactions
contract LibEIP712 {
    // EIP712Domain structure
    // name - protocol name
    // version - protocol version
    // verifyingContract - signed message verifying contract
    struct EIP712Domain {
        string  name;
        string  version;
        address verifyingContract;
    }

    // Calculate typehash of ERC712Domain
    bytes32 constant internal EIP712DOMAIN_TYPEHASH = keccak256(abi.encodePacked(
        "EIP712Domain(",
        "string name,",
        "string version,",
        "address verifyingContract",
        ")"
    ));

    // solhint-disable-next-line var-name-mixedcase
    bytes32 internal DOMAIN_SEPARATOR;

    // Calculate domain separator at creation
    constructor () public {
        DOMAIN_SEPARATOR = keccak256(abi.encode(
            EIP712DOMAIN_TYPEHASH,
            keccak256("Opium Network"),
            keccak256("1"),
            address(this)
        ));
    }

    /// @notice Hashes EIP712Message
    /// @param hashStruct bytes32 Hash of structured message
    /// @return result bytes32 Hash of EIP712Message
    function hashEIP712Message(bytes32 hashStruct) internal view returns (bytes32 result) {
        bytes32 domainSeparator = DOMAIN_SEPARATOR;

        assembly {
            // Load free memory pointer
            let memPtr := mload(64)

            mstore(memPtr, 0x1901000000000000000000000000000000000000000000000000000000000000)  // EIP191 header
            mstore(add(memPtr, 2), domainSeparator)                                            // EIP712 domain hash
            mstore(add(memPtr, 34), hashStruct)                                                 // Hash of struct

            // Compute hash
            result := keccak256(memPtr, 66)
        }
        return result;
    }
}
