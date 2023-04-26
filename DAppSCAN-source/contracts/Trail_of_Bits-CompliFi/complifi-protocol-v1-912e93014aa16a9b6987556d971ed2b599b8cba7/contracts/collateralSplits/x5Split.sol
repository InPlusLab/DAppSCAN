// "SPDX-License-Identifier: GPL-3.0-or-later"

pragma solidity 0.7.6;

import "./CollateralSplitParent.sol";

contract x5Split is CollateralSplitParent {
    function symbol() external pure override returns (string memory) {
        return "x5";
    }

    function splitNominalValue(int256 _normalizedValue)
        public
        pure
        override
        returns (int256)
    {
        if (_normalizedValue <= -(FRACTION_MULTIPLIER / 5)) {
            return 0;
        } else if (
            _normalizedValue > -(FRACTION_MULTIPLIER / 5) &&
            _normalizedValue < FRACTION_MULTIPLIER / 5
        ) {
            return (FRACTION_MULTIPLIER + _normalizedValue * 5) / 2;
        } else {
            return FRACTION_MULTIPLIER;
        }
    }
}
