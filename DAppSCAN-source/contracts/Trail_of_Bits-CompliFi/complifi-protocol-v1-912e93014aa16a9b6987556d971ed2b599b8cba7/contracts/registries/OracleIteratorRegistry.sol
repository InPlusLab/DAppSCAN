// "SPDX-License-Identifier: GPL-3.0-or-later"

pragma solidity 0.7.6;

import "./AddressRegistryParent.sol";
import "../oracleIterators/IOracleIterator.sol";

contract OracleIteratorRegistry is AddressRegistryParent {
    function generateKey(address _value)
        public
        view
        override
        returns (bytes32 _key)
    {
        require(
            IOracleIterator(_value).isOracleIterator(),
            "Should be oracle iterator"
        );
        return keccak256(abi.encodePacked(IOracleIterator(_value).symbol()));
    }
}
