// "SPDX-License-Identifier: GPL-3.0-or-later"

pragma solidity 0.7.6;

import "./CollateralSplitParent.sol";

contract StableSplit is CollateralSplitParent {
    function symbol() external pure override returns (string memory) {
        return "Stab";
    }

    function splitNominalValue(int256 _normalizedValue)
        public
        pure
        override
        returns (int256)
    {
        if (_normalizedValue <= -(FRACTION_MULTIPLIER / 2)) {
            return FRACTION_MULTIPLIER;
        } else {
            return
                (FRACTION_MULTIPLIER * FRACTION_MULTIPLIER) /
                (2 * (FRACTION_MULTIPLIER + _normalizedValue));
        }
    }
}
