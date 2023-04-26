// "SPDX-License-Identifier: GPL-3.0-or-later"

pragma solidity 0.7.6;

import "./CollateralSplitParent.sol";

contract x1Split is CollateralSplitParent {
    function symbol() external pure override returns (string memory) {
        return "x1";
    }

    function splitNominalValue(int256 _normalizedValue)
        public
        pure
        override
        returns (int256)
    {
        return (FRACTION_MULTIPLIER + _normalizedValue) / 2;
    }
}
