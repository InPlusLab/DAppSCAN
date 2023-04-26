// "SPDX-License-Identifier: GPL-3.0-or-later"

pragma solidity 0.7.6;

import "./AddressRegistryParent.sol";
import "../IDerivativeSpecification.sol";

contract DerivativeSpecificationRegistry is AddressRegistryParent {
    mapping(bytes32 => bool) internal _uniqueFieldsHashMap;

    function generateKey(address _value)
        public
        view
        override
        returns (bytes32 _key)
    {
        return
            keccak256(
                abi.encodePacked(IDerivativeSpecification(_value).symbol())
            );
    }

    function _check(bytes32 _key, address _value) internal virtual override {
        super._check(_key, _value);
        IDerivativeSpecification derivative = IDerivativeSpecification(_value);
        require(
            derivative.isDerivativeSpecification(),
            "Should be derivative specification"
        );

        bytes32 uniqueFieldsHash =
            keccak256(
                abi.encode(
                    derivative.oracleSymbols(),
                    derivative.oracleIteratorSymbols(),
                    derivative.collateralTokenSymbol(),
                    derivative.collateralSplitSymbol(),
                    derivative.livePeriod(),
                    derivative.primaryNominalValue(),
                    derivative.complementNominalValue(),
                    derivative.authorFee()
                )
            );

        require(!_uniqueFieldsHashMap[uniqueFieldsHash], "Same spec params");

        _uniqueFieldsHashMap[uniqueFieldsHash] = true;
    }
}
