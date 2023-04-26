// SPDX-License-Identifier: Apache-2.0

// File: contracts/lib/EIP712Domain.sol

pragma solidity 0.6.12;
import "./EIP712.sol";

abstract contract EIP712Domain {
    bytes32 public DOMAIN_SEPARATOR;

    function _setDomainSeparator(string memory name, string memory version)
        internal
    {
        DOMAIN_SEPARATOR = EIP712.makeDomainSeparator(name, version);
    }
}