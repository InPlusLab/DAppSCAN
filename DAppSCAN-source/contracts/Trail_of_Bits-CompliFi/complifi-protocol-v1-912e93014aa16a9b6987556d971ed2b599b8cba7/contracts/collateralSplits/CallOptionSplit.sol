// "SPDX-License-Identifier: GPL-3.0-or-later"

pragma solidity 0.7.6;

import "./CollateralSplitParent.sol";

contract CallOptionSplit is CollateralSplitParent {
    function symbol() external pure override returns (string memory) {
        return "CallOption";
    }

    function splitNominalValue(int256 _normalizedValue)
        public
        pure
        override
        returns (int256)
    {
        if (_normalizedValue > 0) {
            return
                (FRACTION_MULTIPLIER * _normalizedValue) /
                (FRACTION_MULTIPLIER + _normalizedValue);
        } else {
            return 0;
        }
    }
}
