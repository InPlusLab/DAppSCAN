// "SPDX-License-Identifier: GPL-3.0-or-later"

pragma solidity 0.7.6;

import "./AddressRegistryParent.sol";
import "../collateralSplits/ICollateralSplit.sol";

contract CollateralSplitRegistry is AddressRegistryParent {
    function generateKey(address _value)
        public
        view
        override
        returns (bytes32 _key)
    {
        require(
            ICollateralSplit(_value).isCollateralSplit(),
            "Should be collateral split"
        );
        return keccak256(abi.encodePacked(ICollateralSplit(_value).symbol()));
    }
}
